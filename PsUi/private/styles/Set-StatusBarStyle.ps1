function Set-StatusBarStyle {
    <#
    .SYNOPSIS
        Applies theme styling to a status bar control.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Border]$StatusBar
    )

    # Bind to dynamic theme resources so the bar repaints on theme switches
    $StatusBar.SetResourceReference(
        [System.Windows.Controls.Border]::BackgroundProperty, 'HeaderBackgroundBrush')
    $StatusBar.SetResourceReference(
        [System.Windows.Controls.Border]::BorderBrushProperty, 'BorderBrush')

    # Hairline top border, no other sides
    $StatusBar.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
    $StatusBar.Padding          = [System.Windows.Thickness]::new(8, 4, 8, 4)

    # Fixed height prevents content from shifting the bar up and down
    # 38px accommodates a standard 28px button with vertical centering
    $StatusBar.Height = 38
}
