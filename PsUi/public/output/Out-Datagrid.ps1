function Out-Datagrid {
    <#
    .SYNOPSIS
        Displays data in a filterable, sortable grid - a better Out-GridView.
    .DESCRIPTION
        Creates a themed data grid window with filtering, sorting, export to CSV,
        copy to clipboard, and optional selection passthrough. Use -PassThru to
        return selected items when the window closes.
    .PARAMETER Data
        Data to display in the grid. Accepts pipeline input.
    .PARAMETER TitleText
        Window title.
    .PARAMETER IsFilterable
        Enable live text filtering.
    .PARAMETER PassThru
        Return selected items when the OK button is clicked.
    .PARAMETER OutputMode
        Selection mode: None, Single, or Multiple. Defaults to Multiple with PassThru.
    .PARAMETER Theme
        Color theme: Light, Dark, etc.
    .PARAMETER Width
        Window width (400-2000).
    .PARAMETER Height
        Window height (300-1500).
    .EXAMPLE
        Get-Process | Out-Datagrid -TitleText 'Processes' -IsFilterable
        # Display processes in a grid
    .EXAMPLE
        Get-Service | Out-Datagrid -PassThru | Restart-Service
        # Select services and restart them
    .EXAMPLE
        Get-ChildItem | Out-Datagrid -PassThru -OutputMode Single
        # Select a single file
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object[]]$Data,

        [string]$TitleText = 'Data Grid',

        [switch]$IsFilterable,

        [switch]$PassThru,

        [ValidateSet('None', 'Single', 'Multiple')]
        [string]$OutputMode = 'Multiple',

        [ArgumentCompleter({ [PsUi.ThemeEngine]::GetAvailableThemes() })]
        [string]$Theme = 'Light',

        [ValidateRange(400, 2000)]
        [int]$Width = 900,

        [ValidateRange(300, 1500)]
        [int]$Height = 600
    )

    begin {
        # ShowDialog requires the UI thread - block async button actions from calling this
        if ([PsUi.AsyncExecutor]::CurrentExecutor) {
            Write-Error 'Out-DataGrid cannot be called from an async button action (ShowDialog requires the UI thread). Use -NoAsync on your button, or call this function outside the DSL.'
            return
        }

        Write-Debug "Starting with Title='$TitleText', Theme='$Theme', PassThru=$PassThru"

        # Helper to show themed dialogs
        function Show-ThemedDialog {
            param(
                [string]$Title,
                [string]$Message,
                [string]$Buttons = 'OK',
                [string]$Icon = 'Info'
            )
            Show-UiMessageDialog -Title $Title -Message $Message -Buttons $Buttons -Icon $Icon -ThemeColors $colors
        }

        $allData = [System.Collections.Generic.List[object]]::new()
        $result = @{ Selection = $null }
    }

    process {
        if ($Data) {
            foreach ($item in $Data) {
                [void]$allData.Add($item)
            }
        }
    }

    end {
        if ($allData.Count -eq 0) {
            Write-Warning 'No data to display'
            return
        }

        $isStandalone = !(Test-Path variable:__WPFThemeColors)
        Write-Debug "Context: isStandalone=$isStandalone, Items=$($allData.Count)"

        if ($isStandalone) {
            $colors = Initialize-UITheme -Theme $Theme
        }
        else {
            $colors = Get-Variable -Name __WPFThemeColors -ValueOnly -ErrorAction SilentlyContinue
        }

        if (!$colors) {
            $colors = Initialize-UITheme -Theme 'Light'
        }

        # Build window
        $window = [System.Windows.Window]@{
            Title                 = $TitleText
            Width                 = $Width
            Height                = $Height
            MinWidth              = 400
            MinHeight             = 300
            WindowStartupLocation = 'CenterScreen'
            FontFamily            = [System.Windows.Media.FontFamily]::new('Segoe UI')
            ResizeMode            = 'CanResizeWithGrip'
        }

        # Link to parent window for proper layering
        $null = Set-WindowOwner -Window $window
        $window.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'WindowBackgroundBrush')
        $window.SetResourceReference([System.Windows.Window]::ForegroundProperty, 'ControlForegroundBrush')

        Set-UIResources -Window $window -Colors $colors

        $appId = "PsUi.DataGrid." + [Guid]::NewGuid().ToString("N").Substring(0, 8)
        [PsUi.WindowManager]::SetWindowAppId($window, $appId)

        $gridWindowIcon = $null
        try {
            $gridWindowIcon = New-WindowIcon -Colors $colors
            if ($gridWindowIcon) {
                $window.Icon = $gridWindowIcon
            }
        }
        catch {
            Write-Verbose "Failed to create window icon: $_"
        }

        $overlayIcon = $null
        try {
            $gridGlyph = [PsUi.ModuleContext]::GetIcon('Grid')
            $overlayIcon = New-TaskbarOverlayIcon -GlyphChar $gridGlyph -Color $colors.Accent
            # Store glyph in resources for theme updates
            $window.Resources['OverlayGlyph'] = $gridGlyph
        }
        catch { Write-Debug "Taskbar overlay failed: $_" }

        $capturedGridWindow = $window
        $capturedGridIcon   = $gridWindowIcon
        $capturedOverlay    = $overlayIcon

        $window.Add_Loaded({
            if ($capturedGridIcon) {
                [PsUi.WindowManager]::SetTaskbarIcon($capturedGridWindow, $capturedGridIcon)
            }
            if ($capturedOverlay) {
                [PsUi.WindowManager]::SetTaskbarOverlay($capturedGridWindow, $capturedOverlay, 'Data')
            }
        }.GetNewClosure())

        $mainPanel = [System.Windows.Controls.DockPanel]@{ LastChildFill = $true }
        $window.Content = $mainPanel

        # Header bar
        $headerBorder = [System.Windows.Controls.Border]@{
            Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
            Tag     = 'HeaderBorder'
        }
        $headerBorder.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'HeaderBackgroundBrush')
        [System.Windows.Controls.DockPanel]::SetDock($headerBorder, 'Top')

        $headerGrid = [System.Windows.Controls.Grid]::new()
        $col1 = [System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        $col2 = [System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::Auto }
        [void]$headerGrid.ColumnDefinitions.Add($col1)
        [void]$headerGrid.ColumnDefinitions.Add($col2)

        $headerStack = [System.Windows.Controls.StackPanel]@{ Orientation = 'Horizontal' }
        [System.Windows.Controls.Grid]::SetColumn($headerStack, 0)

        $headerIcon = [System.Windows.Controls.TextBlock]@{
            Text              = [PsUi.ModuleContext]::GetIcon('Grid')
            FontFamily        = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            FontSize          = 24
            VerticalAlignment = 'Center'
            Width             = 32
            TextAlignment     = 'Center'
            Margin            = [System.Windows.Thickness]::new(0, 0, 12, 0)
            Tag               = 'HeaderText'
        }
        $headerIcon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'HeaderForegroundBrush')
        [void]$headerStack.Children.Add($headerIcon)

        $headerTitle = [System.Windows.Controls.TextBlock]@{
            Text              = $TitleText
            FontSize          = 18
            FontWeight        = [System.Windows.FontWeights]::SemiBold
            VerticalAlignment = 'Center'
            Tag               = 'HeaderText'
        }
        $headerTitle.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'HeaderForegroundBrush')
        [void]$headerStack.Children.Add($headerTitle)

        [void]$headerGrid.Children.Add($headerStack)

        # Theme button (standalone only)
        if ($isStandalone) {
            $themeButtonData = New-ThemePopupButton -Container $window -CurrentTheme $Theme
            [System.Windows.Controls.Grid]::SetColumn($themeButtonData.Button, 1)
            [void]$headerGrid.Children.Add($themeButtonData.Button)
        }

        $headerBorder.Child = $headerGrid
        [void]$mainPanel.Children.Add($headerBorder)

        # Content area
        $contentPanel = [System.Windows.Controls.DockPanel]@{
            Margin        = [System.Windows.Thickness]::new(12)
            LastChildFill = $true
        }
        [void]$mainPanel.Children.Add($contentPanel)

        # Filter toolbar
        $toolbar = [System.Windows.Controls.StackPanel]@{
            Orientation = 'Horizontal'
            Margin      = [System.Windows.Thickness]::new(0, 0, 0, 8)
        }
        [System.Windows.Controls.DockPanel]::SetDock($toolbar, 'Top')
        [void]$contentPanel.Children.Add($toolbar)

        $filterBox = $null
        if ($IsFilterable) {
            $filterLabel = [System.Windows.Controls.TextBlock]@{
                Text              = 'Filter:'
                VerticalAlignment = 'Center'
                Margin            = [System.Windows.Thickness]::new(0, 0, 8, 0)
            }
            $filterLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'ControlForegroundBrush')
            [void]$toolbar.Children.Add($filterLabel)

            $filterBoxContainer = [System.Windows.Controls.Grid]@{
                Width             = 200
                Height            = 26
                VerticalAlignment = 'Center'
            }

            $filterBox = [System.Windows.Controls.TextBox]@{
                Height  = 26
                Padding = [System.Windows.Thickness]::new(4, 0, 20, 0)
            }
            Set-TextBoxStyle -TextBox $filterBox
            [void]$filterBoxContainer.Children.Add($filterBox)

            # Clear button overlaid on filter box
            $filterClearBtn = [System.Windows.Controls.Button]@{
                Content             = [PsUi.ModuleContext]::GetIcon('Cancel')
                FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
                FontSize            = 10
                Width               = 16
                Height              = 16
                Padding             = [System.Windows.Thickness]::new(0)
                Margin              = [System.Windows.Thickness]::new(0, 0, 5, 0)
                HorizontalAlignment = 'Right'
                VerticalAlignment   = 'Center'
                Background          = [System.Windows.Media.Brushes]::Transparent
                BorderThickness     = [System.Windows.Thickness]::new(0)
                Cursor              = [System.Windows.Input.Cursors]::Hand
                Visibility          = 'Collapsed'
                ToolTip             = 'Clear'
                Tag                 = $filterBox
            }
            $filterClearBtn.SetResourceReference([System.Windows.Controls.Button]::ForegroundProperty, 'SecondaryTextBrush')
            $filterClearBtn.Add_Click({ $this.Tag.Text = ''; $this.Tag.Focus() }.GetNewClosure())
            [void]$filterBoxContainer.Children.Add($filterClearBtn)

            $filterBox.Tag = @{ ClearButton = $filterClearBtn }
            [void]$toolbar.Children.Add($filterBoxContainer)
        }

        # Button panel at bottom
        $buttonPanel = [System.Windows.Controls.StackPanel]@{
            Orientation         = 'Horizontal'
            HorizontalAlignment = 'Right'
            Margin              = [System.Windows.Thickness]::new(0, 8, 0, 0)
        }
        [System.Windows.Controls.DockPanel]::SetDock($buttonPanel, 'Bottom')
        [void]$contentPanel.Children.Add($buttonPanel)

        # Export button
        $exportBtn = [System.Windows.Controls.Button]@{
            Width   = 36
            Height  = 32
            Margin  = [System.Windows.Thickness]::new(0, 0, 8, 0)
            ToolTip = 'Export to CSV'
            Padding = [System.Windows.Thickness]::new(0)
        }
        $exportIcon = [System.Windows.Controls.TextBlock]@{
            Text                = [PsUi.ModuleContext]::GetIcon('SaveLocal')
            FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            FontSize            = 16
            HorizontalAlignment = 'Center'
            VerticalAlignment   = 'Center'
        }
        $exportBtn.Content = $exportIcon
        Set-ButtonStyle -Button $exportBtn
        [void]$buttonPanel.Children.Add($exportBtn)

        # Copy button
        $copyBtn = [System.Windows.Controls.Button]@{
            Width   = 36
            Height  = 32
            Margin  = [System.Windows.Thickness]::new(0, 0, 8, 0)
            ToolTip = 'Copy selected to clipboard'
            Padding = [System.Windows.Thickness]::new(0)
        }
        $copyIcon = [System.Windows.Controls.TextBlock]@{
            Text                = [PsUi.ModuleContext]::GetIcon('Copy')
            FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            FontSize            = 16
            HorizontalAlignment = 'Center'
            VerticalAlignment   = 'Center'
        }
        $copyBtn.Content = $copyIcon
        Set-ButtonStyle -Button $copyBtn
        [void]$buttonPanel.Children.Add($copyBtn)

        # OK button (only shown when PassThru)
        $okBtn = $null
        if ($PassThru) {
            $okBtn = [System.Windows.Controls.Button]@{
                Content = 'OK'
                Width   = 80
                Height  = 32
                Margin  = [System.Windows.Thickness]::new(0, 0, 8, 0)
            }
            Set-ButtonStyle -Button $okBtn -Accent
            [void]$buttonPanel.Children.Add($okBtn)
        }

        # Cancel/Close button
        $cancelBtn = [System.Windows.Controls.Button]@{
            Content = if ($PassThru) { 'Cancel' } else { 'Close' }
            Width   = 80
            Height  = 32
        }
        Set-ButtonStyle -Button $cancelBtn
        [void]$buttonPanel.Children.Add($cancelBtn)

        # DataGrid
        $selectionMode = switch ($OutputMode) {
            'Single' { 'Single' }
            default  { 'Extended' }
        }
        $dataGrid = [System.Windows.Controls.DataGrid]::new()
        Set-DataGridStyle -Grid $dataGrid -SelectionMode $selectionMode
        $dataGrid.AutoGenerateColumns         = $true
        $dataGrid.IsReadOnly                  = $true
        $dataGrid.EnableRowVirtualization     = $true
        $dataGrid.EnableColumnVirtualization  = $true
        [System.Windows.Controls.VirtualizingPanel]::SetIsVirtualizing($dataGrid, $true)
        [System.Windows.Controls.VirtualizingPanel]::SetVirtualizationMode($dataGrid, 'Recycling')
        [void]$contentPanel.Children.Add($dataGrid)

        # Context menu
        $null = New-DataGridContextMenu -DataGrid $dataGrid

        # Per-window state captured by closures (avoids $script: collisions between grids)
        $gridState = @{
            SearchCache     = @{}
            UnfilteredItems = [System.Collections.Generic.List[object]]::new()
            DataObservable  = $null
            CollectionView  = $null
            FilterTimer     = $null
            CopyTimer       = $null
        }

        # Load data and pre-cache search strings for fast filtering
        $observable = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        foreach ($item in $allData) {
            [void]$observable.Add($item)
            [void]$gridState.UnfilteredItems.Add($item)
            # Build a single concatenated search string for each item
            $searchParts = [System.Collections.Generic.List[string]]::new()
            foreach ($prop in $item.PSObject.Properties) {
                if ($null -ne $prop.Value) {
                    $searchParts.Add($prop.Value.ToString())
                }
            }
            $gridState.SearchCache[$item] = $searchParts -join '|'
        }
        $gridState.DataObservable = $observable
        $gridState.CollectionView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($observable)
        $dataGrid.ItemsSource = $gridState.CollectionView

        # Manually create columns with explicit SortMemberPath for reliable sorting
        $dataGrid.AutoGenerateColumns = $false
        if ($allData.Count -gt 0) {
            $firstItem = $allData[0]
            foreach ($prop in $firstItem.PSObject.Properties) {
                $col = [System.Windows.Controls.DataGridTextColumn]::new()
                $col.Header = $prop.Name
                $col.Binding = [System.Windows.Data.Binding]::new($prop.Name)
                $col.SortMemberPath = $prop.Name
                $col.CanUserSort = $true
                [void]$dataGrid.Columns.Add($col)
            }
        }

        # Filter handler with debouncing - rebuilds collection to avoid delegate issues with sorting
        if ($IsFilterable -and $filterBox) {
            $filterBox.Add_TextChanged({
                $clearBtn = $filterBox.Tag.ClearButton
                if ($clearBtn) {
                    $clearBtn.Visibility = if ([string]::IsNullOrEmpty($filterBox.Text)) { 'Collapsed' } else { 'Visible' }
                }

                if ($gridState.FilterTimer) {
                    $gridState.FilterTimer.Stop()
                    $gridState.FilterTimer = $null
                }

                $gridState.FilterTimer = [System.Windows.Threading.DispatcherTimer]::new()
                $gridState.FilterTimer.Interval = [TimeSpan]::FromMilliseconds(300)

                $gridState.FilterTimer.Add_Tick({
                    $text = $filterBox.Text.Trim()

                    # Collection rebuild avoids delegate issues with WPF sorting
                    if ($gridState.UnfilteredItems -and $gridState.DataObservable) {
                        # Capture current sort state
                        $sortDescriptions = @()
                        if ($gridState.CollectionView) {
                            foreach ($sd in $gridState.CollectionView.SortDescriptions) {
                                $sortDescriptions += $sd
                            }
                        }

                        $gridState.DataObservable.Clear()

                        foreach ($item in $gridState.UnfilteredItems) {
                            if ([string]::IsNullOrEmpty($text)) {
                                [void]$gridState.DataObservable.Add($item)
                            }
                            else {
                                $cached = $gridState.SearchCache[$item]
                                if ($cached -and $cached.IndexOf($text, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                    [void]$gridState.DataObservable.Add($item)
                                }
                            }
                        }

                        # Reapply sort
                        if ($gridState.CollectionView -and $sortDescriptions.Count -gt 0) {
                            $gridState.CollectionView.SortDescriptions.Clear()
                            foreach ($sd in $sortDescriptions) {
                                $gridState.CollectionView.SortDescriptions.Add($sd)
                            }
                        }
                    }

                    $gridState.FilterTimer.Stop()
                    $gridState.FilterTimer = $null
                })

                $gridState.FilterTimer.Start()
            })
        }

        # Export handler
        $exportBtn.Add_Click({
            $saveDialog = [Microsoft.Win32.SaveFileDialog]::new()
            $saveDialog.Filter = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
            $saveDialog.DefaultExt = '.csv'
            $saveDialog.FileName = 'export.csv'
            if ($saveDialog.ShowDialog()) {
                try {
                    $items = @($dataGrid.ItemsSource)
                    if ($items.Count -gt 0) {
                        $items | Export-Csv -Path $saveDialog.FileName -NoTypeInformation -Force
                        Show-ThemedDialog -Title 'Export Complete' -Message "Exported to:`n$($saveDialog.FileName)" -Buttons OK -Icon Info
                    }
                }
                catch {
                    Show-ThemedDialog -Title 'Export Failed' -Message "Failed: $_" -Buttons OK -Icon Error
                }
            }
        }.GetNewClosure())

        # Copy handler
        $copyBtn.Add_Click({
            if ($dataGrid.SelectedItems.Count -gt 0) {
                try {
                    $text = $dataGrid.SelectedItems | ConvertTo-Csv -NoTypeInformation | Out-String
                    [System.Windows.Clipboard]::SetText($text)

                    # Visual feedback
                    $copyIcon.Text = [PsUi.ModuleContext]::GetIcon('Check')
                    $originalBg = $copyBtn.Background
                    $accentBrush = [System.Windows.Application]::Current.TryFindResource('AccentBrush')
                    if ($accentBrush) { $copyBtn.Background = $accentBrush }

                    $gridState.CopyTimer = [System.Windows.Threading.DispatcherTimer]::new()
                    $gridState.CopyTimer.Interval = [TimeSpan]::FromMilliseconds(1500)
                    $gridState.CopyTimer.Tag = @{ Button = $copyBtn; Icon = $copyIcon; OriginalBg = $originalBg }
                    $gridState.CopyTimer.Add_Tick({
                        param($sender, $eventArgs)
                        $data = $sender.Tag
                        $data.Button.Background = $data.OriginalBg
                        $data.Icon.Text = [PsUi.ModuleContext]::GetIcon('Copy')
                        $sender.Stop()
                    })
                    $gridState.CopyTimer.Start()
                }
                catch {
                    Show-ThemedDialog -Title 'Copy Failed' -Message "Failed: $_" -Buttons OK -Icon Error
                }
            }
            else {
                Show-ThemedDialog -Title 'No Selection' -Message 'Select rows to copy' -Buttons OK -Icon Warning
            }
        }.GetNewClosure())

        # OK button returns selection and closes
        if ($okBtn) {
            $okBtn.Add_Click({
                $result.Selection = @($dataGrid.SelectedItems)
                $window.Close()
            }.GetNewClosure())
        }

        # Cancel just closes
        $cancelBtn.Add_Click({ $window.Close() }.GetNewClosure())

        # Standard window setup
        Initialize-UiWindowLoaded -Window $window -SetIcon

        # Cleanup on window close
        $window.Add_Closed({
            # Stop any active filter timer to prevent callbacks on disposed controls
            if ($gridState.FilterTimer) {
                $gridState.FilterTimer.Stop()
                $gridState.FilterTimer = $null
            }

            # Release data structures
            $gridState.SearchCache     = $null
            $gridState.UnfilteredItems = $null
            $gridState.DataObservable  = $null
            $gridState.CollectionView  = $null

            if ($isStandalone) {
                $sessionId = [PsUi.SessionManager]::CurrentSessionId
                if ($sessionId -ne [Guid]::Empty) {
                    [PsUi.SessionManager]::DisposeSession($sessionId)
                }
            }
        }.GetNewClosure())

        # Position window on parent's monitor when launched from PsUi context
        if (!$isStandalone) {
            Set-UiDialogPosition -Dialog $window
        }

        [void]$window.ShowDialog()

        # Return selection if PassThru and OK was clicked
        if ($PassThru -and $result.Selection) {
            return $result.Selection
        }
    }
}
