function Initialize-UiWindowLoaded {
    <#
    .SYNOPSIS
        Wires up the standard window Loaded event handler.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [System.Windows.UIElement]$FocusElement,

        [switch]$SelectAll,

        [switch]$SetIcon,

        [string]$TitleBarBackground,

        [string]$TitleBarForeground
    )

    # Capture parameters for closure - must copy to local variables
    $capturedWindow     = $Window
    $capturedFocus      = $FocusElement
    $capturedSelectAll  = $SelectAll
    $capturedSetIcon    = $SetIcon
    $capturedTitleBg    = $TitleBarBackground
    $capturedTitleFg    = $TitleBarForeground

    $Window.Add_Loaded({
        # Fade-in animation with easing for a more polished feel
        # This will likely need a but mroe adjustment if we ever do custom window chrome all across
        # For now, it looks decent enough.
        try {
            $fadeIn = [System.Windows.Media.Animation.DoubleAnimation]@{
                From     = 0.0
                To       = 1.0
                Duration = [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds(350))
            }

            # Add quadratic ease-out for smoother deceleration
            # Not sure if this is the best choice, but it looks ok
            $fadeIn.EasingFunction = [System.Windows.Media.Animation.QuadraticEase]@{
                EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
            }

            $capturedWindow.BeginAnimation([System.Windows.Window]::OpacityProperty, $fadeIn)
        }

        catch { $capturedWindow.Opacity = 1 }         

        # Disable Topmost so window doesn't stay on top permanently
        $capturedWindow.Topmost = $false

        # Apply title bar theming
        try {
            $colors = Get-ThemeColors

            # Use custom colors if provided, otherwise use theme colors
            $bgColor = if ($capturedTitleBg) { $capturedTitleBg } else { $colors.HeaderBackground }
            $fgColor = if ($capturedTitleFg) { $capturedTitleFg } else { $colors.HeaderForeground }

            $headerBg = [System.Windows.Media.ColorConverter]::ConvertFromString($bgColor)
            $headerFg = [System.Windows.Media.ColorConverter]::ConvertFromString($fgColor)
            [PsUi.WindowManager]::SetTitleBarColor($capturedWindow, $headerBg, $headerFg)
        }

        catch { Write-Verbose "Failed to set title bar color: $_" }

        # Set themed window icon if requested
        if ($capturedSetIcon) {
            try {
                $colors = Get-ThemeColors
                $icon = New-WindowIcon -Colors $colors
                if ($icon) {
                    $capturedWindow.Icon = $icon
                    
                    # Force taskbar to use our icon
                    [PsUi.WindowManager]::SetTaskbarIcon($capturedWindow, $icon)
                }
            }
            catch { Write-Verbose "Failed to set window icon: $_" }
        }

        # Focus the specified element if provided; useful for dialogs
        if ($capturedFocus) {
            $capturedFocus.Focus()

            # Select all text if requested and control supports it
            if ($capturedSelectAll) {
                if ($capturedFocus -is [System.Windows.Controls.TextBox] -or
                    $capturedFocus -is [System.Windows.Controls.PasswordBox]) {
                    $capturedFocus.SelectAll()
                }
            }
        }
    }.GetNewClosure())
}
