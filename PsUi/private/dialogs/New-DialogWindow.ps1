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

        # CanResizeWithGrip is out of the set because WPF draws that grip 16px clear of the window, in the window shadow.
        # The grip built further down sits on the chrome instead, and CanResize keeps WS_THICKFRAME so the edges still drag.
        [ValidateSet('NoResize', 'CanResize')]
        [string]$ResizeMode = 'NoResize',

        [string]$AppIdSuffix = 'Dialog',

        [char]$OverlayGlyph,

        [string]$OverlayColor,

        [char]$TitleIcon,

        [object]$ThemeColors
    )

    # First PsUi UI in the process means no Application, so no control styles. Every text and password box draws without a border or a background.
    # Can't fix that by creating one, so it would outlive the dialog owning no windows, and the next New-UiWindow builds on its own STA thread and drops to messed up theming.
    $dialogNeedsOwnTheme = $null -eq [System.Windows.Application]::Current

    $colors = if ($ThemeColors) { $ThemeColors } else { Get-ThemeColors }
    $overlayColorFinal = if ($OverlayColor) { $OverlayColor } else { $colors.Accent }

    if (!$OverlayGlyph) { $OverlayGlyph = [PsUi.ModuleContext]::GetIcon('Info') }

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

    # Brushes and control styles go straight onto the window when there is no Application to hold them.
    if ($dialogNeedsOwnTheme) { [PsUi.ThemeEngine]::ApplyStandaloneTheme($window, $colors) }

    $null = Set-WindowOwner -Window $window

    [PsUi.WindowManager]::SetWindowAppId($window, "PsUi.$AppIdSuffix")

    # Only the PowerShell view passes one. Everything else sizes to its content.
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

    # Both calls below reach for the window handle, and there is none until Loaded.
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

    # Grid rather than DockPanel, so the grip can overlay the chrome's corner
    $chromeGrid = [System.Windows.Controls.Grid]::new()
    [void]$chromeGrid.Children.Add($mainPanel)
    $mainBorder.Child = $chromeGrid

    if ($ResizeMode -ne 'NoResize') {
        $resizeGrip = [System.Windows.Controls.Primitives.ResizeGrip]@{
            HorizontalAlignment = 'Right'
            VerticalAlignment   = 'Bottom'
            Cursor              = [System.Windows.Input.Cursors]::SizeNWSE
        }
        [void]$chromeGrid.Children.Add($resizeGrip)

        # The grip is 17px square, so where you press inside it changes the offset, the mousedown works out the real one.
        $gripGrab      = @{ X = 16; Y = 16 }
        $gripWindow    = $window
        $gripMinWidth  = $MinWidth
        $gripMinHeight = $MinHeight

        $resizeGrip.Add_MouseLeftButtonDown({
            param($sender, $eventArgs)
            # Turn it off first, or SizeToContent overrides every Height written during the drag.
            $gripWindow.SizeToContent = 'Manual'
            $downPos     = [System.Windows.Input.Mouse]::GetPosition($gripWindow)
            $gripGrab.X  = $gripWindow.ActualWidth  - $downPos.X
            $gripGrab.Y  = $gripWindow.ActualHeight - $downPos.Y
            $null = $sender.CaptureMouse()
            $eventArgs.Handled = $true
        }.GetNewClosure())

        $resizeGrip.Add_MouseMove({
            param($sender, $eventArgs)
            if (!$sender.IsMouseCaptured) { return }
            $mousePos          = [System.Windows.Input.Mouse]::GetPosition($gripWindow)
            $gripWindow.Width  = [Math]::Max($gripMinWidth,  $mousePos.X + $gripGrab.X)
            $gripWindow.Height = [Math]::Max($gripMinHeight, $mousePos.Y + $gripGrab.Y)
            $eventArgs.Handled = $true
        }.GetNewClosure())

        $resizeGrip.Add_MouseLeftButtonUp({
            param($sender, $eventArgs)
            $sender.ReleaseMouseCapture()
            $eventArgs.Handled = $true
        })
    }

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
            FontFamily        = [PsUi.ModuleContext]::ActiveIconFontFamily
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

    $titleBar.Add_MouseLeftButtonDown({ $capturedWindow.DragMove() }.GetNewClosure())

    # Where each dialog puts its own controls
    $contentPanel = [System.Windows.Controls.DockPanel]@{
        Margin        = [System.Windows.Thickness]::new(16)
        LastChildFill = $true
    }
    [void]$mainPanel.Children.Add($contentPanel)

    return @{
        Window       = $window
        MainBorder   = $mainBorder
        MainPanel    = $mainPanel
        TitleBar     = $titleBar
        ContentPanel = $contentPanel
        Colors       = $colors
    }
}
