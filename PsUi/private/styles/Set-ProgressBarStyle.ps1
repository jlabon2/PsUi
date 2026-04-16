function Set-ProgressBarStyle {
    <#
    .SYNOPSIS
        Applies theme styling to a progress bar control.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ProgressBar]$ProgressBar
    )

    # Skip custom template for indeterminate mode - WPF native animation is better
    if ($ProgressBar.IsIndeterminate) {
        $colors = Get-ThemeColors
        if ($colors) {
            $ProgressBar.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom($colors.Accent)
            $ProgressBar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom($colors.ControlBg)
        }
        $ProgressBar.Height = 6
        return
    }

    # Apply modern style template for determinate mode
    $styleApplied = $false
    try {
        if ($null -ne [System.Windows.Application]::Current) {
            $style = [System.Windows.Application]::Current.TryFindResource('ModernProgressBarStyle')
            if ($null -ne $style) {
                $ProgressBar.Style = $style
                $styleApplied = $true
            }
        }
    }
    catch {
        Write-Verbose "Failed to apply ModernProgressBarStyle: $_"
    }

    if (!$styleApplied) {
        Write-Warning "XAML style 'ModernProgressBarStyle' not found. Ensure ThemeEngine.LoadStyles() was called."
    }
    
    $ProgressBar.Height = 6

    # Register with ThemeEngine so progress bars update on theme switch
    try { [PsUi.ThemeEngine]::RegisterElement($ProgressBar) }
    catch { Write-Verbose "Failed to register ProgressBar with ThemeEngine: $_" }
}
