function Test-StatusBarIntercept {
    <#
    .SYNOPSIS
        True when an -Intercept bar will show the action's errors (and so no dialog is needed).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Session
    )

    foreach ($key in @($Session.SafeVariables.Keys)) {
        $candidate = $Session.GetControl($key)
        if (!$candidate -or $candidate.Tag -isnot [hashtable]) { continue }
        if (!$candidate.Tag['IsStatusBar'] -or !$candidate.Tag['Intercept']) { continue }

        # After Hide-UiStatusBar the badges still count, just not visibily... collapsing an expander or picking another tab hides them too
        $showing = $true
        $walker  = $candidate
        while ($walker) {
            if ($walker -is [System.Windows.UIElement] -and $walker.Visibility -ne [System.Windows.Visibility]::Visible) { $showing = $false; break }
            if ($walker -is [System.Windows.Controls.TabItem] -and !$walker.IsSelected) { $showing = $false; break }
            $walker = $walker.Parent
        }
        if ($showing) { return $true }
    }
    return $false
}
