function Add-StatusBarHistoryEntry {
    <#
    .SYNOPSIS
        Appends a status message to the bar's activity ledger and refreshes the
        hover tooltip. Keeps the last 10 entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Bar,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Progress')]
        [string]$Kind = 'Info'
    )

    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    if (!$Bar -or $Bar.Tag -isnot [hashtable]) { return }

    $meta = $Bar.Tag

    if (!$meta.History) { $meta.History = [System.Collections.Generic.List[object]]::new() }
    $history = $meta.History

    # Coalesce duplicate consecutive entries (rapid Write-Progress with same text)
    if ($history.Count -gt 0) {
        $last = $history[$history.Count - 1]
        if ($last.Message -eq $Message -and $last.Kind -eq $Kind) { return }
    }

    $history.Add([PSCustomObject]@{
        Time    = Get-Date
        Message = $Message
        Kind    = $Kind
    })

    while ($history.Count -gt 10) { $history.RemoveAt(0) }

    # Intercept bars use badge popups instead of the hover tooltip
    if ($meta.Intercept) { return }

    # Rebuild the tooltip text newest-first
    $lines = [System.Collections.Generic.List[string]]::new()
    for ($idx = $history.Count - 1; $idx -ge 0; $idx--) {
        $entry  = $history[$idx]
        $prefix = switch ($entry.Kind) {
            'Success'  { '+' }
            'Warning'  { '!' }
            'Error'    { 'x' }
            'Progress' { '>' }
            default    { ' ' }
        }
        $lines.Add(('[{0:HH:mm:ss}] {1} {2}' -f $entry.Time, $prefix, $entry.Message))
    }

    # Plain string tooltip avoids the popup measure cascade a TextBlock tooltip triggers
    $Bar.ToolTip = "Recent activity (newest first):`n" + ($lines -join "`n")
}
