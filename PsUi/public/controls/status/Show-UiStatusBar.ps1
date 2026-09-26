function Show-UiStatusBar {
    <#
    .SYNOPSIS
        Restores a previously hidden status bar to view.
    .DESCRIPTION
        Sets Visibility to Visible. Safe to call from any thread.
    .PARAMETER Variable
        Optional session variable name. When omitted, the registered status bar is
        resolved automatically (window bars win over inline ones).
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

    $outcome = Invoke-OnUIThread -ArgumentList $session, $Variable -ScriptBlock {
        param($session, $Variable)

        $bar = Resolve-UiStatusBar -Session $session -Variable $Variable
        if (!$bar) { return 'NoBar' }
        $bar.Visibility = [System.Windows.Visibility]::Visible
    }

    if ($outcome -eq 'NoBar') {
        $hint = if ($Variable) { "no control registered as '$Variable'" }
        else { "no status bar registered in this session" }
        Write-Warning "Show-UiStatusBar: $hint"
    }
}
