function Out-CSVDataGrid {
    <#
    .SYNOPSIS
        Displays a CSV file editor with filtering and editing capabilities.
    .DESCRIPTION
        Opens a WPF window for viewing and editing CSV files. Supports loading
        multiple CSV files from a directory, adding/removing rows and columns,
        and saving changes back to disk.

        Known quirk: internal state uses $script: scope, so running two CSV grids
        simultaneously in the same session could cause weird cross-talk. The modal
        dialog pattern prevents this in normal usage, but avoid calling from
        parallel runspaces that share the module scope.
    .PARAMETER CSVDirectory
        Directory containing CSV files to load.
    .PARAMETER CSVFiles
        Specific CSV file paths to load.
    .PARAMETER TitleText
        Window title.
    .PARAMETER IsFilterable
        Enable text filtering.
    .PARAMETER IsResizeable
        Enable window resizing.
    .PARAMETER ColumnsToPopupOnSelection
        Columns that open in a separate viewer/editor window when selected.
    .PARAMETER ColumnComboBoxes
        Hashtable defining columns to be edited via ComboBox dropdowns.
        Key = column name, Value = array of allowed values or hashtable with Values and DefaultValue.
        Example: @{ Status = @('Active', 'Inactive'); Priority = @{ Values = @('Low', 'High'); DefaultValue = 'Low' } }
    .PARAMETER ReadOnlyColumns
        Array of column names that should be read-only. Users cannot edit these cells inline.
        Columns in both ReadOnlyColumns and ColumnsToPopupOnSelection will open in a read-only viewer.
    .PARAMETER ForceTextWrap
        Enable text wrapping in cells.
    .PARAMETER Width
        Window width.
    .PARAMETER Height
        Window height.
    .PARAMETER Theme
        Color theme for the viewer window.
    .PARAMETER Delimiter
        Column separator character. Defaults to comma.
    .PARAMETER NoHeader
        Treat the first row as data, not column headers.
    .EXAMPLE
        Out-CSVDataGrid -CSVDirectory 'C:\Data' -IsFilterable -IsResizeable
    .EXAMPLE
        Get-ChildItem C:\Logs -Filter *.csv | Out-CSVDataGrid -IsFilterable
    .EXAMPLE
        Out-CSVDataGrid -CSVFiles 'inventory.csv' -ColumnComboBoxes @{
            Status = @('Active', 'Inactive', 'Pending')
            Priority = @('Low', 'Medium', 'High', 'Critical')
        }
    #>
    [CmdletBinding(DefaultParameterSetName = 'Directory')]
    param(
        [Parameter(ParameterSetName = 'Directory')]
        [string]$CSVDirectory,

        [Parameter(ParameterSetName = 'Files', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$CSVFiles,

        [Alias('Title')]
        [string]$TitleText = 'CSV Editor',

        [switch]$IsFilterable,

        [switch]$IsResizeable,

        [string[]]$ColumnsToPopupOnSelection,

        [Parameter()]
        [hashtable]$ColumnComboBoxes,

        [Parameter()]
        [string[]]$ReadOnlyColumns,

        [switch]$ForceTextWrap,

        [ValidateRange(400, 2000)]
        [int]$Width = 1000,

        [ValidateRange(300, 1500)]
        [int]$Height = 700,

        [ArgumentCompleter({ [PsUi.ThemeEngine]::GetAvailableThemes() })]
        [string]$Theme = 'Light',

        [char]$Delimiter = ',',

        [switch]$NoHeader
    )


    begin {
        # ShowDialog requires the UI thread - block async button actions from calling this
        if ([PsUi.AsyncExecutor]::CurrentExecutor) {
            Write-Error 'Out-CSVDataGrid cannot be called from an async button action (ShowDialog requires the UI thread). Use -NoAsync on your button, or call this function outside the DSL.'
            return
        }

        Write-Debug "Starting with Title='$TitleText', Theme='$Theme', Delimiter='$Delimiter'"
        $allFiles = [System.Collections.Generic.List[string]]::new()

        function Show-ThemedDialog {
            param(
                [string]$Title,
                [string]$Message,
                [string]$Buttons = 'OK',
                [string]$Icon = 'Info'
            )
            # Use $colors from parent scope (already has async injection logic)
            Show-UiMessageDialog -Title $Title -Message $Message -Buttons $Buttons -Icon $Icon -ThemeColors $colors
        }

        # Helper function to create themed editing style for DataGrid columns


        # Helper function to create themed editing style for DataGrid columns
        function Get-DataGridEditStyle {
            $editStyle = [System.Windows.Style]::new([System.Windows.Controls.TextBox])

            # Background
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.TextBox]::BackgroundProperty,
                    (ConvertTo-UiBrush $colors.ControlBg)
                ))

            # Foreground
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.TextBox]::ForegroundProperty,
                    (ConvertTo-UiBrush $colors.ControlFg)
                ))

            # Border - KEEP IT MINIMAL OR REMOVE
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.TextBox]::BorderBrushProperty,
                    (ConvertTo-UiBrush $colors.Accent)
                ))

            # Zero border thickness prevents row expansion during edit
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.TextBox]::BorderThicknessProperty,
                    [System.Windows.Thickness]::new(0)
                ))

            # Minimal horizontal padding only to prevent row height changes
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.TextBox]::PaddingProperty,
                    [System.Windows.Thickness]::new(2, 0, 2, 0)
                ))

            # Zero margin prevents cell expansion
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.TextBox]::MarginProperty,
                    [System.Windows.Thickness]::new(0)
                ))

            # Stretch to fill cell exactly
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.TextBox]::VerticalAlignmentProperty,
                    [System.Windows.VerticalAlignment]::Stretch
                ))

            # VerticalContentAlignment - CENTER text inside
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.TextBox]::VerticalContentAlignmentProperty,
                    [System.Windows.VerticalAlignment]::Center
                ))

            return $editStyle
        }

        # Helper function to create themed editing style for DataGridComboBoxColumn
        function Get-DataGridComboBoxEditStyle {
            $editStyle = [System.Windows.Style]::new([System.Windows.Controls.ComboBox])

            # Background
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.ComboBox]::BackgroundProperty,
                    (ConvertTo-UiBrush $colors.ControlBg)
                ))

            # Foreground
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.ComboBox]::ForegroundProperty,
                    (ConvertTo-UiBrush $colors.ControlFg)
                ))

            # Border
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.ComboBox]::BorderBrushProperty,
                    (ConvertTo-UiBrush $colors.Accent)
                ))

            # Border thickness - minimal to prevent row expansion
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.ComboBox]::BorderThicknessProperty,
                    [System.Windows.Thickness]::new(0)
                ))

            # Padding - minimal
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.ComboBox]::PaddingProperty,
                    [System.Windows.Thickness]::new(2, 0, 2, 0)
                ))

            # Margin - zero
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.ComboBox]::MarginProperty,
                    [System.Windows.Thickness]::new(0)
                ))

            # VerticalAlignment - stretch to fill cell
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.ComboBox]::VerticalAlignmentProperty,
                    [System.Windows.VerticalAlignment]::Stretch
                ))

            # VerticalContentAlignment
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new(
                    [System.Windows.Controls.ComboBox]::VerticalContentAlignmentProperty,
                    [System.Windows.VerticalAlignment]::Center
                ))

            return $editStyle
        }
    }

    process {
        if ($CSVFiles) {
            foreach ($file in $CSVFiles) {
                if (Test-Path $file -PathType Leaf) {
                    [void]$allFiles.Add($file)
                }
            }
        }
    }

    end {
        # Filter debouncing timer
        $script:filterTimer = $null

        # A column can't be both a ComboBox and a PopupOnSelection - that's nonsense
        if ($ColumnComboBoxes -and $ColumnsToPopupOnSelection) {
            Write-Debug "Checking for ComboBox/PopupOnSelection overlap"
            $overlap = $ColumnComboBoxes.Keys | Where-Object { $_ -in $ColumnsToPopupOnSelection }
            if ($overlap) {
                Write-Debug "Found overlapping columns: $($overlap -join ', ')"
                Write-Warning "Columns cannot use both ComboBox and PopupOnSelection: $($overlap -join ', ')"
                throw "Parameter conflict: Remove overlapping columns from either ColumnComboBoxes or ColumnsToPopupOnSelection"
            }
        }

        # Load from directory if specified
        if ($CSVDirectory -and (Test-Path $CSVDirectory -PathType Container)) {
            Get-ChildItem $CSVDirectory -Filter '*.csv' -File | ForEach-Object {
                [void]$allFiles.Add($_.FullName)
            }
        }

        if ($allFiles.Count -eq 0) {
            Write-Debug "No CSV files found in provided paths"
            Write-Warning 'No CSV files found'
            return
        }

        Write-Debug "Found $($allFiles.Count) CSV file(s) to load"

        $isStandalone = !(Test-Path variable:__WPFThemeColors)

        if ($isStandalone) {
            # Standalone: use -Theme parameter and initialize full theme resources
            $colors = Initialize-UITheme -Theme $Theme
        }
        else {
            # Child window: use injected theme colors from parent context
            $colors = Get-Variable -Name __WPFThemeColors -ValueOnly -ErrorAction SilentlyContinue
        }

        # Ultimate fallback
        if (!$colors) {
            $colors = Initialize-UITheme -Theme 'Light'
        }
        $Script:CurrentCSVData = @{}
        $Script:HasChanges = $false

        foreach ($filePath in $allFiles) {
            $fileName = [System.IO.Path]::GetFileName($filePath)
            try {
                $importParams = @{
                    Path      = $filePath
                    Delimiter = $Delimiter
                }
                if ($NoHeader) {
                    # Dynamically generate column headers based on first row
                    $firstLine = Get-Content $filePath -First 1
                    $columnCount = ($firstLine -split [regex]::Escape($Delimiter)).Count
                    $headers = 1..$columnCount | ForEach-Object { "Column$_" }
                    $importParams['Header'] = $headers
                }
                $csvData = Import-Csv @importParams
                $Script:CurrentCSVData[$fileName] = @{
                    Path      = $filePath
                    Data      = [System.Collections.ArrayList]@($csvData)
                    Modified  = $false
                    Delimiter = $Delimiter
                }
            }
            catch {
                Write-Warning "Failed to load $fileName`: $_"
            }
        }

        if ($Script:CurrentCSVData.Count -eq 0) {
            Write-Warning 'No valid CSV files loaded'
            return
        }

        $window = [System.Windows.Window]@{
            Title                 = $TitleText
            Width                 = $Width
            Height                = $Height
            MinWidth              = 400
            MinHeight             = 300
            WindowStartupLocation = 'CenterScreen'
            FontFamily            = [System.Windows.Media.FontFamily]::new('Segoe UI')
            ResizeMode            = if ($IsResizeable) { 'CanResizeWithGrip' } else { 'CanResize' }
        }

        # Set parent ownership when launched from a PsUi window
        $null = Set-WindowOwner -Window $window
        $window.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'WindowBackgroundBrush')
        $window.SetResourceReference([System.Windows.Window]::ForegroundProperty, 'ControlForegroundBrush')

        Set-UIResources -Window $window -Colors $colors

        $appId = "PsUi.CSVEditor." + [Guid]::NewGuid().ToString("N").Substring(0, 8)
        [PsUi.WindowManager]::SetWindowAppId($window, $appId)

        $csvWindowIcon = $null
        try {
            $csvWindowIcon = New-WindowIcon -Colors $colors
            if ($csvWindowIcon) {
                $window.Icon = $csvWindowIcon
            }
        }
        catch {
            Write-Verbose "Failed to create window icon: $_"
        }

        $overlayIcon = $null
        try {
            $csvGlyph = [PsUi.ModuleContext]::GetIcon('Document')
            $overlayIcon = New-TaskbarOverlayIcon -GlyphChar $csvGlyph -Color $colors.Accent
            # Store glyph in resources for theme updates
            $window.Resources['OverlayGlyph'] = $csvGlyph
        }
        catch { Write-Debug "Taskbar overlay failed: $_" }

        $capturedCsvWindow = $window
        $capturedCsvIcon   = $csvWindowIcon
        $capturedOverlay   = $overlayIcon

        $window.Add_Loaded({
            if ($capturedCsvIcon) {
                [PsUi.WindowManager]::SetTaskbarIcon($capturedCsvWindow, $capturedCsvIcon)
            }
            if ($capturedOverlay) {
                [PsUi.WindowManager]::SetTaskbarOverlay($capturedCsvWindow, $capturedOverlay, 'CSV')
            }
        }.GetNewClosure())

        $mainPanel = [System.Windows.Controls.DockPanel]@{
            LastChildFill = $true
        }
        $window.Content = $mainPanel

        # Header bar
        $headerBorder = [System.Windows.Controls.Border]@{
            Padding    = [System.Windows.Thickness]::new(16, 12, 16, 12)
            Tag        = 'HeaderBorder'
        }
        $headerBorder.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'HeaderBackgroundBrush')
        [System.Windows.Controls.DockPanel]::SetDock($headerBorder, 'Top')

        $headerGrid = [System.Windows.Controls.Grid]::new()
        $col1 = [System.Windows.Controls.ColumnDefinition]@{
            Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        }
        $col2 = [System.Windows.Controls.ColumnDefinition]@{
            Width = [System.Windows.GridLength]::Auto
        }
        [void]$headerGrid.ColumnDefinitions.Add($col1)
        [void]$headerGrid.ColumnDefinitions.Add($col2)

        $headerStack = [System.Windows.Controls.StackPanel]@{
            Orientation = 'Horizontal'
        }
        [System.Windows.Controls.Grid]::SetColumn($headerStack, 0)

        $headerIcon = [System.Windows.Controls.TextBlock]@{
            Text              = [PsUi.ModuleContext]::GetIcon('Document')
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

        # Add theme button to header - only when running standalone
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

        # Top toolbar with Grid layout for right-aligned filter
        $toolbar = [System.Windows.Controls.Grid]@{
            Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        }
        [System.Windows.Controls.DockPanel]::SetDock($toolbar, 'Top')

        # Two columns: left (file selector), right (filter)
        $col1 = [System.Windows.Controls.ColumnDefinition]@{
            Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        }
        $col2 = [System.Windows.Controls.ColumnDefinition]@{
            Width = [System.Windows.GridLength]::Auto
        }
        [void]$toolbar.ColumnDefinitions.Add($col1)
        [void]$toolbar.ColumnDefinitions.Add($col2)

        # Left panel - File selector
        $leftPanel = [System.Windows.Controls.StackPanel]@{
            Orientation = 'Horizontal'
        }
        [System.Windows.Controls.Grid]::SetColumn($leftPanel, 0)

        $fileLabel = [System.Windows.Controls.TextBlock]@{
            Text              = 'File:'
            VerticalAlignment = 'Center'
            Margin            = [System.Windows.Thickness]::new(0, 0, 8, 0)
        }
        $fileLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'ControlForegroundBrush')
        [void]$leftPanel.Children.Add($fileLabel)

        $fileCombo = [System.Windows.Controls.ComboBox]::new()
        $fileCombo.Width = 200
        $fileCombo.Margin = [System.Windows.Thickness]::new(0, 0, 16, 0)
        foreach ($fileName in $Script:CurrentCSVData.Keys) {
            [void]$fileCombo.Items.Add($fileName)
        }
        $fileCombo.SelectedIndex = 0
        Set-ComboBoxStyle -ComboBox $fileCombo
        [void]$leftPanel.Children.Add($fileCombo)

        [void]$toolbar.Children.Add($leftPanel)

        # Right panel - Filter (ALWAYS visible)
        $rightPanel = [System.Windows.Controls.StackPanel]::new()
        $rightPanel.Orientation = 'Horizontal'
        $rightPanel.HorizontalAlignment = 'Right'
        [System.Windows.Controls.Grid]::SetColumn($rightPanel, 1)

        $filterLabel = [System.Windows.Controls.TextBlock]::new()
        $filterLabel.Text = 'Filter:'
        $filterLabel.VerticalAlignment = 'Center'
        $filterLabel.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
        $filterLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'ControlForegroundBrush')
        [void]$rightPanel.Children.Add($filterLabel)

        # Wrap TextBox in Grid to overlay clear button
        $filterBoxContainer = [System.Windows.Controls.Grid]::new()
        $filterBoxContainer.Width = 200
        $filterBoxContainer.Height = 26
        $filterBoxContainer.VerticalAlignment = 'Center'

        $filterBox = [System.Windows.Controls.TextBox]::new()
        $filterBox.Height = 26
        $filterBox.Padding = [System.Windows.Thickness]::new(4, 0, 20, 0)
        Set-TextBoxStyle -TextBox $filterBox
        [void]$filterBoxContainer.Children.Add($filterBox)

        $filterClearBtn = [System.Windows.Controls.Button]::new()
        $filterClearBtn.Content = [PsUi.ModuleContext]::GetIcon('Cancel')
        $filterClearBtn.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $filterClearBtn.FontSize = 10
        $filterClearBtn.Width = 16
        $filterClearBtn.Height = 16
        $filterClearBtn.Padding = [System.Windows.Thickness]::new(0)
        $filterClearBtn.Margin = [System.Windows.Thickness]::new(0, 0, 5, 0)
        $filterClearBtn.HorizontalAlignment = 'Right'
        $filterClearBtn.VerticalAlignment = 'Center'
        $filterClearBtn.Background = [System.Windows.Media.Brushes]::Transparent
        $filterClearBtn.BorderThickness = [System.Windows.Thickness]::new(0)
        $filterClearBtn.SetResourceReference([System.Windows.Controls.Button]::ForegroundProperty, 'SecondaryTextBrush')
        $filterClearBtn.Cursor = [System.Windows.Input.Cursors]::Hand
        $filterClearBtn.Visibility = 'Collapsed'
        $filterClearBtn.ToolTip = 'Clear'
        $filterClearBtn.Tag = $filterBox
        $filterClearBtn.Add_Click({ $this.Tag.Text = ''; $this.Tag.Focus() }.GetNewClosure())
        [void]$filterBoxContainer.Children.Add($filterClearBtn)

        $filterBox.Tag = @{ ClearButton = $filterClearBtn }
        [void]$rightPanel.Children.Add($filterBoxContainer)

        [void]$toolbar.Children.Add($rightPanel)
        [void]$contentPanel.Children.Add($toolbar)

        # Row operations toolbar
        $rowToolbar = [System.Windows.Controls.StackPanel]::new()
        $rowToolbar.Orientation = 'Horizontal'
        $rowToolbar.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        [System.Windows.Controls.DockPanel]::SetDock($rowToolbar, 'Top')
        [void]$contentPanel.Children.Add($rowToolbar)

        # Add Row button
        $addRowBtn = [System.Windows.Controls.Button]::new()
        $addRowBtn.Width = 36
        $addRowBtn.Height = 28
        $addRowBtn.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
        $addRowBtn.ToolTip = 'Add new row'
        $addRowBtn.Padding = [System.Windows.Thickness]::new(0)

        $addRowIcon = [System.Windows.Controls.TextBlock]::new()
        $addRowIcon.Text = [PsUi.ModuleContext]::GetIcon('Add')
        $addRowIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $addRowIcon.FontSize = 14
        $addRowIcon.HorizontalAlignment = 'Center'
        $addRowIcon.VerticalAlignment = 'Center'
        $addRowBtn.Content = $addRowIcon

        Set-ButtonStyle -Button $addRowBtn
        [void]$rowToolbar.Children.Add($addRowBtn)

        # Delete Row button
        $deleteRowBtn = [System.Windows.Controls.Button]::new()
        $deleteRowBtn.Width = 36
        $deleteRowBtn.Height = 28
        $deleteRowBtn.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
        $deleteRowBtn.ToolTip = 'Delete selected row(s)'
        $deleteRowBtn.Padding = [System.Windows.Thickness]::new(0)

        $deleteRowIcon = [System.Windows.Controls.TextBlock]::new()
        $deleteRowIcon.Text = [PsUi.ModuleContext]::GetIcon('Delete')
        $deleteRowIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $deleteRowIcon.FontSize = 14
        $deleteRowIcon.HorizontalAlignment = 'Center'
        $deleteRowIcon.VerticalAlignment = 'Center'
        $deleteRowBtn.Content = $deleteRowIcon

        Set-ButtonStyle -Button $deleteRowBtn
        [void]$rowToolbar.Children.Add($deleteRowBtn)

        # Copy Row button
        $copyRowBtn = [System.Windows.Controls.Button]::new()
        $copyRowBtn.Width = 36
        $copyRowBtn.Height = 28
        $copyRowBtn.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
        $copyRowBtn.ToolTip = 'Duplicate selected row'
        $copyRowBtn.Padding = [System.Windows.Thickness]::new(0)

        $copyRowIcon = [System.Windows.Controls.TextBlock]::new()
        $copyRowIcon.Text = [PsUi.ModuleContext]::GetIcon('Copy')
        $copyRowIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $copyRowIcon.FontSize = 14
        $copyRowIcon.HorizontalAlignment = 'Center'
        $copyRowIcon.VerticalAlignment = 'Center'
        $copyRowBtn.Content = $copyRowIcon

        Set-ButtonStyle -Button $copyRowBtn
        [void]$rowToolbar.Children.Add($copyRowBtn)

        # Save button (overwrites original file)
        $saveBtn = [System.Windows.Controls.Button]::new()
        $saveBtn.Width = 36
        $saveBtn.Height = 28
        $saveBtn.Margin = [System.Windows.Thickness]::new(8, 0, 4, 0)
        $saveBtn.ToolTip = 'Save (overwrite original)'
        $saveBtn.Padding = [System.Windows.Thickness]::new(0)

        $saveIcon = [System.Windows.Controls.TextBlock]::new()
        $saveIcon.Text = [PsUi.ModuleContext]::GetIcon('Save')
        $saveIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $saveIcon.FontSize = 14
        $saveIcon.HorizontalAlignment = 'Center'
        $saveIcon.VerticalAlignment = 'Center'
        $saveBtn.Content = $saveIcon

        Set-ButtonStyle -Button $saveBtn
        [void]$rowToolbar.Children.Add($saveBtn)

        # Save All button
        $saveAllBtn = [System.Windows.Controls.Button]::new()
        $saveAllBtn.Width = 36
        $saveAllBtn.Height = 28
        $saveAllBtn.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
        $saveAllBtn.ToolTip = 'Save All files'
        $saveAllBtn.Padding = [System.Windows.Thickness]::new(0)

        $saveAllIcon = [System.Windows.Controls.TextBlock]::new()
        $saveAllIcon.Text = [PsUi.ModuleContext]::GetIcon('SaveLocal')
        $saveAllIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $saveAllIcon.FontSize = 14
        $saveAllIcon.HorizontalAlignment = 'Center'
        $saveAllIcon.VerticalAlignment = 'Center'
        $saveAllBtn.Content = $saveAllIcon

        Set-ButtonStyle -Button $saveAllBtn
        [void]$rowToolbar.Children.Add($saveAllBtn)

        # Save As button (export to new file)
        $saveAsBtn = [System.Windows.Controls.Button]::new()
        $saveAsBtn.Width = 36
        $saveAsBtn.Height = 28
        $saveAsBtn.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
        $saveAsBtn.ToolTip = 'Save As (export to new file)'
        $saveAsBtn.Padding = [System.Windows.Thickness]::new(0)

        $saveAsIcon = [System.Windows.Controls.TextBlock]::new()
        $saveAsIcon.Text = [PsUi.ModuleContext]::GetIcon('SaveAs')
        $saveAsIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $saveAsIcon.FontSize = 14
        $saveAsIcon.HorizontalAlignment = 'Center'
        $saveAsIcon.VerticalAlignment = 'Center'
        $saveAsBtn.Content = $saveAsIcon

        Set-ButtonStyle -Button $saveAsBtn
        [void]$rowToolbar.Children.Add($saveAsBtn)

        # Data Type Info button
        $typeInfoBtn = [System.Windows.Controls.Button]::new()
        $typeInfoBtn.Width = 36
        $typeInfoBtn.Height = 28
        $typeInfoBtn.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
        $typeInfoBtn.ToolTip = 'Show column type information'
        $typeInfoBtn.Padding = [System.Windows.Thickness]::new(0)

        $typeInfoIcon = [System.Windows.Controls.TextBlock]::new()
        $typeInfoIcon.Text = [PsUi.ModuleContext]::GetIcon('Info')
        $typeInfoIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $typeInfoIcon.FontSize = 14
        $typeInfoIcon.HorizontalAlignment = 'Center'
        $typeInfoIcon.VerticalAlignment = 'Center'
        $typeInfoBtn.Content = $typeInfoIcon

        Set-ButtonStyle -Button $typeInfoBtn
        [void]$rowToolbar.Children.Add($typeInfoBtn)

        # DataGrid for CSV editing
        $dataGrid = [System.Windows.Controls.DataGrid]::new()
        Set-DataGridStyle -Grid $dataGrid -SelectionMode Extended
        $dataGrid.EnableRowVirtualization = $true
        $dataGrid.EnableColumnVirtualization = $false  # Keep false for ComboBoxes
        $dataGrid.CanUserAddRows = $false
        $dataGrid.IsReadOnly = $false
        [void]$contentPanel.Children.Add($dataGrid)

        # Store unfiltered data separately - filtering will rebuild the observable collection
        # This avoids CollectionView.Filter which breaks with PowerShell delegates during WPF sorting
        $script:unfilteredData = $null
        $script:currentFilterText = ''


        # PopupOnSelection handler - opens text viewer/editor when cell is selected
        $dataGrid.Add_BeginningEdit({
                param($sender, $eventArgs)

                if ($ColumnsToPopupOnSelection -and $ColumnsToPopupOnSelection.Count -gt 0) {
                    $columnHeader = $eventArgs.Column.Header

                    if ($columnHeader -in $ColumnsToPopupOnSelection) {
                        # Cancel normal inline edit
                        $eventArgs.Cancel = $true

                        # Determine if this column is readonly
                        $isColumnReadOnly = $ReadOnlyColumns -and ($columnHeader -in $ReadOnlyColumns)

                        # Get current cell value
                        $row = $eventArgs.Row.Item
                        $currentValue = $row.$columnHeader

                        # Open Out-TextEditor (readonly for readonly columns)
                        $titlePrefix = if ($isColumnReadOnly) { 'View' } else { 'Edit' }
                        $result = Out-TextEditor -InitialText $currentValue -TitleText "${titlePrefix}: $columnHeader" -ReadOnly:$isColumnReadOnly

                        # Only update if editable and result returned
                        if (!$isColumnReadOnly -and $null -ne $result) {
                            # Update the cell value
                            $row.$columnHeader = $result

                            # Mark file as modified
                            if ($script:currentFileName) {
                                $Script:CurrentCSVData[$script:currentFileName].Modified = $true
                            }

                            # Force UI refresh using multiple approaches
                            if ($script:collectionView) { $script:collectionView.Refresh() }
                            $dataGrid.Items.Refresh()
                            $dataGrid.UpdateLayout()

                            # Deselect and reselect to force cell redraw
                            $tempSelected = $dataGrid.SelectedItem
                            $dataGrid.SelectedItem = $null
                            $dataGrid.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Render)
                            $dataGrid.SelectedItem = $tempSelected
                            $dataGrid.ScrollIntoView($row)
                        }
                    }
                }
            }.GetNewClosure())

        # Context menu for CSV grid
        $null = New-DataGridContextMenu -DataGrid $dataGrid

        $script:currentObservable = $null
        $script:currentFileName = $null

        $loadCSVFile = {
            param($fileName)

            $script:currentFileName = $fileName
            $csvInfo = $Script:CurrentCSVData[$fileName]
            $data = $csvInfo.Data

            $dataGrid.Columns.Clear()

            if ($data.Count -gt 0) {
                $propNames = $data[0].PSObject.Properties.Name

                foreach ($propName in $propNames) {
                    # Column config: ComboBox binding, read-only status, and popup handling
                    $isInPopupList = $ColumnsToPopupOnSelection -and ($propName -in $ColumnsToPopupOnSelection)
                    $isReadOnly = $ReadOnlyColumns -and ($propName -in $ReadOnlyColumns) -and !$isInPopupList

                    if ($ColumnComboBoxes -and $ColumnComboBoxes.ContainsKey($propName)) {
                        # CREATE COMBOBOX COLUMN
                        $col = [System.Windows.Controls.DataGridComboBoxColumn]::new()
                        $col.Header = $propName
                        $col.SortMemberPath = $propName
                        $col.IsReadOnly = $isReadOnly
                        $col.SelectedItemBinding = [System.Windows.Data.Binding]::new($propName)
                        $col.SelectedItemBinding.Mode = [System.Windows.Data.BindingMode]::TwoWay
                        $col.SelectedItemBinding.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::PropertyChanged

                        # Get allowed values (support both simple array and advanced hashtable)
                        $allowedValues = if ($ColumnComboBoxes[$propName] -is [array]) {
                            $ColumnComboBoxes[$propName]
                        }
                        else {
                            $ColumnComboBoxes[$propName].Values
                        }

                        # STRATEGY 1: Add existing values from CSV if not in list (preserve data)
                        $existingValues = $data | Select-Object -ExpandProperty $propName -Unique -ErrorAction SilentlyContinue
                        $allValues = [System.Collections.Generic.List[object]]::new()
                        foreach ($val in $allowedValues) {
                            [void]$allValues.Add($val)
                        }
                        foreach ($val in $existingValues) {
                            if ($val -and $val -notin $allValues) {
                                [void]$allValues.Add($val)
                            }
                        }

                        # Set ItemsSource
                        $col.ItemsSource = $allValues

                        # Apply full ComboBox styling (uses Set-ComboBoxStyle for complete theming)
                        $tempCombo = [System.Windows.Controls.ComboBox]::new()
                        Set-ComboBoxStyle -ComboBox $tempCombo
                        $col.ElementStyle = $tempCombo.Style
                        $col.EditingElementStyle = Get-DataGridComboBoxEditStyle

                        # Column width
                        if ($ForceTextWrap) {
                            $col.Width = [System.Windows.Controls.DataGridLength]::new(150)
                        }
                        else {
                            $col.Width = [System.Windows.Controls.DataGridLength]::new(1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
                        }

                        [void]$dataGrid.Columns.Add($col)
                    }
                    else {
                        # CREATE NORMAL TEXT COLUMN
                        $col = [System.Windows.Controls.DataGridTextColumn]::new()
                        $col.Header = $propName
                        $col.SortMemberPath = $propName
                        $col.IsReadOnly = $isReadOnly
                        $col.Binding = [System.Windows.Data.Binding]::new($propName)
                        $col.Binding.Mode = [System.Windows.Data.BindingMode]::TwoWay
                        $col.Binding.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::LostFocus

                        # Apply themed editing style
                        $col.EditingElementStyle = Get-DataGridEditStyle

                        if ($ForceTextWrap) {
                            $col.Width = [System.Windows.Controls.DataGridLength]::new(150)
                        }
                        else {
                            # Set column width to star sizing for even distribution
                            $col.Width = [System.Windows.Controls.DataGridLength]::new(1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
                        }

                        [void]$dataGrid.Columns.Add($col)
                    }
                }

                $script:currentObservable = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
                foreach ($item in $data) {
                    [void]$script:currentObservable.Add($item)
                }

                # Store a copy of unfiltered data for filtering without CollectionView.Filter
                $script:unfilteredData = [System.Collections.Generic.List[object]]::new()
                foreach ($item in $data) {
                    [void]$script:unfilteredData.Add($item)
                }

                $script:collectionView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($script:currentObservable)
                $dataGrid.ItemsSource = $script:collectionView

                # Clear any previous filter text when switching files
                $script:currentFilterText = ''
            }
            else {
                $dataGrid.ItemsSource = $null
                $script:currentObservable = $null
            }
        }

        # Initial load
        $firstFile = @($Script:CurrentCSVData.Keys)[0]
        & $loadCSVFile $firstFile

        # File combo handler
        $fileCombo.Add_SelectionChanged({
                $selectedFile = $this.SelectedItem
                if ($selectedFile) {
                    & $loadCSVFile $selectedFile
                }
            }.GetNewClosure())

        # Filter handler with debouncing (300ms delay)
        $filterBox.Add_TextChanged({
            # Show/hide clear button
            $clearBtn = $filterBox.Tag.ClearButton
            if ($clearBtn) {
                $clearBtn.Visibility = if ([string]::IsNullOrEmpty($filterBox.Text)) { 'Collapsed' } else { 'Visible' }
            }

            # Cancel existing timer
            if ($script:filterTimer) {
                $script:filterTimer.Stop()
                $script:filterTimer = $null
            }

            # Create new timer (300ms delay)
            $script:filterTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $script:filterTimer.Interval = [TimeSpan]::FromMilliseconds(300)

            $script:filterTimer.Add_Tick({
                $filterText = $filterBox.Text.Trim()
                $script:currentFilterText = $filterText

                # Rebuild the ObservableCollection with filtered items
                # This avoids CollectionView.Filter which breaks with PowerShell delegates during WPF sorting
                if ($script:unfilteredData -and $script:currentObservable) {
                    # Preserve current sort descriptions before rebuilding
                    $sortDescriptions = @()
                    if ($script:collectionView) {
                        foreach ($sd in $script:collectionView.SortDescriptions) {
                            $sortDescriptions += $sd
                        }
                    }

                    # Clear and repopulate the observable collection
                    $script:currentObservable.Clear()

                    foreach ($item in $script:unfilteredData) {
                        if ([string]::IsNullOrEmpty($filterText)) {
                            # No filter - add all items
                            [void]$script:currentObservable.Add($item)
                        }
                        else {
                            # Check if any property contains the filter text
                            $matches = $false
                            foreach ($prop in $item.PSObject.Properties) {
                                $val = $prop.Value
                                if ($val -and $val.ToString().IndexOf($filterText, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                    $matches = $true
                                    break
                                }
                            }
                            if ($matches) {
                                [void]$script:currentObservable.Add($item)
                            }
                        }
                    }

                    # Put sort back
                    if ($script:collectionView -and $sortDescriptions.Count -gt 0) {
                        $script:collectionView.SortDescriptions.Clear()
                        foreach ($sd in $sortDescriptions) {
                            $script:collectionView.SortDescriptions.Add($sd)
                        }
                    }
                }

                # Stop and cleanup timer
                $script:filterTimer.Stop()
                $script:filterTimer = $null
            })

            $script:filterTimer.Start()
        })

        # Add Row handler
        $addRowBtn.Add_Click({
                try {
                    if (!$script:currentFileName) {
                        Show-ThemedDialog -Title 'No File' -Message 'No file selected.' -Buttons OK -Icon Warning
                        return
                    }
                    if (!$script:currentObservable) {
                        Show-ThemedDialog -Title 'No Data' -Message 'No data loaded.' -Buttons OK -Icon Warning
                        return
                    }

                    $csvInfo = $Script:CurrentCSVData[$script:currentFileName]
                    if (!$csvInfo -or $csvInfo.Data.Count -eq 0) {
                        Show-ThemedDialog -Title 'No Data' -Message 'No CSV data available.' -Buttons OK -Icon Warning
                        return
                    }

                    # Create new row with empty values or defaults from ComboBoxes
                    $newRow = [PSCustomObject]@{}
                    foreach ($prop in $csvInfo.Data[0].PSObject.Properties) {
                        $defaultValue = ''

                        # If column has ComboBox, use first value as default
                        if ($ColumnComboBoxes -and $ColumnComboBoxes.ContainsKey($prop.Name)) {
                            $comboConfig = $ColumnComboBoxes[$prop.Name]

                            if ($comboConfig -is [array]) {
                                # Simple array format - use first value
                                if ($comboConfig.Count -gt 0) {
                                    $defaultValue = $comboConfig[0]
                                }
                            }
                            else {
                                # Advanced hashtable format - check for DefaultValue
                                if ($comboConfig.DefaultValue) {
                                    $defaultValue = $comboConfig.DefaultValue
                                }
                                elseif ($comboConfig.Values -and $comboConfig.Values.Count -gt 0) {
                                    $defaultValue = $comboConfig.Values[0]
                                }
                            }
                        }

                        $newRow | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $defaultValue
                    }

                    [void]$script:currentObservable.Add($newRow)
                    [void]$csvInfo.Data.Add($newRow)

                    # Also add to unfiltered master list
                    if ($script:unfilteredData) {
                        [void]$script:unfilteredData.Add($newRow)
                    }

                    $csvInfo.Modified = $true

                    # Refresh view and scroll to new row
                    if ($script:collectionView) {
                        $script:collectionView.Refresh()
                    }

                    # Select and scroll to the new row
                    $dataGrid.SelectedItem = $newRow
                    $dataGrid.ScrollIntoView($newRow)
                }
                catch {
                    Show-ThemedDialog -Title 'Add Failed' -Message "Failed to add row: $_" -Buttons OK -Icon Error
                    return
                }
            })

        # Delete Row handler
        $deleteRowBtn.Add_Click({
                try {
                    if (!$script:currentFileName) {
                        Show-ThemedDialog -Title 'No File' -Message 'No file selected.' -Buttons OK -Icon Warning
                        return
                    }
                    if (!$script:currentObservable) {
                        Show-ThemedDialog -Title 'No Data' -Message 'No data loaded.' -Buttons OK -Icon Warning
                        return
                    }

                    $selected = $dataGrid.SelectedItems
                    if (!$selected -or $selected.Count -eq 0) {
                        Show-ThemedDialog -Title 'No Selection' -Message 'Please select row(s) to delete.' -Buttons OK -Icon Warning
                        return
                    }

                    $count = $selected.Count
                    $result = Show-ThemedDialog -Title 'Confirm Delete' -Message "Delete $count row(s)?" -Buttons YesNo -Icon Question

                    if ($result -eq 'Yes') {
                        $csvInfo = $Script:CurrentCSVData[$script:currentFileName]
                        $toRemove = @($selected)
                        foreach ($item in $toRemove) {
                            [void]$script:currentObservable.Remove($item)
                            [void]$csvInfo.Data.Remove($item)

                            # Also remove from unfiltered master list
                            if ($script:unfilteredData) {
                                [void]$script:unfilteredData.Remove($item)
                            }
                        }
                        $csvInfo.Modified = $true

                        if ($script:collectionView) {
                            $script:collectionView.Refresh()
                        }

                        Show-ThemedDialog -Title 'Deleted' -Message "$count row(s) deleted." -Buttons OK -Icon Info
                    }
                }
                catch {
                    Show-ThemedDialog -Title 'Delete Failed' -Message "Failed to delete rows: $_" -Buttons OK -Icon Error
                }
            })

        # Copy Row handler
        $copyRowBtn.Add_Click({
                try {
                    if (!$script:currentFileName) {
                        Show-ThemedDialog -Title 'No File' -Message 'No file selected.' -Buttons OK -Icon Warning
                        return
                    }
                    if (!$script:currentObservable) {
                        Show-ThemedDialog -Title 'No Data' -Message 'No data loaded.' -Buttons OK -Icon Warning
                        return
                    }

                    $selected = $dataGrid.SelectedItem
                    if (!$selected) {
                        Show-ThemedDialog -Title 'No Selection' -Message 'Please select a row to duplicate.' -Buttons OK -Icon Warning
                        return
                    }

                    $csvInfo = $Script:CurrentCSVData[$script:currentFileName]
                    $newRow = [PSCustomObject]@{}
                    foreach ($prop in $selected.PSObject.Properties) {
                        $newRow | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
                    }

                    [void]$script:currentObservable.Add($newRow)
                    [void]$csvInfo.Data.Add($newRow)
                    $csvInfo.Modified = $true

                    # Refresh view and scroll to new row
                    if ($script:collectionView) {
                        $script:collectionView.Refresh()
                    }

                    $dataGrid.SelectedItem = $newRow
                    $dataGrid.ScrollIntoView($newRow)
                }
                catch {
                    Show-ThemedDialog -Title 'Copy Failed' -Message "Failed to duplicate row: $_" -Buttons OK -Icon Error
                }
            })

        # Track cell edits - fires when any cell edit completes
        $dataGrid.Add_CellEditEnding({
                param($sender, $eventArgs)
                if ($script:currentFileName -and $eventArgs.EditAction -eq 'Commit') {
                    $Script:CurrentCSVData[$script:currentFileName].Modified = $true
                    Write-Debug "CellEditEnding - marked '$script:currentFileName' as modified"
                }
            })

        # Track row edits (backup detection)
        $dataGrid.Add_RowEditEnding({
                param($sender, $eventArgs)
                if ($script:currentFileName -and $eventArgs.EditAction -eq 'Commit') {
                    $Script:CurrentCSVData[$script:currentFileName].Modified = $true
                    Write-Debug "RowEditEnding - marked '$script:currentFileName' as modified"
                }
            })

        # For ComboBox columns - detect selection changes via PreparingCellForEdit
        $dataGrid.Add_PreparingCellForEdit({
                param($sender, $eventArgs)
                $editElement = $eventArgs.EditingElement
                if ($editElement -is [System.Windows.Controls.ComboBox]) {
                    # Hook into ComboBox selection change
                    $editElement.Add_SelectionChanged({
                        if ($script:currentFileName) {
                            $Script:CurrentCSVData[$script:currentFileName].Modified = $true
                            Write-Debug "ComboBox SelectionChanged - marked as modified"
                        }
                    })
                }
            })

        # Save handler (overwrite original file)
        $saveBtn.Add_Click({
                if ($script:currentFileName) {
                    try {
                        $csvInfo = $Script:CurrentCSVData[$script:currentFileName]
                        $exportParams = @{
                            Path              = $csvInfo.Path
                            NoTypeInformation = $true
                            Force             = $true
                        }
                        if ($csvInfo.Delimiter) {
                            $exportParams['Delimiter'] = $csvInfo.Delimiter
                        }
                        $csvInfo.Data | Export-Csv @exportParams
                        Show-ThemedDialog -Title 'Saved' -Message "Saved: $script:currentFileName" -Buttons OK -Icon Info
                    }
                    catch {
                        Show-ThemedDialog -Title 'Save Failed' -Message "Failed to save: $_" -Buttons OK -Icon Error
                    }
                }
                else {
                    Show-ThemedDialog -Title 'No File' -Message 'No file is currently selected.' -Buttons OK -Icon Warning
                }
            })

        # Save All handler (save all files)
        $saveAllBtn.Add_Click({
                $savedCount = 0
                $errorCount = 0
                foreach ($fileName in $Script:CurrentCSVData.Keys) {
                    $csvInfo = $Script:CurrentCSVData[$fileName]
                    try {
                        $exportParams = @{
                            Path              = $csvInfo.Path
                            NoTypeInformation = $true
                            Force             = $true
                        }
                        if ($csvInfo.Delimiter) {
                            $exportParams['Delimiter'] = $csvInfo.Delimiter
                        }
                        $csvInfo.Data | Export-Csv @exportParams
                        $savedCount++
                    }
                    catch {
                        $errorCount++
                        Write-Warning "Failed to save $fileName`: $_"
                    }
                }
                $msg = "Saved $savedCount file(s)."
                if ($errorCount -gt 0) { $msg += " $errorCount error(s)." }
                Show-ThemedDialog -Title 'Save All' -Message $msg -Buttons OK -Icon Info
            })

        # Save As handler (export to new file)
        $saveAsBtn.Add_Click({
                if ($script:currentFileName) {
                    $saveDialog = [Microsoft.Win32.SaveFileDialog]::new()
                    $saveDialog.Filter = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
                    $saveDialog.DefaultExt = '.csv'
                    $saveDialog.FileName = "export_$script:currentFileName"
                    if ($saveDialog.ShowDialog()) {
                        try {
                            $csvInfo = $Script:CurrentCSVData[$script:currentFileName]
                            $exportParams = @{
                                Path              = $saveDialog.FileName
                                NoTypeInformation = $true
                                Force             = $true
                            }
                            if ($csvInfo.Delimiter) {
                                $exportParams['Delimiter'] = $csvInfo.Delimiter
                            }
                            $csvInfo.Data | Export-Csv @exportParams
                            Show-ThemedDialog -Title 'Saved' -Message "Data saved to:`n$($saveDialog.FileName)" -Buttons OK -Icon Info
                        }
                        catch {
                            Show-ThemedDialog -Title 'Save Failed' -Message "Failed to save: $_" -Buttons OK -Icon Error
                        }
                    }
                }
                else {
                    Show-ThemedDialog -Title 'No File' -Message 'No file is currently selected.' -Buttons OK -Icon Warning
                }
            })

        # Type Info handler
        $typeInfoBtn.Add_Click({
                if ($script:currentFileName) {
                    $csvInfo = $Script:CurrentCSVData[$script:currentFileName]
                    if ($csvInfo.Data.Count -gt 0) {
                        $rowCount = $csvInfo.Data.Count
                        $colCount = @($csvInfo.Data[0].PSObject.Properties).Count

                        $message = "File: $script:currentFileName`nPath: $($csvInfo.Path)`nRows: $rowCount`nColumns: $colCount`nDelimiter: '$($csvInfo.Delimiter)'`nModified: $($csvInfo.Modified)"

                        Show-ThemedDialog -Title 'Data Information' -Message $message -Buttons OK -Icon Info
                    }
                }
                else {
                    Show-ThemedDialog -Title 'No File' -Message 'No file is currently selected.' -Buttons OK -Icon Warning
                }
            })

        # Wire up standard window loaded behavior with icon
        Initialize-UiWindowLoaded -Window $window -SetIcon

        # Cleanup on window close
        $window.Add_Closed({
            # Stop any active filter timer to prevent callbacks on disposed controls
            if ($script:filterTimer) {
                $script:filterTimer.Stop()
                $script:filterTimer = $null
            }

            # Clear collection view reference
            $script:collectionView = $null

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

        # Cleanup script-scoped data
        $Script:CurrentCSVData = @{}
    }
}
