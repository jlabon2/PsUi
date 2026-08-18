function Clear-UiStatus {
    <#
    .SYNOPSIS
        Resets a status bar to its initial state.
    .DESCRIPTION
        Clears the status text, cancels any pending severity auto-reset, drops the tint back to Info,
        and zeros the embedded progress bar (if any).
        Safe to call from any thread.
    .PARAMETER Variable
        The variable name the status bar was registered under. When omitted, the active status bar is 
        resolved automatically.
    .EXAMPLE
        Clear-UiStatus
    .EXAMPLE
        Clear-UiStatus -Variable 'uploadBar'
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
            $hint = if ($Variable) { "no control registered as '$Variable'" } else { "no status bar registered in this session" }
            Write-Warning "Clear-UiStatus: $hint"
            return
        }

        $meta = if ($bar.Tag -is [hashtable]) { $bar.Tag } else { @{} }

        # Cancel any pending severity auto-reset before clearing the tint
        if ($meta.SeverityTimer) { $meta.SeverityTimer.Stop() }

        if ($meta.StatusText) { $meta.StatusText.Text = ''; $meta.StatusText.ToolTip = $null }

        # Drop the bar tint and severity icon back to Info
        $meta.Severity = 'Info'
        Set-StatusBarSeverityVisual -Bar $bar -Severity 'Info'

        # Zero all badge counts, clear popup message panels, close any open popups
        if ($meta.Intercept) { Reset-StatusBarBadges -Meta $meta }

        # Clear the progress label above the bar
        if ($meta.ProgressLabel) {
            $meta.ProgressLabel.Text       = ''
            $meta.ProgressLabel.Visibility = [System.Windows.Visibility]::Collapsed
        }

        # Zero the embedded progress bar, hide it, and clear its severity tint. Also releases any ManualBar hold.
        $meta.ManualBar = $false
        $progBar = $meta.ProgressBar
        if ($progBar) {
            $progBar.IsIndeterminate = $false
            $progBar.Value           = 0
            $progBar.Visibility      = [System.Windows.Visibility]::Hidden
            if ($progBar.Tag -is [hashtable]) {
                $progBar.Tag.Severity = 'Info'
                $progBar.Tag.BrushTag = Get-SeverityBrushKey -Severity 'Info' -UseAccentDefault
                try { Set-ProgressBarStyle -ProgressBar $progBar }
                catch { Write-Debug "Clear-UiStatus: Set-ProgressBarStyle failed: $_" }
            }
        }
    }
}
