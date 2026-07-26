function Add-UiDataGridRowContextMenuItems {
    <#
    .SYNOPSIS
        Prepends items to the DataGrid context menu.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        # IDictionary so [ordered]@{} arrives intact - menu items render in declaration order.
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Items
    )

    $menu = $DataGrid.ContextMenu
    if (!$menu) {
        $menu = [System.Windows.Controls.ContextMenu]::new()
        $DataGrid.ContextMenu = $menu
    }

    $rowMenuItems = [System.Collections.Generic.List[object]]::new()
    $insertIndex  = 0

    # Right click target. WPF never moves CurrentCell or selection on rightclick, and a fresh grid's CurrentCell.Item is DependencyProperty.UnsetValue (not $null, that would be too easy) - resolving the target from CurrentCell at click time acted on the last LEFT clicked row, or fed UnsetValue to the action. ContextMenuOpening fires before the menu shows: walk from the click source to the row and remember it. A click outside the current selection also retargets the selection (Explorer convention).
    $clickState = @{ Item = $null }
    $DataGrid.Add_ContextMenuOpening({
        param($sender, $eventArgs)
        $clickState.Item = $null
        $src = $eventArgs.OriginalSource -as [System.Windows.DependencyObject]
        while ($src -and $src -isnot [System.Windows.Controls.DataGridRow]) {
            # Inline Runs and other ContentElements aren't Visuals - fall back to the logical tree for those hops.
            $src = if ($src -is [System.Windows.Media.Visual] -or $src -is [System.Windows.Media.Media3D.Visual3D]) {
                [System.Windows.Media.VisualTreeHelper]::GetParent($src)
            }
            else { [System.Windows.LogicalTreeHelper]::GetParent($src) }
        }
        if (!$src) {
            Write-Debug "RowContextMenu: right-click resolved no DataGridRow (empty grid space) - no target stashed."
            return
        }

        $clickState.Item = $src.Item
        Write-Debug "RowContextMenu: right-click target = row item '$($src.Item)'."
        if (!$sender.SelectedItems.Contains($src.Item)) {
            # SelectedItems.Clear() throws on Single mode grids ("Can only change SelectedItems collection in multiple selection modes") even when it's empty - clearing nothing counts as a change, apparently. And this handler runs on every rightclick. SelectedItem assignment replaces the selection in Single mode by itself.
            if ($sender.SelectionMode -ne [System.Windows.Controls.DataGridSelectionMode]::Single) { $sender.SelectedItems.Clear() }
            $sender.SelectedItem = $src.Item
        }
    }.GetNewClosure())

    # Per row Enabled eval. Throws are eaten and treated as disabled. Write-Error inside a callback has nowhere to go. Both the enablement pass when the menu opens and the click dispatch close over this. $null means "no Enabled given". A literal $false has to stay $false, so no truth shortcut here.
    $testEnabled = {
        param($EnabledRef, $Row)
        if ($null -eq $EnabledRef) { return $true }
        try {
            if ($EnabledRef -is [scriptblock]) {
                $vars = [System.Collections.Generic.List[psvariable]]::new()
                $vars.Add([psvariable]::new('_', $Row))
                $vars.Add([psvariable]::new('row', $Row))
                $result = $EnabledRef.InvokeWithContext($null, $vars, $Row)
                return [bool](@($result) | Select-Object -Last 1)
            }
            return [bool]$EnabledRef
        }
        catch {
            Write-Debug "RowContextMenu Enabled check failed: $_"
            return $false
        }
    }

    foreach ($label in $Items.Keys) {
        $itemDef    = $Items[$label]
        $actionRef  = $null
        $enabledRef = $null
        $iconName   = $null
        $syncRef    = $false

        if ($itemDef -is [scriptblock]) { $actionRef = $itemDef }
        elseif ($itemDef -is [System.Collections.IDictionary]) {
            $actionRef  = $itemDef['Action']
            $enabledRef = $itemDef['Enabled']
            $iconName   = [string]$itemDef['Icon']
            if ($itemDef.Contains('Sync')) { $syncRef = [bool]$itemDef['Sync'] }
        }

        if (!$actionRef) {
            Write-Warning "RowContextMenu: '$label' has no Action; skipping."
            continue
        }

        $menuItem = [System.Windows.Controls.MenuItem]::new()
        $menuItem.Header = [string]$label

        if ($iconName) {
            $glyph = [PsUi.ModuleContext]::GetIcon($iconName)
            if ($glyph) {
                $iconTb = [System.Windows.Controls.TextBlock]@{
                    Text       = $glyph
                    FontFamily = [PsUi.ModuleContext]::ActiveIconFontFamily
                    FontSize   = 14
                }
                $menuItem.Icon = $iconTb
            }
        }

        $capturedAction  = $actionRef
        $capturedEnabled = $enabledRef
        $capturedSync    = $syncRef
        $gridRef         = $DataGrid

        $capturedLabel = [string]$label

        $menuItem.Add_Click({
            # ContextMenuOpening stashed the row under the rightclick. SelectedItem covers menus opened from the keyboard (Shift+F10) where no mouse walk happened.
            $clicked = $clickState.Item
            if ($null -eq $clicked) { $clicked = $gridRef.SelectedItem }
            if ($null -eq $clicked) {
                Write-Debug "RowContextMenu '$capturedLabel': no target (clickState and SelectedItem both null) - nothing to act on."
                return
            }

            # If the rightclick landed inside a multi selection, fan the action across every selected row (Excel / Explorer convention). Otherwise act on the click target only.
            # Outer @() is load bearing: when the if yields a single element PS unwraps it to a scalar, and a scalar's .Count is $null under 5.1.
            $selected = @($gridRef.SelectedItems)
            $targets  = @(if ($selected.Count -gt 1 -and ($selected -contains $clicked)) { $selected } else { $clicked })

            # Reeval Enabled per row before dispatch. The menu enables when any row passes, so a mixed selection lands here with some rows ineligible. Skip them silently.
            $eligible = [System.Collections.Generic.List[object]]::new()
            foreach ($target in $targets) {
                if ($null -ne $capturedEnabled -and !(& $testEnabled $capturedEnabled $target)) { continue }
                [void]$eligible.Add($target)
            }
            if ($eligible.Count -eq 0) {
                Write-Debug "RowContextMenu '$capturedLabel': all $($targets.Count) target(s) failed the Enabled check - action skipped."
                return
            }
            Write-Debug "RowContextMenu '$capturedLabel': dispatching to $($eligible.Count) row(s)."

            # ONE Invoke-UiAction call for the whole batch: a single background runspace loops the rows, so Stop-UiAsync / the status bar's AutoCancel cancel all of them (a runspace per row left Cancel holding only the last one) and the action's AST is scanned once, not N times.
            # -FanOut skips the Remove+Insert container regen workaround. One Items.Refresh at the end covers the whole batch.
            $itemArg = if ($eligible.Count -eq 1) { $eligible[0] } else { $eligible }
            Invoke-UiAction -Action $capturedAction -Item $itemArg -RefreshTarget $gridRef -Sync:$capturedSync -FanOut:($eligible.Count -gt 1)
        }.GetNewClosure())

        # Literal bool is a constant - set it once and skip probing on every open. Scriptblocks reevaluate through Tag each time the menu opens (a static IsEnabled would freeze on the first row).
        if ($capturedEnabled -is [scriptblock]) {
            $menuItem.Tag = @{ EnabledRef = $capturedEnabled; GridRef = $gridRef }
        }
        elseif ($null -ne $capturedEnabled) {
            # Tag the static state too - without it the Opened pass below can't tell a deliberate $false from an item with no Enabled clause, and would happily reenable it.
            $menuItem.IsEnabled = [bool]$capturedEnabled
            $menuItem.Tag       = @{ StaticEnabled = [bool]$capturedEnabled }
        }

        $menu.Items.Insert($insertIndex, $menuItem)
        $insertIndex++
        $rowMenuItems.Add($menuItem)
    }

    if ($rowMenuItems.Count -eq 0) { return }

    $separator = [System.Windows.Controls.Separator]::new()
    $menu.Items.Insert($insertIndex, $separator)
    $rowMenuItems.Add($separator)

    $itemsRef  = $rowMenuItems
    $gridForRef = $DataGrid
    $menu.Add_Opened({
        param($sender, $eventArgs)

        # No row under the click and nothing selected (rightclick on empty grid space): the row actions have nothing to act on, so gray them all out rather than let a click die silently. Matches Explorer - rightclick the void, the item commands are dead.
        $target = $clickState.Item
        if ($null -eq $target) { $target = $gridForRef.SelectedItem }
        if ($null -eq $target) {
            Write-Debug "RowContextMenu: opened over no target - disabling all row items."
            foreach ($mi in $itemsRef) {
                if ($mi -is [System.Windows.Controls.MenuItem]) { $mi.IsEnabled = $false }
            }
            return
        }

        foreach ($mi in $itemsRef) {

            if ($mi -isnot [System.Windows.Controls.MenuItem]) { continue }
            $tag = $mi.Tag
            
            # A literal Enabled item carries StaticEnabled - restore exactly that, so a deliberate $false stays grayed after a no target open.
            if ($tag -and $tag.ContainsKey('StaticEnabled')) { $mi.IsEnabled = $tag.StaticEnabled; continue }
            
            # Reenable items with no enabled clause... an earlier open over empty space leaves them grayed.
            if (!$tag -or !$tag.EnabledRef) { $mi.IsEnabled = $true; continue }

            # Mirror the click handler's targetting. The item enables when any target passes. The click handler rechecks each row anyway.
            # Probe cap at 20 rows. the loop dies on the first pass, but 10k selected rows against a slow enabled would freeze the menu open and that would suck. 
            # Beyond the cap, enable optimisticaly. The click handler still filters. ContextMenuOpening already ran (it fires before Opened), so $clickState is fresh.
            $clicked = $clickState.Item
            if ($null -eq $clicked) { $clicked = $tag.GridRef.SelectedItem }
            
            # Same @() as the click handler. A single element unwraps to a scalar whose .Count is $null under 5.1, which zeroed probeMax and skipped the probe (menu item stuck disabled). Keep it an array.
            $selected = @($tag.GridRef.SelectedItems)
            $targets  = @(if ($selected.Count -gt 1 -and ($selected -contains $clicked)) { $selected } else { $clicked })

            $probeMax = [Math]::Min(20, $targets.Count)
            $enabled  = $targets.Count -gt $probeMax
            
            for ($i = 0; $i -lt $probeMax -and !$enabled; $i++) {
                if (& $testEnabled $tag.EnabledRef $targets[$i]) { $enabled = $true }
            }
            $mi.IsEnabled = $enabled
        }
    }.GetNewClosure())
}
