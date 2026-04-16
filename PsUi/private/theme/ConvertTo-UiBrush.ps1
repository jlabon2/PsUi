<#
.SYNOPSIS
    Converts a hex color string to a WPF SolidColorBrush.
#>
# Module-scoped brush cache — frozen brushes are immutable and safe to reuse.
# Cleared on theme change by Reset-BrushCache (called from Set-ActiveTheme).
if (!$script:_brushCache) { $script:_brushCache = @{} }

function ConvertTo-UiBrush {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Color
    )

    $cached = $script:_brushCache[$Color]
    if ($cached) { return $cached }

    try {
        $wpfColor = [System.Windows.Media.ColorConverter]::ConvertFromString($Color)
        $brush    = [System.Windows.Media.SolidColorBrush]::new($wpfColor)
        $brush.Freeze()
        $script:_brushCache[$Color] = $brush
        return $brush
    }
    catch {
        return [System.Windows.Media.Brushes]::Gray
    }
}

function Reset-BrushCache {
    <#
    .SYNOPSIS
        Clears the cached brush lookup. Called on theme switches.
    #>
    $script:_brushCache = @{}
}
