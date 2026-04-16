<#
.SYNOPSIS
    Sets the active theme for the application.
#>
function Set-ActiveTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Theme
    )

    # Bail if theme doesn't exist
    $themes = [PsUi.ModuleContext]::Themes
    if (!$themes -or !$themes.ContainsKey($Theme)) {
        $available = if ($themes) { $themes.Keys -join ', ' } else { 'none' }
        Write-Warning "Theme '$Theme' not found. Available: $available"
        return
    }

    [PsUi.ModuleContext]::ActiveTheme = $Theme

    # Clear cached brushes since theme colors are changing
    $script:_brushCache = @{}

    if ([PsUi.ModuleContext]::IsInitialized) {
        # Pass theme colors to C# engine - it handles all control updates
        # including the theme button icon via Tag='ThemeButtonIcon'
        $colors = $themes[$Theme]
        [PsUi.ThemeEngine]::ApplyTheme($Theme, $colors)
        Write-Verbose "Applied theme '$Theme' from PowerShell definitions"
    }
}