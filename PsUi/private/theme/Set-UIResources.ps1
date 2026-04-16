<#
.SYNOPSIS
    Sets window icon and title bar colors.
#>
function Set-UIResources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,
        
        [hashtable]$Colors,
        
        [string]$IconPath
    )
    
    # Set window icon
    try {
        if ($IconPath -and (Test-Path $IconPath)) {
            $iconUri = [System.Uri]::new([System.IO.Path]::GetFullPath($IconPath))
            $Window.Icon = [System.Windows.Media.Imaging.BitmapImage]::new($iconUri)
        }
        else {
            $iconImage = New-WindowIcon -Colors $Colors
            if ($iconImage) {
                $Window.Icon = $iconImage
            }
        }
    }
    catch {
        Write-Verbose "Failed to set window icon: $_"
    }

    # Set title bar colors
    try {
        if ([PsUi.ModuleContext]::IsInitialized) {
            $headerBg = [System.Windows.Media.ColorConverter]::ConvertFromString($Colors.HeaderBackground)
            $headerFg = [System.Windows.Media.ColorConverter]::ConvertFromString($Colors.HeaderForeground)
            [PsUi.WindowManager]::SetTitleBarColor($Window, $headerBg, $headerFg)
        }
    }
    catch {
        Write-Verbose "Failed to set title bar colors: $_"
    }
}
