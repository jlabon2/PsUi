function Start-UIFadeIn {
    <#
    .SYNOPSIS
        Animates a window fade-in with easing - used by windows upon opening
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,
        
        [ValidateRange(1, 5000)]
        [int]$DurationMs = 350
    )
    
    # This seems to work pretty solid but wrap in try/catch to avoid breaking UIs if something goes wrong
    try {
        $fadeIn = [System.Windows.Media.Animation.DoubleAnimation]@{
            From     = 0
            To       = 1
            Duration = [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds($DurationMs))
        }
        
        # Quadratic ease  for smooth deceleration
        $fadeIn.EasingFunction = [System.Windows.Media.Animation.QuadraticEase]@{
            EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        }
        
        $Window.BeginAnimation([System.Windows.Window]::OpacityProperty, $fadeIn)
    }
    catch {
        $Window.Opacity = 1
        Write-Verbose "Animation failed, falling back to direct opacity: $_"
    }
}
