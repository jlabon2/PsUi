function New-UiSeparator {
    <#
    .SYNOPSIS
        Adds a horizontal line separator with elegant gradient fade.
    .PARAMETER Style
        Visual style of the separator:
        - Fade (default): Gradient that fades from transparent at edges to visible in center
        - Solid: Simple solid line
        - Accent: Uses accent color with fade effect
    .PARAMETER Height
        Line thickness in pixels. Defaults to 1.
    .PARAMETER TopMargin
        Space above the separator in pixels.
    .PARAMETER BottomMargin
        Space below the separator in pixels.
    .PARAMETER FullWidth
        Forces the separator to take full width in WrapPanel layouts.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
    .EXAMPLE
        New-UiSeparator
    .EXAMPLE
        New-UiSeparator -Style Accent
    .EXAMPLE
        New-UiSeparator -Style Solid
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Fade', 'Solid', 'Accent')]
        [string]$Style = 'Fade',

        [int]$Height = 1,
        [int]$TopMargin = 8,
        [int]$BottomMargin = 8,

        [switch]$FullWidth,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiSeparator'
    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent
    Write-Debug "Style=$Style, Height=$Height, Parent: $($parent.GetType().Name)"

    # Build the brush based on style
    $brush = switch ($Style) {
        'Solid' {
            ConvertTo-UiBrush $colors.Border
        }
        'Accent' {
            # Accent color with gradient fade at edges
            $accentColor = [System.Windows.Media.ColorConverter]::ConvertFromString($colors.Accent)
            $transparentAccent = [System.Windows.Media.Color]::FromArgb(0, $accentColor.R, $accentColor.G, $accentColor.B)
            $gradient = [System.Windows.Media.LinearGradientBrush]::new()
            $gradient.StartPoint = [System.Windows.Point]::new(0, 0.5)
            $gradient.EndPoint   = [System.Windows.Point]::new(1, 0.5)
            [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($transparentAccent, 0))
            [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($accentColor, 0.15))
            [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($accentColor, 0.85))
            [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($transparentAccent, 1))
            $gradient
        }
        default {
            # 'Fade' - Border color with gradient fade at edges
            $borderColor = [System.Windows.Media.ColorConverter]::ConvertFromString($colors.Border)
            $transparentBorder = [System.Windows.Media.Color]::FromArgb(0, $borderColor.R, $borderColor.G, $borderColor.B)
            $gradient = [System.Windows.Media.LinearGradientBrush]::new()
            $gradient.StartPoint = [System.Windows.Point]::new(0, 0.5)
            $gradient.EndPoint   = [System.Windows.Point]::new(1, 0.5)
            [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($transparentBorder, 0))
            [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($borderColor, 0.1))
            [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($borderColor, 0.9))
            [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($transparentBorder, 1))
            $gradient
        }
    }

    # Store style in Tag for theme updates
    $separator = [System.Windows.Controls.Border]@{
        Height              = $Height
        Margin              = [System.Windows.Thickness]::new(0, $TopMargin, 0, $BottomMargin)
        Background          = $brush
        HorizontalAlignment = 'Stretch'
        Tag                 = "Separator_$Style"
    }

    # Complete setup: constraints, properties, add to parent
    Complete-UiControlSetup -Control $separator -Parent $parent -FullWidth:$FullWidth -WPFProperties $WPFProperties
}
