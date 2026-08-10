function Invoke-UiAction {
    <#
    .SYNOPSIS
        Runs a user action async by default. -Sync pins to UI thread.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action,

        # One row or a whole selection. An array runs the action once per row inside a SINGLE background runspace, so Stop-UiAsync/AutoCancel own the whole batch (a runspace per row left Cancel reaching only the last one).
        [Parameter(Mandatory)]
        $Item,

        # DataGrid (or any items control). Items.Refresh() after the action lands. Optional.
        $RefreshTarget,

        # Default: action runs in a background runspace. Use -Sync when the action has to stay on the UI thread (dialogs and clipboard work, mostly).
        [switch]$Sync,

        # Multi row fan out (RowContextMenu acting on a selection). Skips the per target Remove+Insert workaround - concurrent runspaces racing the shared SourceCollection were the cause of the ~20% mutation drop. Items.Refresh alone is race free. The visual fidelity tradeoff (custom binding cells lag a redraw) is acceptable next to losing the mutation entirely.
        [switch]$FanOut
    )

    $useAsync = !$Sync

    $refreshRef  = $RefreshTarget
    $refreshItem = $Item
    $fanOutMode  = [bool]$FanOut
    $refresh = {
        if (!$refreshRef) { return }
        # Rebind to locals before building $repaint: nested .GetNewClosure() captures only the immediate scope's locals, NOT what the outer closure captured - $repaint saw $refreshRef as $null and the post action redraw silently died on Items.Refresh().
        $localGrid   = $refreshRef
        $localItem   = $refreshItem
        $localFanOut = $fanOutMode
        $repaint = {
            try {
                # Owned rows carry a baked _SearchText and the filter predicate reads it before anything else, so an in place write leaves the row matching its pre action values. Filter on the old text and it still shows, search the new one and it never appears. Both paths (cell edits, Toggle cells) rebuild it the same way.
                $gridTag = $localGrid.Tag
                foreach ($touched in @($localItem)) {
                    if ($null -eq $touched -or !$touched.PSObject.Properties['_SearchText']) { continue }
                    try { Add-UiDataGridSearchText -PsObject $touched -Force }
                    catch { Write-Debug "Search text rebuild after action failed: $_" }
                }
                try {
                    $filterBox = if ($gridTag -is [hashtable]) { $gridTag.FilterBox } else { $null }
                    if ($filterBox -and $filterBox.Tag -and $filterBox.Tag.ClearSearchCache) { & $filterBox.Tag.ClearSearchCache }
                }
                catch { Write-Debug "Filter cache invalidation after action failed: $_" }

                # Items.Refresh on its own redraws reliably in clean tests, but inside a real PsUi grid (styled cells, filter view, fan out from worker runspaces) the cell bindings sometimes don't pull again from the mutated PSCustomObject. Force a surgical regen of just the touched row's container by removing and reinserting at the same index - WPF can't collapse a paired Remove/Insert into nothing the way it silently drops a same reference indexer assignment. Saved selection state restores around the Remove so multi select fan out doesn't shed rows.
                # New-UiDataGrid sets ItemsSource to a ListCollectionView, so unwrap to SourceCollection or the IList check fails and the Remove/Insert path never fires.
                #
                # Skipped under -FanOut: N parallel runspaces all racing the same source list caused IndexOf misses and dropped per row mutations. Items.Refresh below is idempotent and survives the parallel barrage.
                $source = $localGrid.ItemsSource
                if ($source -is [System.ComponentModel.ICollectionView]) { $source = $source.SourceCollection }
                $regenerated = $false
                if (!$localFanOut -and $localItem -and $source -is [System.Collections.IList] -and !$source.IsReadOnly) {
                    $idx = $source.IndexOf($localItem)
                    if ($idx -ge 0) {
                        $wasSelected = $localGrid.SelectedItems.Contains($localItem)
                        $source.RemoveAt($idx)
                        $source.Insert($idx, $localItem)
                        # SelectedItems mutation throws on Single mode grids ("Can only change SelectedItems collection in multiple selection modes"), which killed the whole redraw. SelectedItem assignment is legal everywhere but Single needs it.
                        if ($wasSelected) {
                            if ($localGrid.SelectionMode -eq [System.Windows.Controls.DataGridSelectionMode]::Single) { $localGrid.SelectedItem = $localItem }
                            else { [void]$localGrid.SelectedItems.Add($localItem) }
                        }
                        # Remove and Insert raise CollectionChanged, which drops the brush key on its own, and the regenerated container recomputes it through LoadingRow.
                        $regenerated = $source -is [System.Collections.Specialized.INotifyCollectionChanged]
                    }
                }

                # -RowBackground holds one brush per row and an in place write raises nothing, so the touched rows have to be dropped by hand.
                # Only where the Remove/Insert above didn't already do it and calling both ran the user's scriptblock twice per row.
                if (!$regenerated -and $gridTag -is [hashtable] -and $gridTag.InvalidateRowBackground) { & $gridTag.InvalidateRowBackground $localItem }

                $localGrid.Items.Refresh()
            }
            catch { Write-Debug "Invoke-UiAction refresh failed: $_" }
        }.GetNewClosure()
        try {
            $dispatcher = $refreshRef.Dispatcher
            if ($dispatcher -and !$dispatcher.CheckAccess()) { $dispatcher.Invoke([Action]$repaint) }
            else { & $repaint }
        }
        catch { Write-Debug "Invoke-UiAction refresh dispatch failed: $_" }
    }.GetNewClosure()

    # ForEach-Object binds $_ directly from the parameter. Wrapping the action in another scriptblock loses $_ across scope / session state boundaries, leaving the user's action with $_ as $null.
    # One bad row shouldn't sour the rest of a selection. Failures collect and surface once at the end and grid actions have no output panel, so a silent Write-Debug meant the user never learned the click did nothing.
    if (!$useAsync) {
        $rowFailures = [System.Collections.Generic.List[string]]::new()
        foreach ($actionTarget in @($Item)) {
            try { $actionTarget | ForEach-Object -Process $Action }
            catch { [void]$rowFailures.Add($_.Exception.Message) }
        }
        & $refresh
        if ($rowFailures.Count -gt 0) {
            Write-Debug "Invoke-UiAction sync failed: $($rowFailures -join '; ')"
            try { Show-UiMessageDialog -Title 'Action Error' -Message ($rowFailures -join [Environment]::NewLine) -Icon Error }
            catch { Write-Debug "Action error dialog failed: $_" }
        }
        return
    }

    # Stringify and rebuild the user action via [scriptblock]::Create() so its $_ binds to this runspace's ExecutionContext. ForEach-Object handles the $_ bind - calling positionally leaves the action with a null $_ (verified, same trap as the sync path).
    # Rows run one at a time. A throwing row reemits its ORIGINAL record on the error stream (the AsyncExecutor routes it to OnError) and the loop moves on. A collect and rethrow here stamped every failure with this wrap's throw site, so dialogs pointed at PsUi internals instead of the user's action line.
    $actionScriptText = $Action.ToString()
    $wrapped = {
        if ([string]::IsNullOrWhiteSpace($actionScriptText)) { return }
        $userActionScript = [scriptblock]::Create($actionScriptText)
        foreach ($actionTarget in @($itemForAction)) {
            try { $actionTarget | ForEach-Object -Process $userActionScript }
            catch { Write-Error -ErrorRecord $_ }
        }
    }

    # Auto capture inside Invoke-UiAsync scans $wrapped's AST (three locals), not the user's body.
    # Prefill Variables here from the user's AST so sibling control vars ($searchText, etc.) hydrate like in New-UiButton -Action.
    # User functions need an imported module or Sync = $true on the action's hashtable.
    $harvested = @{ itemForAction = $Item; actionScriptText = $actionScriptText }
    $builtinVars = @('_', 'PSItem', 'this', 'args', 'input', 'PSCmdlet', 'PSBoundParameters',
                     'MyInvocation', 'ExecutionContext', 'null', 'true', 'false', 'PSScriptRoot',
                     'PSCommandPath', 'PID', 'Host', 'PSVersionTable', 'Error', 'StackTrace',
                     'HOME', 'PROFILE', 'PSCulture', 'PSUICulture', 'ShellId', 'NestedPromptLevel',
                     'ErrorActionPreference', 'PSDefaultParameterValues', 'PWD', 'OFS',
                     'LASTEXITCODE', 'VerbosePreference', 'DebugPreference', 'WarningPreference',
                     'WhatIfPreference', 'OutputEncoding', 'ConfirmPreference')

    # AST scan + calling-scope walk instead of GetNewClosure. The async path stringifies $Action and rebuilds it via [scriptblock]::Create() so closure captures don't transfer - anything the walk misses is gone. Add to $builtinVars above to skip a common shell var without breaking a user reference.
    $referencedVars = $Action.Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.VariableExpressionAst]
    }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Select-Object -Unique

    foreach ($varName in $referencedVars) {
        if ($varName -in $builtinVars) { continue }
        if ($harvested.ContainsKey($varName)) { continue }

        $scopeIndex = 1
        while ($true) {
            try {
                $val = Get-Variable -Name $varName -Scope $scopeIndex -ValueOnly -ErrorAction Stop
                $harvested[$varName] = $val
                break
            }
            catch [System.Management.Automation.ItemNotFoundException] { $scopeIndex++ }
            catch [System.ArgumentOutOfRangeException] { break }
            catch { break }
        }
    }

    # Write-Host from the worker runspace lands on whatever thread the AsyncExecutor's host hook fires on. Route back to this window's UI thread so PsUi's existing host hook captures it.
    # Not Application.Current, it stays pinned to the first window of the process, so in a second window it points at a thread that already exited and every routed line disappears.
    $hostSession   = [PsUi.SessionManager]::Current
    $appDispatcher = if ($hostSession -and $hostSession.Window) { $hostSession.Window.Dispatcher }
                     elseif ([System.Windows.Application]::Current) { [System.Windows.Application]::Current.Dispatcher }

    $onHost = {
        param($record)
        if (!$appDispatcher) { return }
        $isHostRec = $record -is [PsUi.HostOutputRecord]
        $msg       = if ($isHostRec) { $record.Message }         else { [string]$record }
        $fg        = if ($isHostRec) { $record.ForegroundColor } else { $null }
        $nl        = $isHostRec -and $record.NoNewLine
        try {
            # BeginInvoke runs this after the current invocation scope has popped, and $msg/$fg/$nl resolve to $null without the snapshot.
            $appDispatcher.BeginInvoke([Action]{
                $params = @{ Object = $msg; NoNewline = $nl }
                # $null test, not truthiness - ConsoleColor.Black is enum value 0 and a truthy check silently dropped it.
                if ($null -ne $fg) { $params.ForegroundColor = $fg }
                Write-Host @params
            }.GetNewClosure()) | Out-Null
        }
        catch { Write-Debug "Invoke-UiAction host route failed: $_" }
    }.GetNewClosure()

    $asyncArgs = @{
        ScriptBlock   = $wrapped
        Variables     = $harvested
        NoAutoCapture = $true
        OnComplete    = $refresh
        OnError       = {
            param($errInfo)
            Write-Debug "Invoke-UiAction async failed: $errInfo"
            # No output panel on the grid action path - a dialog is the only place the failure can land (same as New-UiButton's NoOutput error dialog).
            if ($errInfo -and $appDispatcher -and !$appDispatcher.HasShutdownStarted) {
                $errorMsg = [string]$errInfo
                try {
                    $appDispatcher.Invoke([Action]{
                        Show-UiMessageDialog -Title 'Action Error' -Message $errorMsg -Icon Error
                    }.GetNewClosure())
                }
                catch { Write-Debug "Action error dialog skipped (window closed): $_" }
            }
            # No refresh here. Invoke-UiAsync raises OnError from inside its OnComplete handler and no longer stops there, so OnComplete runs the refresh right after this returns. Doing it here as well ran the whole thing twice for every touched row.
        }.GetNewClosure()
        OnHost        = $onHost
    }
    $asyncHandle = Invoke-UiAsync @asyncArgs

    # Hook the run's lifecycle into any -AutoProgress / -AutoCancel / -Intercept status bar (same pattern as New-UiButton).
    # Hooks after ExecuteAsync because Invoke-UiAsync owns the AsyncExecutor's creation. The sub tick gap is fine - routed events fire a tick later anyway.
    $statusSession = [PsUi.SessionManager]::Current
    if ($statusSession -and $asyncHandle -and $asyncHandle.Executor) { Add-StatusBarAutoWiring -Executor $asyncHandle.Executor -Session $statusSession }
}
