function Show-StreamingOutput {
    <#
    .SYNOPSIS
        Streaming output window for async runs: live console, errors, warnings, results tabs.
    #>
    # Too big. Wants splitting into smaller functions.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Executor,
        [string]$Title = 'Running...',
        [int]$Width = 900,
        [int]$Height = 600,
        [System.Windows.Window]$ParentWindow,
        [scriptblock]$Action,
        [hashtable]$Parameters,
        [hashtable[]]$ResultActions,
        [switch]$SingleSelect,
        [string[]]$LinkedVariables,
        [string[]]$LinkedFunctions,
        [string[]]$LinkedModules,
        [System.Collections.IDictionary]$LinkedVariableValues,
        [System.Collections.IDictionary]$LinkedFunctionDefinitions,
        [string[]]$Capture,
        [switch]$HideUntilContent,
        [switch]$NoWait,
        [switch]$ScrollToTop
    )

    # Debug output goes to console if the parent window was created with -Debug
    $debugEnabled = $false
    $currentSession = [PsUi.SessionManager]::Current
    if ($currentSession) { $debugEnabled = $currentSession.DebugMode }

    $writeDebug = {
        param([string]$Message)
        if ($debugEnabled) { [Console]::WriteLine("[DEBUG] $Message") }
    }

    & $writeDebug "Show-StreamingOutput started (Title='$Title', Width=$Width, Height=$Height)"
    & $writeDebug "  HideUntilContent=$HideUntilContent, ResultActions=$($ResultActions.Count)"

    if (!$Executor -or !$Executor.PSObject.Methods['ExecuteAsync']) {
        & $writeDebug "Invalid executor (null or missing ExecuteAsync), returning"
        return
    }
    & $writeDebug "Executor validated (Type=$($Executor.GetType().Name))"

    $hydrationParams = @{
        LinkedVariableValues      = $LinkedVariableValues
        LinkedFunctionDefinitions = $LinkedFunctionDefinitions
        LinkedVariables           = $LinkedVariables
        LinkedFunctions           = $LinkedFunctions
        LinkedModules             = $LinkedModules
        DebugEnabled              = $debugEnabled
    }

    $hydrationResult = Register-VariableHydration @hydrationParams
    $varValues       = $hydrationResult.Variables
    $funcDefs        = $hydrationResult.Functions
    $capturedModules = $hydrationResult.Modules
    
    & $writeDebug "Hydration complete - Vars: $($varValues.Count), Funcs: $($funcDefs.Count), Modules: $($capturedModules.Count)"

    if ($debugEnabled -and $varValues.Count -gt 0) {
        $varNames = ($varValues.Keys | Select-Object -First 10) -join ', '
        & $writeDebug "  Variables: $varNames$(if ($varValues.Count -gt 10) { '...' })"
    }

    if ($debugEnabled -and $funcDefs.Count -gt 0) {
        $funcNames = ($funcDefs.Keys | Select-Object -First 10) -join ', '
        & $writeDebug "  Functions: $funcNames$(if ($funcDefs.Count -gt 10) { '...' })"
    }

    if ($debugEnabled -and $capturedModules.Count -gt 0) {
        & $writeDebug "  Modules: $($capturedModules -join ', ')"
    }

    $colors = Get-ThemeColors

    if (!$colors) {
        $colors = @{
            WindowBg         = '#FFFFFF'
            WindowFg         = '#1A1A1A'
            ControlBg        = '#F3F3F3'
            ControlFg        = '#1A1A1A'
            Accent           = '#0078D4'
            Border           = '#D1D1D1'
            HeaderBackground = '#0078D4'
            HeaderForeground = '#FFFFFF'
        }
    }

    $customLogo = if ($currentSession) { $currentSession.CustomLogo } else { $null }
    $window = New-OutputWindow -Title $Title -Width $Width -Height $Height -ParentWindow $ParentWindow -Colors $colors -CustomLogo $customLogo

    $windowRefs  = $window.Tag
    $contentArea = $windowRefs.ContentArea

    # HideUntilContent keeps the window invisible until something actually arrives - good for quick async actions where a brief flash of "nothing yet" looks like a bug.
    $showWindowOnData = $HideUntilContent

    # Take ownership of dialog parenting so child Show-Ui* dialogs centre on this window.
    if ($currentSession) { $currentSession.ActiveDialogParent = $window }

    # Catch-all UnhandledException handler. Log and swallow so a stray throw on the UI thread doesn't tear the whole app down.
    $window.Dispatcher.add_UnhandledException({
        param($sender, $eventArgs)
        $ex = $eventArgs.Exception

        # SuspendStoppingPipeline NREs in UI-thread handlers - no parent pipeline to suspend.
        # Harmless (caught internally, execution proceeds) but it spams the console three or four times per event. Drop it here.
        $stack = ''

        if ($ex.InnerException -and $ex.InnerException.StackTrace) { $stack = $ex.InnerException.StackTrace }
        elseif ($ex.StackTrace) { $stack = $ex.StackTrace }

        if ($ex -is [System.NullReferenceException] -and $stack.Contains('SuspendStoppingPipeline')) {
            $eventArgs.Handled = $true
            return
        }

        if ($ex.InnerException -is [System.NullReferenceException] -and $stack.Contains('SuspendStoppingPipeline')) {
            $eventArgs.Handled = $true
            return
        }

        [Console]::WriteLine("[PsUi] Dispatcher exception: $($ex.Message)")
        if ($ex.InnerException) {
            [Console]::WriteLine("[PsUi] Inner exception: $($ex.InnerException.Message)")
            [Console]::WriteLine("[PsUi] Inner stack: $($ex.InnerException.StackTrace)")
        }
        else { [Console]::WriteLine("[PsUi] Stack: $($ex.StackTrace)") }

        $eventArgs.Handled = $true

    }.GetNewClosure())

    # Esc cancels the running async action - confirms first so a stray keystroke doesn't kill work.
    $executorRef = $Executor
    $window.add_PreviewKeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            if ($executorRef -and $executorRef.IsRunning) {
                # Unpin temporarily so the confirm dialog doesn't open behind the window. Deferred via DispatcherTimer so the Topmost change settles before the modal grabs focus (Start-Sleep would freeze the UI).
                $wasPinned = $window.Topmost
                if ($wasPinned) { $window.Topmost = $false }

                $capturedWindow   = $window
                $capturedExec     = $executorRef
                $capturedWasPin   = $wasPinned
                $unpinTimer          = [System.Windows.Threading.DispatcherTimer]::new()
                $unpinTimer.Interval = [TimeSpan]::FromMilliseconds(50)
                $unpinTimer.Add_Tick({
                    $this.Stop()
                    $confirm = Show-UiConfirmDialog -Title "Cancel Operation" -Message "Are you sure you want to cancel the running task?"
                    if ($capturedWasPin) { $capturedWindow.Topmost = $true }

                    if ($confirm -and $capturedExec.IsRunning) {
                        [PsUi.KeyCaptureDialog]::CloseCurrentDialog()
                        $capturedExec.Cancel()
                    }
                }.GetNewClosure())
                $unpinTimer.Start()

                $eventArgs.Handled = $true
            }
        }
    }.GetNewClosure())

    $mainPanel = [System.Windows.Controls.DockPanel]::new()
    $contentArea.Child = $mainPanel

    # Status header sits below the title bar - holds the spinner/check icon and the script title.
    $statusHeader = [System.Windows.Controls.Border]@{
        Background = ConvertTo-UiBrush $colors.HeaderBackground
        Padding    = [System.Windows.Thickness]::new(16, 8, 16, 8)
        Tag        = 'HeaderBorder'
    }
    [System.Windows.Controls.DockPanel]::SetDock($statusHeader, 'Top')

    $statusPanel = [System.Windows.Controls.StackPanel]@{ Orientation = 'Horizontal' }

    $statusIndicatorResult = New-StatusIndicator -Colors $colors
    $statusIndicator = $statusIndicatorResult.Container
    $statusSpinner   = $statusIndicatorResult.Spinner
    $statusSuccess   = $statusIndicatorResult.Success
    $statusWarning   = $statusIndicatorResult.Warning
    [void]$statusPanel.Children.Add($statusIndicator)

    $headerTitle = [System.Windows.Controls.TextBlock]@{
        FontSize          = 16
        FontWeight        = 'SemiBold'
        Foreground        = ConvertTo-UiBrush $colors.HeaderForeground
        VerticalAlignment = 'Center'
        Text              = $Title
        Tag               = 'HeaderText'
    }
    [void]$statusPanel.Children.Add($headerTitle)

    # Subtitle shows whatever the script set on $host.UI.RawUI.WindowTitle, hidden until used.
    $headerSubtitle = [System.Windows.Controls.TextBlock]@{
        FontSize          = 12
        FontStyle         = 'Italic'
        Foreground        = ConvertTo-UiBrush $colors.SecondaryText
        VerticalAlignment = 'Center'
        Margin            = [System.Windows.Thickness]::new(8, 0, 0, 0)
        Visibility        = 'Collapsed'
        Tag               = 'HeaderSubtitle'
    }
    [void]$statusPanel.Children.Add($headerSubtitle)

    $statusHeader.Child = $statusPanel
    [void]$mainPanel.Children.Add($statusHeader)

    $progressPanelResult = New-ProgressPanel -Colors $colors
    $progressPanel      = $progressPanelResult.Panel
    $progressActivities = $progressPanelResult.Activities
    $defaultProgressUI  = $progressPanelResult.DefaultUI
    $progressBar        = $progressPanelResult.ProgressBar
    $createProgressUI   = $progressPanelResult.CreateProgressUI
    [System.Windows.Controls.DockPanel]::SetDock($progressPanel, 'Bottom')

    [void]$mainPanel.Children.Add($progressPanel)

    $tabControl = [System.Windows.Controls.TabControl]@{
        Margin          = [System.Windows.Thickness]::new(12)
        Background      = [System.Windows.Media.Brushes]::Transparent
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
    }

    # Spinner overlay covers the empty tab area until the first record lands.
    $loadingPanel = [System.Windows.Controls.Grid]@{
        Background = ConvertTo-UiBrush $colors.WindowBg
        Margin     = [System.Windows.Thickness]::new(12)
    }
    $loadingStack = [System.Windows.Controls.StackPanel]@{
        HorizontalAlignment = 'Center'
        VerticalAlignment   = 'Center'
    }
    $loadingSpinner = New-UiLoadingSpinner -Size 32 -Color $colors.Accent
    $loadingSpinner.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    [void]$loadingStack.Children.Add($loadingSpinner)
    $loadingLabel = [System.Windows.Controls.TextBlock]@{
        Text                = 'Running...'
        FontSize            = 14
        Foreground          = ConvertTo-UiBrush $colors.SecondaryText
        HorizontalAlignment = 'Center'
    }
    [void]$loadingStack.Children.Add($loadingLabel)
    [void]$loadingPanel.Children.Add($loadingStack)

    # Stack the tab control and the spinner overlay in a single cell so they overlap.
    $contentGrid = [System.Windows.Controls.Grid]::new()
    [void]$contentGrid.Children.Add($tabControl)
    [void]$contentGrid.Children.Add($loadingPanel)
    [System.Windows.Controls.Panel]::SetZIndex($loadingPanel, 100)

    [void]$mainPanel.Children.Add($contentGrid)

    $consoleResult                = New-ConsoleTabFull -Colors $colors
    $consoleTab                   = $consoleResult.Tab
    $consoleTextBox               = $consoleResult.TextBox
    $consoleParagraph             = $consoleResult.Paragraph
    $autoScrollCheckbox           = $consoleResult.AutoScrollCheckbox
    $pinToTopCheckbox             = $consoleResult.PinToTopCheckbox
    $consoleColorMap              = $consoleResult.ConsoleColorMap
    $rawColorMap                  = $consoleResult.RawColorMap
    $appendConsoleText            = $consoleResult.AppendConsoleText
    $appendState                  = $consoleResult.AppendState
    $consoleFindState             = $consoleResult.FindState
    $highlightRunMatches          = $consoleResult.HighlightRunMatches

    # Pin checkbox flips the window's Topmost - useful when running against a list of items in another window and the output needs to stay visible.
    $pinToTopCheckbox.Add_Checked({ $window.Topmost = $true }.GetNewClosure())
    $pinToTopCheckbox.Add_Unchecked({ $window.Topmost = $false }.GetNewClosure())

    [void]$tabControl.Items.Add($consoleTab)

    # Errors tab is built on first error - building upfront slows window show on every action.
    $errorsTabState = @{
        Built       = $false
        Tab         = $null
        Container   = $null
        DataGrid    = $null
        List        = $null
        TotalErrors = 0
    }

    $ensureErrorsTab = {
        if ($errorsTabState.Built) { return }
        $errorsTabState.Built = $true

        $result                   = New-ErrorsTab -Colors $colors
        $errorsTabState.Tab       = $result.Tab
        $errorsTabState.Container = $result.Container
        $errorsTabState.DataGrid  = $result.DataGrid
        $errorsTabState.List      = $result.List

        $detailsParams = @{
            Colors       = $colors
            Container    = $result.Container
            DataGrid     = $result.DataGrid
            ErrorsList   = $result.List
            CopyButton   = $result.CopyButton
            ExportButton = $result.ExportButton
        }
        Add-ErrorDetailsPanel @detailsParams

        [void]$tabControl.Items.Add($result.Tab)
    }.GetNewClosure()

    # Warnings tab same deal - lazy built on the first warning record.
    $warningsTabState = @{
        Built     = $false
        Tab       = $null
        TextBox   = $null
        Paragraph = $null
    }

    $ensureWarningsTab = {
        if ($warningsTabState.Built) { return }
        $warningsTabState.Built = $true

        $result                       = New-WarningsTabFull -Colors $colors
        $warningsTabState.Tab         = $result.Tab
        $warningsTabState.TextBox     = $result.TextBox
        $warningsTabState.Paragraph   = $result.Paragraph

        [void]$tabControl.Items.Add($result.Tab)
    }.GetNewClosure()

    # outputData is the flat list for the single type case. outputDataByType buckets results by type name when the script returns multiple types - drives the tab per type Results view.
    $outputData = [System.Collections.Generic.List[object]]::new()
    $outputDataByType = [ordered]@{}
    $warningCount = @{ Value = 0 }
    $state = @{
        IsCancelled          = $false
        WindowRevealed       = $false
        LoadingHidden        = $false
        DebugEnabled         = $debugEnabled
        IsAutoScrolling      = $false
        HostQueueTimer       = $null
        ConsoleFindState     = $consoleFindState
        HighlightRunMatches  = $highlightRunMatches
        ConsoleTextBox       = $consoleTextBox
        AutoScrollCheckbox   = $autoScrollCheckbox
    }

    # Drops the spinner overlay once content arrives. One shot via $state.LoadingHidden.
    $hideLoading = {
        if (!$state.LoadingHidden) {
            $state.LoadingHidden = $true
            $loadingPanel.Visibility = 'Collapsed'
        }
    }.GetNewClosure()

    # In HideUntilContent mode the window starts invisible - reveal it on the first record.
    $revealWindow = {
        if (!$state.WindowRevealed -and $showWindowOnData) {
            $state.WindowRevealed = $true

            # Route to the UI thread - AsyncExecutor events come from a background runspace.
            # Titlebar theming attaches via the Loaded event registered earlier.
            $window.Dispatcher.Invoke([Action]{
                $window.Show()
                $window.Activate()
            })

            Write-Verbose "Window revealed due to content"
        }
    }.GetNewClosure()

    # Unread badges per tab. Cleared on tab activation.
    $tabNotifications = @{
        Console  = @{
            TotalCount  = 0
            UnreadCount = 0
        }
        Errors   = @{
            TotalCount  = 0
            UnreadCount = 0
        }
        Warnings = @{
            TotalCount  = 0
            UnreadCount = 0
        }
    }

    # Tab switch clears that tab's unread badge - same UX as Slack/Discord channels.
    $tabControl.Add_SelectionChanged({
        param($sender, $eventArgs)
        $selectedTab = $sender.SelectedItem

        if ($selectedTab -eq $consoleTab) {
            $tabNotifications.Console.UnreadCount = 0
            $consoleTab.Header = "Console"
        }
        elseif ($errorsTabState.Tab -and $selectedTab -eq $errorsTabState.Tab) {
            $tabNotifications.Errors.UnreadCount = 0
            # TotalErrors, not List.Count - the New-ErrorsTab filter rebuilds List, so its Count reads as "matching the filter" midstream.
            $eCount = [int]$errorsTabState.TotalErrors
            $errorsTabState.Tab.Header = if ($eCount -gt 0) { "Errors ($eCount)" } else { "Errors" }
        }
        elseif ($warningsTabState.Tab -and $selectedTab -eq $warningsTabState.Tab) {
            $tabNotifications.Warnings.UnreadCount = 0
            $warningsTabState.Tab.Header = if ($warningCount.Value -gt 0) { "Warnings ($($warningCount.Value))" } else { "Warnings" }
        }
    }.GetNewClosure())

    # .Count, not truthiness - Match() returns an empty but truthy collection when the member is missing.
    if ($Executor.PSObject.Properties.Match('UiDispatcher').Count -gt 0) {
        $Executor.UiDispatcher = $window.Dispatcher
    }

    # Batched AsyncExecutor handlers - one invoke per record floods the UI thread under heavy output.
    $Executor.add_OnHostBatch({
        param([System.Collections.Generic.List[PsUi.HostOutputRecord]]$records)
        if ($state.IsCancelled) { return }
        if ($null -eq $records -or $records.Count -eq 0) { return }

        if ($HideUntilContent) { & $revealWindow }

        & $hideLoading
        if ($consoleTab.Visibility -ne 'Visible') {
            $consoleTab.Visibility   = 'Visible'
            $tabControl.SelectedItem = $consoleTab
        }

        # Skip per record scroll - one scroll at the end of the batch is enough.
        $lastIndex = $records.Count - 1
        for ($i = 0; $i -lt $records.Count; $i++) {
            $record     = $records[$i]
            $skipScroll = $i -lt $lastIndex
            [void](Add-OutputLine -Record $record -AppendFunc $appendConsoleText -ColorMap $consoleColorMap -RawColorMap $rawColorMap -State $appendState -SkipScroll:$skipScroll)
        }

        if ($tabControl.SelectedItem -ne $consoleTab) {
            $tabNotifications.Console.UnreadCount += $records.Count
            $consoleTab.Header = "Console (+$($tabNotifications.Console.UnreadCount))"
        }
    }.GetNewClosure())

    # Queue + poll instead of per event UI invokes - log parsers can emit thousands of lines a second and per event routing pegs the UI thread before output catches up. Pipeline mode does the same for large result sets, not just Write-Host floods.
    $Executor.UseQueueMode = $true
    $Executor.UsePipelineQueueMode = $true

    # 50ms tick - looks live without flooding the UI thread.
    $state.HostQueueTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $state.HostQueueTimer.Interval = [TimeSpan]::FromMilliseconds(50)

    $state.HostQueueTimer.Add_Tick({
        if ($state.IsCancelled) { return }

        # 100 at a time keeps each tick fast enough that the UI never blocks visibly.
        $pipelineItems = $Executor.DrainPipelineQueue(100)
        $hadPipeline   = $null -ne $pipelineItems -and $pipelineItems.Count -gt 0
        if ($hadPipeline) {
            foreach ($item in $pipelineItems) {
                if ($null -eq $item) { continue }

                # ErrorRecords go to the Errors tab, not the Results grid.
                if ($item -is [System.Management.Automation.ErrorRecord]) {
                    & $ensureErrorsTab
                    $displayRecord = New-ErrorDisplayRecord -ErrorRecord $item
                    [void]$errorsTabState.List.Add($displayRecord)
                    $errorsTabState.TotalErrors = [int]$errorsTabState.TotalErrors + 1

                    if ($errorsTabState.Tab.Visibility -eq 'Collapsed') {
                        $errorsTabState.Tab.Visibility = 'Visible'
                    }

                    if ($tabControl.SelectedItem -ne $errorsTabState.Tab) {
                        $tabNotifications.Errors.UnreadCount++
                        $errorsTabState.Tab.Header = "Errors ($([int]$errorsTabState.TotalErrors)) +$($tabNotifications.Errors.UnreadCount)"
                    }
                    else {
                        $errorsTabState.Tab.Header = "Errors ($([int]$errorsTabState.TotalErrors))"
                    }
                    continue
                }

                # Bucket by type name. Multi type returns get a tab per bucket downstream.
                $displayName = Get-CleanTypeName -Item $item
                if (!$outputDataByType.Contains($displayName)) {
                    $outputDataByType[$displayName] = [System.Collections.Generic.List[object]]::new()
                }
                [void]$outputDataByType[$displayName].Add($item)
                [void]$outputData.Add([psobject]$item)
            }
        }

        $records = $Executor.DrainHostQueue(100)
        $hadHost = $null -ne $records -and $records.Count -gt 0

        # Both queues empty and the run is done; nothing left to poll.
        if (!$hadPipeline -and !$hadHost -and $state.ExecutorDone) {
            $state.HostQueueTimer.Stop()
            return
        }
        if (!$hadHost) { return }

        if ($HideUntilContent) { & $revealWindow }
        & $hideLoading
        if ($consoleTab.Visibility -ne 'Visible') {
            $consoleTab.Visibility   = 'Visible'
            $tabControl.SelectedItem = $consoleTab
        }

        foreach ($record in $records) {
            [void](Add-OutputLine -Record $record -AppendFunc $appendConsoleText -ColorMap $consoleColorMap -RawColorMap $rawColorMap -State $appendState -SkipScroll)
        }

        # One scroll at the end of the batch, not per record.
        if ($autoScrollCheckbox.IsChecked) {
            $state.IsAutoScrolling = $true
            $consoleTextBox.ScrollToEnd()
            $state.IsAutoScrolling = $false
        }

        if ($tabControl.SelectedItem -ne $consoleTab) {
            $tabNotifications.Console.UnreadCount += $records.Count
            $consoleTab.Header = "Console (+$($tabNotifications.Console.UnreadCount))"
        }
    }.GetNewClosure())

    $state.HostQueueTimer.Start()

    # Fallback per message handler for the rare case where queue mode isn't available.
    $Executor.add_OnHost({
        param($record)
        if ($state.DebugEnabled) { [Console]::WriteLine("DEBUG: OnHost fired - record type: " + $record.GetType().Name) }

        if ($state.IsCancelled) { return }

        $message   = $null
        $fgColor   = $null
        $bgColor   = $null
        $noNewLine = $false
        if ($record -is [PsUi.HostOutputRecord]) {
            $message   = $record.Message
            $fgColor   = $record.ForegroundColor
            $bgColor   = $record.BackgroundColor
            $noNewLine = $record.NoNewLine
        }
        else {
            $message = "$record"
        }

        if ($state.DebugEnabled) { [Console]::WriteLine("DEBUG: OnHost message: " + $message) }

        # Empty message = "just add a newline". IsNullOrWhiteSpace would eat valid space only output.
        if ([string]::IsNullOrEmpty($message)) {
            if (!$noNewLine) {
                & $appendConsoleText "`n" $null $null -NoNewLine -State $appendState
            }
            return
        }

        if ($HideUntilContent) { & $revealWindow }
        & $hideLoading
        if ($consoleTab.Visibility -ne 'Visible') {
            $consoleTab.Visibility = 'Visible'
            $tabControl.SelectedItem = $consoleTab
        }

        $cleanOutput = $message -replace '\x1b\[[0-9;]*m', ''
        $fgBrush = $null
        if ($null -ne $fgColor -and $consoleColorMap.ContainsKey($fgColor)) {
            $fgBrush = $consoleColorMap[$fgColor]
        }
        $bgBrush = $null
        if ($null -ne $bgColor -and $consoleColorMap.ContainsKey($bgColor)) {
            $bgBrush = $consoleColorMap[$bgColor]
        }

        # Direct append. The queue mode handler above usually beats this one to the records.
        if ($noNewLine) { & $appendConsoleText $cleanOutput $fgBrush $bgBrush -NoNewLine -State $appendState  }
        else {  & $appendConsoleText $cleanOutput $fgBrush $bgBrush -State $appendState }
    }.GetNewClosure())

    $Executor.add_OnError({
        param($errorRecord)
        try {
            if ($state.IsCancelled) { return }
            if ($null -eq $errorRecord) { return }

            if ($state.DebugEnabled) {
                $errMsg = if ($errorRecord.Message) { $errorRecord.Message } else { $errorRecord.ToString() }
                $errType = if ($errorRecord.Exception) { $errorRecord.Exception.GetType().Name } else { 'Unknown' }
                [Console]::WriteLine("[DEBUG] OnError: $errType - $errMsg")
                if ($errorRecord.ScriptStackTrace) { [Console]::WriteLine("[DEBUG]   StackTrace: $($errorRecord.ScriptStackTrace -replace "`n", " -> ")")  }
            }

            if ($HideUntilContent) { & $revealWindow }

            & $hideLoading

            & $ensureErrorsTab

            if ($errorsTabState.Tab.Visibility -eq 'Collapsed') {
                $errorsTabState.Tab.Visibility = 'Visible'

                # Errors tab grabs focus only when nothing else is showing yet, otherwise the script's output should stay focused
                if ($consoleTab.Visibility -eq 'Collapsed') { $tabControl.SelectedItem = $errorsTabState.Tab }
            }

            $displayRecord = New-ErrorDisplayRecord -ErrorRecord $errorRecord
            [void]$errorsTabState.List.Add($displayRecord)
            $errorsTabState.TotalErrors = [int]$errorsTabState.TotalErrors + 1

            # Echo to the console tab too - red text so it stands out from regular output.
            $displayMessage = if ($errorRecord.Message) { $errorRecord.Message } else { $errorRecord.ToString() }
            & $appendConsoleText "[ERROR] $displayMessage" ([System.Windows.Media.Brushes]::IndianRed) $null -State $appendState

            if ($tabControl.SelectedItem -ne $errorsTabState.Tab) {
                $tabNotifications.Errors.UnreadCount++
                $errorsTabState.Tab.Header = "Errors ($([int]$errorsTabState.TotalErrors)) +$($tabNotifications.Errors.UnreadCount)"
            }
            else { $errorsTabState.Tab.Header = "Errors ($([int]$errorsTabState.TotalErrors))" }

            if ($tabControl.SelectedItem -ne $consoleTab) {
                $tabNotifications.Console.UnreadCount++
                $consoleTab.Header = "Console (+$($tabNotifications.Console.UnreadCount))"
            }
        }
        catch {
            # Eat any failure in the error handler itself - the handler crashing the window is worse than losing the diagnostic.
            [Console]::Error.WriteLine("[PsUi] OnError handler failed: $($_.Exception.Message)")
        }
    }.GetNewClosure())

    $Executor.add_OnWarning({
        param($warningMessage)
        if ($state.IsCancelled) { return }
        if ([string]::IsNullOrWhiteSpace($warningMessage)) { return }

        if ($HideUntilContent) { & $revealWindow }

        & $hideLoading

        & $ensureWarningsTab

        if ($warningsTabState.Tab.Visibility -eq 'Collapsed') {
            $warningsTabState.Tab.Visibility = 'Visible'
            # Same focus rule as the errors tab - only steal focus if nothing else is showing.
            $errorsTabVisible = $errorsTabState.Tab -and $errorsTabState.Tab.Visibility -ne 'Collapsed'
            if ($consoleTab.Visibility -eq 'Collapsed' -and !$errorsTabVisible) {
                $tabControl.SelectedItem = $warningsTabState.Tab
            }
        }

        # Warnings also stream to Console below, so the tab needs to be visible regardless.
        if ($consoleTab.Visibility -ne 'Visible') { $consoleTab.Visibility = 'Visible' }

        $warningCount.Value++
        $warningRun = [System.Windows.Documents.Run]::new("$warningMessage`n")
        [void]$warningsTabState.Paragraph.Inlines.Add($warningRun)
        $warningsTabState.TextBox.ScrollToEnd()
        & $appendConsoleText "[WARNING] $warningMessage" ([System.Windows.Media.Brushes]::DarkGoldenrod) $null -State $appendState

        if ($tabControl.SelectedItem -ne $warningsTabState.Tab) {
            $tabNotifications.Warnings.UnreadCount++
            $warningsTabState.Tab.Header = "Warnings ($($warningCount.Value)) +$($tabNotifications.Warnings.UnreadCount)"
        }
        else { $warningsTabState.Tab.Header = "Warnings ($($warningCount.Value))" }

        if ($tabControl.SelectedItem -ne $consoleTab) {
            $tabNotifications.Console.UnreadCount++
            $consoleTab.Header = "Console (+$($tabNotifications.Console.UnreadCount))"
        }
    }.GetNewClosure())

    $Executor.add_OnVerbose({
        param($verboseMessage)
        if ($state.IsCancelled) { return }
        if ([string]::IsNullOrWhiteSpace($verboseMessage)) { return }
        & $appendConsoleText "[VERBOSE] $verboseMessage" ([System.Windows.Media.Brushes]::Gray) $null -State $appendState
    }.GetNewClosure())

    # OnDebug goes straight to the real console, not the UI. For diagnosing the async machinery itself, where touching the UI would just hide the bug.
    $Executor.add_OnDebug({
        param($debugMessage)
        if ($state.IsCancelled) { return }
        if ([string]::IsNullOrWhiteSpace($debugMessage)) { return }
        if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] $debugMessage") }
    }.GetNewClosure())

    $Executor.add_OnProgress({
        param($progressRecord)
        if ($state.IsCancelled) { return }
        if ($null -eq $progressRecord) { return }

        $actId    = $progressRecord.ActivityId
        $parentId = $progressRecord.ParentActivityId
        $isChild  = ($parentId -ge 0)

        # Completed records tear down the bar except ActivityId 0, which is permanent.
        if ($progressRecord.RecordType -eq [System.Management.Automation.ProgressRecordType]::Completed) {
            if ($progressActivities.ContainsKey($actId)) {
                if ($actId -ne 0) {
                    $ui = $progressActivities[$actId]
                    [void]$progressPanel.Children.Remove($ui.Container)
                    $progressActivities.Remove($actId)
                }
                else { $progressActivities[0].Active = $false }

                # Hide once no real activity remains. Count non default bars, not total, since the permanent Id 0 bar stays in the dictionary after it completes - but a mid run Id 0 has to hold the panel open too, or a secondary activity finishing first collapses it out from under the running default bar.
                $activeCount  = @($progressActivities.Keys | Where-Object { $_ -ne 0 }).Count
                $idZeroActive = $progressActivities.ContainsKey(0) -and $progressActivities[0].Active
                if ($activeCount -eq 0 -and !$idZeroActive) {
                    $progressPanel.Visibility = 'Collapsed'
                }
            }
            return
        }

        if (!$progressActivities.ContainsKey($actId)) {
            if ($actId -eq 0) {
                # ActivityId 0 reuses the prebuilt default bar instead of creating a new one.
                $progressActivities[0] = $defaultProgressUI
                [void]$progressPanel.Children.Add($defaultProgressUI.Container)
            }
            else {
                $newUI = & $createProgressUI $actId $isChild
                $progressActivities[$actId] = $newUI

                # Slot child activities under their parent so the visual hierarchy mirrors Write-Progress.
                if ($isChild -and $progressActivities.ContainsKey($parentId)) {
                    $parentIdx = $progressPanel.Children.IndexOf($progressActivities[$parentId].Container)
                    $progressPanel.Children.Insert($parentIdx + 1, $newUI.Container)
                }
                else {
                    [void]$progressPanel.Children.Add($newUI.Container)
                }
            }
        }

        $progressPanel.Visibility = 'Visible'

        if ($actId -eq 0) { $progressActivities[0].Active = $true }

        $ui = $progressActivities[$actId]

        if ($progressRecord.PercentComplete -ge 0) {
            $ui.Bar.IsIndeterminate = $false
            $ui.Bar.Value           = $progressRecord.PercentComplete
        }
        else { $ui.Bar.IsIndeterminate = $true }

        $statusParts = [System.Collections.Generic.List[string]]::new()

        if (![string]::IsNullOrWhiteSpace($progressRecord.Activity)) { $statusParts.Add($progressRecord.Activity) }

        if (![string]::IsNullOrWhiteSpace($progressRecord.StatusDescription)) { $statusParts.Add($progressRecord.StatusDescription) }

        if (![string]::IsNullOrWhiteSpace($progressRecord.CurrentOperation)) { $statusParts.Add("($($progressRecord.CurrentOperation))") }

        if ($progressRecord.SecondsRemaining -gt 0) {
            $remaining = [TimeSpan]::FromSeconds($progressRecord.SecondsRemaining)
            if ($remaining.TotalHours -ge 1) {
                $statusParts.Add("[{0:h\:mm\:ss} remaining]" -f $remaining)
            }
            else { $statusParts.Add("[{0:m\:ss} remaining]" -f $remaining) }
        }

        $ui.Label.Text = $statusParts -join " - "

        # Top level activities also drive the window title so it's readable from the taskbar.
        if (!$isChild) { $headerTitle.Text = "$Title - $($progressRecord.StatusDescription)" }
    }.GetNewClosure())

    $Executor.add_OnPipelineOutput({
        param($pipelineObject)
        if ($state.IsCancelled) { return }
        if ($null -eq $pipelineObject) { return }

        if ($outputData.Count -eq 0) {
            if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] First pipeline output: $($pipelineObject.GetType().FullName)") }
        }
        elseif ($state.DebugEnabled -and ($outputData.Count % 100) -eq 0) {
            [Console]::WriteLine("[DEBUG] Pipeline output count: $($outputData.Count)")
        }

        # Same bucketing as the queue mode path - tab per type Results view.
        $displayName = Get-CleanTypeName -Item $pipelineObject
        if (!$outputDataByType.Contains($displayName)) {
            if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] New result type bucket: $displayName") }
            $outputDataByType[$displayName] = [System.Collections.Generic.List[object]]::new()
        }
        [void]$outputDataByType[$displayName].Add($pipelineObject)
        [void]$outputData.Add([psobject]$pipelineObject)
    }.GetNewClosure())

    # Hooks the blocking input host APIs (Read-Host / Get-Credential / $host.UI.Prompt) to themed dialogs so a UI app doesn't hang on console input that never arrives.
    $inputParams = @{
        Executor        = $Executor
        Window          = $window
        ClearHostAction = { $consoleParagraph.Inlines.Clear() }.GetNewClosure()
        DebugEnabled    = $debugEnabled
    }
    Add-InputProviders @inputParams

    # The completion handler context. Everything Invoke-OnCompleteHandler needs to swap the window from "running" to "done" lives in here so the callback closure stays small.
    $onCompleteContext = @{
        Executor            = $Executor
        State               = $state
        OutputData          = $outputData
        OutputDataByType    = $outputDataByType
        ConsoleColorMap     = $consoleColorMap
        RawColorMap         = $rawColorMap
        AppendConsoleText   = $appendConsoleText
        AppendState         = $appendState
        ConsoleParagraph    = $consoleParagraph
        ConsoleTextBox      = $consoleTextBox
        ConsoleTab          = $consoleTab
        AutoScrollCheckbox  = $autoScrollCheckbox
        ErrorsTabState      = $errorsTabState
        EnsureErrorsTab     = $ensureErrorsTab
        WarningsTabState    = $warningsTabState
        EnsureWarningsTab   = $ensureWarningsTab
        WarningCount        = $warningCount
        TabControl          = $tabControl
        TabNotifications    = $tabNotifications
        Window              = $window
        HideLoading         = $hideLoading
        LoadingPanel        = $loadingPanel
        LoadingSpinner      = $loadingSpinner
        LoadingStack        = $loadingStack
        LoadingLabel        = $loadingLabel
        ProgressBar         = $progressBar
        ProgressPanel       = $progressPanel
        HeaderTitle         = $headerTitle
        Title               = $Title
        HideUntilContent    = $HideUntilContent
        StatusSpinner       = $statusSpinner
        StatusSuccess       = $statusSuccess
        StatusWarning       = $statusWarning
        StatusIndicator     = $statusIndicator
        Colors              = $colors
        ResultActions       = $ResultActions
        SingleSelect        = $SingleSelect
        VarValues           = $varValues
        FuncDefs            = $funcDefs
        CapturedModules     = $capturedModules
        DefaultProgressUI   = $defaultProgressUI
        ParentWindow        = $ParentWindow
        ScrollToTop         = $ScrollToTop
    }
    & $writeDebug "OnComplete context prepared, hooking events..."

    # Script can set window title via $host.UI.RawUI.WindowTitle
    $Executor.add_OnWindowTitle({
        param($title)
        if ($state.IsCancelled) { return }
        if ([string]::IsNullOrWhiteSpace($title)) {
            $headerSubtitle.Visibility = 'Collapsed'
        }
        else {
            $headerSubtitle.Text       = "- $title"
            $headerSubtitle.Visibility = 'Visible'
        }
    }.GetNewClosure())

    $Executor.add_OnComplete({
        & $writeDebug "OnComplete handler fired"
        $state.ExecutorDone = $true

        # Run is over, drop the ActiveExecutor claim now. Dispose stays in the Closing handler, result actions and captures still read this AsyncExecutor.
        if ($currentSession -and [object]::ReferenceEquals($currentSession.ActiveExecutor, $Executor)) { $currentSession.ActiveExecutor = $null }
        Invoke-OnCompleteHandler -Context $onCompleteContext
    }.GetNewClosure())

    # Cancellation flips the spinner to a warning icon and drops a coloured message into the console so it's clear something stopped the script - not just that it returned nothing.
    $Executor.add_OnCancelled({
        & $writeDebug "OnCancelled handler fired"
        $state.ExecutorDone = $true
        if ($currentSession -and [object]::ReferenceEquals($currentSession.ActiveExecutor, $Executor)) { $currentSession.ActiveExecutor = $null }

        $statusSpinner.Visibility = 'Collapsed'
        $statusWarning.Visibility = 'Visible'
        $headerTitle.Text         = "$Title - Cancelled"

        $progressPanel.Visibility = 'Collapsed'

        $cancelPara = [System.Windows.Documents.Paragraph]::new()
        $cancelRun  = [System.Windows.Documents.Run]::new("Operation cancelled by user")
        $cancelRun.Foreground = [System.Windows.Media.Brushes]::Orange
        [void]$cancelPara.Inlines.Add($cancelRun)
        [void]$consoleTextBox.Document.Blocks.Add($cancelPara)
        $consoleTextBox.ScrollToEnd()
    }.GetNewClosure())

    $capturedSession = $currentSession

    $window.Add_Closing({
        param($sender, $eventArgs)

        # If a script is still running, confirm before closing - and keep any open Read-Host dialog alive so Esc inside that dialog still cancels normally.
        if ($Executor.IsRunning) {
            # Drop Topmost first so the confirm dialog doesn't open behind this window.
            $wasPinned = $window.Topmost
            if ($wasPinned) { $window.Topmost = $false }

            $confirm = Show-UiConfirmDialog -Title "Cancel Operation" -Message "A task is still running. Cancel and close?"
            if (!$confirm) {
                if ($wasPinned) { $window.Topmost = $true }
                $eventArgs.Cancel = $true
                [PsUi.KeyCaptureDialog]::BringToFront()
                return
            }
        }

        # Past the confirm gate - tear down any open Read-Host / Get-Credential dialog so the script's blocking input call returns and the runspace can wind down.
        [PsUi.KeyCaptureDialog]::CancelInputSession()
        [PsUi.KeyCaptureDialog]::CloseCurrentDialog()

        & $writeDebug "Window closing..."

        # Skip the cancel call on a finished script - otherwise the cancelled UI overlays on top of a successful completion, which reads like a fake error.
        if ($Executor.IsRunning) {
            $state.IsCancelled = $true
            $Executor.Cancel()
        }

        # Hand dialog parenting back to whoever had it. Otherwise the next dialog tries to centre on a closed window and ends up off screen.
        if ($capturedSession -and $capturedSession.ActiveDialogParent -eq $window) {  $capturedSession.ActiveDialogParent = $null   }

        # DispatcherTimer keeps a strong reference to its tick handler - leak the window without an explicit Stop() and the closure pins everything it captured.
        if ($state.HostQueueTimer -and $state.HostQueueTimer.IsEnabled) {  $state.HostQueueTimer.Stop()  }

        # Drop the UiDispatcher reference - otherwise late OnHost events from the runspace try to route back to a dead window and throw.
        if ($Executor.PSObject.Properties.Match('UiDispatcher').Count -gt 0) { $Executor.UiDispatcher = $null  }

        if ($Executor.PSObject.Methods.Match('Dispose').Count -gt 0) {
            try { $Executor.Dispose() } catch { Write-Debug "Suppressed dispose error: $_" }
        }

        # Window closed mid-run still gives up the claim.
        if ($capturedSession -and [object]::ReferenceEquals($capturedSession.ActiveExecutor, $Executor)) { $capturedSession.ActiveExecutor = $null }
    }.GetNewClosure())

    # HideUntilContent path: kick off execution now, only show the window if data shows up.
    if ($showWindowOnData) {
        & $writeDebug "HideUntilContent mode - starting execution without showing window"

        if ($Capture) {  $Executor.CaptureVariables = [string[]]$Capture }

        # Don't wait for window load - in this mode the window won't load until data shows up.
        if ($Action) {
            & $writeDebug "Starting ExecuteAsync - Action: $($Action.ToString().Length) chars"
            try {
                $Executor.ExecuteAsync($Action, $Parameters, $varValues, $funcDefs, $capturedModules, $debugEnabled)
                & $writeDebug "ExecuteAsync called successfully"
            }
            catch {
                & $writeDebug "ExecuteAsync FAILED: $($_.Exception.Message)"
                Write-Verbose "Failed to start async execution: $_"
            }
        }

        # Keep dispatching messages until the script's done AND the window's been closed (if it was ever shown). Exit out early on cancellation (usually the window closing itself)
        while (!$state.IsCancelled -and ($Executor.IsRunning -or ($state.WindowRevealed -and $window.IsVisible))) {
            [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{ } )
            Start-Sleep -Milliseconds 10
        }

        # Final check. Scripts that finish faster than the 50ms tick leave output sitting in the queues. Peek the counts only, the OnComplete drain owns the queues, and draining them here threw the pipeline items away (a fast object only action revealed an empty window with no Results tab).
        if (!$state.WindowRevealed) {
            $hasOutput = ($Executor.HostQueueCount -gt 0) -or ($Executor.PipelineQueueCount -gt 0)

            if ($hasOutput) {
                $state.WindowRevealed = $true

                & $hideLoading
                $consoleTab.Visibility = 'Visible'
                $tabControl.SelectedItem = $consoleTab

                # Header flip is cosmetic, so skip it if the template's already down
                try {
                    $statusSpinner.Visibility = 'Collapsed'
                    $statusSuccess.Visibility = 'Visible'
                    $headerTitle.Text         = "$Title - Complete"
                }
                catch { }

                $window.Opacity = 1
                $window.Show()
                $window.Activate()

                try {
                    $currentColors = Get-ThemeColors
                    $headerBg      = [System.Windows.Media.ColorConverter]::ConvertFromString($currentColors.HeaderBackground)
                    $headerFg      = [System.Windows.Media.ColorConverter]::ConvertFromString($currentColors.HeaderForeground)
                    [PsUi.WindowManager]::SetTitleBarColor($window, $headerBg, $headerFg)
                }
                catch { Write-Debug "Title bar theming failed: $_" }

                # Block until the window closes - same dispatch loop as the main one, just slower tick.
                while (!$state.IsCancelled -and $window.IsVisible) {
                    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
                        [System.Windows.Threading.DispatcherPriority]::Background,
                        [Action]{ }
                    )
                    Start-Sleep -Milliseconds 50
                }
            }
        }

        # Never revealed window still holds its runspace + UI thread. Close it explicitly so they release.
        if (!$state.WindowRevealed) {
            & $writeDebug "No output produced - closing hidden window to prevent leak"
            # Close can race a window that's already torn down - nothing left to do then.
            try { $window.Close() } catch { }
        }

        & $writeDebug "HideUntilContent execution complete"
    }
    else {
        # Standard path: show the window first, kick off execution once it's loaded.
        $window.Opacity = 0

        # CaptureVariables has to be set before the Add_Loaded closure captures the AsyncExecutor.
        if ($Capture) { $Executor.CaptureVariables = [string[]]$Capture }

        $window.Add_Loaded({
            Start-UIFadeIn -Window $window

            # Title bar colors come from the theme. Windows API call, separate from the control brushes.
            try {
                $currentColors = Get-ThemeColors
                $headerBg      = [System.Windows.Media.ColorConverter]::ConvertFromString($currentColors.HeaderBackground)
                $headerFg      = [System.Windows.Media.ColorConverter]::ConvertFromString($currentColors.HeaderForeground)
                [PsUi.WindowManager]::SetTitleBarColor($window, $headerBg, $headerFg)
            }
            catch { Write-Verbose "Failed to set title bar colors: $_" }

            if ($Action) {
                & $writeDebug "Starting ExecuteAsync - Action: $($Action.ToString().Length) chars"
                try {
                    $Executor.ExecuteAsync($Action, $Parameters, $varValues, $funcDefs, $capturedModules, $debugEnabled)
                    & $writeDebug "ExecuteAsync called successfully"
                }
                catch {
                    & $writeDebug "ExecuteAsync FAILED: $($_.Exception.Message)"
                    Write-Verbose "Failed to start async execution: $_"
                }
            }
            else { & $writeDebug "No Action provided" }
        }.GetNewClosure())

        & $writeDebug "Calling ShowDialog..."
        try {
            if ($NoWait) {
                # NoWait skips ShowDialog so the parent runspace keeps going. The calling script hooks the returned window's Closed event for any cleanup that needs to wait it out.
                $window.Show()
                return $window
            }
            else { [void]$window.ShowDialog() }
        }
        catch { Write-Warning "Output window error: $($_.Exception.Message)" }
    }
}
