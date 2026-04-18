
# TODO: this function is pushing 1200 lines. Would benefit from splitting the
# queue-polling loop and the window construction into separate helpers, but the
# shared closures make that tricky. Revisit when we have time to untangle it.
function Show-UiOutput {
    <#
    .SYNOPSIS
        Displays streaming async output in a themed WPF window.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PsUi.AsyncExecutor]$Executor,

        [string]$Title = 'Output',

        [ValidateRange(400, 2000)]
        [int]$Width = 900,

        [ValidateRange(300, 1500)]
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
        
        # Variable names to capture from runspace after execution
        [string[]]$Capture,

        [switch]$HideUntilContent,
        
        # Non-blocking mode - output window doesn't block parent
        [switch]$NoWait,

        # Scroll console to top on completion instead of staying at bottom
        [switch]$ScrollToTop,
        
        # Legacy parameter - ignored but kept for backward compatibility
        [switch]$Streaming
    )

    # Delegate to streaming output implementation
    $streamingParams = @{
        Executor                  = $Executor
        Title                     = $Title
        Width                     = $Width
        Height                    = $Height
        ParentWindow              = $ParentWindow
        Action                    = $Action
        Parameters                = $Parameters
        ResultActions             = $ResultActions
        SingleSelect              = $SingleSelect
        LinkedVariables           = $LinkedVariables
        LinkedFunctions           = $LinkedFunctions
        LinkedModules             = $LinkedModules
        LinkedVariableValues      = $LinkedVariableValues
        LinkedFunctionDefinitions = $LinkedFunctionDefinitions
        Capture                   = $Capture
        HideUntilContent          = $HideUntilContent
        NoWait                    = $NoWait
        ScrollToTop               = $ScrollToTop
    }
    Show-StreamingOutput @streamingParams
}

function Show-StreamingOutput {
    <#
    .SYNOPSIS
        Displays streaming output from async execution with tabbed interface.
    #>
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

    # Prepare linked variables/functions using helper
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

    # Get theme colors with fallback defaults
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

    # Create window using helper (returns custom chrome window with title bar)
    $customLogo = if ($currentSession) { $currentSession.CustomLogo } else { $null }
    $window = New-OutputWindow -Title $Title -Width $Width -Height $Height -ParentWindow $ParentWindow -Colors $colors -CustomLogo $customLogo

    # Get references from window tag
    $windowRefs   = $window.Tag
    $shadowBorder = $windowRefs.ShadowBorder
    $mainGrid     = $windowRefs.MainGrid
    $contentArea  = $windowRefs.ContentArea
    $titleText    = $windowRefs.TitleText

    # For HideUntilContent: window will not be shown until data arrives
    $showWindowOnData = $HideUntilContent

    # Set this output window as the active dialog parent so dialogs center on it
    if ($currentSession) {
        $currentSession.ActiveDialogParent = $window
    }

    # Add global dispatcher exception handler to prevent crashes
    # Exceptions are logged for debugging but marked as handled to avoid app termination
    $window.Dispatcher.add_UnhandledException({
        param($sender, $eventArgs)
        # Log to console — Write-Debug is invisible unless $DebugPreference is set
        [Console]::WriteLine("[PsUi] Dispatcher exception: $($eventArgs.Exception.Message)")
        [Console]::WriteLine("[PsUi] Stack: $($eventArgs.Exception.StackTrace)")
        $eventArgs.Handled = $true
    }.GetNewClosure())

    # Escape key cancels the running async operation with confirmation
    $executorRef = $Executor
    $window.add_PreviewKeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            if ($executorRef -and $executorRef.IsRunning) {
                # Unpin temporarily so the confirm dialog doesn't open behind us
                $wasPinned = $window.Topmost
                if ($wasPinned) {
                    $window.Topmost = $false
                    Start-Sleep -Milliseconds 500
                }

                $confirm = Show-UiConfirmDialog -Title "Cancel Operation" -Message "Are you sure you want to cancel the running task?"
                if ($wasPinned) { $window.Topmost = $true }

                # Re-check after dialog - task may have finished while waiting
                if ($confirm -and $executorRef.IsRunning) {
                    # Close any open ReadKey dialog before cancelling
                    [PsUi.KeyCaptureDialog]::CloseCurrentDialog()
                    $executorRef.Cancel()
                }
                $eventArgs.Handled = $true
            }
        }
    }.GetNewClosure())

    # Build content panel (goes into the ContentArea)
    $mainPanel = [System.Windows.Controls.DockPanel]::new()
    $contentArea.Child = $mainPanel

    # Create status header bar (below title bar, shows running status)
    $statusHeader = [System.Windows.Controls.Border]@{
        Background = ConvertTo-UiBrush $colors.HeaderBackground
        Padding    = [System.Windows.Thickness]::new(16, 8, 16, 8)
        Tag        = 'HeaderBorder'
    }
    [System.Windows.Controls.DockPanel]::SetDock($statusHeader, 'Top')

    # Status header content - horizontal with status indicator and title
    $statusPanel = [System.Windows.Controls.StackPanel]@{ Orientation = 'Horizontal' }

    # Create status indicator using helper
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
    
    # Subtitle for script-set window title ($host.UI.RawUI.WindowTitle)
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

    # Create progress panel using helper
    $progressPanelResult = New-ProgressPanel -Colors $colors
    $progressPanel      = $progressPanelResult.Panel
    $progressActivities = $progressPanelResult.Activities
    $defaultProgressUI  = $progressPanelResult.DefaultUI
    $progressBar        = $progressPanelResult.ProgressBar
    $createProgressUI   = $progressPanelResult.CreateProgressUI
    [System.Windows.Controls.DockPanel]::SetDock($progressPanel, 'Bottom')

    [void]$mainPanel.Children.Add($progressPanel)

    # Create tab control
    $tabControl = [System.Windows.Controls.TabControl]@{
        Margin          = [System.Windows.Thickness]::new(12)
        Background      = [System.Windows.Media.Brushes]::Transparent
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
    }

    # Create loading spinner overlay (shown until content arrives)
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

    # Create a grid to hold both tab control and loading overlay
    $contentGrid = [System.Windows.Controls.Grid]::new()
    [void]$contentGrid.Children.Add($tabControl)
    [void]$contentGrid.Children.Add($loadingPanel)
    [System.Windows.Controls.Panel]::SetZIndex($loadingPanel, 100)

    [void]$mainPanel.Children.Add($contentGrid)

    # Create Console tab using helper (includes toolbar, find, context menu, etc.)
    $consoleResult                = New-ConsoleTabFull -Colors $colors
    $consoleTab                   = $consoleResult.Tab
    $consoleContainer             = $consoleResult.Container
    $consoleTextBox               = $consoleResult.TextBox
    $consoleDocument              = $consoleResult.Document
    $consoleParagraph             = $consoleResult.Paragraph
    $autoScrollCheckbox           = $consoleResult.AutoScrollCheckbox
    $wrapCheckbox                 = $consoleResult.WrapCheckbox
    $pinToTopCheckbox             = $consoleResult.PinToTopCheckbox
    $consoleColorMap              = $consoleResult.ConsoleColorMap
    $rawColorMap                  = $consoleResult.RawColorMap
    $appendConsoleText            = $consoleResult.AppendConsoleText
    $appendState                  = $consoleResult.AppendState
    $consoleFindState             = $consoleResult.FindState
    $highlightRunMatches          = $consoleResult.HighlightRunMatches

    # Keep window on top when Pin checkbox is toggled
    $pinToTopCheckbox.Add_Checked({ $window.Topmost = $true }.GetNewClosure())
    $pinToTopCheckbox.Add_Unchecked({ $window.Topmost = $false }.GetNewClosure())

    [void]$tabControl.Items.Add($consoleTab)

    # Lazy Errors tab — deferred until first error arrives for faster startup
    $errorsTabState = @{
        Built     = $false
        Tab       = $null
        Container = $null
        DataGrid  = $null
        List      = $null
    }

    $ensureErrorsTab = {
        if ($errorsTabState.Built) { return }
        $errorsTabState.Built = $true

        $result                   = New-ErrorsTab -Colors $colors
        $errorsTabState.Tab       = $result.Tab
        $errorsTabState.Container = $result.Container
        $errorsTabState.DataGrid  = $result.DataGrid
        $errorsTabState.List      = $result.List

        # Wire up details panel and toolbar buttons
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

    # Lazy Warnings tab — deferred until first warning arrives
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

    # State tracking for the output window
    # outputData is flat list for single-type, outputDataByType buckets multi-type
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

    # Hide loading spinner and show first tab with content
    $hideLoading = {
        if (!$state.LoadingHidden) {
            $state.LoadingHidden = $true
            $loadingPanel.Visibility = 'Collapsed'
        }
    }.GetNewClosure()

    # Reveal the hidden window when content arrives (HideUntilContent mode)
    $revealWindow = {
        if (!$state.WindowRevealed -and $showWindowOnData) {
            $state.WindowRevealed = $true
            
            # Show the window for the first time - must use dispatcher since events fire on background thread
            # Titlebar theming is handled by Loaded event registered earlier
            $window.Dispatcher.Invoke([Action]{
                $window.Show()
                $window.Activate()
            })
            
            Write-Verbose "Window revealed due to content"
        }
    }.GetNewClosure()

    # Tab notification state
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

    # Add SelectionChanged handler to TabControl to clear badges
    $tabControl.Add_SelectionChanged({
        param($sender, $eventArgs)
        $selectedTab = $sender.SelectedItem

        # Clear unread count for the selected tab and update header
        if ($selectedTab -eq $consoleTab) {
            $tabNotifications.Console.UnreadCount = 0
            $consoleTab.Header = "Console"
        }
        elseif ($errorsTabState.Tab -and $selectedTab -eq $errorsTabState.Tab) {
            $tabNotifications.Errors.UnreadCount = 0
            $eCount = if ($errorsTabState.List) { $errorsTabState.List.Count } else { 0 }
            $errorsTabState.Tab.Header = if ($eCount -gt 0) { "Errors ($eCount)" } else { "Errors" }
        }
        elseif ($warningsTabState.Tab -and $selectedTab -eq $warningsTabState.Tab) {
            $tabNotifications.Warnings.UnreadCount = 0
            $warningsTabState.Tab.Header = if ($warningCount.Value -gt 0) { "Warnings ($($warningCount.Value))" } else { "Warnings" }
        }
    }.GetNewClosure())

    if ($Executor.PSObject.Properties.Match('UiDispatcher')) {
        $Executor.UiDispatcher = $window.Dispatcher
    }

    # Wire up executor event handlers (batched to avoid dispatcher spam)
    $Executor.add_OnHostBatch({
        param([System.Collections.Generic.List[PsUi.HostOutputRecord]]$records)
        if ($state.IsCancelled) { return }
        if ($null -eq $records -or $records.Count -eq 0) { return }

        # Reveal window if in HideUntilContent mode
        if ($HideUntilContent) { & $revealWindow }

        # Show console tab and hide loading spinner
        & $hideLoading
        if ($consoleTab.Visibility -ne 'Visible') {
            $consoleTab.Visibility   = 'Visible'
            $tabControl.SelectedItem = $consoleTab
        }

        # Process all records in the batch, skipping scroll until the last one
        $lastIndex = $records.Count - 1
        for ($i = 0; $i -lt $records.Count; $i++) {
            $record    = $records[$i]
            $skipScrol = $i -lt $lastIndex
            [void](Add-OutputLine -Record $record -AppendFunc $appendConsoleText -ColorMap $consoleColorMap -RawColorMap $rawColorMap -State $appendState -SkipScroll:$skipScrol)
        }

        # Update badge if Console tab is not selected
        if ($tabControl.SelectedItem -ne $consoleTab) {
            $tabNotifications.Console.UnreadCount += $records.Count
            $consoleTab.Header = "Console (+$($tabNotifications.Console.UnreadCount))"
        }
    }.GetNewClosure())

    # Queue-based polling for high-volume output (avoids dispatcher flooding/saturation)
    $Executor.UseQueueMode = $true
    $Executor.UsePipelineQueueMode = $true  # Critical: prevents dispatcher saturation with large result sets

    $state.HostQueueTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $state.HostQueueTimer.Interval = [TimeSpan]::FromMilliseconds(50)  # Faster polling for smoother updates

    $state.HostQueueTimer.Add_Tick({
        if ($state.IsCancelled) { return }

        # Drain pipeline objects (batched to prevent UI saturation)
        $pipelineItems = $Executor.DrainPipelineQueue(100)
        if ($null -ne $pipelineItems -and $pipelineItems.Count -gt 0) {
            foreach ($item in $pipelineItems) {
                if ($null -eq $item) { continue }

                # Route ErrorRecords to Errors tab instead of Results
                if ($item -is [System.Management.Automation.ErrorRecord]) {
                    & $ensureErrorsTab
                    $displayRecord = New-ErrorDisplayRecord -ErrorRecord $item
                    [void]$errorsTabState.List.Add($displayRecord)
                    
                    if ($errorsTabState.Tab.Visibility -eq 'Collapsed') {
                        $errorsTabState.Tab.Visibility = 'Visible'
                    }
                    
                    # Update badge if Errors tab not selected
                    if ($tabControl.SelectedItem -ne $errorsTabState.Tab) {
                        $tabNotifications.Errors.UnreadCount++
                        $errorsTabState.Tab.Header = "Errors ($($errorsTabState.List.Count)) +$($tabNotifications.Errors.UnreadCount)"
                    }
                    else {
                        $errorsTabState.Tab.Header = "Errors ($($errorsTabState.List.Count))"
                    }
                    continue
                }

                # Bucket by type name for multi-type view
                $displayName = Get-CleanTypeName -Item $item
                if (!$outputDataByType.Contains($displayName)) {
                    $outputDataByType[$displayName] = [System.Collections.Generic.List[object]]::new()
                }
                [void]$outputDataByType[$displayName].Add($item)
                [void]$outputData.Add([psobject]$item)
            }
        }

        # Drain host output (console text)
        $records = $Executor.DrainHostQueue(100)
        if ($null -eq $records -or $records.Count -eq 0) { return }

        # Reveal window if in HideUntilContent mode
        if ($HideUntilContent) { & $revealWindow }
        & $hideLoading
        if ($consoleTab.Visibility -ne 'Visible') {
            $consoleTab.Visibility   = 'Visible'
            $tabControl.SelectedItem = $consoleTab
        }

        # Process each record and append to console output
        foreach ($record in $records) {
            [void](Add-OutputLine -Record $record -AppendFunc $appendConsoleText -ColorMap $consoleColorMap -RawColorMap $rawColorMap -State $appendState -SkipScroll)
        }

        # Single scroll at end of batch
        if ($autoScrollCheckbox.IsChecked) {
            $state.IsAutoScrolling = $true
            $consoleTextBox.ScrollToEnd()
            $state.IsAutoScrolling = $false
        }

        # Update badge if Console tab is not selected
        if ($tabControl.SelectedItem -ne $consoleTab) {
            $tabNotifications.Console.UnreadCount += $records.Count
            $consoleTab.Header = "Console (+$($tabNotifications.Console.UnreadCount))"
        }
    }.GetNewClosure())

    # Start the queue polling timer
    $state.HostQueueTimer.Start()

    # Fallback handler for individual messages when queue mode unavailable
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

        # Empty = "just add newline". Don't use IsNullOrWhiteSpace - spaces are valid output
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

        # Append directly to console (fallback path - rarely used when batch mode is active)
        if ($noNewLine) {
            & $appendConsoleText $cleanOutput $fgBrush $bgBrush -NoNewLine -State $appendState
        }
        else {
            & $appendConsoleText $cleanOutput $fgBrush $bgBrush -State $appendState
        }
    }.GetNewClosure())

    $Executor.add_OnError({
        param($errorRecord)
        try {
            if ($state.IsCancelled) { return }
            if ($null -eq $errorRecord) { return }
            
            # Log error details for debugging
            if ($state.DebugEnabled) {
                $errMsg = if ($errorRecord.Message) { $errorRecord.Message } else { $errorRecord.ToString() }
                $errType = if ($errorRecord.Exception) { $errorRecord.Exception.GetType().Name } else { 'Unknown' }
                [Console]::WriteLine("[DEBUG] OnError: $errType - $errMsg")
                if ($errorRecord.ScriptStackTrace) {
                    [Console]::WriteLine("[DEBUG]   StackTrace: $($errorRecord.ScriptStackTrace -replace "`n", " -> ")")
                }
            }

            # Reveal window if in HideUntilContent mode
            if ($HideUntilContent) {
                & $revealWindow
            }

            # Hide loading spinner
            & $hideLoading

            # Lazily build the Errors tab on first error
            & $ensureErrorsTab

            if ($errorsTabState.Tab.Visibility -eq 'Collapsed') {
                $errorsTabState.Tab.Visibility = 'Visible'
                # Select errors tab if nothing else is selected yet
                if ($consoleTab.Visibility -eq 'Collapsed') {
                    $tabControl.SelectedItem = $errorsTabState.Tab
                }
            }

            # Create and add error display record
            $displayRecord = New-ErrorDisplayRecord -ErrorRecord $errorRecord
            [void]$errorsTabState.List.Add($displayRecord)

            # Show in console tab too with red color
            $displayMessage = if ($errorRecord.Message) { $errorRecord.Message } else { $errorRecord.ToString() }
            & $appendConsoleText "[ERROR] $displayMessage" ([System.Windows.Media.Brushes]::IndianRed) $null -State $appendState

            # Update badges
            if ($tabControl.SelectedItem -ne $errorsTabState.Tab) {
                $tabNotifications.Errors.UnreadCount++
                $errorsTabState.Tab.Header = "Errors ($($errorsTabState.List.Count)) +$($tabNotifications.Errors.UnreadCount)"
            }
            else {
                $errorsTabState.Tab.Header = "Errors ($($errorsTabState.List.Count))"
            }

            # Also update console badge if not selected
            if ($tabControl.SelectedItem -ne $consoleTab) {
                $tabNotifications.Console.UnreadCount++
                $consoleTab.Header = "Console (+$($tabNotifications.Console.UnreadCount))"
            }
        }
        catch {
            # Log error handler failures for troubleshooting - don't let them crash the app
            [Console]::Error.WriteLine("[PsUi] OnError handler failed: $($_.Exception.Message)")
        }
    }.GetNewClosure())

    $Executor.add_OnWarning({
        param($warningMessage)
        if ($state.IsCancelled) { return }
        if ([string]::IsNullOrWhiteSpace($warningMessage)) { return }

        # Reveal window if in HideUntilContent mode
        if ($HideUntilContent) {
            & $revealWindow
        }

        # Hide loading spinner
        & $hideLoading

        # Lazily build the Warnings tab on first warning
        & $ensureWarningsTab

        if ($warningsTabState.Tab.Visibility -eq 'Collapsed') {
            $warningsTabState.Tab.Visibility = 'Visible'
            # Select warnings tab if nothing else is selected yet
            $errorsTabVisible = $errorsTabState.Tab -and $errorsTabState.Tab.Visibility -ne 'Collapsed'
            if ($consoleTab.Visibility -eq 'Collapsed' -and !$errorsTabVisible) {
                $tabControl.SelectedItem = $warningsTabState.Tab
            }
        }

        # Show console tab too since we append warnings there
        if ($consoleTab.Visibility -ne 'Visible') {
            $consoleTab.Visibility = 'Visible'
        }

        $warningCount.Value++
        $warningRun = [System.Windows.Documents.Run]::new("$warningMessage`n")
        [void]$warningsTabState.Paragraph.Inlines.Add($warningRun)
        $warningsTabState.TextBox.ScrollToEnd()
        & $appendConsoleText "[WARNING] $warningMessage" ([System.Windows.Media.Brushes]::DarkGoldenrod) $null -State $appendState

        # Update badges
        if ($tabControl.SelectedItem -ne $warningsTabState.Tab) {
            $tabNotifications.Warnings.UnreadCount++
            $warningsTabState.Tab.Header = "Warnings ($($warningCount.Value)) +$($tabNotifications.Warnings.UnreadCount)"
        }
        else {
            $warningsTabState.Tab.Header = "Warnings ($($warningCount.Value))"
        }

        # Also update console badge if not selected
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

    # Route debug stream output to main console (for troubleshooting async execution)
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

        # Completed records = time to tear down the progress bar
        if ($progressRecord.RecordType -eq [System.Management.Automation.ProgressRecordType]::Completed) {
            if ($progressActivities.ContainsKey($actId)) {
                if ($actId -ne 0) {
                    # Remove non-default progress bars
                    $ui = $progressActivities[$actId]
                    [void]$progressPanel.Children.Remove($ui.Container)
                    $progressActivities.Remove($actId)
                }

                # Hide progress panel when no active progress bars remain (or only default)
                if ($progressActivities.Count -le 1) {
                    $progressPanel.Visibility = 'Collapsed'
                }
            }
            return
        }

        # Get or create progress UI for this activity
        if (!$progressActivities.ContainsKey($actId)) {
            if ($actId -eq 0) {
                # Use the pre-created default progress UI for ActivityId 0
                $progressActivities[0] = $defaultProgressUI
                [void]$progressPanel.Children.Add($defaultProgressUI.Container)
            }
            else {
                # Create new progress UI for non-zero ActivityIds
                $newUI = & $createProgressUI $actId $isChild
                $progressActivities[$actId] = $newUI

                # Insert child activities after their parent, others at end
                if ($isChild -and $progressActivities.ContainsKey($parentId)) {
                    $parentIdx = $progressPanel.Children.IndexOf($progressActivities[$parentId].Container)
                    $progressPanel.Children.Insert($parentIdx + 1, $newUI.Container)
                }
                else {
                    [void]$progressPanel.Children.Add($newUI.Container)
                }
            }
        }

        # Always show progress panel when any progress is active
        $progressPanel.Visibility = 'Visible'

        $ui = $progressActivities[$actId]

        # Update progress bar value
        if ($progressRecord.PercentComplete -ge 0) {
            $ui.Bar.IsIndeterminate = $false
            $ui.Bar.Value           = $progressRecord.PercentComplete
        }
        else {
            $ui.Bar.IsIndeterminate = $true
        }

        # Build status text with activity, status, and optional time remaining
        $statusParts = [System.Collections.Generic.List[string]]::new()
        if (![string]::IsNullOrWhiteSpace($progressRecord.Activity)) {
            $statusParts.Add($progressRecord.Activity)
        }
        if (![string]::IsNullOrWhiteSpace($progressRecord.StatusDescription)) {
            $statusParts.Add($progressRecord.StatusDescription)
        }
        if (![string]::IsNullOrWhiteSpace($progressRecord.CurrentOperation)) {
            $statusParts.Add("($($progressRecord.CurrentOperation))")
        }
        if ($progressRecord.SecondsRemaining -gt 0) {
            $remaining = [TimeSpan]::FromSeconds($progressRecord.SecondsRemaining)
            if ($remaining.TotalHours -ge 1) {
                $statusParts.Add("[{0:h\:mm\:ss} remaining]" -f $remaining)
            }
            else {
                $statusParts.Add("[{0:m\:ss} remaining]" -f $remaining)
            }
        }
        $ui.Label.Text = $statusParts -join " - "

        # Update window title with primary (non-child) activity
        if (!$isChild) {
            $headerTitle.Text = "$Title - $($progressRecord.StatusDescription)"
        }
    }.GetNewClosure())

    $Executor.add_OnPipelineOutput({
        param($pipelineObject)
        if ($state.IsCancelled) { return }
        if ($null -eq $pipelineObject) { return }

        # Log first pipeline object and every 100th for debugging
        if ($outputData.Count -eq 0) {
            if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] First pipeline output: $($pipelineObject.GetType().FullName)") }
        }
        elseif ($state.DebugEnabled -and ($outputData.Count % 100) -eq 0) {
            [Console]::WriteLine("[DEBUG] Pipeline output count: $($outputData.Count)")
        }

        # Bucket by type name for multi-type view
        $displayName = Get-CleanTypeName -Item $pipelineObject
        if (!$outputDataByType.Contains($displayName)) {
            if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] New result type bucket: $displayName") }
            $outputDataByType[$displayName] = [System.Collections.Generic.List[object]]::new()
        }
        [void]$outputDataByType[$displayName].Add($pipelineObject)
        [void]$outputData.Add([psobject]$pipelineObject)
    }.GetNewClosure())

    # Configure all input providers for dialogs (Read-Host, Get-Credential, etc.)
    $inputParams = @{
        Executor        = $Executor
        Window          = $window
        ClearHostAction = { $consoleParagraph.Inlines.Clear() }.GetNewClosure()
        DebugEnabled    = $debugEnabled
    }
    Add-InputProviders @inputParams

    # Wire up execution completion callback
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
    & $writeDebug "OnComplete context prepared, wiring events..."

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
        Invoke-OnCompleteHandler -Context $onCompleteContext
    }.GetNewClosure())

    # Handle cancellation with visual feedback
    $Executor.add_OnCancelled({
        & $writeDebug "OnCancelled handler fired"
        
        # Stop spinner and show cancelled state
        $statusSpinner.Visibility = 'Collapsed'
        $statusWarning.Visibility = 'Visible'
        $headerTitle.Text         = "$Title - Cancelled"
        
        # Hide progress bar
        $progressPanel.Visibility = 'Collapsed'
        
        # Add cancelled message to console
        $cancelPara = [System.Windows.Documents.Paragraph]::new()
        $cancelRun  = [System.Windows.Documents.Run]::new("Operation cancelled by user")
        $cancelRun.Foreground = [System.Windows.Media.Brushes]::Orange
        [void]$cancelPara.Inlines.Add($cancelRun)
        [void]$consoleTextBox.Document.Blocks.Add($cancelPara)
        $consoleTextBox.ScrollToEnd()
    }.GetNewClosure())

    # Capture session for closure
    $capturedSession = $currentSession

    $window.Add_Closing({
        param($sender, $eventArgs)
        
        # If a task is running, ask for confirmation before closing
        # Keep ReadKey dialog open during confirmation so user can still cancel via Escape
        if ($Executor.IsRunning) {
            # Drop topmost before showing the confirm dialog
            $wasPinned = $window.Topmost
            if ($wasPinned) {
                $window.Topmost = $false
                Start-Sleep -Milliseconds 500
            }

            $confirm = Show-UiConfirmDialog -Title "Cancel Operation" -Message "A task is still running. Cancel and close?"
            if (!$confirm) {
                if ($wasPinned) { $window.Topmost = $true }
                $eventArgs.Cancel = $true
                # Bring the ReadKey dialog back to front (it may have been hidden behind confirm dialog)
                [PsUi.KeyCaptureDialog]::BringToFront()
                return
            }
            # Task may have finished while dialog was open
        }
        
        # User confirmed (or no task running) - now cancel the input session
        # This closes any open ReadKey dialog and stops the script
        [PsUi.KeyCaptureDialog]::CancelInputSession()
        [PsUi.KeyCaptureDialog]::CloseCurrentDialog()
        
        & $writeDebug "Window closing..."
        
        # Only cancel if still running - avoids overlaying cancelled visuals on completed task
        if ($Executor.IsRunning) {
            $state.IsCancelled = $true
            $Executor.Cancel()
        }

        # Clear active dialog parent so future dialogs don't try to center on closed window
        if ($capturedSession -and $capturedSession.ActiveDialogParent -eq $window) {
            $capturedSession.ActiveDialogParent = $null
        }

        # Stop the host queue timer to prevent memory leak and post-close ticks
        if ($state.HostQueueTimer -and $state.HostQueueTimer.IsEnabled) {
            $state.HostQueueTimer.Stop()
        }

        # Clear the dispatcher reference to prevent further UI marshaling
        if ($Executor.PSObject.Properties.Match('UiDispatcher')) {
            $Executor.UiDispatcher = $null
        }

        # Dispose to clean up resources
        if ($Executor.PSObject.Methods.Match('Dispose')) {
            try { $Executor.Dispose() } catch { Write-Debug "Suppressed executor dispose error: $_" }
        }
    }.GetNewClosure())

    # HideUntilContent mode: start execution now, show window only if data arrives
    if ($showWindowOnData) {
        & $writeDebug "HideUntilContent mode - starting execution without showing window"
        
        # Set capture variables if specified
        if ($Capture) {
            $Executor.CaptureVariables = [string[]]$Capture
        }
        
        # Start async execution immediately (not waiting for window to load)
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
        
        # Process WPF messages until execution completes AND window is closed (if shown)
        # The loop continues while: executor running OR (window was revealed AND still visible)
        # Also break if cancellation was requested (e.g., window closing)
        while (!$state.IsCancelled -and ($Executor.IsRunning -or ($state.WindowRevealed -and $window.IsVisible))) {
            [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
                [System.Windows.Threading.DispatcherPriority]::Background,
                [Action]{ }
            )
            Start-Sleep -Milliseconds 10
        }
        
        # Final queue drain: fast scripts may finish before timer ticks, leaving output in queue
        # Pending output should still reveal the window even if the script raced ahead
        if (!$state.WindowRevealed) {
            $pendingRecords = $Executor.DrainHostQueue(1000)
            $pendingPipeline = $Executor.DrainPipelineQueue(1000)
            
            $hasOutput = (
                ($null -ne $pendingRecords -and $pendingRecords.Count -gt 0) -or
                ($null -ne $pendingPipeline -and $pendingPipeline.Count -gt 0)
            )
            
            if ($hasOutput) {
                $state.WindowRevealed = $true
                
                # Hide loading, show console with output
                & $hideLoading
                $consoleTab.Visibility = 'Visible'
                $tabControl.SelectedItem = $consoleTab
                
                # Process pending host output
                if ($pendingRecords -and $pendingRecords.Count -gt 0) {
                    foreach ($record in $pendingRecords) {
                        [void](Add-OutputLine -Record $record -AppendFunc $appendConsoleText -ColorMap $consoleColorMap -RawColorMap $rawColorMap -State $appendState -SuppressErrors)
                    }
                }
                
                # Update status to complete
                try {
                    $statusSpinner.Visibility = 'Collapsed'
                    $statusSuccess.Visibility = 'Visible'
                    $headerTitle.Text = "$Title - Complete"
                } catch { <# UI may be unavailable #> }
                
                # Show window - must set opacity since window was created with Opacity=0 for fade-in
                $window.Opacity = 1
                $window.Show()
                $window.Activate()
                
                # Apply title bar theming
                try {
                    $currentColors = Get-ThemeColors
                    $headerBg = [System.Windows.Media.ColorConverter]::ConvertFromString($currentColors.HeaderBackground)
                    $headerFg = [System.Windows.Media.ColorConverter]::ConvertFromString($currentColors.HeaderForeground)
                    [PsUi.WindowManager]::SetTitleBarColor($window, $headerBg, $headerFg)
                } catch { <# Theming failure is non-fatal #> }
                
                # Wait for user to close window
                while (!$state.IsCancelled -and $window.IsVisible) {
                    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
                        [System.Windows.Threading.DispatcherPriority]::Background,
                        [Action]{ }
                    )
                    Start-Sleep -Milliseconds 50
                }
            }
        }
        
        # Close hidden window if never shown (prevents leak)
        if (!$state.WindowRevealed) {
            & $writeDebug "No output produced - closing hidden window to prevent leak"
            try { $window.Close() } catch { <# Window may already be disposed #> }
        }
        
        & $writeDebug "HideUntilContent execution complete"
    }
    else {
        # Normal mode: show window immediately and start execution on load
        $window.Opacity = 0
        
        # Set capture variables if specified (before Add_Loaded closure captures executor)
        if ($Capture) {
            $Executor.CaptureVariables = [string[]]$Capture
        }

        $window.Add_Loaded({
            # Fade-in animation
            Start-UIFadeIn -Window $window

            # Apply title bar color customization
            try {
                $currentColors = Get-ThemeColors
                $headerBg      = [System.Windows.Media.ColorConverter]::ConvertFromString($currentColors.HeaderBackground)
                $headerFg      = [System.Windows.Media.ColorConverter]::ConvertFromString($currentColors.HeaderForeground)
                [PsUi.WindowManager]::SetTitleBarColor($window, $headerBg, $headerFg)
            }
            catch {
                Write-Verbose "Failed to set title bar colors: $_"
            }

            # Start async execution if action was provided
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
            else {
                & $writeDebug "No Action provided"
            }
        }.GetNewClosure())

        & $writeDebug "Calling ShowDialog..."
        try {
            if ($NoWait) {
                # Non-blocking mode - show window without blocking parent
                # Return window so caller can wire up Closed event for cleanup
                $window.Show()
                return $window
            }
            else {
                # Default modal behavior - blocks parent window
                [void]$window.ShowDialog()
            }
        }
        catch {
            Write-Warning "Output window error: $($_.Exception.Message)"
        }
    }
}
