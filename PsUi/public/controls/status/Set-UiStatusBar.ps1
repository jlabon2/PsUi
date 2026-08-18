function Set-UiStatusBar {
    <#
    .SYNOPSIS
        Updates status bar text, progress, and severity from any thread.
    .DESCRIPTION
        Pass any combination of parameters. Only bound parameters take effect.
        -Severity tint auto-resets to Info after 5 seconds unless -Timeout
        overrides; pass 0 to keep the tint until the next change.
    .PARAMETER Text
        Status text. Sets .Text on the bar's status label (the first non-glyph TextBlock).
        Pass an empty string to clear.
    .PARAMETER Progress
        Progress value (0-100). Sets .Value on the embedded progress bar.
        If both -Progress and -Increment are bound, -Progress wins. A value
        above zero holds the bar on screen across actions; zero releases the
        hold and hides the bar. For a visible not-started state, use
        -Indeterminate instead of zero.
    .PARAMETER Increment
        Adds to the current progress value. Clamps to [0, 100].
        Ignored when -Progress is also bound.
    .PARAMETER Severity
        Bar tint: Info, Success, Warning, Error. Survives theme switches.
    .PARAMETER Indeterminate
        Toggles indeterminate mode on the embedded progress bar.
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

         # Skipping [ValidateRange] here and on -Increment. Percentage math can occasionally round up to 101, and crashing the loop with a parameter error is much worse than just capping the progress bar.
        [int]$Progress,

        [int]$Increment,

        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Severity,

        [switch]$Indeterminate,

        [int]$Timeout,

        [string]$Variable
    )

    if (!$PSBoundParameters.Count) { return }

    # v2.x -Indeterminate took [bool]. Under [switch] a space-form '-Indeterminate $false' leaves the switch present (=$true) and spills $false to the next free positional slot: -Text when no text was passed ('False'/'True'), -Progress when text is bound (0/1), -Increment when both are (0/1).
    # Recover only when the switch is on - an explicit -Indeterminate:$false / splat $false is a modern caller who means it, so honor their -Text/-Progress as is. The spilled bool always lands in Text, Progress, or Increment; read it back.
    # Known edges, chosen not to chase: a modern caller pairing -Indeterminate with a literal -Text 'True'/'False', or with -Progress 0/1, gets reinterpreted as a v2.x spill. No in-repo caller does either, and a real status text is never the bare word 'True'.
    $indeterminateValue = [bool]$Indeterminate
    if ($Indeterminate) {
        if ($PSBoundParameters.ContainsKey('Text') -and $Text -in 'True', 'False') {
            $indeterminateValue = $Text -eq 'True'
            [void]$PSBoundParameters.Remove('Text')
            $Text = ''
        }
        elseif ($PSBoundParameters.ContainsKey('Text') -and $PSBoundParameters.ContainsKey('Progress') -and
                $Progress -in 0, 1 -and !$PSBoundParameters.ContainsKey('Increment')) {
            $indeterminateValue = $Progress -eq 1
            [void]$PSBoundParameters.Remove('Progress')
        }
        # Text and Progress both bound by name pushes the spill one slot further, into -Increment. -Progress plus -Increment in one call is already contradictory (set vs bump), so a 0/1 Increment here can only be the spilled bool.
        elseif ($PSBoundParameters.ContainsKey('Increment') -and $Increment -in 0, 1 -and
                $PSBoundParameters.ContainsKey('Text') -and $PSBoundParameters.ContainsKey('Progress')) {
            $indeterminateValue = $Increment -eq 1
            [void]$PSBoundParameters.Remove('Increment')
        }
    }

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
                $progBar.IsIndeterminate = $indeterminateValue
                Set-ProgressBarStyle -ProgressBar $progBar
            }

            if ($wantsProgress) {
                if ($progBar.IsIndeterminate) {
                    $meta.ManualBar = $true
                }
                elseif ($progBar.Value -gt 0) {
                    if (($boundKeys -contains 'Progress') -or ($boundKeys -contains 'Increment')) { $meta.ManualBar = $true }
                    else { $meta.ManualBar = $false }
                }
                else {
                    $meta.ManualBar     = $false
                    $progBar.Visibility = [System.Windows.Visibility]::Hidden
                }
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
