function Set-UiProgress {
    <#
    .SYNOPSIS
        Updates a progress bar's value, label, severity tint, or mode.
    .DESCRIPTION
        Updates a New-UiProgress bar while an action runs: set or increment the value, swap the
        label, tint by severity, or flip indeterminate mode. Safe to call from async actions.
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
        Toggle indeterminate mode on/off. Bar template is fixed at construction, so the first
        toggle starts the animation cold. Pass -Indeterminate to New-UiProgress up front
        for cleaner motion.
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

        # Bool can't be null, so only PSBoundParameters.ContainsKey() says whether your script asked to toggle the mode.
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

    # Only what was passed goes across and is keyed by parameter name
    $change = @{}
    foreach ($key in 'Value', 'Increment', 'Label', 'Severity', 'Indeterminate') {
        if ($PSBoundParameters.ContainsKey($key)) { $change[$key] = $PSBoundParameters[$key] }
    }

    # Only -Variable passed? Don't bother the UI thread about it.
    if (!$change.Count) { return }

    if ($change.Contains('Severity')) { $change.BrushKey = Get-SeverityBrushKey -Severity $Severity -UseAccentDefault }

    $labelMissed = Invoke-OnUIThread -ArgumentList $progress, $change -ScriptBlock {
        param($progress, $change)

        if ($change.Contains('Value') -or $change.Contains('Increment')) {
            # Read $progress.Value here on the UI thread, so -Increment in a tight loop sees the latest committed value and not whatever was current when the call queued
            $newValue = if ($change.Contains('Value')) { $change.Value } else { $progress.Value }

            if ($change.Contains('Increment')) { $newValue += $change.Increment }

            # Clamp so your script doesn't have to think about it
            if ($newValue -lt $progress.Minimum) { $newValue = $progress.Minimum }
            if ($newValue -gt $progress.Maximum) { $newValue = $progress.Maximum }
            $progress.Value = $newValue
        }

        if ($change.Contains('Severity')) {
            # Clear local value so the resource binding wins
            $progress.ClearValue([System.Windows.Controls.Control]::ForegroundProperty)
            $progress.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, $change.BrushKey)
        }

        $meta = $progress.Tag
        if ($meta -is [hashtable]) {
            if ($change.Contains('Label')) {
                if ($meta.LabelBlock) { $meta.LabelBlock.Text = $change.Label }
                else { $true }
            }
            if ($change.Contains('Severity')) {
                $meta.Severity = $change.Severity
                $meta.BrushTag = $change.BrushKey
            }
        }

        # See .PARAMETER Indeterminate for the construction time caveat.
        if ($change.Contains('Indeterminate')) { $progress.IsIndeterminate = $change.Indeterminate }
    }

    if ($labelMissed) { Write-Verbose "Set-UiProgress: '$Variable' was created without -Label; skipping label update." }
    if ($change.Contains('Indeterminate')) { Write-Verbose "Set-UiProgress: toggled IsIndeterminate=$Indeterminate on '$Variable'." }
}
