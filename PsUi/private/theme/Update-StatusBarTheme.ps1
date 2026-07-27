function Update-StatusBarTheme {
    <#
    .SYNOPSIS
        Applies theme + severity-aware styling to a status bar Border.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Border]$Bar,

        [Parameter(Mandatory)]
        [hashtable]$Colors
    )

    $meta     = if ($Bar.Tag -is [hashtable]) { $Bar.Tag } else { @{} }
    $severity = $meta['Severity']

    $bgKey = if ($severity -and $severity -ne 'Info') {
        switch ($severity) {
            'Success' { 'SuccessBrush' }
            'Warning' { 'WarningBrush' }
            'Error'   { 'ErrorBrush' }
            default   { 'HeaderBackgroundBrush' }
        }
    }
    else {
        'HeaderBackgroundBrush'
    }

    $Bar.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $bgKey)
    $Bar.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'BorderBrush')

    # Defer text contrast to Loaded priority so it lands after sibling theme handlers
    # that would otherwise overwrite TextBlock foregrounds via their Tag bindings.
    # GetNewClosure captures locals into a dynamic module so the dispatcher callback
    # can resolve both the captured variables and the module-scoped functions.
    $effectiveSev   = if ($severity) { $severity } else { 'Info' }
    $capturedBar    = $Bar
    $capturedSev    = $effectiveSev
    $capturedColors = $Colors
    [void]$Bar.Dispatcher.BeginInvoke(
        [Action]{
            Set-StatusBarSeverityVisual -Bar $capturedBar -Severity $capturedSev -Colors $capturedColors

            # Recalculate badge text foreground against the badge's own background
            $barMeta = if ($capturedBar.Tag -is [hashtable]) { $capturedBar.Tag } else { @{} }
            if ($barMeta.Intercept) {
                foreach ($badgeInfo in @($barMeta.WarningBadge, $barMeta.ErrorBadge, $barMeta.HostBadge, $barMeta.VerboseBadge, $barMeta.DebugBadge)) {
                    if (!$badgeInfo) { continue }
                    $sevHex = switch ($badgeInfo.BrushKey) {
                        'WarningBrush'       { $capturedColors.Warning }
                        'ErrorBrush'         { $capturedColors.Error }
                        'AccentBrush'        { $capturedColors.Accent }
                        'SecondaryTextBrush' { $capturedColors.SecondaryText }
                    }
                    if ($sevHex) {
                        $fgBrush = ConvertTo-UiBrush (Get-ContrastColor -HexColor $sevHex)
                        $badgeInfo.GlyphText.Foreground = $fgBrush
                        $badgeInfo.CountText.Foreground = $fgBrush
                    }
                }
            }
        }.GetNewClosure(),
        [System.Windows.Threading.DispatcherPriority]::Loaded)
}
