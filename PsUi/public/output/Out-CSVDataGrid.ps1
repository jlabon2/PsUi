function Out-CSVDataGrid {
    <#
    .SYNOPSIS
        Opens CSV files for viewing and editing. Save writes back to disk.
    .DESCRIPTION
        A bulk CSV editor. Point it at one or more CSVs and you get a window that
        opens, sorts, filters, and edits them. Saves go back to the file they came
        from, or to a new path if you use Save As.

        Internals use $script: scoped state, so opening two CSV grids from the same
        session at the same time can step on itself. Modal dialogs keep this from
        happening in normal use. Avoid calling this in parallel runspaces sharing the
        module.
    .PARAMETER CSVDirectory
        Folder to load every .csv file from. Top level only, no recursion - pipe
        Get-ChildItem -Recurse output to -CSVFiles for that.
    .PARAMETER CSVFiles
        One or more CSV file paths. Also takes pipeline input from Get-ChildItem.
    .PARAMETER TitleText
        Window title.
    .PARAMETER IsFilterable
        Kept for v2.x call sites. The filter box is always on now, so this switch
        changes nothing.
    .PARAMETER IsResizeable
        Adds the corner resize grip. The window resizes either way. Kept for v2.x
        call sites.
    .PARAMETER ColumnsToPopupOnSelection
        Column names that pop a separate viewer when clicked. Use for long values
        you can't easily edit inline.
    .PARAMETER ColumnComboBoxes
        Columns you want edited via a dropdown instead of a textbox. Key is the
        column name, value is either an array of allowed values or a hashtable
        @{ Values = @(...); DefaultValue = '...' }.

        Example: @{ Priority = @{ Values = @('Low', 'High'); DefaultValue = 'Low' } }

        A column can't be in both this and ColumnsToPopupOnSelection - that throws at startup.
    .PARAMETER ReadOnlyColumns
        Columns that can't be edited. If a column is also in ColumnsToPopupOnSelection,
        the popup viewer goes read-only too.
    .PARAMETER ForceTextWrap
        Wrap text inside cells instead of clipping it.
    .PARAMETER Width
        Window width in pixels (400-2000). Defaults to 1000.
    .PARAMETER Height
        Window height in pixels (300-1500). Defaults to 700.
    .PARAMETER Theme
        Color theme. See Get-UiThemeTemplate for the list. When not given, follows
        the session's active theme if one is loaded, otherwise Light.
    .PARAMETER Delimiter
        Column separator character. Defaults to comma. Use ';' for semicolon-delimited
        files or ``"`t"`` for tab-delimited files.
    .PARAMETER NoHeader
        Treat the first row as data, not headers. Columns get named Column1..ColumnN.
    .PARAMETER IconFont
        Which icon font to use for the toolbar: Inherit (default), Auto, SegoeMDL2 (Win10),
        or SegoeFluentIcons (Win11). Only matters when this is the top-level window. When
        hosted inside another PsUi window, that window's font wins.
    .PARAMETER NoIconFontFallback
        Don't borrow glyphs from the other Segoe icon font when the active one is
        missing them. Absent toolbar icons render as empty boxes instead.
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

        [switch]$NoHeader,

        # Default 'Inherit' (rather than leaving unbound) so $IconFont always satisfies the ValidateSet. Otherwise any .GetNewClosure() inside the function would explode trying to carry an unbound "" value through the attribute.
        [ValidateSet('Inherit', 'Auto', 'SegoeMDL2', 'SegoeFluentIcons')]
        [string]$IconFont = 'Inherit',

        [switch]$NoIconFontFallback
    )


    begin {
        # Out-CSVDataGrid calls ShowDialog on the host thread, so an async button action (already on a worker thread) deadlocks waiting on the UI thread.
        # Block early until the file list path is rebuilt on top of New-UiWindow the way Out-Datagrid is.
        if ([PsUi.AsyncExecutor]::CurrentExecutor) {
            Write-Error 'Out-CSVDataGrid cannot be called from an async button action (ShowDialog requires the UI thread). Use -NoAsync on the button, or call Out-Datagrid instead if you only need to view tabular data.'
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
            # $colors gets hydrated into this scope by the async runspace - no need to resolve it again.
            Show-UiMessageDialog -Title $Title -Message $Message -Buttons $Buttons -Icon $Icon -ThemeColors $colors
        }

        function Get-DataGridEditStyle {
            $editStyle = [System.Windows.Style]::new([System.Windows.Controls.TextBox])

            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBox]::BackgroundProperty, (ConvertTo-UiBrush $colors.ControlBg)))
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBox]::ForegroundProperty, (ConvertTo-UiBrush $colors.ControlFg)))
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBox]::BorderBrushProperty, (ConvertTo-UiBrush $colors.Accent)))

            # No border - keeps the row height stable when editing starts.
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBox]::BorderThicknessProperty, [System.Windows.Thickness]::new(0)))
            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBox]::PaddingProperty, [System.Windows.Thickness]::new(2, 0, 2, 0)))

            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBox]::MarginProperty, [System.Windows.Thickness]::new(0)))

            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBox]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Stretch))

            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBox]::VerticalContentAlignmentProperty, [System.Windows.VerticalAlignment]::Center))

            return $editStyle
        }

        function Get-DataGridComboBoxEditStyle {
            $editStyle = [System.Windows.Style]::new([System.Windows.Controls.ComboBox])

            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.ComboBox]::BackgroundProperty, (ConvertTo-UiBrush $colors.ControlBg)))

            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.ComboBox]::ForegroundProperty, (ConvertTo-UiBrush $colors.ControlFg)))

            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.ComboBox]::BorderBrushProperty, (ConvertTo-UiBrush $colors.Accent)))

            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.ComboBox]::BorderThicknessProperty, [System.Windows.Thickness]::new(0)))

            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.ComboBox]::PaddingProperty, [System.Windows.Thickness]::new(2, 0, 2, 0)))

            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.ComboBox]::MarginProperty, [System.Windows.Thickness]::new(0)))

            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.ComboBox]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Stretch))

            [void]$editStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.ComboBox]::VerticalContentAlignmentProperty, [System.Windows.VerticalAlignment]::Center))

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
        # Outermost net: stray NullRefs from close time handlers otherwise ride up to the parent button -Action catch and pop an "Error: Open Out-CSVDataGrid" dialog on the way out. Real errors hit the inner try/catch sites.
        try {
            $script:filterTimer = $null
            $windowShown = $false

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

            # __WPFThemeColors isn't injected into a -NoAsync button action, so $isStandalone reads $true even for a nested launch from a live window. A session already current at entry means a parent owns it - capture that so the close handler never disposes someone else's session.
            $hasParentSession = [PsUi.SessionManager]::CurrentSessionId -ne [System.Guid]::Empty

            # RowContextMenu actions invoke without __WPFThemeColors in scope - fall back to ActiveTheme, otherwise the default 'Light' below flips the parent window via Initialize-UITheme.
            if (!$PSBoundParameters.ContainsKey('Theme')) {
                $active = [PsUi.ModuleContext]::ActiveTheme
                if (![string]::IsNullOrWhiteSpace($active)) { $Theme = $active }
            }

            if ($isStandalone) {
                # Create the Application on this (ShowDialog) thread before Initialize-UITheme - ThemeEngine no longer creates it, and a cross thread App loses content theming. Does nothing if one exists.
                [void][PsUi.ThemeEngine]::EnsureApplication()
                $colors = Initialize-UITheme -Theme $Theme
            }
            else {
                $colors = Get-Variable -Name __WPFThemeColors -ValueOnly -ErrorAction SilentlyContinue
            }

            # Last resort fallback if the lookups above all came back empty.
            if (!$colors) {
                $colors = Initialize-UITheme -Theme $Theme
            }

            # Push -IconFont override when standalone. Returns $null when inside a parent (parent's font wins) or when no override params were supplied. Restore runs after ShowDialog on the success path. The trap below covers throws between here and there.
            $overrideParams = @{
                IsStandalone       = $isStandalone
                BoundParameters    = $PSBoundParameters
                IconFont           = $IconFont
                NoIconFontFallback = [bool]$NoIconFontFallback
            }
            $iconFontSnap = Push-UiIconFontOverride @overrideParams

            # A throw between the push and the post ShowDialog restore would leak the override.
            # trap catches it at function scope, restores, then break rethrows.
            trap {
                if ($iconFontSnap) {
                    [PsUi.ModuleContext]::RestoreIconFontState($iconFontSnap)
                    $iconFontSnap = $null
                }
                break
            }

            $Script:CurrentCSVData = @{}
            $Script:HasChanges = $false

            foreach ($filePath in $allFiles) {
                $baseName = [System.IO.Path]::GetFileName($filePath)
                try {
                    $importParams = @{
                        Path      = $filePath
                        Delimiter = $Delimiter
                    }
                    if ($NoHeader) {
                        # No header row to read from - make up column names from the column count.
                        $firstLine = Get-Content $filePath -First 1
                        $columnCount = ($firstLine -split [regex]::Escape($Delimiter)).Count
                        $headers = 1..$columnCount | ForEach-Object { "Column$_" }
                        $importParams['Header'] = $headers
                    }
                    $csvData = Import-Csv @importParams

                    # Two files sharing a basename (e.g. -Recurse over folders each holding config.csv) collapsed to one key - the earlier vanished from the combo and Save misfired to the survivor's path. Tag the parent folder on collision so each file keeps its own entry and Path. The key is opaque: it's the combo label and the save lookup key, nothing rebuilds it from the path.
                    $fileName = $baseName
                    if ($Script:CurrentCSVData.ContainsKey($fileName)) {
                        $parentDir = Split-Path -Leaf (Split-Path -Parent $filePath)
                        $fileName  = '{0}  ({1})' -f $baseName, $parentDir
                        $dupIndex  = 2
                        while ($Script:CurrentCSVData.ContainsKey($fileName)) {
                            $fileName = '{0}  ({1} {2})' -f $baseName, $parentDir, $dupIndex
                            $dupIndex++
                        }
                    }
                    $Script:CurrentCSVData[$fileName] = @{
                        Path      = $filePath
                        Data      = [System.Collections.ArrayList]@($csvData)
                        Modified  = $false
                        Delimiter = $Delimiter
                    }
                }
                catch {
                    Write-Warning "Failed to load $baseName`: $_"
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

            # Owner chain so an Alt+Tab back to the parent window brings this one with it.
            $null = Set-WindowOwner -Window $window
            $window.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'WindowBackgroundBrush')
            $window.SetResourceReference([System.Windows.Window]::ForegroundProperty, 'ControlForegroundBrush')

            Set-UIResources -Window $window -Colors $colors

            $appId = "PsUi.CSVEditor." + [Guid]::NewGuid().ToString("N").Substring(0, 8)
            [PsUi.WindowManager]::SetWindowAppId($window, $appId)

            $csvWindowIcon = $null
            try {
                $csvWindowIcon = New-WindowIcon -Colors $colors
                if ($csvWindowIcon) { window.Icon = $csvWindowIcon   }
            }
            catch {
                Write-Verbose "Failed to create window icon: $_"
            }

            $overlayIcon = $null
            try {
                $csvGlyph = [PsUi.ModuleContext]::GetIcon('Document')
                $overlayIcon = New-TaskbarOverlayIcon -GlyphChar $csvGlyph -Color $colors.Accent
                # Stash the glyph in Resources so the theme handler can rebuild the overlay on theme switch.
                $window.Resources['OverlayGlyph'] = $csvGlyph
            }
            catch { Write-Debug "Taskbar overlay failed: $_" }

            $capturedCsvWindow = $window
            $capturedCsvIcon   = $csvWindowIcon
            $capturedOverlay   = $overlayIcon

            $window.Add_Loaded({
                if ($capturedCsvIcon) { [PsUi.WindowManager]::SetTaskbarIcon($capturedCsvWindow, $capturedCsvIcon) }
                if ($capturedOverlay) {    [PsUi.WindowManager]::SetTaskbarOverlay($capturedCsvWindow, $capturedOverlay, 'CSV')  }
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
            $col1 = [System.Windows.Controls.ColumnDefinition]@{  Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
            $col2 = [System.Windows.Controls.ColumnDefinition]@{  Width = [System.Windows.GridLength]::Auto }
            [void]$headerGrid.ColumnDefinitions.Add($col1)
            [void]$headerGrid.ColumnDefinitions.Add($col2)

            $headerStack = [System.Windows.Controls.StackPanel]@{ Orientation = 'Horizontal' }
            [System.Windows.Controls.Grid]::SetColumn($headerStack, 0)

            $headerIcon = [System.Windows.Controls.TextBlock]@{
                Text              = [PsUi.ModuleContext]::GetIcon('Document')
                FontFamily        = [PsUi.ModuleContext]::ActiveIconFontFamily
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

            # Add theme button to header but only when running standalone
            if ($isStandalone) {
                $themeButtonData = New-ThemePopupButton -Container $window -CurrentTheme $Theme
                [System.Windows.Controls.Grid]::SetColumn($themeButtonData.Button, 1)
                [void]$headerGrid.Children.Add($themeButtonData.Button)
            }

            $headerBorder.Child = $headerGrid
            [void]$mainPanel.Children.Add($headerBorder)

            $contentPanel = [System.Windows.Controls.DockPanel]@{
                Margin        = [System.Windows.Thickness]::new(12)
                LastChildFill = $true
            }
            [void]$mainPanel.Children.Add($contentPanel)

            $toolbar = [System.Windows.Controls.Grid]@{   Margin = [System.Windows.Thickness]::new(0, 0, 0, 8) }
            [System.Windows.Controls.DockPanel]::SetDock($toolbar, 'Top')

            $col1 = [System.Windows.Controls.ColumnDefinition]@{  Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
            $col2 = [System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::Auto }
            [void]$toolbar.ColumnDefinitions.Add($col1)
            [void]$toolbar.ColumnDefinitions.Add($col2)

            $leftPanel = [System.Windows.Controls.StackPanel]@{  Orientation = 'Horizontal' }
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
            
            foreach ($fileName in $Script:CurrentCSVData.Keys) {  [void]$fileCombo.Items.Add($fileName) }
            
            $fileCombo.SelectedIndex = 0
            
            Set-ComboBoxStyle -ComboBox $fileCombo
            
            [void]$leftPanel.Children.Add($fileCombo)
            [void]$toolbar.Children.Add($leftPanel)

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

            $filterBoxContainer = [System.Windows.Controls.Grid]::new()
            $filterBoxContainer.Width = 200
            $filterBoxContainer.Height = 26
            $filterBoxContainer.VerticalAlignment = 'Center'

            $filterBox = [System.Windows.Controls.TextBox]::new()
            $filterBox.Height = 26
            $filterBox.Padding = [System.Windows.Thickness]::new(4, 0, 20, 0)
            Set-TextBoxStyle -TextBox $filterBox
            [void]$filterBoxContainer.Children.Add($filterBox)

            # Clear button pinned to the right edge of the filter box.
            $filterClearBtn = [System.Windows.Controls.Button]::new()
            $filterClearBtn.Content = [PsUi.ModuleContext]::GetIcon('Cancel')
            $filterClearBtn.FontFamily = [PsUi.ModuleContext]::ActiveIconFontFamily
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

            $rowToolbar = [System.Windows.Controls.StackPanel]::new()
            $rowToolbar.Orientation = 'Horizontal'
            $rowToolbar.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
            [System.Windows.Controls.DockPanel]::SetDock($rowToolbar, 'Top')
            [void]$contentPanel.Children.Add($rowToolbar)

            $addRowBtn = [System.Windows.Controls.Button]::new()
            $addRowBtn.Width = 36
            $addRowBtn.Height = 28
            $addRowBtn.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
            $addRowBtn.ToolTip = 'Add new row'
            $addRowBtn.Padding = [System.Windows.Thickness]::new(0)

            $addRowIcon = [System.Windows.Controls.TextBlock]::new()
            $addRowIcon.Text = [PsUi.ModuleContext]::GetIcon('Add')
            $addRowIcon.FontFamily = [PsUi.ModuleContext]::ActiveIconFontFamily
            $addRowIcon.FontSize = 14
            $addRowIcon.HorizontalAlignment = 'Center'
            $addRowIcon.VerticalAlignment = 'Center'
            $addRowBtn.Content = $addRowIcon

            Set-ButtonStyle -Button $addRowBtn
            [void]$rowToolbar.Children.Add($addRowBtn)

            $deleteRowBtn = [System.Windows.Controls.Button]::new()
            $deleteRowBtn.Width = 36
            $deleteRowBtn.Height = 28
            $deleteRowBtn.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
            $deleteRowBtn.ToolTip = 'Delete selected row(s)'
            $deleteRowBtn.Padding = [System.Windows.Thickness]::new(0)

            $deleteRowIcon = [System.Windows.Controls.TextBlock]::new()
            $deleteRowIcon.Text = [PsUi.ModuleContext]::GetIcon('Delete')
            $deleteRowIcon.FontFamily = [PsUi.ModuleContext]::ActiveIconFontFamily
            $deleteRowIcon.FontSize = 14
            $deleteRowIcon.HorizontalAlignment = 'Center'
            $deleteRowIcon.VerticalAlignment = 'Center'
            $deleteRowBtn.Content = $deleteRowIcon

            Set-ButtonStyle -Button $deleteRowBtn
            [void]$rowToolbar.Children.Add($deleteRowBtn)

            $copyRowBtn = [System.Windows.Controls.Button]::new()
            $copyRowBtn.Width = 36
            $copyRowBtn.Height = 28
            $copyRowBtn.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
            $copyRowBtn.ToolTip = 'Duplicate selected row'
            $copyRowBtn.Padding = [System.Windows.Thickness]::new(0)

            $copyRowIcon = [System.Windows.Controls.TextBlock]::new()
            $copyRowIcon.Text = [PsUi.ModuleContext]::GetIcon('Copy')
            $copyRowIcon.FontFamily = [PsUi.ModuleContext]::ActiveIconFontFamily
            $copyRowIcon.FontSize = 14
            $copyRowIcon.HorizontalAlignment = 'Center'
            $copyRowIcon.VerticalAlignment = 'Center'
            $copyRowBtn.Content = $copyRowIcon

            Set-ButtonStyle -Button $copyRowBtn
            [void]$rowToolbar.Children.Add($copyRowBtn)

            $saveBtn = [System.Windows.Controls.Button]::new()
            $saveBtn.Width = 36
            $saveBtn.Height = 28
            $saveBtn.Margin = [System.Windows.Thickness]::new(8, 0, 4, 0)
            $saveBtn.ToolTip = 'Save (overwrite original)'
            $saveBtn.Padding = [System.Windows.Thickness]::new(0)

            $saveIcon = [System.Windows.Controls.TextBlock]::new()
            $saveIcon.Text = [PsUi.ModuleContext]::GetIcon('Save')
            $saveIcon.FontFamily = [PsUi.ModuleContext]::ActiveIconFontFamily
            $saveIcon.FontSize = 14
            $saveIcon.HorizontalAlignment = 'Center'
            $saveIcon.VerticalAlignment = 'Center'
            $saveBtn.Content = $saveIcon

            Set-ButtonStyle -Button $saveBtn
            [void]$rowToolbar.Children.Add($saveBtn)

            $saveAllBtn = [System.Windows.Controls.Button]::new()
            $saveAllBtn.Width = 36
            $saveAllBtn.Height = 28
            $saveAllBtn.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
            $saveAllBtn.ToolTip = 'Save All files'
            $saveAllBtn.Padding = [System.Windows.Thickness]::new(0)

            $saveAllIcon = [System.Windows.Controls.TextBlock]::new()
            $saveAllIcon.Text = [PsUi.ModuleContext]::GetIcon('SaveLocal')
            $saveAllIcon.FontFamily = [PsUi.ModuleContext]::ActiveIconFontFamily
            $saveAllIcon.FontSize = 14
            $saveAllIcon.HorizontalAlignment = 'Center'
            $saveAllIcon.VerticalAlignment = 'Center'
            $saveAllBtn.Content = $saveAllIcon

            Set-ButtonStyle -Button $saveAllBtn
            [void]$rowToolbar.Children.Add($saveAllBtn)

            $saveAsBtn = [System.Windows.Controls.Button]::new()
            $saveAsBtn.Width = 36
            $saveAsBtn.Height = 28
            $saveAsBtn.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
            $saveAsBtn.ToolTip = 'Save As (export to new file)'
            $saveAsBtn.Padding = [System.Windows.Thickness]::new(0)

            $saveAsIcon = [System.Windows.Controls.TextBlock]::new()
            $saveAsIcon.Text = [PsUi.ModuleContext]::GetIcon('SaveAs')
            $saveAsIcon.FontFamily = [PsUi.ModuleContext]::ActiveIconFontFamily
            $saveAsIcon.FontSize = 14
            $saveAsIcon.HorizontalAlignment = 'Center'
            $saveAsIcon.VerticalAlignment = 'Center'
            $saveAsBtn.Content = $saveAsIcon

            Set-ButtonStyle -Button $saveAsBtn
            [void]$rowToolbar.Children.Add($saveAsBtn)

            $typeInfoBtn = [System.Windows.Controls.Button]::new()
            $typeInfoBtn.Width = 36
            $typeInfoBtn.Height = 28
            $typeInfoBtn.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
            $typeInfoBtn.ToolTip = 'Show column type information'
            $typeInfoBtn.Padding = [System.Windows.Thickness]::new(0)

            $typeInfoIcon = [System.Windows.Controls.TextBlock]::new()
            $typeInfoIcon.Text = [PsUi.ModuleContext]::GetIcon('Info')
            $typeInfoIcon.FontFamily = [PsUi.ModuleContext]::ActiveIconFontFamily
            $typeInfoIcon.FontSize = 14
            $typeInfoIcon.HorizontalAlignment = 'Center'
            $typeInfoIcon.VerticalAlignment = 'Center'
            $typeInfoBtn.Content = $typeInfoIcon

            Set-ButtonStyle -Button $typeInfoBtn
            [void]$rowToolbar.Children.Add($typeInfoBtn)

            $dataGrid = [System.Windows.Controls.DataGrid]::new()
            Set-DataGridStyle -Grid $dataGrid -SelectionMode Extended
            $dataGrid.EnableRowVirtualization = $true
            $dataGrid.EnableColumnVirtualization = $false  # Keep false for ComboBoxes
            $dataGrid.CanUserAddRows = $false
            $dataGrid.IsReadOnly = $false
            [void]$contentPanel.Children.Add($dataGrid)

            # Striping survives both themes. One shot - $loadCSVFile reentry mustn't stack handlers.
            Add-UiDataGridAlternatingBrush -DataGrid $dataGrid

            # Store unfiltered data separately - filtering will rebuild the observable collection
            $script:unfilteredData = $null
            $script:currentFilterText = ''


            # Columns in -ColumnsToPopupOnSelection get an Out-TextEditor on edit instead of inline.
            $dataGrid.Add_BeginningEdit({
                    param($sender, $eventArgs)

                    if ($ColumnsToPopupOnSelection -and $ColumnsToPopupOnSelection.Count -gt 0) {
                        $columnHeader = $eventArgs.Column.Header

                        if ($columnHeader -in $ColumnsToPopupOnSelection) {
                            $eventArgs.Cancel = $true

                            $isColumnReadOnly = $ReadOnlyColumns -and ($columnHeader -in $ReadOnlyColumns)

                            $row = $eventArgs.Row.Item
                            $currentValue = $row.$columnHeader

                            $titlePrefix = if ($isColumnReadOnly) { 'View' } else { 'Edit' }
                            $result = Out-TextEditor -InitialText $currentValue -TitleText "${titlePrefix}: $columnHeader" -ReadOnly:$isColumnReadOnly

                            if (!$isColumnReadOnly -and $null -ne $result) {
                                $row.$columnHeader = $result

                                if ($script:currentFileName) {
                                    $Script:CurrentCSVData[$script:currentFileName].Modified = $true
                                }

                                # PSCustomObject doesn't notify on property change. Refresh + UpdateLayout + a selection bounce is the smallest combo that reliably gets the cell showing the new value.
                                if ($script:collectionView) { $script:collectionView.Refresh() }
                                $dataGrid.Items.Refresh()
                                $dataGrid.UpdateLayout()

                                $tempSelected = $dataGrid.SelectedItem
                                $dataGrid.SelectedItem = $null
                                $dataGrid.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Render)
                                $dataGrid.SelectedItem = $tempSelected
                                $dataGrid.ScrollIntoView($row)
                            }
                        }
                    }
                }.GetNewClosure())

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
                        $isInPopupList = $ColumnsToPopupOnSelection -and ($propName -in $ColumnsToPopupOnSelection)
                        $isReadOnly = $ReadOnlyColumns -and ($propName -in $ReadOnlyColumns) -and !$isInPopupList

                        if ($ColumnComboBoxes -and $ColumnComboBoxes.ContainsKey($propName)) {
                            $col = [System.Windows.Controls.DataGridComboBoxColumn]::new()
                            $col.Header = $propName
                            $col.SortMemberPath = $propName
                            $col.IsReadOnly = $isReadOnly
                            $col.SelectedItemBinding = [System.Windows.Data.Binding]::new($propName)
                            $col.SelectedItemBinding.Mode = [System.Windows.Data.BindingMode]::TwoWay
                            $col.SelectedItemBinding.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::PropertyChanged

                            $allowedValues = if ($ColumnComboBoxes[$propName] -is [array]) {
                                $ColumnComboBoxes[$propName]
                            }
                            else {
                                $ColumnComboBoxes[$propName].Values
                            }

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

                            $col.ItemsSource = $allValues

                            $tempCombo = [System.Windows.Controls.ComboBox]::new()
                            Set-ComboBoxStyle -ComboBox $tempCombo
                            $col.ElementStyle = $tempCombo.Style
                            $col.EditingElementStyle = Get-DataGridComboBoxEditStyle

                            if ($ForceTextWrap) {
                                $col.Width = [System.Windows.Controls.DataGridLength]::new(150)
                            }
                            else {
                                $col.Width = [System.Windows.Controls.DataGridLength]::new(1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
                            }

                            [void]$dataGrid.Columns.Add($col)
                        }
                        else {
                            $col = [System.Windows.Controls.DataGridTextColumn]::new()
                            $col.Header = $propName
                            $col.SortMemberPath = $propName
                            $col.IsReadOnly = $isReadOnly
                            $col.Binding = [System.Windows.Data.Binding]::new($propName)
                            $col.Binding.Mode = [System.Windows.Data.BindingMode]::TwoWay
                            $col.Binding.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::LostFocus

                            $col.EditingElementStyle = Get-DataGridEditStyle

                            if ($ForceTextWrap) {
                                $col.Width = [System.Windows.Controls.DataGridLength]::new(150)
                            }
                            else {
                                $col.Width = [System.Windows.Controls.DataGridLength]::new(1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
                            }

                            [void]$dataGrid.Columns.Add($col)
                        }
                    }

                    $script:currentObservable = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
                    foreach ($item in $data) {
                        [void]$script:currentObservable.Add($item)
                    }

                    $script:unfilteredData = [System.Collections.Generic.List[object]]::new()
                    foreach ($item in $data) {
                        [void]$script:unfilteredData.Add($item)
                    }

                    $script:collectionView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($script:currentObservable)
                    $dataGrid.ItemsSource = $script:collectionView

                    # Decorate empty cells. Swap bool text columns for glyphs. Both helpers skip already processed columns so file switches don't double up.
                    Add-UiDataGridEmptyCellDecorator -DataGrid $dataGrid -Items $data
                    Convert-UiDataGridBoolColumnsToGlyph -DataGrid $dataGrid -Items $data

                    $script:currentFilterText = ''
                }
                else {
                    $dataGrid.ItemsSource = $null
                    $script:currentObservable = $null
                }
            }

            $firstFile = @($Script:CurrentCSVData.Keys)[0]
            & $loadCSVFile $firstFile

            $fileCombo.Add_SelectionChanged({
                    $selectedFile = $this.SelectedItem
                    if ($selectedFile) {
                        & $loadCSVFile $selectedFile
                    }
                }.GetNewClosure())

            $filterBox.Add_TextChanged({
                $clearBtn = $filterBox.Tag.ClearButton
                if ($clearBtn) {
                    $clearBtn.Visibility = if ([string]::IsNullOrEmpty($filterBox.Text)) { 'Collapsed' } else { 'Visible' }
                }

                if ($script:filterTimer) {
                    $script:filterTimer.Stop()
                    $script:filterTimer = $null
                }

                $script:filterTimer = [System.Windows.Threading.DispatcherTimer]::new()
                $script:filterTimer.Interval = [TimeSpan]::FromMilliseconds(300)

                $script:filterTimer.Add_Tick({
                    $filterText = $filterBox.Text.Trim()
                    $script:currentFilterText = $filterText

                    # Rebuild instead of CollectionView.Filter - PS delegates break during WPF sorting
                    if ($script:unfilteredData -and $script:currentObservable) {
                        $sortDescriptions = @()
                        if ($script:collectionView) {
                            foreach ($sd in $script:collectionView.SortDescriptions) {
                                $sortDescriptions += $sd
                            }
                        }

                        $script:currentObservable.Clear()

                        foreach ($item in $script:unfilteredData) {
                            if ([string]::IsNullOrEmpty($filterText)) {
                                [void]$script:currentObservable.Add($item)
                            }
                            else {
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

                        if ($script:collectionView -and $sortDescriptions.Count -gt 0) {
                            $script:collectionView.SortDescriptions.Clear()
                            foreach ($sd in $sortDescriptions) {
                                $script:collectionView.SortDescriptions.Add($sd)
                            }
                        }
                    }

                    $script:filterTimer.Stop()
                    $script:filterTimer = $null
                })

                $script:filterTimer.Start()
            })

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

                        $newRow = [PSCustomObject]@{}
                        foreach ($prop in $csvInfo.Data[0].PSObject.Properties) {
                            $defaultValue = ''

                            if ($ColumnComboBoxes -and $ColumnComboBoxes.ContainsKey($prop.Name)) {
                                $comboConfig = $ColumnComboBoxes[$prop.Name]

                                if ($comboConfig -is [array]) {
                                    if ($comboConfig.Count -gt 0) {
                                        $defaultValue = $comboConfig[0]
                                    }
                                }
                                else {
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

                        if ($script:unfilteredData) {
                            [void]$script:unfilteredData.Add($newRow)
                        }

                        $csvInfo.Modified = $true

                        if ($script:collectionView) {
                            $script:collectionView.Refresh()
                        }

                        $dataGrid.SelectedItem = $newRow
                        $dataGrid.ScrollIntoView($newRow)
                    }
                    catch {
                        Show-ThemedDialog -Title 'Add Failed' -Message "Failed to add row: $_" -Buttons OK -Icon Error
                        return
                    }
                })

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

            $dataGrid.Add_CellEditEnding({
                    param($sender, $eventArgs)
                    if ($script:currentFileName -and $eventArgs.EditAction -eq 'Commit') {
                        $Script:CurrentCSVData[$script:currentFileName].Modified = $true
                        Write-Debug "CellEditEnding - marked '$script:currentFileName' as modified"
                    }
                })

            $dataGrid.Add_RowEditEnding({
                    param($sender, $eventArgs)
                    if ($script:currentFileName -and $eventArgs.EditAction -eq 'Commit') {
                        $Script:CurrentCSVData[$script:currentFileName].Modified = $true
                        Write-Debug "RowEditEnding - marked '$script:currentFileName' as modified"
                    }
                })

            # ComboBox columns don't fire CellEditEnding on selection change
            $dataGrid.Add_PreparingCellForEdit({
                    param($sender, $eventArgs)
                    $editElement = $eventArgs.EditingElement
                    if ($editElement -is [System.Windows.Controls.ComboBox]) {
                        $editElement.Add_SelectionChanged({
                            if ($script:currentFileName) {
                                $Script:CurrentCSVData[$script:currentFileName].Modified = $true
                                Write-Debug "ComboBox SelectionChanged - marked as modified"
                            }
                        })
                    }
                })

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

            Initialize-UiWindowLoaded -Window $window -SetIcon

            $window.Add_Closed({
                # Stop the filter timer before controls dispose
                if ($script:filterTimer) {
                    $script:filterTimer.Stop()
                    $script:filterTimer = $null
                }

                $script:collectionView = $null

                if ($isStandalone -and !$hasParentSession) {
                    $sessionId = [PsUi.SessionManager]::CurrentSessionId
                    if ($sessionId -ne [Guid]::Empty) {
                        [PsUi.SessionManager]::DisposeSession($sessionId)
                    }
                }
            }.GetNewClosure())

            if (!$isStandalone) {
                Set-UiDialogPosition -Dialog $window
            }

            $windowShown = $true
            [void]$window.ShowDialog()

            # Restore the icon font if an override was pushed - nothing to restore when $iconFontSnap is $null.
            # Tail statement, not a finally: off pipeline (called from a -NoAsync click) a finally NREs on exit. The function scope trap above covers a throw from ShowDialog.
            [PsUi.ModuleContext]::RestoreIconFontState($iconFontSnap)
            $iconFontSnap = $null

            $Script:CurrentCSVData = @{}
        }
        catch {
            Write-Debug "Out-CSVDataGrid: dispatch caught: $($_.Exception.GetType().Name): $($_.Exception.Message)"
            Write-Debug "Stack: $($_.ScriptStackTrace)"
            # Before the window shows, a throw is a real setup/validation failure (e.g. the deliberate ComboBox/PopupOnSelection conflict) - surface it so bad calls stop the calling script. After it shows, a throw is close time teardown noise from an unwinding handler. Log and swallow so it doesn't pop an "Error: Open Out-CSVDataGrid" dialog.
            if (!$windowShown) { throw }
        }
    }
}
