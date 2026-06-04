function New-StatusBarBadge {
    <#
    .SYNOPSIS
        Creates a clickable pill badge for the status bar intercept feature.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Warning', 'Error', 'Info')]
        [string]$Severity
    )

    # Pick glyph, brush key, and display noun based on severity
    $glyph   = switch ($Severity) {
        'Warning' { [char]0xE7BA }
        'Error'   { [char]0xE783 }
        'Info'    { [char]0xE756 }
    }
    $brushKey = switch ($Severity) {
        'Warning' { 'WarningBrush' }
        'Error'   { 'ErrorBrush' }
        'Info'    { 'AccentBrush' }
    }
    $noun = switch ($Severity) {
        'Warning' { 'Warning' }
        'Error'   { 'Error' }
        'Info'    { 'Message' }
    }

    # Icon glyph - tagged so severity DFS skips it
    $glyphText = [System.Windows.Controls.TextBlock]@{
        Text              = $glyph
        FontFamily        = [PsUi.ModuleContext]::ActiveIconFontFamily
        FontSize          = 10
        VerticalAlignment = 'Center'
        Tag               = @{ IsBadgeText = $true }
    }

    # Count label - also tagged
    $countText = [System.Windows.Controls.TextBlock]@{
        Text              = '0'
        FontSize          = 11
        VerticalAlignment = 'Center'
        Margin            = [System.Windows.Thickness]::new(3, 0, 0, 0)
        Tag               = @{ IsBadgeText = $true }
    }

    # Horizontal stack inside the pill
    $inner = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Horizontal'
    }
    [void]$inner.Children.Add($glyphText)
    [void]$inner.Children.Add($countText)

    # All badges start visible but dimmed at zero count
    $initialVis     = 'Visible'
    $initialOpacity = 0.35

    # Pill border with a thin outline so it stands out on severity-tinted bars
    $pill = [System.Windows.Controls.Border]@{
        Height            = 20
        CornerRadius      = [System.Windows.CornerRadius]::new(3)
        Padding           = [System.Windows.Thickness]::new(5, 0, 5, 0)
        Margin            = [System.Windows.Thickness]::new(2, 0, 2, 0)
        BorderThickness   = [System.Windows.Thickness]::new(1)
        VerticalAlignment = 'Center'
        Cursor            = [System.Windows.Input.Cursors]::Hand
        Visibility        = $initialVis
        Opacity           = $initialOpacity
        Child             = $inner
        ToolTip           = "0 ${noun}s"
    }
    $pill.Tag = @{ IsBadgePill = $true; BrushKey = $brushKey }
    $pill.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $brushKey)
    $pill.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'BorderBrush')

    # Hover feedback: subtle opacity shift, but only when the badge is active
    $pill.Add_MouseEnter({
        if ($this.Opacity -gt 0.35) { $this.Opacity = 0.80 }
    })
    $pill.Add_MouseLeave({
        if ($this.Opacity -gt 0.35) { $this.Opacity = 1.0 }
    })

    # Contrast the text against the severity background
    $colors     = Get-ThemeColors
    $severityHx = switch ($Severity) {
        'Warning' { $colors.Warning }
        'Error'   { $colors.Error }
        'Info'    { $colors.Accent }
    }
    if ($severityHx) {
        $fgHex = Get-ContrastColor -HexColor $severityHx
        $brush = ConvertTo-UiBrush $fgHex
        $glyphText.Foreground = $brush
        $countText.Foreground = $brush
    }

    @{
        Badge     = $pill
        CountText = $countText
        GlyphText = $glyphText
        BrushKey  = $brushKey
        Noun      = $noun
    }
}
