<#
.SYNOPSIS
    Initializes the UI theme and returns color palette.
#>
function Initialize-UITheme {
    [CmdletBinding()]
    param(
        [string]$Theme = 'Light'
    )
    
    try {
        Set-ActiveTheme -Theme $Theme
    }
    catch {
        Write-Warning "Failed to load theme: $_. Using default colors."
    }
    
    # Load control styles into Application resources
    if ([System.Windows.Application]::Current) {
        [PsUi.ThemeEngine]::LoadStyles()
    }
    
    $colors = Get-ThemeColors
    if (!$colors) {
        $colors = @{
            WindowBg         = '#FFFFFF'
            WindowFg         = '#1A1A1A'
            ControlBg        = '#F3F3F3'
            ControlFg        = '#1A1A1A'
            Accent           = '#0078D4'
            Border           = '#D1D1D1'
            HeaderBackground = '#0078D4'
            HeaderForeground = '#FFFFFF'
        }
    }
    
    return $colors
}
