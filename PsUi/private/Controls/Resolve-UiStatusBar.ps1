function Resolve-UiStatusBar {
    <#
    .SYNOPSIS
        Finds a status bar by -Variable or the window's bar if none exist.
    #>
    [CmdletBinding()]
    param(
        [string]$Variable,

        # Handed over by the helpers
        $Session
    )

    if (!$Session) { $Session = Get-UiSession }
    if (!$Session) { return $null }

    if ($Variable) { return $Session.GetControl($Variable) }

    # Collect every IsStatusBar-tagged control in the session
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($key in @($Session.SafeVariables.Keys)) {
        $candidate = $Session.GetControl($key)
        if ($candidate -and $candidate.Tag -is [hashtable] -and $candidate.Tag['IsStatusBar']) {
            $candidates.Add($candidate)
        }
    }

    if ($candidates.Count -eq 0) { return $null }
    if ($candidates.Count -eq 1) { return $candidates[0] }

    # Window bar over other bars, bottom over top, then the first one built
    # SafeVariables hands its keys back in hash order, which 5.1 and 7 don't agree on, so the build order breaks ties
    $best = $candidates[0]
    for ($idx = 1; $idx -lt $candidates.Count; $idx++) {
        $other     = $candidates[$idx]
        $bestMeta  = if ($best.Tag -is [hashtable])  { $best.Tag }  else { @{} }
        $otherMeta = if ($other.Tag -is [hashtable]) { $other.Tag } else { @{} }

        $bestWindow  = [bool]$bestMeta['IsWindowBar']
        $otherWindow = [bool]$otherMeta['IsWindowBar']
        if ($otherWindow -and !$bestWindow) { $best = $other; continue }
        if ($bestWindow -and !$otherWindow) { continue }

        $bestBottom  = [System.Windows.Controls.DockPanel]::GetDock($best) -eq [System.Windows.Controls.Dock]::Bottom
        $otherBottom = [System.Windows.Controls.DockPanel]::GetDock($other) -eq [System.Windows.Controls.Dock]::Bottom
        if ($otherBottom -and !$bestBottom) { $best = $other; continue }
        if ($bestBottom -and !$otherBottom) { continue }

        # Somebody tagged a Border by hand
        $bestBuilt  = if ($bestMeta.ContainsKey('BuiltAt'))  { [long]$bestMeta['BuiltAt'] }  else { [long]::MaxValue }
        $otherBuilt = if ($otherMeta.ContainsKey('BuiltAt')) { [long]$otherMeta['BuiltAt'] } else { [long]::MaxValue }
        if ($otherBuilt -lt $bestBuilt) { $best = $other }
    }

    return $best
}
