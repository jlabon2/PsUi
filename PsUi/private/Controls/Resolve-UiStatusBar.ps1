function Resolve-UiStatusBar {
    <#
    .SYNOPSIS
        Finds a status bar in the current session. With -Variable, looks up by name.
        Without, returns the first IsStatusBar-tagged control, preferring window-docked
        bars over inline ones so writes default to the window's primary bar when
        multiple bars exist.
    #>
    [CmdletBinding()]
    param(
        [string]$Variable
    )

    $session = Get-UiSession
    if (!$session) { return $null }

    if ($Variable) { return $session.GetControl($Variable) }

    # Collect every IsStatusBar-tagged control in the session
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($key in @($session.SafeVariables.Keys)) {
        $candidate = $session.GetControl($key)
        if ($candidate -and $candidate.Tag -is [hashtable] -and $candidate.Tag['IsStatusBar']) {
            $candidates.Add($candidate)
        }
    }

    if ($candidates.Count -eq 0) { return $null }
    if ($candidates.Count -eq 1) { return $candidates[0] }

    # Pick the best bar: window-level wins over inline, then bottom over top
    $best = $candidates[0]
    for ($idx = 1; $idx -lt $candidates.Count; $idx++) {
        $other    = $candidates[$idx]
        $bestMeta  = if ($best.Tag -is [hashtable])  { $best.Tag }  else { @{} }
        $otherMeta = if ($other.Tag -is [hashtable]) { $other.Tag } else { @{} }

        $bestWindow  = [bool]$bestMeta['IsWindowBar']
        $otherWindow = [bool]$otherMeta['IsWindowBar']
        if ($otherWindow -and !$bestWindow) { $best = $other; continue }
        if ($bestWindow -and !$otherWindow) { continue }

        $bestDock  = [System.Windows.Controls.DockPanel]::GetDock($best)
        $otherDock = [System.Windows.Controls.DockPanel]::GetDock($other)
        if ($otherDock -eq [System.Windows.Controls.Dock]::Bottom -and
            $bestDock  -ne [System.Windows.Controls.Dock]::Bottom) { $best = $other }
    }

    return $best
}
