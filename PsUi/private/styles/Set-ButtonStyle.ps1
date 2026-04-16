<#
.SYNOPSIS
    Styles a Button with rounded corners and hover effects.
#>
function Set-ButtonStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$Button,

        [switch]$Accent,

        [switch]$IconOnly
    )

    # For accent buttons, set hover brush BEFORE applying style so template picks it up
    if ($Accent) {
        $hoverBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(40, 255, 255, 255))
        $Button.Resources['ButtonHoverBackgroundBrush'] = $hoverBrush
        
        # Clear any existing style so we get a fresh template that sees our resource
        $Button.Style = $null
    }

    $styleApplied = $false
    try {
        if ([System.Windows.Application]::Current -and [System.Windows.Application]::Current.Resources) {
            if ([System.Windows.Application]::Current.Resources.Contains("ModernButtonStyle")) {
                $Button.Style = [System.Windows.Application]::Current.Resources["ModernButtonStyle"]

                # Clear local values so the Style triggers can work properly
                $Button.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
                $Button.ClearValue([System.Windows.Controls.Control]::ForegroundProperty)
                $Button.ClearValue([System.Windows.Controls.Control]::BorderBrushProperty)

                $styleApplied = $true
                Write-Verbose "Applied ModernButtonStyle from XAML resources"
            }
        }
    }
    catch {
        Write-Verbose "Failed to apply ModernButtonStyle from resources: $_"
    }

    if ($Accent) {
        $colors = Get-ThemeColors
        Write-Debug "Accent button - using color: $($colors.Accent)"
        $Button.Background  = ConvertTo-UiBrush $colors.Accent
        $Button.Foreground  = ConvertTo-UiBrush $colors.AccentHeaderFg
        $Button.BorderBrush = ConvertTo-UiBrush $colors.Accent
        
        # Merge IsAccent into existing Tag (don't overwrite the context hashtable!)
        if ($Button.Tag -is [System.Collections.IDictionary]) {
            $Button.Tag['IsAccent'] = $true
        }
        else {
            $Button.Tag = @{ IsAccent = $true }
        }
        
        # Update child TextBlocks to use contrasting foreground (handles StackPanel and ViewBox content)
        if ($Button.Content -is [System.Windows.Controls.StackPanel]) {
            foreach ($child in $Button.Content.Children) {
                if ($child -is [System.Windows.Controls.TextBlock]) {
                    $child.Foreground = ConvertTo-UiBrush $colors.AccentHeaderFg
                }
            }
        }
        elseif ($Button.Content -is [System.Windows.Controls.Viewbox]) {
            $viewBoxChild = $Button.Content.Child
            if ($viewBoxChild -is [System.Windows.Controls.TextBlock]) {
                $viewBoxChild.Foreground = ConvertTo-UiBrush $colors.AccentHeaderFg
            }
            elseif ($viewBoxChild -is [System.Windows.Controls.StackPanel]) {
                # Viewbox wrapping a StackPanel (icon + text)
                foreach ($child in $viewBoxChild.Children) {
                    if ($child -is [System.Windows.Controls.TextBlock]) {
                        $child.Foreground = ConvertTo-UiBrush $colors.AccentHeaderFg
                    }
                }
            }
        }
        elseif ($Button.Content -is [System.Windows.Controls.TextBlock]) {
            $Button.Content.Foreground = ConvertTo-UiBrush $colors.AccentHeaderFg
        }
    }

    # Warn if XAML style not found (indicates ThemeEngine initialization issue)
    if (!$styleApplied) {
        Write-Warning "XAML style 'ModernButtonStyle' not found. Ensure ThemeEngine.LoadStyles() was called."
    }

    try {
        [PsUi.ThemeEngine]::RegisterElement($Button)
    }
    catch {
        Write-Verbose "Failed to register Button with ThemeEngine: $_"
    }
}