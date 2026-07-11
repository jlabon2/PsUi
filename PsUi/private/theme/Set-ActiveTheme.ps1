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
    Reset-BrushCache

    if ([PsUi.ModuleContext]::IsInitialized) {
        
        # Pass theme colors to the C# engine - it handles all control updates including the theme button icon via Tag='ThemeButtonIcon'.
        $colors = $themes[$Theme]
        [PsUi.ThemeEngine]::ApplyTheme($Theme, $colors)

        # ApplyTheme above already produced LinkBrush when the theme defines a Link color.
        # Fallback for themes without one: AccentBrush stands in so DynamicResource('LinkBrush') consumers resolve.
        if ([System.Windows.Application]::Current) {
            try {
                $linkColor = if ($colors.Link) { $colors.Link } else { $colors.Accent }
                if ($linkColor) { [System.Windows.Application]::Current.Resources['LinkBrush'] = (ConvertTo-UiBrush $linkColor)  }
            }
            catch { Write-Debug "LinkBrush registration failed: $_" }
        }

        # Walk the open windows so out-of-session ones (Out-CSVDataGrid / Out-Datagrid) refresh too. Home-thread only: Application.Windows calls VerifyAccess and THROWS on a cross-thread read, so from a secondary STA thread the catch below eats it and the walk no-ops (ThemeEngine reads WindowsInternal via reflection for exactly this reason).
        # CheckAccess skips windows on other dispatchers... those have their own Set-ActiveTheme call.
        try {
            $app = [System.Windows.Application]::Current
            if ($app) {
                foreach ($win in @($app.Windows)) {
                    if ($win -and $win.Dispatcher.CheckAccess()) {  Update-AllControlThemes -Control $win -Colors $colors  }
                }
            }
        }
        catch { Write-Debug "Set-ActiveTheme tree walk failed: $_" }

        Write-Verbose "Applied theme '$Theme' from PowerShell definitions"
    }
}