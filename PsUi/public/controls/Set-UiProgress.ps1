function Set-UiProgress {
    <#
    .SYNOPSIS
        Updates a progress bar's value, label, severity tint, or mode.
    .PARAMETER Variable
        Name of the progress bar to update.
    .PARAMETER Value
        New value. Clamped to the bar's Min/Max.
    .PARAMETER Increment
        Add this to the current value. If combined with -Value, adds to that.
    .PARAMETER Label
        Replace the label text above the bar (only works if built with -Label).
    .PARAMETER Severity
        Re-tint the bar: Info, Success, Warning, Error.
    .PARAMETER Indeterminate
        Toggle marquee mode on/off. Note: the bar's template was chosen at
        construction time, so toggling here rides on WPF's default behavior.
        For the slickest visuals, set -Indeterminate up front on New-UiProgress.
    .EXAMPLE
        Set-UiProgress -Variable 'progress' -Value 50
    .EXAMPLE
        Set-UiProgress -Variable 'files' -Increment 1 -Label "Processed $i of $total"
    .EXAMPLE
        Set-UiProgress -Variable 'job' -Severity Error -Label 'Failed'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Variable,

        [double]$Value,

        [double]$Increment,

        [string]$Label,

        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Severity,

        # Bool can't be null, so PSBoundParameters.ContainsKey() is what tells us
        # whether the caller actually asked to toggle the mode.
        [bool]$Indeterminate
    )

    $session = Get-UiSession
    if (!$session) {
        Write-Verbose "Set-UiProgress: no active session for '$Variable' - update dropped."
        return
    }
    $progress = $session.Variables[$Variable]
    if (!$progress) {
        Write-Verbose "Set-UiProgress: control '$Variable' not found in session - update dropped."
        return
    }

    $hasValue     = $PSBoundParameters.ContainsKey('Value')
    $hasIncrement = $PSBoundParameters.ContainsKey('Increment')
    $hasLabel     = $PSBoundParameters.ContainsKey('Label')
    $hasSeverity  = $PSBoundParameters.ContainsKey('Severity')
    $hasIndeterm  = $PSBoundParameters.ContainsKey('Indeterminate')

    # Nothing to do? Don't bother the dispatcher about it.
    if (!($hasValue -or $hasIncrement -or $hasLabel -or $hasSeverity -or $hasIndeterm)) {
        return
    }

    Invoke-OnUIThread {
        if ($hasValue -or $hasIncrement) {
            # Read $progress.Value here (inside the dispatcher) so -Increment alone
            # sees the latest committed value, not whatever was current when the
            # call queued. Matters when callers fire Set-UiProgress in tight loops.
            $newValue = if ($hasValue) { $Value } else { $progress.Value }

            if ($hasIncrement) { $newValue += $Increment }

            # Clamp so callers don't have to think about it
            if ($newValue -lt $progress.Minimum) { $newValue = $progress.Minimum }
            if ($newValue -gt $progress.Maximum) { $newValue = $progress.Maximum }
            $progress.Value = $newValue
        }

        if ($hasSeverity) {
            # Map severity to brush key for theme-aware tinting
            $brushKey = Get-SeverityBrushKey -Severity $Severity -UseAccentDefault

            # Clear local value so the resource binding wins
            $progress.ClearValue([System.Windows.Controls.Control]::ForegroundProperty)
            $progress.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, $brushKey)
        }

        $meta = $progress.Tag
        if ($meta -is [hashtable]) {
            if ($hasLabel) {
                if ($meta.LabelBlock) { $meta.LabelBlock.Text = $Label }
                else { Write-Verbose "Set-UiProgress: '$Variable' was created without -Label; skipping label update." }
            }
            if ($hasSeverity) {
                $meta.Severity = $Severity
                $meta.BrushTag = $brushKey
            }
        }

        if ($hasIndeterm) {
            # See .PARAMETER Indeterminate for the construction-time caveat.
            $progress.IsIndeterminate = $Indeterminate
            Write-Verbose "Set-UiProgress: toggled IsIndeterminate=$Indeterminate on '$Variable'."
        }
    }
}
