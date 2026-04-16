function New-DialogWindow {
    <#
    .SYNOPSIS
        Creates a standard themed dialog window with common boilerplate.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [int]$Width = 420,

        [int]$MinWidth = 332,

        [int]$Height,

        [int]$MinHeight = 182,

        [int]$MaxHeight = 600,

        [ValidateSet('Height', 'Manual')]
        [string]$SizeToContent = 'Height',

        [ValidateSet('NoResize', 'CanResizeWithGrip')]
        [string]$ResizeMode = 'NoResize',

        [string]$AppIdSuffix = 'Dialog',

        [char]$OverlayGlyph,

        [string]$OverlayColor,

        [char]$TitleIcon,

        [object]$ThemeColors
    )

    $colors = if ($ThemeColors) { $ThemeColors } else { Get-ThemeColors }
    $overlayColorFinal = if ($OverlayColor) { $OverlayColor } else { $colors.Accent }

    # Default overlay glyph to Info icon if not specified
    if (!$OverlayGlyph) { $OverlayGlyph = [PsUi.ModuleContext]::GetIcon('Info') }

    # Create the dialog window with standard properties
    $window = [System.Windows.Window]@{
        Title                 = $Title
        Width                 = $Width + 32
        MinWidth              = $MinWidth
        MinHeight             = $MinHeight
        MaxHeight             = $MaxHeight + 32
        SizeToContent         = $SizeToContent
        WindowStartupLocation = 'CenterScreen'
        FontFamily            = [System.Windows.Media.FontFamily]::new('Segoe UI')
        Background            = [System.Windows.Media.Brushes]::Transparent
        Foreground            = ConvertTo-UiBrush $colors.ControlFg
        ResizeMode            = $ResizeMode
        WindowStyle           = 'None'
        AllowsTransparency    = $true
        Opacity               = 0
    }

    # Attach to parent so dialog stays with its owner
    $null = Set-WindowOwner -Window $window

    # Unique AppUserModelID separates from PowerShell in taskbar
    $appId = "PsUi.$AppIdSuffix." + [Guid]::NewGuid().ToString("N").Substring(0, 8)
    [PsUi.WindowManager]::SetWindowAppId($window, $appId)

    # Set explicit height if provided (used for fixed-size dialogs like PowerShell mode)
    if ($Height -gt 0) { $window.Height = $Height }

    # Themed window icon for taskbar
    $dialogIcon = $null
    try {
        $dialogIcon = New-WindowIcon -Colors $colors
        if ($dialogIcon) { $window.Icon = $dialogIcon }
    }
    catch { Write-Debug "Window icon creation failed: $_" }

    # Overlay icon for taskbar
    $overlayIcon = $null
    try {
        $overlayIcon = New-TaskbarOverlayIcon -GlyphChar $OverlayGlyph -Color $overlayColorFinal
    }
    catch { Write-Debug "Overlay icon creation failed: $_" }

    # Wire up taskbar icon in Loaded event
    $capturedWindow  = $window
    $capturedIcon    = $dialogIcon
    $capturedOverlay = $overlayIcon
    $capturedSuffix  = $AppIdSuffix
    $window.Add_Loaded({
        if ($capturedIcon) {
            [PsUi.WindowManager]::SetTaskbarIcon($capturedWindow, $capturedIcon)
        }
        if ($capturedOverlay) {
            [PsUi.WindowManager]::SetTaskbarOverlay($capturedWindow, $capturedOverlay, $capturedSuffix)
        }
    }.GetNewClosure())

    # Main border with shadow effect
    $mainBorder = [System.Windows.Controls.Border]@{
        Margin          = [System.Windows.Thickness]::new(16)
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
        Background      = ConvertTo-UiBrush $colors.WindowBg
    }

    $shadow = [System.Windows.Media.Effects.DropShadowEffect]@{
        BlurRadius  = 16
        ShadowDepth = 4
        Opacity     = 0.35
        Color       = [System.Windows.Media.Colors]::Black
        Direction   = 270
    }
    $mainBorder.Effect = $shadow
    $window.Content = $mainBorder

    # Main layout panel
    $mainPanel = [System.Windows.Controls.DockPanel]@{
        LastChildFill = $true
        Margin        = [System.Windows.Thickness]::new(0)
    }
    $mainBorder.Child = $mainPanel

    # Title bar
    $titleBar = [System.Windows.Controls.Border]@{
        Background = ConvertTo-UiBrush $colors.HeaderBackground
        Height     = 36
        Padding    = [System.Windows.Thickness]::new(12, 8, 12, 8)
    }
    [System.Windows.Controls.DockPanel]::SetDock($titleBar, 'Top')

    # Title bar content - optional icon + text
    if ($TitleIcon) {
        $titleStack = [System.Windows.Controls.StackPanel]@{
            Orientation       = 'Horizontal'
            VerticalAlignment = 'Center'
        }

        $titleIconBlock = [System.Windows.Controls.TextBlock]@{
            Text              = $TitleIcon
            FontFamily        = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            FontSize          = 14
            Foreground        = ConvertTo-UiBrush $colors.HeaderForeground
            VerticalAlignment = 'Center'
            Margin            = [System.Windows.Thickness]::new(0, 0, 8, 0)
        }
        [void]$titleStack.Children.Add($titleIconBlock)

        $titleText = [System.Windows.Controls.TextBlock]@{
            Text              = $Title
            FontSize          = 14
            FontWeight        = [System.Windows.FontWeights]::SemiBold
            Foreground        = ConvertTo-UiBrush $colors.HeaderForeground
            VerticalAlignment = 'Center'
        }
        [void]$titleStack.Children.Add($titleText)

        $titleBar.Child = $titleStack
    }
    else {
        $titleText = [System.Windows.Controls.TextBlock]@{
            Text              = $Title
            FontSize          = 14
            FontWeight        = [System.Windows.FontWeights]::SemiBold
            Foreground        = ConvertTo-UiBrush $colors.HeaderForeground
            VerticalAlignment = 'Center'
        }
        $titleBar.Child = $titleText
    }

    [void]$mainPanel.Children.Add($titleBar)

    # Wire up drag behavior on title bar
    $titleBar.Add_MouseLeftButtonDown({ $capturedWindow.DragMove() }.GetNewClosure())

    # Content panel for dialog-specific content
    $contentPanel = [System.Windows.Controls.DockPanel]@{
        Margin        = [System.Windows.Thickness]::new(16)
        LastChildFill = $true
    }
    [void]$mainPanel.Children.Add($contentPanel)

    # Return all components for the caller to use
    return @{
        Window       = $window
        MainBorder   = $mainBorder
        MainPanel    = $mainPanel
        TitleBar     = $titleBar
        ContentPanel = $contentPanel
        Colors       = $colors
    }
}
