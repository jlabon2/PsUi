function Hide-UiStatusBar {
    <#
    .SYNOPSIS
        Collapses a status bar from view without removing it.
    .DESCRIPTION
        Sets Visibility to Collapsed so the bar takes no space and disappears.
        Safe to call from any thread. State is preserved - Show-UiStatusBar
        restores it.
    .PARAMETER Variable
        Optional session variable name. Defaults to the resolver fallback
        (statusBar, then any registered IsStatusBar control).
    .EXAMPLE
        Hide-UiStatusBar
    .EXAMPLE
        Hide-UiStatusBar -Variable 'mainBar'
    #>
    [CmdletBinding()]
    param(
        [string]$Variable
    )

    $session = Get-UiSession
    if (!$session) { return }

    Invoke-OnUIThread {
        $bar = Resolve-UiStatusBar -Variable $Variable
        if (!$bar) {
            $hint = if ($Variable) { "no control registered as '$Variable'" }
            else { "no status bar registered in this session" }
            Write-Warning "Hide-UiStatusBar: $hint"
            return
        }
        $bar.Visibility = [System.Windows.Visibility]::Collapsed
    }
}
