function Set-StatusBarChildLayout {
    <#
    .SYNOPSIS
        Walks a status bar's inner panel and applies compact, inline-friendly
        layout to its children so controls fit the bar's 38px height without
        showing focus rectangles or vertical stack labels.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Panel]$Panel
    )

    foreach ($child in @($Panel.Children)) {
        if (!($child -is [System.Windows.FrameworkElement])) { continue }

        # Universal: center vertically in the bar, kill the dotted focus rectangle
        # that looks like a square smear when controls get keyboard focus.
        $child.VerticalAlignment = 'Center'
        $child.FocusVisualStyle  = $null

        # Form controls (New-UiInput, New-UiSlider, New-UiDropdown, New-UiDatePicker,
        # New-UiTimePicker, New-UiTextArea, New-UiRadioGroup, New-UiCredential) tag
        # their wrapper with FormControl=$true plus Label/Control refs. The wrapper
        # is a vertical stack whose first child is the label row - collapse that whole
        # row (not just the inner Label TextBlock) so it doesn't reserve layout space.
        if ($child.Tag -is [hashtable] -and $child.Tag['FormControl'] -and $child.Tag['Control']) {
            if ($child.Children.Count -gt 0) {
                $child.Children[0].Visibility = [System.Windows.Visibility]::Collapsed
            }
            $child.HorizontalAlignment = 'Left'
            $child.VerticalAlignment   = 'Center'
            $child.Margin              = [System.Windows.Thickness]::new(2, 0, 2, 0)

            # Apply compact sizing to the actual input control inside the composite
            Set-StatusBarChildCompact -Control $child.Tag['Control']
            continue
        }

        # Plain panels: recurse so any nested controls also get normalized
        if ($child -is [System.Windows.Controls.Panel]) {
            Set-StatusBarChildLayout -Panel $child
            continue
        }

        # Direct top-level controls get the same compact treatment
        Set-StatusBarChildCompact -Control $child
    }
}
