function Set-StatusBarSeverityVisual {
    <#
    .SYNOPSIS
        Tints the bar background to the severity colour, contrasts text, and
        shows a severity indicator glyph (checkmark, warning, error).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Border]$Bar,

        [Parameter(Mandatory)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Severity,

        [hashtable]$Colors
    )

    if (!$Colors) { $Colors = Get-ThemeColors }

    $bgKey = Get-SeverityBrushKey -Severity $Severity
    $Bar.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $bgKey)

    $meta       = if ($Bar.Tag -is [hashtable]) { $Bar.Tag } else { @{} }
    $innerPanel = if ($meta.InnerPanel) { $meta.InnerPanel } else { $Bar.Child }
    if (!$innerPanel) { return }

    # DFS for every TextBlock inside the bar, skipping badge pill text
    $textBlocks = [System.Collections.Generic.List[System.Windows.Controls.TextBlock]]::new()
    $stack      = [System.Collections.Generic.Stack[object]]::new()
    if (!($innerPanel -is [System.Windows.Controls.Panel])) { return }
    $stack.Push($innerPanel)
    while ($stack.Count -gt 0) {
        $node = $stack.Pop()
        foreach ($child in $node.Children) {
            if ($child -is [System.Windows.Controls.TextBlock]) {
                $isBadge = $child.Tag -is [hashtable] -and $child.Tag['IsBadgeText']
                if (!$isBadge) { $textBlocks.Add($child) }
            }
            if ($child -is [System.Windows.Controls.Panel]) { $stack.Push($child) }
        }
    }

    if ($Severity -eq 'Info') {
        # Hand each block back to the theme system so tag-based colours come back
        foreach ($textBlock in $textBlocks) {
            Update-SingleControlTheme -Control $textBlock -Colors $colors
        }

        # Collapse the severity indicator glyph
        if ($meta.SeverityIcon) {
            $meta.SeverityIcon.Visibility = [System.Windows.Visibility]::Collapsed
        }
        return
    }

    # Non-Info: compute a contrasting text colour from the severity background
    $severityHex = switch ($Severity) {
        'Success' { $colors.Success }
        'Warning' { $colors.Warning }
        'Error'   { $colors.Error }
        default   { $colors.HeaderBackground }
    }
    $textHex   = if ($severityHex) { Get-ContrastColor -HexColor $severityHex } else { $colors.ControlFg }
    $textBrush = ConvertTo-UiBrush $textHex

    foreach ($textBlock in $textBlocks) {
        $textBlock.Foreground = $textBrush
    }

    # Show the severity indicator glyph
    if ($meta.SeverityIcon) {
        $meta.SeverityIcon.Text = switch ($Severity) {
            'Success' { [char]0xE73E }
            'Warning' { [char]0xE7BA }
            'Error'   { [char]0xE783 }
        }
        $meta.SeverityIcon.Visibility = [System.Windows.Visibility]::Visible
    }
}
