function Get-CustomLogoIcon {
    <#
    .SYNOPSIS
        Loads a custom logo image as a WPF BitmapImage.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (!(Test-Path $Path)) { return $null }

    try {
        # Resolve to absolute path and load with proper WPF initialization
        $resolvedPath = [System.IO.Path]::GetFullPath($Path)
        $bitmap       = [System.Windows.Media.Imaging.BitmapImage]::new()
        $bitmap.BeginInit()
        $bitmap.UriSource   = [System.Uri]::new($resolvedPath, [System.UriKind]::Absolute)
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.EndInit()
        $bitmap.Freeze()
        return $bitmap
    }
    catch {
        Write-Verbose "Failed to load custom logo from '$Path': $_"
        return $null
    }
}
