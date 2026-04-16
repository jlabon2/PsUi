function Invoke-OnCompleteHandler {
    <#
    .SYNOPSIS
        Finalizes async output - builds Results tab, updates console, hides loading spinner.
        TO-DO: This does quite a bit, and probably needs to be refactored into smaller pieces in the future?
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    # Extract all context values for readability
    $Executor            = $Context.Executor
    $state               = $Context.State
    $outputData          = $Context.OutputData
    $outputDataByType    = $Context.OutputDataByType
    $consoleColorMap     = $Context.ConsoleColorMap
    $rawColorMap         = $Context.RawColorMap
    $appendConsoleText   = $Context.AppendConsoleText
    $appendState         = $Context.AppendState
    $consoleParagraph    = $Context.ConsoleParagraph
    $consoleTextBox      = $Context.ConsoleTextBox
    $consoleTab          = $Context.ConsoleTab
    $autoScrollCheckbox  = $Context.AutoScrollCheckbox
    $errorsTabState      = $Context.ErrorsTabState
    $ensureErrorsTab     = $Context.EnsureErrorsTab
    $warningsTabState    = $Context.WarningsTabState
    $ensureWarningsTab   = $Context.EnsureWarningsTab
    $warningCount        = $Context.WarningCount
    $tabControl          = $Context.TabControl
    $tabNotifications    = $Context.TabNotifications
    $window              = $Context.Window
    $hideLoading         = $Context.HideLoading
    $loadingPanel        = $Context.LoadingPanel
    $loadingSpinner      = $Context.LoadingSpinner
    $loadingStack        = $Context.LoadingStack
    $loadingLabel        = $Context.LoadingLabel
    $progressBar         = $Context.ProgressBar
    $progressPanel       = $Context.ProgressPanel
    $headerTitle         = $Context.HeaderTitle
    $Title               = $Context.Title
    $HideUntilContent    = $Context.HideUntilContent
    $ParentWindow        = $Context.ParentWindow
    $statusSpinner       = $Context.StatusSpinner
    $statusSuccess       = $Context.StatusSuccess
    $statusWarning       = $Context.StatusWarning
    $statusIndicator     = $Context.StatusIndicator
    $colors              = $Context.Colors
    $ResultActions       = $Context.ResultActions
    $SingleSelect        = $Context.SingleSelect
    $varValues           = $Context.VarValues
    $funcDefs            = $Context.FuncDefs
    $capturedModules     = $Context.CapturedModules
    $defaultProgressUI   = $Context.DefaultProgressUI

    try {
        if ($state.DebugEnabled) { 
            $eCount = if ($errorsTabState.List) { $errorsTabState.List.Count } else { 0 }
            [Console]::WriteLine("[DEBUG] OnComplete fired - Results: $($outputData.Count), Types: $($outputDataByType.Count), Errors: $eCount") 
        }

        if ($state.IsCancelled) { 
            if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] OnComplete cancelled - window was closed") }
            return 
        }

        # Stop queue polling timer and drain any remaining items
        if ($state.HostQueueTimer.IsEnabled) {
            $state.HostQueueTimer.Stop()
        }

        # Drain remaining pipeline queue items (critical for final batch)
        while ($Executor.PipelineQueueCount -gt 0) {
            $pipelineItems = $Executor.DrainPipelineQueue(500)
            if ($null -eq $pipelineItems -or $pipelineItems.Count -eq 0) { break }

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
                    continue
                }

                $displayName = Get-CleanTypeName -Item $item

                if (!$outputDataByType.Contains($displayName)) {
                    $outputDataByType[$displayName] = [System.Collections.Generic.List[object]]::new()
                }
                [void]$outputDataByType[$displayName].Add($item)
                [void]$outputData.Add([psobject]$item)
            }
        }

        if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Final drain - Results: $($outputData.Count), Types: $($outputDataByType.Count)") }
        if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Host queue remaining: $($Executor.HostQueueCount) items") }

        # Drain remaining host queue items
        $hostRecordsDrained = 0
        while ($Executor.HostQueueCount -gt 0) {
            $records = $Executor.DrainHostQueue(500)
            if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Drained " + $records.Count + " host records") }
            if ($null -eq $records -or $records.Count -eq 0) { break }

            foreach ($record in $records) {
                $hadContent = Add-OutputLine -Record $record -AppendFunc $appendConsoleText -ColorMap $consoleColorMap -RawColorMap $rawColorMap -State $appendState -SkipScroll
                if ($hadContent) { $hostRecordsDrained++ }
            }
        }

        # Make Console tab visible if we drained any host records
        if ($hostRecordsDrained -gt 0) {
            if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Making Console tab visible after draining " + $hostRecordsDrained + " records") }
            if ($consoleTab.Visibility -ne 'Visible') {
                $consoleTab.Visibility = 'Visible'
            }
            $tabNotifications.Console.UnreadCount += $hostRecordsDrained
            $consoleTab.Header = "Console (+$($tabNotifications.Console.UnreadCount))"
        }

        # Final scroll
        if ($autoScrollCheckbox.IsChecked) {
            $consoleTextBox.ScrollToEnd()
        }

        # Hide loading spinner on completion regardless
        & $hideLoading

        # If in HideUntilContent mode, check if there's any actual content
        if ($HideUntilContent) {
            # If window was already revealed by the final queue drain, don't close it
            if ($state.WindowRevealed) {
                if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] OnComplete: Window already revealed, skipping close check") }
            }
            else {
                $hasConsoleOutput = $consoleParagraph.Inlines.Count -gt 0
                $hasErrors = $errorsTabState.List -and $errorsTabState.List.Count -gt 0
                $hasWarnings = $warningCount.Value -gt 0
                $hasResults = $outputData.Count -gt 0

                if (!$hasConsoleOutput -and !$hasErrors -and !$hasWarnings -and !$hasResults) {
                    Write-Verbose "No content in any tab, closing silently"
                    # Activate parent window before closing to prevent console stealing focus
                    if ($ParentWindow) {
                        $ParentWindow.Activate()
                    }
                    $window.Close()
                    return
                }

                # If we have content but window wasn't revealed yet, reveal it now
                $state.WindowRevealed = $true
                $window.Visibility = 'Visible'
            }
        }

        $progressBar.IsIndeterminate = $false
        $progressBar.Value = 100
        $headerTitle.Text = "$Title - Complete"
        $progressPanel.Visibility = 'Collapsed'

        # Update status indicator - stop spinner, show success or warning
        $statusSpinner.Visibility = 'Collapsed'
        $hasErrors = $errorsTabState.List -and $errorsTabState.List.Count -gt 0
        $hasWarnings = $warningCount.Value -gt 0
        if ($hasErrors -or $hasWarnings) {
            $statusWarning.Visibility = 'Visible'
            $statusIndicator.ToolTip = "Complete with errors/warnings"

            # Update taskbar overlay to warning/error icon
            try {
                $errorOverlay = New-TaskbarOverlayIcon -GlyphChar ([PsUi.ModuleContext]::GetIcon('Alert')) -Color '#FFA500' -BackgroundColor '#FFFFFF'
                [PsUi.WindowManager]::SetTaskbarOverlay($window, $errorOverlay, 'Completed with warnings')
            }
            catch { Write-Debug "Suppressed taskbar warning overlay error: $_" }
        }
        else {
            $statusSuccess.Visibility = 'Visible'
            $statusIndicator.ToolTip = "Complete"

            # Update taskbar overlay to success checkmark
            try {
                $successOverlay = New-TaskbarOverlayIcon -GlyphChar ([PsUi.ModuleContext]::GetIcon('Accept')) -Color '#107C10' -BackgroundColor '#FFFFFF'
                [PsUi.WindowManager]::SetTaskbarOverlay($window, $successOverlay, 'Completed successfully')
            }
            catch { Write-Debug "Suppressed taskbar success overlay error: $_" }
        }

        if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] About to check outputData.Count = " + $outputData.Count) }

        if ($outputData.Count -gt 0) {
            if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Creating Results tab with " + $outputData.Count + " items") }

            # Convert to safe data array
            $dataArray = ConvertTo-SafeDataArray -DataArray @($outputData.ToArray())

            # Special handling for single dictionary item
            $dataForPresenter = $dataArray
            if ($dataArray.Count -eq 1 -and $dataArray[0] -is [System.Collections.IDictionary]) {
                $dataForPresenter = $dataArray[0]
            }

            $presenterInfo = Get-OutputPresenter -Data $dataForPresenter

            # Create Results tab with toolbar using helper
            $toolbarResult = New-ResultsToolbar -Colors $colors -ResultActions $ResultActions
            $resultsTab       = $toolbarResult.Tab
            $resultsPanel     = $toolbarResult.Panel
            $toolbar          = $toolbarResult.Toolbar
            $toolbar2         = $toolbarResult.Toolbar2
            $rightToolbar     = $toolbarResult.RightToolbar
            $filterPanel      = $toolbarResult.FilterPanel
            $resultsBorder    = $toolbarResult.ResultsBorder
            $exportButton     = $toolbarResult.ExportButton
            $copyButton       = $toolbarResult.CopyButton
            $dropdownPopup    = $toolbarResult.DropdownPopup
            $actionDropdownMenuStack = $toolbarResult.ActionDropdownMenuStack

            $resultsTab.Header = "Results ($($outputData.Count))"

            # Display results
            if ($presenterInfo.Type -in @('Collection', 'SingleObject', 'Dictionary')) {
                $singleSelectParam = if ($SingleSelect) { @{ SingleSelect = $true } } else { @{} }
                $dataGrid = New-StyledDataGrid @singleSelectParam

                if ($presenterInfo.Type -eq 'SingleObject') {
                    $dataGrid.AutoGenerateColumns = $true
                    $dataGrid.CanUserSortColumns = $false
                    $list = [System.Collections.Generic.List[object]]::new()
                    foreach ($prop in $dataArray[0].PSObject.Properties) {
                        $list.Add([PSCustomObject]@{
                            Name  = $prop.Name
                            Value = $prop.Value
                        })
                    }
                    $dataGrid.ItemsSource = [System.Windows.Data.CollectionViewSource]::GetDefaultView($list)
                    $resultsBorder.Child = $dataGrid
                }
                elseif ($presenterInfo.Type -eq 'Dictionary') {
                    $dataGrid.AutoGenerateColumns = $true
                    $list = [System.Collections.Generic.List[object]]::new()
                    $dict = $dataForPresenter
                    foreach ($key in $dict.Keys) {
                        $displayValue = ConvertTo-DisplayValue -Value $dict[$key]
                        $list.Add([PSCustomObject]@{
                            Key   = $key
                            Value = $displayValue
                        })
                    }
                    $dataGrid.ItemsSource = [System.Windows.Data.CollectionViewSource]::GetDefaultView($list)
                    $resultsBorder.Child = $dataGrid
                }
                else {
                    # Multi-type view with sub-TabControl
                    if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Checking multi-type - outputDataByType.Count = " + $outputDataByType.Count) }
                    foreach ($typeKey in $outputDataByType.Keys) {
                        if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Type key: " + $typeKey) }
                    }

                    # Cap to 10 tabs - merge overflow into "Other" bucket
                    $maxTypeTabs   = 10
                    $sortedKeys    = $outputDataByType.Keys | Sort-Object { $outputDataByType[$_].Count } -Descending
                    $typesToRender = @($sortedKeys | Select-Object -First $maxTypeTabs)
                    $overflowTypes = @($sortedKeys | Select-Object -Skip $maxTypeTabs)

                    if ($overflowTypes.Count -gt 0) {
                        $otherBucket = [System.Collections.Generic.List[object]]::new()
                        foreach ($overflowKey in $overflowTypes) {
                            foreach ($item in $outputDataByType[$overflowKey]) {
                                $otherBucket.Add($item)
                            }
                        }
                        $outputDataByType['Other'] = $otherBucket
                        $typesToRender += 'Other'
                        if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Merged " + $overflowTypes.Count + " overflow types into 'Other' bucket (" + $otherBucket.Count + " items)") }
                    }

                    if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Creating type-bucketed sub-TabControl with " + $typesToRender.Count + " tab(s)") }
                    $subTabControl = [System.Windows.Controls.TabControl]::new()
                    $subTabControl.Background = ConvertTo-UiBrush $colors.WindowBg
                    $subTabControl.BorderThickness = [System.Windows.Thickness]::new(0)
                    $subTabControl.Padding = [System.Windows.Thickness]::new(0)

                    $firstDataGrid = $null
                    foreach ($typeName in $typesToRender) {
                        $groupItems = $outputDataByType[$typeName]
                        if ($groupItems.Count -eq 0) { continue }

                        $subTab = [System.Windows.Controls.TabItem]::new()
                        $subTab.Header = "$typeName ($($groupItems.Count))"
                        Set-TabItemStyle -TabItem $subTab

                        $firstItem = $groupItems[0]
                        $isTextType = ($typeName -eq 'String') -or ($firstItem -is [string]) -or
                                      (($firstItem -is [ValueType]) -and !($firstItem -is [System.Collections.DictionaryEntry]))

                        if ($isTextType) {
                            $richTextBox = New-TextDisplayRichTextBox -Colors $colors -Lines $groupItems
                            $subTab.Content = $richTextBox
                            $subTab.Tag = 'TextType'
                            [void]$subTabControl.Items.Add($subTab)
                            if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Added TEXT sub-tab for type '" + $typeName + "' with " + $groupItems.Count + " lines") }
                            continue
                        }

                        if ($firstItem -is [System.Collections.DictionaryEntry]) {
                            $result = New-DictionarySubTab -GroupItems $groupItems -TypeName $typeName -Colors $colors -IsDictionaryEntry
                            [void]$subTabControl.Items.Add($result.Tab)
                            if ($null -eq $firstDataGrid) { $firstDataGrid = $result.DataGrid }
                            if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Added DICTIONARYENTRY sub-tab for type '" + $typeName + "'") }
                            continue
                        }

                        if ($firstItem -is [System.Collections.IDictionary]) {
                            $result = New-DictionarySubTab -GroupItems $groupItems -TypeName $typeName -Colors $colors
                            [void]$subTabControl.Items.Add($result.Tab)
                            if ($null -eq $firstDataGrid) { $firstDataGrid = $result.DataGrid }
                            if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Added DICTIONARY sub-tab for type '" + $typeName + "'") }
                            continue
                        }

                        # Create object DataGrid sub-tab using helper
                        $includeStatus = ($ResultActions -and $ResultActions.Count -gt 0)
                        $subTabParams = @{
                            GroupItems          = $groupItems
                            TypeName            = $typeName
                            Colors              = $colors
                            SubTabControl       = $subTabControl
                            SingleSelect        = $SingleSelect
                            IncludeActionStatus = $includeStatus
                        }
                        $result = New-ObjectSubTab @subTabParams
                        [void]$subTabControl.Items.Add($result.Tab)
                        if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Added sub-tab for type '" + $typeName + "' with " + $groupItems.Count + " items") }

                        if ($null -eq $firstDataGrid) { $firstDataGrid = $result.DataGrid }
                    }

                    if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Multi-type complete - subTabControl has " + $subTabControl.Items.Count + " tabs") }
                    $resultsBorder.Child = $subTabControl
                    $dataGrid = $firstDataGrid

                    # Add SelectionChanged handler to filter ResultAction buttons by ObjectType
                    $capturedToolbar = $toolbar
                    $capturedRightToolbar = $rightToolbar
                    $capturedDropdownMenuStack = $actionDropdownMenuStack
                    $subTabControl.Add_SelectionChanged({
                        param($sender, $eventArgs)
                        
                        # Ignore bubbled SelectionChanged events from child controls (e.g. DataGrid)
                        # Only process events that originated from the TabControl itself
                        if ($eventArgs.OriginalSource -ne $sender -and $eventArgs.OriginalSource -isnot [System.Windows.Controls.TabItem]) {
                            return
                        }
                        
                        $selectedTab = $sender.SelectedItem
                        if (!$selectedTab) { return }

                        # Clear filter on the previously selected tab's DataGrid
                        if ($eventArgs.RemovedItems.Count -gt 0) {
                            $previousTab = $eventArgs.RemovedItems[0]
                            if ($previousTab.Content -is [System.Windows.Controls.DataGrid]) {
                                $prevGrid = $previousTab.Content
                                $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($prevGrid.ItemsSource)
                                if ($view -and $view.Filter) {
                                    $view.Filter = $null
                                    $view.Refresh()
                                }
                            }
                        }

                        # Update filter box enabled state based on tab's indexed status
                        $filterBox = $sender.Tag
                        if ($filterBox) {
                            if (![string]::IsNullOrEmpty($filterBox.Text)) {
                                $filterBox.Text = ''
                            }

                            $isIndexed = ($selectedTab.Tag -in @('Indexed', 'TextType', 'Dictionary'))
                            $filterBox.IsEnabled = $isIndexed
                            $filterBox.ToolTip = if ($isIndexed) { 'Filter results' } else { 'Indexing...' }
                            if ($filterBox.Tag.Watermark) {
                                $filterBox.Tag.Watermark.Text = if ($isIndexed) { 'Filter...' } else { 'Indexing...' }
                            }
                        }

                        # Hide column selector button for non-DataGrid tabs or fixed-column tabs
                        $isDataGrid = $selectedTab.Content -is [System.Windows.Controls.DataGrid]
                        $isDictionary = $selectedTab.Tag -eq 'Dictionary'
                        $showColButton = $isDataGrid -and !$isDictionary
                        foreach ($child in $capturedRightToolbar.Children) {
                            if ($child -is [System.Windows.Controls.Button] -and $child.ToolTip -eq 'Show/Hide Columns') {
                                $child.Visibility = if ($showColButton) { 'Visible' } else { 'Collapsed' }
                            }
                        }

                        # Get the type name from the tab header
                        $selectedTypeName = $selectedTab.Header -replace '\s*\(\d+\)$', ''

                        $matchesObjectType = {
                            param($actionDef)
                            if (!$actionDef.ObjectType) { return $true }
                            $objectTypes = @($actionDef.ObjectType)
                            foreach ($ot in $objectTypes) {
                                if ($selectedTypeName -eq $ot -or $selectedTypeName -like "*.$ot" -or $selectedTypeName -match [regex]::Escape($ot)) {
                                    return $true
                                }
                            }
                            return $false
                        }

                        # Filter individual buttons based on ObjectType
                        foreach ($child in $capturedToolbar.Children) {
                            if ($child -is [System.Windows.Controls.Button] -and $child.Tag -is [hashtable]) {
                                $actionDef = $child.Tag
                                $child.Visibility = if (& $matchesObjectType $actionDef) { 'Visible' } else { 'Collapsed' }
                            }
                        }

                        # Filter dropdown menu items based on ObjectType
                        if ($capturedDropdownMenuStack) {
                            $visibleCount = 0
                            foreach ($menuItem in $capturedDropdownMenuStack.Children) {
                                if ($menuItem -is [System.Windows.Controls.Button] -and $menuItem.Tag -is [hashtable]) {
                                    $actionDef = $menuItem.Tag
                                    $isVisible = & $matchesObjectType $actionDef
                                    $menuItem.Visibility = if ($isVisible) { 'Visible' } else { 'Collapsed' }
                                    if ($isVisible) { $visibleCount++ }
                                }
                            }

                            foreach ($child in $capturedToolbar.Children) {
                                if ($child -is [System.Windows.Controls.Button] -and $child.ToolTip -eq 'Available actions for selected items') {
                                    $child.Visibility = if ($visibleCount -gt 0) { 'Visible' } else { 'Collapsed' }
                                }
                            }
                        }
                    }.GetNewClosure())

                    # Trigger initial filter on first tab
                    if ($subTabControl.Items.Count -gt 0) {
                        $subTabControl.SelectedIndex = 0
                    }

                    # Add filter box and column visibility button
                    $filterControls = Add-MultiTypeFilterControls -SubTabControl $subTabControl -RightToolbar $rightToolbar -FilterPanel $filterPanel -Toolbar2 $toolbar2
                }

                # Wire up action buttons using helper function
                if ($ResultActions -and $ResultActions.Count -gt 0) {
                    $allActionButtons = [System.Collections.Generic.List[object]]::new()
                    if ($actionDropdownMenuStack) {
                        foreach ($menuItem in $actionDropdownMenuStack.Children) {
                            if ($menuItem -is [System.Windows.Controls.Button] -and $menuItem.Tag -is [hashtable]) {
                                $allActionButtons.Add($menuItem)
                            }
                        }
                    }

                    # Ensure tabs exist before passing to result action handlers
                    # (result actions can produce their own errors/warnings)
                    & $ensureErrorsTab
                    & $ensureWarningsTab

                    $actionCaptures = @{
                        Window            = $window
                        State             = $state
                        DataGrid          = $dataGrid
                        ResultsBorder     = $resultsBorder
                        ConsoleTab        = $consoleTab
                        ConsoleParagraph  = $consoleParagraph
                        ConsoleColorMap   = $consoleColorMap
                        AppendConsoleText = $appendConsoleText
                        AppendState       = $appendState
                        ErrorsTab         = $errorsTabState.Tab
                        ErrorsList        = $errorsTabState.List
                        WarningsTab       = $warningsTabState.Tab
                        WarningsTextBox   = $warningsTabState.TextBox
                        WarningCount      = $warningCount
                        ProgressPanel     = $progressPanel
                        ProgressBar       = $progressBar
                        ProgressLabel     = $defaultProgressUI.Label
                        HeaderTitle       = $headerTitle
                        Title             = $Title
                        TabControl        = $tabControl
                        TabNotifications  = $tabNotifications
                        ErrorCount        = $errorsTabState.List.Count
                        StatusSpinner     = $statusSpinner
                        StatusSuccess     = $statusSuccess
                        StatusWarning     = $statusWarning
                        StatusIndicator   = $statusIndicator
                        VarValues         = $varValues
                        FuncDefs          = $funcDefs
                        Modules           = $capturedModules
                    }

                    Add-ResultActionClickHandlers -Captures $actionCaptures -ActionButtons $allActionButtons -DropdownPopup $dropdownPopup
                }

                $copyButton.Add_Click({
                    $text = $dataGrid.ItemsSource | ConvertTo-Csv -NoTypeInformation | Out-String
                    [System.Windows.Clipboard]::SetText($text)
                    Start-UiButtonFeedback -Button $copyButton -OriginalIconChar ([PsUi.ModuleContext]::GetIcon('Copy'))
                }.GetNewClosure())

                # Show and wire up export button for datagrids
                $exportButton.Visibility = 'Visible'
                $exportButton.Add_Click({
                    $saveDialog = [Microsoft.Win32.SaveFileDialog]::new()
                    $saveDialog.Filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
                    $saveDialog.DefaultExt = '.csv'
                    $saveDialog.FileName = "export_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

                    if ($saveDialog.ShowDialog()) {
                        $dataGrid.ItemsSource | Export-Csv -Path $saveDialog.FileName -NoTypeInformation
                        Start-UiButtonFeedback -Button $exportButton -OriginalIconChar ([PsUi.ModuleContext]::GetIcon('Export'))
                    }
                }.GetNewClosure())
            }
            else {
                # Text output with search capability
                $textLines = if ($dataArray.Count -gt 1) { $dataArray } else { @($dataArray[0].ToString()) }
                $richTextBox = New-TextDisplayRichTextBox -Colors $colors -Lines $textLines
                $resultsBorder.Child = $richTextBox

                Add-TextResultsFilter -RichTextBox $richTextBox -FilterPanel $filterPanel -Toolbar2 $toolbar2

                $copyButton.Add_Click({
                    $textRange = [System.Windows.Documents.TextRange]::new($richTextBox.Document.ContentStart, $richTextBox.Document.ContentEnd)
                    [System.Windows.Clipboard]::SetText($textRange.Text)
                    Start-UiButtonFeedback -Button $copyButton -OriginalIconChar ([PsUi.ModuleContext]::GetIcon('Copy'))
                }.GetNewClosure())
            }

            $resultsTab.Content = $resultsPanel
            if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Adding resultsTab to tabControl - resultsPanel has content: " + $resultsPanel.Children.Count) }
            $tabControl.Items.Insert(0, $resultsTab)
            $tabControl.SelectedIndex = 0
            if ($state.DebugEnabled) { [Console]::WriteLine("[DEBUG] Results tab inserted and selected") }
        }
        else {
            # No results returned - check if we have any console/error/warning output
            $hasConsoleOutput = $consoleParagraph.Inlines.Count -gt 0
            $hasErrors = $errorsTabState.List -and $errorsTabState.List.Count -gt 0
            $hasWarnings = $warningCount.Value -gt 0

            if ($hasConsoleOutput -or $hasErrors -or $hasWarnings) {
                if ($consoleTab.Visibility -eq 'Visible') {
                    $tabControl.SelectedItem = $consoleTab
                }
                elseif ($errorsTabState.Tab -and $errorsTabState.Tab.Visibility -eq 'Visible') {
                    $tabControl.SelectedItem = $errorsTabState.Tab
                }
                elseif ($warningsTabState.Tab -and $warningsTabState.Tab.Visibility -eq 'Visible') {
                    $tabControl.SelectedItem = $warningsTabState.Tab
                }
            }
            else {
                # No output at all - show success message
                $loadingSpinner.Visibility = 'Collapsed'

                $successIcon = [System.Windows.Controls.TextBlock]@{
                    Text                = [PsUi.ModuleContext]::GetIcon('Accept')
                    FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
                    FontSize            = 48
                    Foreground          = ConvertTo-UiBrush '#107C10'
                    HorizontalAlignment = 'Center'
                    Margin              = [System.Windows.Thickness]::new(0, 0, 0, 12)
                }
                $loadingStack.Children.Insert(0, $successIcon)

                $loadingLabel.Text = 'Completed successfully. No output was returned.'
                $loadingLabel.FontSize = 13
                $loadingPanel.Visibility = 'Visible'
            }
        }
    }
    catch {
        [Console]::WriteLine("[PsUi] OnComplete error: " + $_.Exception.Message)
        if ($state.DebugEnabled) { [Console]::WriteLine("DEBUG ERROR StackTrace: " + $_.Exception.StackTrace) }

        # Surface the error in the console tab so the user isn't staring at a blank window
        try {
            if ($appendConsoleText -and $appendState) {
                & $appendConsoleText "Internal error rendering results: $($_.Exception.Message)" 'Red' $null -State $appendState
            }
        }
        catch { Write-Debug "Failed to surface OnComplete error to console" }
    }
}
