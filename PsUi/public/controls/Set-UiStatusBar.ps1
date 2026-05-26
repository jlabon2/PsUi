function Set-UiStatusBar {
    <#
    .SYNOPSIS
        Updates status bar text, progress, and severity from any thread.
    .DESCRIPTION
        Pass any combination of parameters. Only bound parameters take effect.
        -Severity tint auto-resets to Info after 5 seconds unless -Timeout
        overrides; pass 0 to keep the tint until the next change.
    .PARAMETER Text
        Status text. Sets .Text on the first TextBlock child.
        Pass an empty string to clear.
    .PARAMETER Progress
        Progress value (0-100). Sets .Value on the embedded progress bar.
        If both -Progress and -Increment are bound, -Progress wins.
    .PARAMETER Increment
        Adds to the current progress value. Clamps to [0, 100].
        Ignored when -Progress is also bound.
    .PARAMETER Severity
        Bar tint: Info (default), Success, Warning, Error. Survives theme switches.
    .PARAMETER Indeterminate
        Toggles marquee mode on the embedded progress bar.
    .PARAMETER Timeout
        Seconds before severity auto-resets to Info. Defaults to 5 when -Severity
        is bound. Pass 0 to keep the tint until the next manual change.
    .PARAMETER Variable
        Session name the bar was registered under. Resolves the active bar when omitted.
    .EXAMPLE
        Set-UiStatusBar -Text 'Deploying...' -Progress 87 -Severity Warning
    .EXAMPLE
        Set-UiStatusBar -Severity Error -Timeout 0 -Text 'Failed'
    #>
    [CmdletBinding()]
    param(
        [string]$Text,

        [int]$Progress,

        [int]$Increment,

        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Severity,

        [bool]$Indeterminate,

        [int]$Timeout,

        [string]$Variable
    )

    if (!$PSBoundParameters.Count) { return }

    $session = Get-UiSession
    if (!$session) { return }

    # Severity auto-reset: explicit -Timeout wins; default to 5s when only -Severity is bound
    $effectiveTimeout = 0
    if ($PSBoundParameters.ContainsKey('Timeout')) {
        $effectiveTimeout = $Timeout
    }
    elseif ($PSBoundParameters.ContainsKey('Severity')) {
        $effectiveTimeout = 5
    }

    $boundKeys = $PSBoundParameters.Keys

    Invoke-OnUIThread {
        $bar = Resolve-UiStatusBar -Variable $Variable
        if (!$bar) {
            $hint = if ($Variable) { "no control registered as '$Variable'" } else { "no status bar registered in this session" }
            Write-Warning "Set-UiStatusBar: $hint"
            return
        }

        $meta      = if ($bar.Tag -is [hashtable]) { $bar.Tag } else { @{} }
        $textBlock = $meta.StatusText
        $progBar   = $meta.ProgressBar

        # Update text and append to the bar's activity ledger
        if ($boundKeys -contains 'Text' -and $textBlock) {
            $textBlock.Text    = $Text
            $textBlock.ToolTip = if ($Text.Length -gt 60) { $Text } else { $null }
            $ledgerKind     = if ($boundKeys -contains 'Severity') { $Severity } else { 'Info' }
            try { Add-StatusBarHistoryEntry -Bar $bar -Message $Text -Kind $ledgerKind }
            catch { Write-Verbose "Set-UiStatusBar ledger entry failed: $_" }
        }

        # Warn when caller passed progress but the bar has no embedded progress bar
        $wantsProgress = ($boundKeys -contains 'Progress') -or ($boundKeys -contains 'Increment') -or ($boundKeys -contains 'Indeterminate')
        if ($wantsProgress -and !$progBar) {
            Write-Verbose "Set-UiStatusBar: -Progress/-Increment/-Indeterminate set but no embedded bar. Re-create the status bar with -AutoProgress."
        }

        if ($progBar) {
            # Show the bar when the caller is actively driving progress
            if ($wantsProgress -and $progBar.Visibility -ne [System.Windows.Visibility]::Visible) {
                $progBar.Visibility = [System.Windows.Visibility]::Visible
            }

            # Progress wins over Increment when both are bound
            if ($boundKeys -contains 'Progress') {
                $clamped = $Progress
                if ($clamped -lt 0)   { $clamped = 0 }
                if ($clamped -gt 100) { $clamped = 100 }
                $progBar.Value = $clamped
            }
            elseif ($boundKeys -contains 'Increment') {
                $newVal = $progBar.Value + $Increment
                if ($newVal -lt 0)   { $newVal = 0 }
                if ($newVal -gt 100) { $newVal = 100 }
                $progBar.Value = $newVal
            }

            if ($boundKeys -contains 'Indeterminate') {
                $progBar.IsIndeterminate = $Indeterminate
                Set-ProgressBarStyle -ProgressBar $progBar
            }
        }

        # Apply severity tint and sync the embedded progress bar's fill
        if ($boundKeys -contains 'Severity') {
            $meta.Severity = $Severity
            Set-StatusBarSeverityVisual -Bar $bar -Severity $Severity

            if ($progBar -and $progBar.Tag -is [hashtable]) {
                $progBar.Tag.Severity = $Severity
                $progBar.Tag.BrushTag = Get-SeverityBrushKey -Severity $Severity -UseAccentDefault
                Set-ProgressBarStyle -ProgressBar $progBar
            }

            if ($effectiveTimeout -gt 0 -and $meta.SeverityTimer) {
                $meta.SeverityTimer.Stop()
                $meta.SeverityTimer.Interval = [TimeSpan]::FromSeconds($effectiveTimeout)
                $meta.SeverityTimer.Start()
            }
            elseif ($effectiveTimeout -le 0 -and $meta.SeverityTimer) {
                $meta.SeverityTimer.Stop()
            }
        }

        $bar.Tag = $meta
    }
}
