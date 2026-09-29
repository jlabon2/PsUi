function New-UiDialogButton {
    <#
    .SYNOPSIS
        Defines one button for Show-UiMessageDialog -CustomButtons.
    .DESCRIPTION
        Builder for the -CustomButtons parameter. Buttons render left to right in call order, and
        the dialog returns the clicked button's -Value. Emits a definition object only - it does
        not show anything itself.

        Equivalent to a @{ Label; Value; IsDefault; IsAccent; IsCancel } hashtable, which
        -CustomButtons still accepts.
    .PARAMETER Label
        Button text.
    .PARAMETER Value
        What Show-UiMessageDialog returns when this button is clicked. Defaults to the label.
    .PARAMETER Default
        Enter activates this button.
    .PARAMETER Accent
        Accent styling for the button you want the eye drawn to.
    .PARAMETER Cancel
        Esc activates this button.
    .EXAMPLE
        $answer = Show-UiMessageDialog -Title 'Unsaved Changes' -Message 'Save changes?' -Icon Question -CustomButtons {
            New-UiDialogButton 'Save' -Accent -Default
            New-UiDialogButton 'Discard'
            New-UiDialogButton 'Cancel' -Cancel
        }
    .EXAMPLE
        # Legacy hashtable form, still supported
        Show-UiMessageDialog -Title 'Unsaved Changes' -Message 'Save changes?' -CustomButtons @(
            @{ Label = 'Save'; Value = 'Save'; IsAccent = $true; IsDefault = $true }
            @{ Label = 'Discard'; Value = 'Discard' }
            @{ Label = 'Cancel'; Value = 'Cancel'; IsCancel = $true }
        )
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Label,

        [Parameter(Position = 1)]
        [object]$Value,

        [switch]$Default,

        [switch]$Accent,

        [switch]$Cancel
    )

    # Value falls back to the label. A definition without Value makes the dialog return $null for that button, which nobody means.
    $button = @{ Label = $Label }
    $button['Value'] = if ($PSBoundParameters.ContainsKey('Value')) { $Value } else { $Label }
    if ($Default) { $button['IsDefault'] = $true }
    if ($Accent) { $button['IsAccent'] = $true }
    if ($Cancel) { $button['IsCancel'] = $true }
    $button
}
