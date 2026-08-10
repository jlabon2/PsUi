function Get-SeverityBrushKey {
    <#
    .SYNOPSIS
        Maps a severity level to its dynamic brush resource key.
        -UseAccentDefault swaps the Info default to AccentBrush for controls
        (progress bars, etc.) where AccentBrush is the neutral fill.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Severity,

        [switch]$UseAccentDefault
    )

    switch ($Severity) {
        'Success' { return 'SuccessBrush' }
        'Warning' { return 'WarningBrush' }
        'Error'   { return 'ErrorBrush' }
        default   {
            if ($UseAccentDefault) { return 'AccentBrush' }
            return 'HeaderBackgroundBrush'
        }
    }
}
