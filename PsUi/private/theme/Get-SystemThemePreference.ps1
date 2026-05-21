function Get-SystemThemePreference {
    <#
    .SYNOPSIS
        Detects the system's light/dark theme preference from the registry.
    #>
    [CmdletBinding()]
    param()

    try {
        $value = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop
        if ($value -eq 0) { return 'Dark' }
        return 'Light'
    }
    catch {  return 'Light' }
}
