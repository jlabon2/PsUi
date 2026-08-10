function ConvertTo-UiBrush {
    <#
    .SYNOPSIS
        Converts a hex color string to a WPF SolidColorBrush.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Color
    )

    # Cache lives here, not at file scope. Injected into background runspaces as Global:ConvertTo-UiBrush, the module's script scope never existed, so a file-top init would be skipped there anyway.
    if (!$script:_brushCache) { $script:_brushCache = @{} }

    $cached = $script:_brushCache[$Color]
    if ($cached) { return $cached }

    try {
        $wpfColor = [System.Windows.Media.ColorConverter]::ConvertFromString($Color)
        $brush    = [System.Windows.Media.SolidColorBrush]::new($wpfColor)
        $brush.Freeze()
        $script:_brushCache[$Color] = $brush
        return $brush
    }
    catch { return [System.Windows.Media.Brushes]::Gray }
}
