function Show-UiStatusBar {
    <#
    .SYNOPSIS
        Restores a previously hidden status bar to view.
    .DESCRIPTION
        Sets Visibility to Visible. Safe to call from any thread.
    .PARAMETER Variable
        Optional session variable name. Defaults to the resolver fallback
        (statusBar, then any registered IsStatusBar control).
    .EXAMPLE
        Show-UiStatusBar
    .EXAMPLE
        Show-UiStatusBar -Variable 'mainBar'
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
            Write-Warning "Show-UiStatusBar: $hint"
            return
        }
        $bar.Visibility = [System.Windows.Visibility]::Visible
    }
}
