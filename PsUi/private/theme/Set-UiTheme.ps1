function Set-UiTheme {
    <#
    .SYNOPSIS
        Changes the active color theme.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ArgumentCompleter({ [PsUi.ThemeEngine]::GetAvailableThemes() })]
        [string]$Theme
    )

    Write-Debug "Changing theme to '$Theme'"

    try {
        Set-ActiveTheme -Theme $Theme
        Write-Debug "Theme applied successfully"
        Write-Verbose "Theme set to $Theme"
    }
    catch {
        Write-Debug "Failed: $_"
        Write-Error "Failed to set theme: $_"
    }
}
