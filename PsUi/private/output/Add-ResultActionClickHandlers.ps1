function Add-ResultActionClickHandlers {
    <#
    .SYNOPSIS
        Wires up click handlers for ResultAction buttons with async execution.
        These buttons appear in Show-UIOutput for relevent results.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Captures,
        
        [Parameter(Mandatory)]
        [System.Collections.IList]$ActionButtons,
        
        [System.Windows.Controls.Primitives.Popup]$DropdownPopup
    )
    
    # Unpack captures for closure access
    # There may be a better/cleaner way to do this, but this works.
    # It is neccessary because the closure created for the click handler
    # needs to capture the current values of these variables, not references.
    $capturedWindow            = $Captures.Window
    $capturedState             = $Captures.State
    $capturedDataGrid          = $Captures.DataGrid
    $capturedResultsBorder     = $Captures.ResultsBorder
    $capturedConsoleTab        = $Captures.ConsoleTab
    $capturedConsoleParagraph  = $Captures.ConsoleParagraph
    $capturedConsoleColorMap   = $Captures.ConsoleColorMap
    $capturedAppendConsoleText = $Captures.AppendConsoleText
    $capturedAppendState       = $Captures.AppendState
    $capturedErrorsTab         = $Captures.ErrorsTab
    $capturedErrorsList        = $Captures.ErrorsList
    $capturedWarningsTab       = $Captures.WarningsTab
    $capturedWarningsTextBox   = $Captures.WarningsTextBox
    $capturedWarningCount      = $Captures.WarningCount
    $capturedProgressPanel     = $Captures.ProgressPanel
    $capturedProgressBar       = $Captures.ProgressBar
    $capturedProgressLabel     = $Captures.ProgressLabel
    $capturedHeaderTitle       = $Captures.HeaderTitle
    $capturedTitle             = $Captures.Title
    $capturedTabControl        = $Captures.TabControl
    $capturedTabNotifications  = $Captures.TabNotifications
    $capturedErrorCount        = $Captures.ErrorCount
    $capturedStatusSpinner     = $Captures.StatusSpinner
    $capturedStatusSuccess     = $Captures.StatusSuccess
    $capturedStatusWarning     = $Captures.StatusWarning
    $capturedStatusIndicator   = $Captures.StatusIndicator
    $capturedVarValues         = $Captures.VarValues
    $capturedFuncDefs          = $Captures.FuncDefs
    $capturedModules           = $Captures.Modules
    $capturedDropdownPopup     = $DropdownPopup
    
    # Capture the Input Dialog command to ensure it's available inside the closure
    $capturedShowInput = Get-Command Show-UiInputDialog -ErrorAction SilentlyContinue
    
    foreach ($actionButton in $ActionButtons) {
        $actionButton.Add_Click({
            try {
                # Close dropdown popup if this is a menu item click
                if ($capturedDropdownPopup -and $capturedDropdownPopup.IsOpen) {
                    $capturedDropdownPopup.IsOpen = $false
                }
                
                $def = $this.Tag
                if ($capturedState.DebugEnabled) { [Console]::WriteLine("[DEBUG] ResultAction clicked: '$($def.Text)'") }
                
                # Get the correct DataGrid - might be in a sub-TabControl for multi-type results
                $activeGrid = $capturedDataGrid
                if ($capturedResultsBorder.Child -is [System.Windows.Controls.TabControl]) {
                    $subTabControl = $capturedResultsBorder.Child
                    $selectedTab = $subTabControl.SelectedItem
                    if ($selectedTab -and $selectedTab.Content -is [System.Windows.Controls.DataGrid]) {
                        $activeGrid = $selectedTab.Content
                    }
                }
                
                $selected = @($activeGrid.SelectedItems)
                if ($capturedState.DebugEnabled) { [Console]::WriteLine("[DEBUG]   Selected items: $($selected.Count)") }
                
                if ($selected.Count -eq 0) {
                    Show-UiMessageDialog -Message "Please select one or more items first." -Title "No Selection" -Icon "Info"
                    return
                }
                
                # Show confirmation if required
                if ($def.Confirm) {
                    $msg = $def.Confirm -f $selected.Count
                    if ($capturedState.DebugEnabled) { [Console]::WriteLine("[DEBUG]   Showing confirmation: $msg") }
                    $result = Show-UiConfirmDialog -Title "Confirm Action" -Message $msg -ConfirmText "Yes" -CancelText "No"
                    if (!$result) {
                        if ($capturedState.DebugEnabled) { [Console]::WriteLine("[DEBUG]   User cancelled") }
                        return
                    }
                }
                
                # Create async executor for action
                $actionExecutor = [PsUi.AsyncExecutor]::new()
                $actionExecutor.UiDispatcher = $capturedWindow.Dispatcher
                
                # Store executor in session for Stop-UiAsync cancellation
                $actionSession = [PsUi.SessionManager]::Current
                if ($actionSession) { $actionSession.ActiveExecutor = $actionExecutor }
                
                # Input provider for Read-Host
                $actionExecutor.InputProvider = {
                    param($PromptText)
                    try {
                        $msg = if (![string]::IsNullOrWhiteSpace($PromptText)) { $PromptText } else { "The running action is requesting input." }
                        
                        if ($capturedShowInput) {
                            return & $capturedShowInput -Title "Action Input Required" -Prompt $msg
                        }
                        return Show-UiInputDialog -Title "Action Input Required" -Prompt $msg
                    }
                    catch {
                        return ""
                    }
                }
                
                # Secure input provider for Read-Host -AsSecureString
                $actionExecutor.SecureInputProvider = {
                    param($PromptText)
                    $secureInput = $null
                    try {
                        $msg = if (![string]::IsNullOrWhiteSpace($PromptText)) { $PromptText } else { "The running action is requesting a password." }
                        
                        if ($capturedShowInput) {
                            $secureInput = & $capturedShowInput -Title "Secure Input Required" -Prompt $msg -Password
                        }
                        else {
                            $secureInput = Show-UiInputDialog -Title "Secure Input Required" -Prompt $msg -Password
                        }
                    }
                    catch {
                        return [System.Security.SecureString]::new()
                    }
                    
                    if ($secureInput) {
                        if ($secureInput -is [System.Security.SecureString]) { return $secureInput }
                        return ConvertTo-SecureString $secureInput -AsPlainText -Force
                    }
                    return [System.Security.SecureString]::new()
                }
                
                # Choice Provider for -Confirm prompts
                $actionExecutor.ChoiceProvider = {
                    param($Caption, $Message, $Choices, $DefaultChoice)
                    return Show-UiChoiceDialog -Caption $Caption -Message $Message -Choices $Choices -DefaultChoice $DefaultChoice
                }
                
                # Credential Provider for Get-Credential
                $actionExecutor.CredentialProvider = {
                    param($Caption, $Message, $UserName, $TargetName)
                    return Show-UiCredentialDialog -Caption $Caption -Message $Message -UserName $UserName -TargetName $TargetName
                }
                
                # Prompt Provider for multi-field prompts
                $actionExecutor.PromptProvider = {
                    param($Caption, $Message, $Descriptions)
                    return Show-UiPromptDialog -Caption $Caption -Message $Message -Descriptions $Descriptions
                }
                
                # ReadKey Provider - handles "Press any key" patterns
                $actionExecutor.ReadKeyProvider = {
                    param($Options)
                    Show-UiMessageDialog -Title "Continue" -Message "Press OK to continue..." -Buttons OK -Icon Info
                }
                
                # ClearHost Provider - clears just the Console tab
                $actionExecutor.ClearHostProvider = {
                    $capturedConsoleParagraph.Inlines.Clear()
                }
                
                # Store selected items, grid, and action name in $capturedState for OnComplete access
                $capturedState.ActiveGrid = $activeGrid
                $capturedState.SelectedItems = @($selected | ForEach-Object { $_ })
                $capturedState.ActionName = $def.Text
                
                # Find and store the Action Status column reference
                $capturedState.StatusColumn = $null
                for ($i = 0; $i -lt $activeGrid.Columns.Count; $i++) {
                    if ($activeGrid.Columns[$i].Header -eq 'Action Status') {
                        $capturedState.StatusColumn = $activeGrid.Columns[$i]
                        break
                    }
                }
                
                # Set "Running" status directly on each cell
                if ($capturedState.StatusColumn) {
                    foreach ($item in $capturedState.SelectedItems) {
                        $row = $activeGrid.ItemContainerGenerator.ContainerFromItem($item)
                        if ($row) {
                            $cell = $capturedState.StatusColumn.GetCellContent($row)
                            if ($cell -is [System.Windows.Controls.TextBlock]) {
                                $cell.Text = "Running ($($def.Text))..."
                            }
                        }
                    }
                }
                
                # Show spinner in header status indicator
                $capturedStatusSpinner.Visibility = 'Visible'
                $capturedStatusSuccess.Visibility = 'Collapsed'
                $capturedStatusWarning.Visibility = 'Collapsed'
                $capturedStatusIndicator.ClearValue([System.Windows.FrameworkElement]::ToolTipProperty)
                $capturedStatusIndicator.ToolTip = "Running ($($def.Text))..."
                
                # Track error state and item count in $capturedState
                $capturedState.ActionErrorOccurred = $false
                $capturedState.ActionErrorCount = 0
                $capturedState.ItemCount = $capturedState.SelectedItems.Count
                $capturedState.CurrentItemIndex = 0
                
                # Update UI - hide progress bar initially
                $capturedHeaderTitle.Text = "$capturedTitle - Running: $($def.Text)..."
                $capturedProgressPanel.Visibility = 'Collapsed'
                
                # Show Console tab and switch to it
                if ($capturedConsoleTab.Visibility -ne 'Visible') {
                    $capturedConsoleTab.Visibility = 'Visible'
                }
                $capturedTabControl.SelectedItem = $capturedConsoleTab
                
                & $capturedAppendConsoleText "`n--- Action: $($def.Text) ---" ([System.Windows.Media.Brushes]::DarkCyan) -State $capturedAppendState
                
                # Wire up OnHost handler for console output
                $actionExecutor.add_OnHost({
                    param($record)
                    if ($capturedState.IsCancelled) { return }
                    
                    $message = $null
                    $fgColor = $null
                    if ($record -is [PsUi.HostOutputRecord]) {
                        $message = $record.Message
                        $fgColor = $record.ForegroundColor
                    }
                    else {
                        $message = "$record"
                    }
                    
                    if ([string]::IsNullOrEmpty($message)) { return }
                    
                    if ($capturedConsoleTab.Visibility -ne 'Visible') {
                        $capturedConsoleTab.Visibility = 'Visible'
                    }
                    if ($capturedTabControl.SelectedItem -ne $capturedConsoleTab) {
                        $capturedTabControl.SelectedItem = $capturedConsoleTab
                    }
                    
                    $brush = $null
                    if ($null -ne $fgColor -and $capturedConsoleColorMap.ContainsKey($fgColor)) {
                        $brush = $capturedConsoleColorMap[$fgColor]
                    }
                    
                    & $capturedAppendConsoleText $message $brush -State $capturedAppendState
                })
                
                # Wire up OnError handler
                $actionExecutor.add_OnError({
                    param($errorRecord)
                    if ($capturedState.IsCancelled) { return }
                    if ($null -eq $errorRecord) { return }
                    
                    if ($capturedErrorsTab.Visibility -eq 'Collapsed') {
                        $capturedErrorsTab.Visibility = 'Visible'
                    }
                    
                    $displayRecord = New-ErrorDisplayRecord -ErrorRecord $errorRecord
                    [void]$capturedErrorsList.Add($displayRecord)
                    
                    $displayMessage = if ($errorRecord.Message) { $errorRecord.Message } else { $errorRecord.ToString() }
                    & $capturedAppendConsoleText "[ERROR] $displayMessage" ([System.Windows.Media.Brushes]::IndianRed) -State $capturedAppendState
                    
                    $capturedState.ActionErrorOccurred = $true
                    $capturedState.ActionErrorCount++
                    
                    # Update badges
                    if ($capturedTabControl.SelectedItem -ne $capturedErrorsTab) {
                        $capturedTabNotifications.Errors.UnreadCount++
                        $totalErrors = $capturedErrorCount + $capturedState.ActionErrorCount
                        $capturedErrorsTab.Header = "Errors ($totalErrors) +$($capturedTabNotifications.Errors.UnreadCount)"
                    }
                    
                    if ($capturedTabControl.SelectedItem -ne $capturedConsoleTab) {
                        $capturedTabNotifications.Console.UnreadCount++
                        $capturedConsoleTab.Header = "Console (+$($capturedTabNotifications.Console.UnreadCount))"
                    }
                })
                
                # Wire up OnProgress handler
                $actionExecutor.add_OnProgress({
                    param($progressRecord)
                    if ($capturedState.IsCancelled) { return }
                    if ($null -eq $progressRecord) { return }
                    
                    if ($progressRecord.RecordType -eq [System.Management.Automation.ProgressRecordType]::Completed) {
                        $capturedProgressPanel.Visibility = 'Collapsed'
                        return
                    }
                    
                    $capturedProgressPanel.Visibility = 'Visible'
                    
                    if ($progressRecord.PercentComplete -ge 0) {
                        $capturedProgressBar.IsIndeterminate = $false
                        $capturedProgressBar.Value = $progressRecord.PercentComplete
                    }
                    else {
                        $capturedProgressBar.IsIndeterminate = $true
                    }
                    
                    $statusParts = [System.Collections.Generic.List[string]]::new()
                    $statusParts.Add($capturedState.ActionName)
                    if (![string]::IsNullOrWhiteSpace($progressRecord.Activity)) {
                        $statusParts.Add($progressRecord.Activity)
                    }
                    if (![string]::IsNullOrWhiteSpace($progressRecord.StatusDescription)) {
                        $statusParts.Add($progressRecord.StatusDescription)
                    }
                    if (![string]::IsNullOrWhiteSpace($progressRecord.CurrentOperation)) {
                        $statusParts.Add("($($progressRecord.CurrentOperation))")
                    }
                    $capturedProgressLabel.Text = $statusParts -join " - "
                })
                
                # Wire up OnComplete handler
                $actionExecutor.add_OnComplete({
                    if ($capturedState.IsCancelled) { return }
                    
                    if ($capturedState.DebugEnabled) { 
                        [Console]::WriteLine("[DEBUG] ResultAction '$($capturedState.ActionName)' complete - Errors: $($capturedState.ActionErrorCount)")
                    }
                    
                    $capturedProgressPanel.Visibility = 'Collapsed'
                    $capturedHeaderTitle.Text = "$capturedTitle - Complete"
                    & $capturedAppendConsoleText "--- Action Complete ---" ([System.Windows.Media.Brushes]::DarkCyan) -State $capturedAppendState
                    
                    $capturedStatusSpinner.Visibility = 'Collapsed'
                    $capturedStatusIndicator.ClearValue([System.Windows.FrameworkElement]::ToolTipProperty)
                    if ($capturedState.ActionErrorOccurred) {
                        $capturedStatusWarning.Visibility = 'Visible'
                        $capturedStatusSuccess.Visibility = 'Collapsed'
                        $capturedStatusIndicator.ToolTip = "Complete ($($capturedState.ActionName)) with errors"
                    }
                    else {
                        $capturedStatusSuccess.Visibility = 'Visible'
                        $capturedStatusWarning.Visibility = 'Collapsed'
                        $capturedStatusIndicator.ToolTip = "Complete ($($capturedState.ActionName))"
                    }
                    
                    # Update status column cells
                    if ($capturedState.StatusColumn) {
                        foreach ($item in $capturedState.SelectedItems) {
                            $statusText = if ($capturedState.ActionErrorOccurred) {
                                "Complete with errors ($($capturedState.ActionName))"
                            }
                            else {
                                "Complete ($($capturedState.ActionName))"
                            }
                            
                            $row = $capturedState.ActiveGrid.ItemContainerGenerator.ContainerFromItem($item)
                            if ($row) {
                                $cell = $capturedState.StatusColumn.GetCellContent($row)
                                if ($cell -is [System.Windows.Controls.TextBlock]) {
                                    $cell.Text = $statusText
                                }
                            }
                        }
                    }
                })
                
                # Build and execute the action script
                $selectedObjects = @($selected)
                $actionScriptString = $def.Action.ToString()
                
                $actionScript = {
                    param($SelectedItems, $ActionScriptString)
                    
                    try {
                        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                        $global:OutputEncoding = [System.Text.Encoding]::UTF8
                    }
                    catch {
                        Write-Verbose "Failed to set UTF-8 encoding, using default: $_"
                    }
                    
                    $Selected = $SelectedItems
                    if (![string]::IsNullOrWhiteSpace($ActionScriptString)) {
                        $ActionScriptBlock = [scriptblock]::Create($ActionScriptString)
                        if ($Selected.Count -eq 1) {
                            $_ = $Selected[0]
                        }
                        else {
                            $_ = $Selected
                        }
                        & $ActionScriptBlock $Selected
                    }
                }
                
                $actionParams = @{
                    SelectedItems      = $selectedObjects
                    ActionScriptString = $actionScriptString
                }
                
                $actionExecutor.ExecuteAsync($actionScript, $actionParams, $capturedVarValues, $capturedFuncDefs, $capturedModules)
            }
            catch {
                Show-UiMessageDialog -Message "Error: $($_.Exception.Message)" -Title "Error" -Icon "Error"
            }
        }.GetNewClosure())
    }
}
