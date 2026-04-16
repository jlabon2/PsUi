function Get-UiTheme {
    <#
    .SYNOPSIS
        Gets the current theme name and color palette.
    #>
    [CmdletBinding()]
    param()

    Write-Debug "Retrieving current theme"
    $colors    = Get-ThemeColors
    $themeName = [PsUi.ModuleContext]::ActiveTheme
    Write-Debug "Active theme: $themeName, Colors count: $($colors.Keys.Count)"

    return [PSCustomObject]@{
        Name   = $themeName
        Colors = $colors
    }
}
