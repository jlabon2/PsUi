function Out-TextEditor {
    <#
    .SYNOPSIS
        Opens a themed text editor window.
    .DESCRIPTION
        Displays text in a themed editor window with find, copy, and optional save.
        Accepts input via parameter or pipeline.
    .PARAMETER InputObject
        Text to display. Accepts string array from pipeline.
    .PARAMETER InitialText
        Initial text content (alias for backward compatibility).
    .PARAMETER TitleText
        Window title.
    .PARAMETER Theme
        Color theme to use. Defaults to Light.
    .PARAMETER ReadOnly
        When specified, the text editor opens in read-only mode. The Save button is hidden
        and the Cancel button becomes "Close" with accent styling.
    .PARAMETER NoWordWrap
        When specified, disables word wrap (shows horizontal scrollbar for long lines).
        Word wrap is enabled by default.
    .PARAMETER SpellCheck
        When specified, enables spell checking with red underlines for misspelled words.
        Spell check is disabled by default.
    .PARAMETER Width
        Window width in pixels.
    .PARAMETER Height
        Window height in pixels.
    .PARAMETER FontFamily
        Font face for the editor. Defaults to Consolas.
    .PARAMETER FontSize
        Font size in points.
    .EXAMPLE
        Out-TextEditor -InitialText "Hello World"
    .EXAMPLE
        Get-Content C:\file.txt | Out-TextEditor -Theme Dark
    .EXAMPLE
        "Line 1", "Line 2", "Line 3" | Out-TextEditor
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string[]]$InputObject,

        [string]$InitialText = '',
        [Alias('Title')]
        [string]$TitleText = 'Text Editor',
        [ArgumentCompleter({ [PsUi.ThemeEngine]::GetAvailableThemes() })]
        [string]$Theme = 'Light',
        [ValidateRange(300, 2000)]
        [int]$Width = 800,
        [ValidateRange(200, 1500)]
        [int]$Height = 600,
        [string]$FontFamily = 'Consolas',
        [ValidateRange(8, 24)]
        [int]$FontSize = 12,
        [switch]$ReadOnly,
        [switch]$NoWordWrap,
        [switch]$SpellCheck
    )

    begin {
        # ShowDialog requires the UI thread - block async button actions from calling this
        if ([PsUi.AsyncExecutor]::CurrentExecutor) {
            Write-Error 'Out-TextEditor cannot be called from an async button action (ShowDialog requires the UI thread). Use -NoAsync on your button, or call this function outside the DSL.'
            return
        }

        Write-Debug "Starting with Title='$TitleText', Theme='$Theme', Font='$FontFamily' $FontSize pt"
        $collectedLines = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($InputObject) {
            foreach ($line in $InputObject) {
                [void]$collectedLines.Add($line)
            }
        }
    }

    end {
    # Combine pipeline input with InitialText parameter
    $finalText = if ($collectedLines.Count -gt 0) {
        Write-Debug "Collected $($collectedLines.Count) lines from pipeline"
        $collectedLines -join "`n"
    }
    elseif ($InitialText) {
        Write-Debug "Using InitialText parameter ($($InitialText.Length) chars)"
        $InitialText
    }
    else {
        Write-Debug "No initial content"
        ''
    }

    $isStandalone = !(Test-Path variable:__WPFThemeColors)
    Write-Debug "Context: isStandalone=$isStandalone, textLength=$($finalText.Length)"

    if ($isStandalone) {
        # Standalone: use -Theme parameter and initialize full theme resources
        $colors = Initialize-UITheme -Theme $Theme
    }
    else {
        # Child window: use injected theme colors from parent context
        $colors = Get-Variable -Name __WPFThemeColors -ValueOnly -ErrorAction SilentlyContinue
    }

    # Ultimate fallback theme colors
    if (!$colors) {
        $colors = @{
            WindowBg         = '#FFFFFF'
            WindowFg         = '#202020'
            ControlBg        = '#F3F3F3'
            ControlFg        = '#202020'
            HeaderBackground = '#F0F0F0'
            HeaderForeground = '#202020'
            Border           = '#D1D1D1'
            Accent           = '#0078D4'
            SecondaryText    = '#666666'
            ButtonBg         = '#FFFFFF'
            ButtonFg         = '#202020'
            ButtonHover      = '#EFEFEF'
        }
    }

    $window = [System.Windows.Window]@{
        Title                 = $TitleText
        Width                 = $Width
        Height                = $Height
        MinWidth              = 300
        MinHeight             = 200
        WindowStartupLocation = 'CenterScreen'
        FontFamily            = [System.Windows.Media.FontFamily]::new('Segoe UI')
        ResizeMode            = 'CanResizeWithGrip'
    }

    # Bind to parent for consistent window management
    $null = Set-WindowOwner -Window $window
    $window.SetResourceReference([System.Windows.Window]::BackgroundProperty, 'WindowBackgroundBrush')
    $window.SetResourceReference([System.Windows.Window]::ForegroundProperty, 'ControlForegroundBrush')

    Set-UIResources -Window $window -Colors $colors

    $appId = "PsUi.TextEditor." + [Guid]::NewGuid().ToString("N").Substring(0, 8)
    [PsUi.WindowManager]::SetWindowAppId($window, $appId)

    $editorWindowIcon = $null
    try {
        $editorWindowIcon = New-WindowIcon -Colors $colors
        if ($editorWindowIcon) {
            $window.Icon = $editorWindowIcon
        }
    }
    catch {
        Write-Verbose "Failed to create window icon: $_"
    }

    $overlayIcon = $null
    try {
        $docGlyph = [PsUi.ModuleContext]::GetIcon('Document')
        $overlayIcon = New-TaskbarOverlayIcon -GlyphChar $docGlyph -Color $colors.Accent
        # Store glyph in resources for theme updates
        $window.Resources['OverlayGlyph'] = $docGlyph
    }
    catch { Write-Debug "Taskbar overlay failed: $_" }

    $capturedEditorWindow = $window
    $capturedEditorIcon   = $editorWindowIcon
    $capturedOverlay      = $overlayIcon

    $window.Add_Loaded({
        if ($capturedEditorIcon) {
            [PsUi.WindowManager]::SetTaskbarIcon($capturedEditorWindow, $capturedEditorIcon)
        }
        if ($capturedOverlay) {
            [PsUi.WindowManager]::SetTaskbarOverlay($capturedEditorWindow, $capturedOverlay, 'Document')
        }
    }.GetNewClosure())

    $mainPanel = [System.Windows.Controls.DockPanel]@{
        LastChildFill = $true
    }
    $window.Content = $mainPanel

    # Header bar
    $headerBorder = [System.Windows.Controls.Border]@{
        Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
        Tag = 'HeaderBorder'
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
        Text              = [PsUi.ModuleContext]::GetIcon('Edit')
        FontFamily        = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize          = 24
        VerticalAlignment = 'Center'
        Width             = 32
        TextAlignment     = 'Center'
        Margin            = [System.Windows.Thickness]::new(0, 0, 12, 0)
        Tag               = 'AccentIcon'
    }
    # SetResourceReference is a method, not a property, so it must be called after object creation
    $headerIcon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush')
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

    # Toolbar at top
    $toolbar = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Horizontal'
        Margin      = [System.Windows.Thickness]::new(0, 0, 0, 8)
        Height      = 32
    }
    [System.Windows.Controls.DockPanel]::SetDock($toolbar, 'Top')
    [void]$contentPanel.Children.Add($toolbar)

    # Copy All button with icon
    $copyAllBtn = [System.Windows.Controls.Button]::new()
    $copyAllPanel = [System.Windows.Controls.StackPanel]::new()
    $copyAllPanel.Orientation = 'Horizontal'
    $copyAllIcon = [System.Windows.Controls.TextBlock]::new()
    $copyAllIcon.Text = [PsUi.ModuleContext]::GetIcon('Copy')
    $copyAllIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $copyAllIcon.FontSize = 12
    $copyAllIcon.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
    $copyAllIcon.VerticalAlignment = 'Center'
    [void]$copyAllPanel.Children.Add($copyAllIcon)
    $copyAllText = [System.Windows.Controls.TextBlock]::new()
    $copyAllText.Text = 'Copy All'
    $copyAllText.VerticalAlignment = 'Center'
    [void]$copyAllPanel.Children.Add($copyAllText)
    $copyAllBtn.Content = $copyAllPanel
    $copyAllBtn.Height = 28
    $copyAllBtn.Padding = [System.Windows.Thickness]::new(8, 4, 8, 4)
    $copyAllBtn.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
    $copyAllBtn.VerticalAlignment = 'Center'
    $copyAllBtn.ToolTip = 'Copy all text to clipboard (Ctrl+Shift+C)'
    Set-ButtonStyle -Button $copyAllBtn
    [void]$toolbar.Children.Add($copyAllBtn)

    # Clear button with icon
    $clearBtn = [System.Windows.Controls.Button]::new()
    $clearPanel = [System.Windows.Controls.StackPanel]::new()
    $clearPanel.Orientation = 'Horizontal'
    $clearIcon = [System.Windows.Controls.TextBlock]::new()
    $clearIcon.Text = [PsUi.ModuleContext]::GetIcon('Delete')
    $clearIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $clearIcon.FontSize = 12
    $clearIcon.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
    $clearIcon.VerticalAlignment = 'Center'
    [void]$clearPanel.Children.Add($clearIcon)
    $clearText = [System.Windows.Controls.TextBlock]::new()
    $clearText.Text = 'Clear'
    $clearText.VerticalAlignment = 'Center'
    [void]$clearPanel.Children.Add($clearText)
    $clearBtn.Content = $clearPanel
    $clearBtn.Height = 28
    $clearBtn.Padding = [System.Windows.Thickness]::new(8, 4, 8, 4)
    $clearBtn.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $clearBtn.VerticalAlignment = 'Center'
    $clearBtn.ToolTip = 'Clear all text'
    Set-ButtonStyle -Button $clearBtn
    [void]$toolbar.Children.Add($clearBtn)

    $wrapCheck = [System.Windows.Controls.CheckBox]::new()
    $wrapCheck.Content = 'Word Wrap'
    $wrapCheck.IsChecked = !$NoWordWrap
    $wrapCheck.VerticalAlignment = 'Center'
    $wrapCheck.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $wrapCheck.ToolTip = 'Toggle word wrapping'
    Set-CheckBoxStyle -CheckBox $wrapCheck
    $wrapCheck.SetResourceReference([System.Windows.Controls.CheckBox]::ForegroundProperty, 'ControlForegroundBrush')
    [void]$toolbar.Children.Add($wrapCheck)

    $spellCheckBox = [System.Windows.Controls.CheckBox]::new()
    $spellCheckBox.Content = 'Spell Check'
    $spellCheckBox.IsChecked = $SpellCheck
    $spellCheckBox.VerticalAlignment = 'Center'
    $spellCheckBox.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $spellCheckBox.ToolTip = 'Toggle spell checking'
    Set-CheckBoxStyle -CheckBox $spellCheckBox
    $spellCheckBox.SetResourceReference([System.Windows.Controls.CheckBox]::ForegroundProperty, 'ControlForegroundBrush')
    [void]$toolbar.Children.Add($spellCheckBox)

    # Font size control with label beneath slider
    $fontSizePanel = [System.Windows.Controls.StackPanel]::new()
    $fontSizePanel.Orientation = 'Vertical'
    $fontSizePanel.VerticalAlignment = 'Center'
    $fontSizePanel.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)

    $fontSizeSlider = [System.Windows.Controls.Slider]::new()
    $fontSizeSlider.Minimum = 8
    $fontSizeSlider.Maximum = 32
    $fontSizeSlider.Value = $FontSize
    $fontSizeSlider.Width = 100
    $fontSizeSlider.TickFrequency = 1
    $fontSizeSlider.IsSnapToTickEnabled = $true
    $fontSizeSlider.ToolTip = 'Adjust font size (8-32pt). Ctrl+Scroll to change. Double-click to reset.'
    $fontSizeSlider.Tag = $FontSize
    Set-SliderStyle -Slider $fontSizeSlider
    [void]$fontSizePanel.Children.Add($fontSizeSlider)

    $fontLabel = [System.Windows.Controls.TextBlock]::new()
    $fontLabel.Text = 'Font Size'
    $fontLabel.HorizontalAlignment = 'Center'
    $fontLabel.FontSize = 10
    $fontLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'ControlForegroundBrush')
    [void]$fontSizePanel.Children.Add($fontLabel)

    [void]$toolbar.Children.Add($fontSizePanel)

    # Status and search bar at bottom
    $statusBar = [System.Windows.Controls.Border]::new()
    $statusBar.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'HeaderBackgroundBrush')
    $statusBar.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'BorderBrush')
    $statusBar.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
    $statusBar.Padding = [System.Windows.Thickness]::new(8, 4, 8, 4)
    $statusBar.Height = 32
    $statusBar.Tag = 'HeaderBorder'
    [System.Windows.Controls.DockPanel]::SetDock($statusBar, 'Bottom')

    $statusGrid = [System.Windows.Controls.Grid]::new()
    $statusCol1 = [System.Windows.Controls.ColumnDefinition]::new()
    $statusCol1.Width = [System.Windows.GridLength]::Auto
    $statusCol2 = [System.Windows.Controls.ColumnDefinition]::new()
    $statusCol2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $statusCol3 = [System.Windows.Controls.ColumnDefinition]::new()
    $statusCol3.Width = [System.Windows.GridLength]::Auto
    [void]$statusGrid.ColumnDefinitions.Add($statusCol1)
    [void]$statusGrid.ColumnDefinitions.Add($statusCol2)
    [void]$statusGrid.ColumnDefinitions.Add($statusCol3)

    $statusText = [System.Windows.Controls.TextBlock]::new()
    $statusText.Text = 'Line: 1  Col: 1'
    $statusText.FontSize = 11
    $statusText.VerticalAlignment = 'Center'
    $statusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'HeaderForegroundBrush')
    $statusText.Tag = 'HeaderText'
    [System.Windows.Controls.Grid]::SetColumn($statusText, 0)
    [void]$statusGrid.Children.Add($statusText)

    $findPanel = [System.Windows.Controls.StackPanel]::new()
    $findPanel.Orientation = 'Horizontal'
    $findPanel.HorizontalAlignment = 'Right'
    $findPanel.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($findPanel, 2)

    $findLabel = [System.Windows.Controls.TextBlock]::new()
    $findLabel.Text = 'Find:'
    $findLabel.FontSize = 11
    $findLabel.VerticalAlignment = 'Center'
    $findLabel.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
    $findLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'HeaderForegroundBrush')
    $findLabel.Tag = 'HeaderText'
    [void]$findPanel.Children.Add($findLabel)

    # Wrap findBox in Grid to overlay clear button
    $findBoxContainer = [System.Windows.Controls.Grid]::new()
    $findBoxContainer.Width = 200
    $findBoxContainer.Height = 20
    $findBoxContainer.VerticalAlignment = 'Center'

    $findBox = [System.Windows.Controls.TextBox]::new()
    $findBox.Height = 20
    $findBox.FontSize = 11
    $findBox.VerticalAlignment = 'Center'
    $findBox.Padding = [System.Windows.Thickness]::new(2, 0, 18, 0)
    $findBox.ToolTip = 'Search for text (case-insensitive by default)'
    Set-TextBoxStyle -TextBox $findBox
    $findBox.BorderThickness = [System.Windows.Thickness]::new(1)
    [void]$findBoxContainer.Children.Add($findBox)

    $findClearBtn = [System.Windows.Controls.Button]::new()
    $findClearBtn.Content = [PsUi.ModuleContext]::GetIcon('Cancel')
    $findClearBtn.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $findClearBtn.FontSize = 9
    $findClearBtn.Width = 14
    $findClearBtn.Height = 14
    $findClearBtn.Padding = [System.Windows.Thickness]::new(0)
    $findClearBtn.Margin = [System.Windows.Thickness]::new(0, 0, 3, 0)
    $findClearBtn.HorizontalAlignment = 'Right'
    $findClearBtn.VerticalAlignment = 'Center'
    $findClearBtn.Background = [System.Windows.Media.Brushes]::Transparent
    $findClearBtn.BorderThickness = [System.Windows.Thickness]::new(0)
    $findClearBtn.SetResourceReference([System.Windows.Controls.Button]::ForegroundProperty, 'SecondaryTextBrush')
    $findClearBtn.Cursor = [System.Windows.Input.Cursors]::Hand
    $findClearBtn.Visibility = 'Collapsed'
    $findClearBtn.ToolTip = 'Clear'
    $findClearBtn.Tag = $findBox
    $findClearBtn.Add_Click({ $this.Tag.Text = ''; $this.Tag.Focus() }.GetNewClosure())
    [void]$findBoxContainer.Children.Add($findClearBtn)

    $findBox.Tag = @{ ClearButton = $findClearBtn }
    [void]$findPanel.Children.Add($findBoxContainer)

    $findPrevBtn = [System.Windows.Controls.Button]::new()
    $findPrevBtn.Width = 24
    $findPrevBtn.Height = 20
    $findPrevBtn.Padding = [System.Windows.Thickness]::new(0)
    $findPrevBtn.Margin = [System.Windows.Thickness]::new(2, 0, 0, 0)
    $findPrevBtn.VerticalAlignment = 'Center'
    $findPrevBtn.ToolTip = 'Find previous occurrence (Shift+F3)'
    $findPrevIcon = [System.Windows.Controls.TextBlock]::new()
    $findPrevIcon.Text = [PsUi.ModuleContext]::GetIcon('ArrowLeft')
    $findPrevIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $findPrevIcon.FontSize = 12
    $findPrevIcon.HorizontalAlignment = 'Center'
    $findPrevIcon.VerticalAlignment = 'Center'
    $findPrevBtn.Content = $findPrevIcon
    Set-ButtonStyle -Button $findPrevBtn
    [void]$findPanel.Children.Add($findPrevBtn)

    $findNextBtn = [System.Windows.Controls.Button]::new()
    $findNextBtn.Width = 24
    $findNextBtn.Height = 20
    $findNextBtn.Padding = [System.Windows.Thickness]::new(0)
    $findNextBtn.Margin = [System.Windows.Thickness]::new(2, 0, 0, 0)
    $findNextBtn.VerticalAlignment = 'Center'
    $findNextBtn.ToolTip = 'Find next occurrence (F3)'
    $findNextIcon = [System.Windows.Controls.TextBlock]::new()
    $findNextIcon.Text = [PsUi.ModuleContext]::GetIcon('ArrowRight')
    $findNextIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $findNextIcon.FontSize = 12
    $findNextIcon.HorizontalAlignment = 'Center'
    $findNextIcon.VerticalAlignment = 'Center'
    $findNextBtn.Content = $findNextIcon
    Set-ButtonStyle -Button $findNextBtn
    [void]$findPanel.Children.Add($findNextBtn)

    $matchCaseCheck = [System.Windows.Controls.CheckBox]::new()
    $matchCaseCheck.Content = 'Aa'
    $matchCaseCheck.ToolTip = 'Enable case-sensitive search'
    $matchCaseCheck.FontSize = 10
    $matchCaseCheck.VerticalAlignment = 'Center'
    $matchCaseCheck.VerticalContentAlignment = 'Center'
    $matchCaseCheck.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
    Set-CheckBoxStyle -CheckBox $matchCaseCheck
    $matchCaseCheck.SetResourceReference([System.Windows.Controls.CheckBox]::ForegroundProperty, 'HeaderForegroundBrush')
    [void]$findPanel.Children.Add($matchCaseCheck)

    # Find counter label
    # Width sized for "99 found" or "9 of 99" - prevents layout shifts when text changes
    $FIND_COUNTER_WIDTH = 60
    $findCountLabel = [System.Windows.Controls.TextBlock]::new()
    $findCountLabel.Text = ''
    $findCountLabel.FontSize = 10
    $findCountLabel.VerticalAlignment = 'Center'
    $findCountLabel.Margin = [System.Windows.Thickness]::new(8, 1, 0, 0)
    $findCountLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'HeaderForegroundBrush')
    $findCountLabel.Tag = 'HeaderText'
    $findCountLabel.ToolTip = 'Shows current match / total matches'
    $findCountLabel.Width = $FIND_COUNTER_WIDTH
    $findCountLabel.TextAlignment = 'Left'
    # Start hidden to reserve space
    $findCountLabel.Visibility = [System.Windows.Visibility]::Hidden
    [void]$findPanel.Children.Add($findCountLabel)

    [void]$statusGrid.Children.Add($findPanel)
    $statusBar.Child = $statusGrid
    [void]$contentPanel.Children.Add($statusBar)

    # Button panel
    $buttonPanel = [System.Windows.Controls.StackPanel]::new()
    $buttonPanel.Orientation = 'Horizontal'
    $buttonPanel.HorizontalAlignment = 'Right'
    $buttonPanel.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($buttonPanel, 'Bottom')
    [void]$contentPanel.Children.Add($buttonPanel)

    $saveBtn = [System.Windows.Controls.Button]::new()
    $saveBtn.Content = 'Save'
    $saveBtn.Width = 90
    $saveBtn.Height = 32
    $saveBtn.Margin = [System.Windows.Thickness]::new(0, 0, 8, 8)
    Set-ButtonStyle -Button $saveBtn -Accent
    if ($ReadOnly) { $saveBtn.Visibility = 'Collapsed' }
    [void]$buttonPanel.Children.Add($saveBtn)

    $cancelBtn = [System.Windows.Controls.Button]::new()
    $cancelBtn.Content = if ($ReadOnly) { 'Close' } else { 'Cancel' }
    $cancelBtn.Width = 90
    $cancelBtn.Height = 32
    $cancelBtn.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    Set-ButtonStyle -Button $cancelBtn
    if ($ReadOnly) { Set-ButtonStyle -Button $cancelBtn -Accent }
    [void]$buttonPanel.Children.Add($cancelBtn)

    $scrollViewer = [System.Windows.Controls.ScrollViewer]::new()
    $scrollViewer.VerticalScrollBarVisibility = 'Auto'
    
    # Default to wrap on unless NoWordWrap specified
    $scrollViewer.HorizontalScrollBarVisibility = if ($NoWordWrap) { 'Auto' } else { 'Disabled' }
    [void]$contentPanel.Children.Add($scrollViewer)

    # Multi-line editor textbox - don't use Set-TextBoxStyle since it applies a single-line template
    # Instead, manually apply theme colors for proper multi-line behavior
    $textBox = [System.Windows.Controls.TextBox]::new()
    $textBox.Text = $finalText
    $textBox.AcceptsReturn = $true
    $textBox.AcceptsTab = $true
    $textBox.TextWrapping = if ($NoWordWrap) { 'NoWrap' } else { 'Wrap' }
    $textBox.VerticalScrollBarVisibility = 'Hidden'
    $textBox.HorizontalScrollBarVisibility = 'Hidden'
    $textBox.IsInactiveSelectionHighlightEnabled = $true
    $textBox.VerticalContentAlignment = 'Top'
    $textBox.BorderThickness = [System.Windows.Thickness]::new(0.5)
    $textBox.FontFamily = [System.Windows.Media.FontFamily]::new($FontFamily)
    $textBox.FontSize = $FontSize
    $textBox.Padding = [System.Windows.Thickness]::new(8)
    $textBox.IsReadOnly = $ReadOnly
    
    # Enable spell check only if explicitly requested
    [System.Windows.Controls.SpellCheck]::SetIsEnabled($textBox, $SpellCheck)
    
    # Create base context menu (we'll add spell suggestions dynamically)
    $baseContextMenu = New-TextBoxContextMenu -ReadOnly:$ReadOnly
    $textBox.ContextMenu = $baseContextMenu
    
    # Add spell check suggestions when context menu opens
    $textBox.Add_ContextMenuOpening({
        param($sender, $eventArgs)
        
        # Get the textbox and its context menu
        $tb = $sender
        $menu = $tb.ContextMenu
        
        # Remove any previous spell check items (they have Tag = 'SpellCheck')
        $itemsToRemove = @($menu.Items | Where-Object { $_.Tag -eq 'SpellCheck' })
        foreach ($item in $itemsToRemove) {
            [void]$menu.Items.Remove($item)
        }
        
        # Spell check suggestions go at the top of the context menu
        if ([System.Windows.Controls.SpellCheck]::GetIsEnabled($tb)) {
            # Get the character index at the mouse position (not caret position)
            $mousePos = [System.Windows.Input.Mouse]::GetPosition($tb)
            $charIndex = $tb.GetCharacterIndexFromPoint($mousePos, $true)
            
            if ($charIndex -ge 0) {
                $spellingError = $tb.GetSpellingError($charIndex)
                
                if ($spellingError) {
                    $suggestions = $spellingError.Suggestions
                    $insertIndex = 0
                    
                    # Add spelling suggestions
                    if ($suggestions) {
                        foreach ($suggestion in $suggestions) {
                            $suggestionItem = [System.Windows.Controls.MenuItem]::new()
                            $suggestionItem.Header = $suggestion
                            $suggestionItem.FontWeight = [System.Windows.FontWeights]::SemiBold
                            $suggestionItem.Tag = 'SpellCheck'
                            
                            # Capture values for the click handler
                            $capturedSuggestion = $suggestion
                            $capturedError = $spellingError
                            $capturedTextBox = $tb
                            $suggestionItem.Add_Click({
                                $capturedTextBox.BeginChange()
                                $capturedError.Correct($capturedSuggestion)
                                $capturedTextBox.EndChange()
                            }.GetNewClosure())
                            
                            [void]$menu.Items.Insert($insertIndex, $suggestionItem)
                            $insertIndex++
                        }
                        
                        # Add separator after spell check suggestions
                        $spellSeparator = [System.Windows.Controls.Separator]::new()
                        $spellSeparator.Tag = 'SpellCheck'
                        [void]$menu.Items.Insert($insertIndex, $spellSeparator)
                    }
                }
            }
        }
    }.GetNewClosure())

    # Apply theme colors via resource references
    $textBox.SetResourceReference([System.Windows.Controls.TextBox]::BackgroundProperty, 'ControlBackgroundBrush')
    $textBox.SetResourceReference([System.Windows.Controls.TextBox]::ForegroundProperty, 'ControlForegroundBrush')
    $textBox.SetResourceReference([System.Windows.Controls.TextBox]::BorderBrushProperty, 'BorderBrush')
    $textBox.SetResourceReference([System.Windows.Controls.TextBox]::CaretBrushProperty, 'ControlForegroundBrush')
    $textBox.SetResourceReference([System.Windows.Controls.Primitives.TextBoxBase]::SelectionBrushProperty, 'AccentBrush')
    $textBox.SelectionOpacity = 0.4

    $scrollViewer.Content = $textBox

    # Autofocus textbox when not in readonly mode
    if (!$ReadOnly) {
        $window.Add_ContentRendered({ $textBox.Focus() }.GetNewClosure())
    }

    $textBox.Add_SelectionChanged({
        try {
            $text = $textBox.Text
            $caretIndex = $textBox.CaretIndex
            $lineNumber = 1
            $colNumber = 1
            if ($caretIndex -gt 0 -and $text.Length -gt 0) {
                $beforeCaret = $text.Substring(0, [Math]::Min($caretIndex, $text.Length))
                $lineNumber = ($beforeCaret.ToCharArray() | Where-Object { $_ -eq "`n" }).Count + 1
                $lastNewLine = $beforeCaret.LastIndexOf("`n")
                $colNumber = if ($lastNewLine -ge 0) { $caretIndex - $lastNewLine } else { $caretIndex + 1 }
            }
            $statusText.Text = "Line: $lineNumber  Col: $colNumber  Length: $($text.Length)"
        }
        catch {
            Write-Verbose "Failed to update status text: $_"
        }
    }.GetNewClosure())

    $wrapCheck.Add_Checked({
        $textBox.TextWrapping = 'Wrap'
        $scrollViewer.HorizontalScrollBarVisibility = 'Disabled'
    }.GetNewClosure())

    $wrapCheck.Add_Unchecked({
        $textBox.TextWrapping = 'NoWrap'
        $scrollViewer.HorizontalScrollBarVisibility = 'Auto'
    }.GetNewClosure())

    $spellCheckBox.Add_Checked({
        [System.Windows.Controls.SpellCheck]::SetIsEnabled($textBox, $true)
    }.GetNewClosure())

    $spellCheckBox.Add_Unchecked({
        [System.Windows.Controls.SpellCheck]::SetIsEnabled($textBox, $false)
    }.GetNewClosure())

    $fontSizeSlider.Add_ValueChanged({
        $textBox.FontSize = $fontSizeSlider.Value
    }.GetNewClosure())

    # Double-click slider to reset to default (use Preview to catch before thumb handles it)
    $fontSizeSlider.Add_PreviewMouseDoubleClick({
        $fontSizeSlider.Value = $fontSizeSlider.Tag
    }.GetNewClosure())

    # Ctrl+scroll over textbox area to change font size
    $scrollViewer.Add_PreviewMouseWheel({
        param($sender, $wheelArgs)
        if ([System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
            $wheelArgs.Handled = $true
            $delta    = if ($wheelArgs.Delta -gt 0) { 1 } else { -1 }
            $newValue = $fontSizeSlider.Value + $delta

            if ($newValue -ge $fontSizeSlider.Minimum -and $newValue -le $fontSizeSlider.Maximum) {
                $fontSizeSlider.Value = $newValue
            }
        }
    }.GetNewClosure())

    $copyAllBtn.Add_Click({
        if ($textBox.Text.Length -gt 0) {
            [System.Windows.Clipboard]::SetText($textBox.Text)
            # Brief visual feedback - change text and flash accent color
            $copyAllText.Text = 'Copied!'
            $originalBg = $copyAllBtn.Background
            $copyAllBtn.Background = $window.TryFindResource('AccentBrush')

            # Use script-scoped variables for timer callback
            $script:_copyTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $script:_copyTimer.Interval = [TimeSpan]::FromMilliseconds(2000)
            $script:_copyTimer.Tag = @{ Button = $copyAllBtn; Text = $copyAllText; OriginalBg = $originalBg }
            $script:_copyTimer.Add_Tick({
                param($sender, $eventArgs)
                $data = $sender.Tag
                $data.Button.Background = $data.OriginalBg
                $data.Text.Text = 'Copy All'
                $sender.Stop()
            })
            $script:_copyTimer.Start()
        }
    }.GetNewClosure())

    $clearBtn.Add_Click({
        if ($textBox.Text.Length -gt 0) {
            $result = Show-UiMessageDialog -Title 'Confirm Clear' -Message 'Clear all text? This cannot be undone.' -Buttons YesNo -Icon Question -ThemeColors $colors
            if ($result -eq 'Yes') {
                $textBox.Text = ''
                # Reset find state
                $findCountLabel.Visibility = [System.Windows.Visibility]::Hidden
                $findCountLabel.Text = ''
            }
        }
    }.GetNewClosure())

    # Text search with real-time highlighting and match counter
    # Use a hashtable to encapsulate state for this specific instance
    $findState = @{
        Matches = [System.Collections.Generic.List[int]]::new()
        CurrentIndex = -1
    }

    # Helper function to update selection with visual focus toggle
    # Forces WPF to render the selection by briefly focusing the textbox
    $updateSelectionWithFocus = {
        param(
            [int]$index,
            [int]$length
        )

        # Bail on invalid range
        if ($index -lt 0 -or $length -lt 0) {
            Write-Verbose "Invalid selection range: index=$index, length=$length"
            return
        }

        $textBox.SelectionStart = $index
        $textBox.SelectionLength = $length
        $textBox.Focus()  # Give focus to render selection
        $textBox.ScrollToLine($textBox.GetLineIndexFromCharacterIndex($index))
        $findBox.Focus()  # Immediately return focus to Find box
        # Selection remains visible due to IsInactiveSelectionHighlightEnabled
    }

    $updateFindMatches = {
        $searchText = $findBox.Text
        $findState.Matches = [System.Collections.Generic.List[int]]::new()
        $findState.CurrentIndex = -1
        $findCountLabel.Text = ''

        # Hide label when search is empty
        if ([string]::IsNullOrEmpty($searchText)) {
            $findCountLabel.Visibility = [System.Windows.Visibility]::Hidden
            return
        }

        $text = $textBox.Text
        $comparison = if ($matchCaseCheck.IsChecked) {
            [System.StringComparison]::Ordinal
        }
        else {
            [System.StringComparison]::OrdinalIgnoreCase
        }

        $index = 0
        while ($index -lt $text.Length) {
            $foundIndex = $text.IndexOf($searchText, $index, $comparison)
            if ($foundIndex -ge 0) {
                $findState.Matches.Add($foundIndex)
                $index = $foundIndex + 1
            }
            else {
                break
            }
        }

        if ($findState.Matches.Count -gt 0) {
            $findCountLabel.Text = "$($findState.Matches.Count) found"
            $findCountLabel.Visibility = [System.Windows.Visibility]::Visible
            $findState.CurrentIndex = 0

            # Update selection with visual focus toggle
            & $updateSelectionWithFocus $findState.Matches[0] $searchText.Length
        }
        else {
            $findCountLabel.Text = "0 found"
            $findCountLabel.Visibility = [System.Windows.Visibility]::Visible
        }
    }

    # Ctrl+Z/Ctrl+Y in findBox must not propagate through the focus toggle to the main editor.
    # The focus toggle in $updateSelectionWithFocus briefly gives focus to the textBox, and
    # if the undo keystroke is still being processed, WPF routes it there mid-undo — crash.
    $findBox.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        $mod = [System.Windows.Input.Keyboard]::Modifiers
        if ($mod -eq 'Control' -and ($eventArgs.Key -eq 'Z' -or $eventArgs.Key -eq 'Y')) {
            try {
                if ($eventArgs.Key -eq 'Z') { $sender.Undo() }
                else { $sender.Redo() }
            }
            catch { <# Undo unit may be open from in-progress text change — not critical #> }
            $eventArgs.Handled = $true
        }
    })

    $findBox.Add_TextChanged({
        # Show/hide clear button
        $clearBtn = $findBox.Tag.ClearButton
        if ($clearBtn) {
            $clearBtn.Visibility = if ([string]::IsNullOrEmpty($findBox.Text)) { 'Collapsed' } else { 'Visible' }
        }
        & $updateFindMatches
    }.GetNewClosure())

    $matchCaseCheck.Add_Checked({
        & $updateFindMatches
    }.GetNewClosure())

    $matchCaseCheck.Add_Unchecked({
        & $updateFindMatches
    }.GetNewClosure())

    $findNextBtn.Add_Click({
        if ($findState.Matches.Count -gt 0) {
            $findState.CurrentIndex = ($findState.CurrentIndex + 1) % $findState.Matches.Count
            $searchText = $findBox.Text

            # Update selection with visual focus toggle
            & $updateSelectionWithFocus $findState.Matches[$findState.CurrentIndex] $searchText.Length

            $findCountLabel.Text = "$($findState.CurrentIndex + 1) of $($findState.Matches.Count)"
        }
    }.GetNewClosure())

    $findPrevBtn.Add_Click({
        if ($findState.Matches.Count -gt 0) {
            $findState.CurrentIndex = ($findState.CurrentIndex - 1)
            if ($findState.CurrentIndex -lt 0) {
                $findState.CurrentIndex = $findState.Matches.Count - 1
            }
            $searchText = $findBox.Text

            # Update selection with visual focus toggle
            & $updateSelectionWithFocus $findState.Matches[$findState.CurrentIndex] $searchText.Length

            $findCountLabel.Text = "$($findState.CurrentIndex + 1) of $($findState.Matches.Count)"
        }
    }.GetNewClosure())

    $cancelBtn.Add_Click({ $window.Tag = $null; $window.Close() }.GetNewClosure())
    $saveBtn.Add_Click({ $window.Tag = $textBox.Text; $window.Close() }.GetNewClosure())

    # Wire up standard window loaded behavior with icon
    Initialize-UiWindowLoaded -Window $window -SetIcon

    # Clean up session on window close (only if we created it)
    $window.Add_Closed({
        if ($isStandalone) {
            $sessionId = [PsUi.SessionManager]::CurrentSessionId
            if ($sessionId -ne [Guid]::Empty) {
                [PsUi.SessionManager]::DisposeSession($sessionId)
            }
        }
    }.GetNewClosure())

    [void]$window.ShowDialog()

    return $window.Tag
    } # end block
}