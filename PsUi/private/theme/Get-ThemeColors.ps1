<#
.SYNOPSIS
    Gets the color palette for a theme.
#>
function Get-ThemeColors {
    [CmdletBinding()]
    param(
        [string]$ThemeName
    )

    $themes = [PsUi.ModuleContext]::Themes
    $activeTheme = [PsUi.ModuleContext]::ActiveTheme

    # If specific theme requested, return it
    if (![string]::IsNullOrEmpty($ThemeName)) {
        if ($themes.ContainsKey($ThemeName)) { return $themes[$ThemeName] }
        return $themes['Light']
    }

    # Try active theme from ModuleContext
    if (![string]::IsNullOrEmpty($activeTheme)) {
        if ($themes.ContainsKey($activeTheme)) { return $themes[$activeTheme] }
    }

    # Fallback: Light theme
    Write-Verbose "[Get-ThemeColors] Falling back to Light theme"
    if ($themes -and $themes.ContainsKey('Light')) { return $themes['Light'] }
    
    # Ultimate fallback if even Themes isn't loaded
    $fallback = @{
        WindowBg = '#FFFFFF'
        WindowFg = '#000000'
        ControlBg = '#F0F0F0'
        ControlFg = '#000000'
        Accent = '#0078D4'
        Border = '#CCCCCC'
        HeaderBackground = '#0078D4'
        HeaderForeground = '#FFFFFF'
        SelectionTextBrush = '#FFFFFF'
    }
    return $fallback
}