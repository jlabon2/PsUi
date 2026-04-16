<#
.SYNOPSIS
    Styles a Slider with XAML template from resources.
#>
function Set-SliderStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Slider]$Slider
    )

    # Try to apply XAML style from resources
    $styleApplied = $false
    try {
        if ([System.Windows.Application]::Current -and [System.Windows.Application]::Current.Resources) {
            if ([System.Windows.Application]::Current.Resources.Contains("ModernSliderStyle")) {
                $Slider.Style = [System.Windows.Application]::Current.Resources["ModernSliderStyle"]
                
                # Clear local values so style setters (with DynamicResource) take effect
                $Slider.ClearValue([System.Windows.Controls.Control]::ForegroundProperty)
                $Slider.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
                $Slider.ClearValue([System.Windows.Controls.Control]::BorderBrushProperty)
                
                $styleApplied = $true
                Write-Verbose "Applied ModernSliderStyle from XAML resources"
            }
        }
    }
    catch {
        Write-Verbose "Failed to apply ModernSliderStyle from resources: $_"
    }

    # Warn if XAML style not found (indicates ThemeEngine initialization issue)
    if (!$styleApplied) {
        Write-Warning "XAML style 'ModernSliderStyle' not found. Ensure ThemeEngine.LoadStyles() was called."
    }

    $Slider.Cursor = [System.Windows.Input.Cursors]::Hand
    
    # Set default dimensions for horizontal orientation
    if ($Slider.Orientation -eq 'Horizontal') {
        $Slider.MinHeight = 22
        $Slider.MinWidth = 100
    }
    else {
        $Slider.Width = 32
        $Slider.MinHeight = 50
    }

    try {
        [PsUi.ThemeEngine]::RegisterElement($Slider)
    }
    catch {
        Write-Verbose "Failed to register Slider with ThemeEngine: $_"
    }
}
