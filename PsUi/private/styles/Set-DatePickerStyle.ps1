function Set-DatePickerStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DatePicker]$DatePicker
    )

    # Try to apply the Modern XAML style
    $styleApplied = $false
    try {
        if ($null -ne [System.Windows.Application]::Current) {
            $style = [System.Windows.Application]::Current.TryFindResource('ModernDatePickerStyle')
            if ($null -ne $style) {
                $DatePicker.Style = $style
                $styleApplied = $true
            }
        }
    }
    catch {
        Write-Verbose "Failed to apply ModernDatePickerStyle from resources: $_"
    }

    # Warn if XAML style not found (indicates ThemeEngine initialization issue)
    if (!$styleApplied) {
        Write-Warning "XAML style 'ModernDatePickerStyle' not found. Ensure ThemeEngine.LoadStyles() was called."
    }
    
    # Clear local values so DynamicResource in style works
    $DatePicker.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
    $DatePicker.ClearValue([System.Windows.Controls.Control]::ForegroundProperty)
    $DatePicker.ClearValue([System.Windows.Controls.Control]::BorderBrushProperty)

    try {
        [PsUi.ThemeEngine]::RegisterElement($DatePicker)
    }
    catch {
        Write-Verbose "Failed to register DatePicker with ThemeEngine: $_"
    }
}