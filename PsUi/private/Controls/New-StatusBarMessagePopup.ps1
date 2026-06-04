function New-StatusBarMessagePopup {
    <#
    .SYNOPSIS
        Creates a themed popup for displaying accumulated warning or error messages.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Warning', 'Error', 'Info')]
        [string]$Severity,

        [Parameter(Mandatory)]
        [System.Windows.UIElement]$PlacementTarget,

        [hashtable]$BadgeInfo,

        [System.Collections.Generic.List[hashtable]]$MessageList,

        [System.Windows.Controls.Border]$Bar
    )

    $colors = Get-ThemeColors

    # Header label colored by severity
    $headerBrushKey = switch ($Severity) {
        'Warning' { 'WarningBrush' }
        'Error'   { 'ErrorBrush' }
        'Info'    { 'AccentBrush' }
    }
    $noun = if ($BadgeInfo -and $BadgeInfo.Noun) { $BadgeInfo.Noun } else { $Severity }
    $headerText = [System.Windows.Controls.TextBlock]@{
        Text              = "0 ${noun}s"
        FontWeight        = 'SemiBold'
        FontSize          = 13
        VerticalAlignment = 'Center'
        Margin            = [System.Windows.Thickness]::new(8, 6, 8, 6)
    }
    $headerText.SetResourceReference(
        [System.Windows.Controls.TextBlock]::ForegroundProperty, $headerBrushKey)

    # Clear button
    $clearButton = [System.Windows.Controls.Button]@{
        Content           = 'Clear'
        FontSize          = 11
        Padding           = [System.Windows.Thickness]::new(8, 2, 8, 2)
        Margin            = [System.Windows.Thickness]::new(0, 4, 6, 4)
        VerticalAlignment = 'Center'
        Cursor            = [System.Windows.Input.Cursors]::Hand
    }
    try { Set-ButtonStyle -Button $clearButton } catch { Write-Debug "Popup clear button styling failed: $_" }
    $clearButton.Height          = 22
    $clearButton.FocusVisualStyle = $null

    # Copy button - dumps accumulated messages to the clipboard
    $copyButton = [System.Windows.Controls.Button]@{
        Content           = 'Copy'
        FontSize          = 11
        Padding           = [System.Windows.Thickness]::new(8, 2, 8, 2)
        Margin            = [System.Windows.Thickness]::new(0, 4, 2, 4)
        VerticalAlignment = 'Center'
        Cursor            = [System.Windows.Input.Cursors]::Hand
    }
    try { Set-ButtonStyle -Button $copyButton } catch { Write-Debug "Popup copy button styling failed: $_" }
    $copyButton.Height          = 22
    $copyButton.FocusVisualStyle = $null

    # Close button (X glyph, inherits foreground from themed button style)
    $closeGlyph = [System.Windows.Controls.TextBlock]@{
        Text                = [char]0xE711
        FontFamily          = [PsUi.ModuleContext]::ActiveIconFontFamily
        FontSize            = 10
        VerticalAlignment   = 'Center'
        HorizontalAlignment = 'Center'
    }
    $closeButton = [System.Windows.Controls.Button]@{
        Content           = $closeGlyph
        Width             = 22
        Height            = 22
        Padding           = [System.Windows.Thickness]::new(0)
        Margin            = [System.Windows.Thickness]::new(0, 4, 4, 4)
        VerticalAlignment = 'Center'
        Cursor            = [System.Windows.Input.Cursors]::Hand
    }
    try { Set-ButtonStyle -Button $closeButton } catch { Write-Debug "Popup close button styling failed: $_" }
    $closeButton.FocusVisualStyle = $null

    # Header row: right-docked buttons in DockPanel insertion order (rightmost first)
    $headerRow = [System.Windows.Controls.DockPanel]::new()
    [System.Windows.Controls.DockPanel]::SetDock($closeButton, 'Right')
    [void]$headerRow.Children.Add($closeButton)
    [System.Windows.Controls.DockPanel]::SetDock($clearButton, 'Right')
    [void]$headerRow.Children.Add($clearButton)
    [System.Windows.Controls.DockPanel]::SetDock($copyButton, 'Right')
    [void]$headerRow.Children.Add($copyButton)
    [void]$headerRow.Children.Add($headerText)

    # Separator
    $separator = [System.Windows.Controls.Separator]@{
        Margin = [System.Windows.Thickness]::new(4, 0, 4, 0)
    }

    # Message panel inside a scroll viewer
    $messagePanel = [System.Windows.Controls.StackPanel]@{
        Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
    }
    $scrollViewer = [System.Windows.Controls.ScrollViewer]@{
        VerticalScrollBarVisibility = 'Auto'
        Content                     = $messagePanel
    }

    # Main container
    $mainPanel = [System.Windows.Controls.DockPanel]::new()
    [System.Windows.Controls.DockPanel]::SetDock($headerRow, 'Top')
    [System.Windows.Controls.DockPanel]::SetDock($separator, 'Top')
    [void]$mainPanel.Children.Add($headerRow)
    [void]$mainPanel.Children.Add($separator)
    [void]$mainPanel.Children.Add($scrollViewer)

    # Shadow effect
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]@{
        BlurRadius  = 10
        ShadowDepth = 2
        Opacity     = 0.25
        Color       = [System.Windows.Media.Colors]::Black
    }

    # Outer border with themed colors
    $outerBorder = [System.Windows.Controls.Border]@{
        MinWidth     = 280
        MaxWidth     = 450
        MaxHeight    = 320
        CornerRadius = [System.Windows.CornerRadius]::new(4)
        BorderThickness = [System.Windows.Thickness]::new(1)
        Padding      = [System.Windows.Thickness]::new(0)
        Effect       = $shadow
        Child        = $mainPanel
    }
    $outerBorder.SetResourceReference(
        [System.Windows.Controls.Border]::BackgroundProperty, 'ControlBackgroundBrush')
    $outerBorder.SetResourceReference(
        [System.Windows.Controls.Border]::BorderBrushProperty, 'BorderBrush')

    # Inherited foreground for all child TextBlocks - tracks the active theme
    # so popup entries pick up the correct color without needing explicit brushes
    $outerBorder.SetResourceReference(
        [System.Windows.Documents.TextElement]::ForegroundProperty, 'ControlForegroundBrush')

    # Popup
    $popup = [System.Windows.Controls.Primitives.Popup]@{
        PlacementTarget    = $PlacementTarget
        Placement          = 'Top'
        StaysOpen          = $false
        AllowsTransparency = $true
        Child              = $outerBorder
    }

    # Wire Clear button to reset badge and close popup
    $capturedBadge   = $BadgeInfo
    $capturedMsgList = $MessageList
    $capturedPanel   = $messagePanel
    $capturedHeader  = $headerText
    $capturedPopup   = $popup
    $capturedBar     = $Bar
    $capturedNoun     = $noun

    $clearButton.Add_Click({
        $capturedMsgList.Clear()
        $capturedPanel.Children.Clear()
        $capturedHeader.Text = "0 ${capturedNoun}s"
        if ($capturedBadge) {
            $capturedBadge.CountText.Text = '0'
            $capturedBadge.Badge.ToolTip  = "0 ${capturedNoun}s"

            $capturedBadge.Badge.Opacity = 0.35
        }
        $capturedPopup.IsOpen = $false
    }.GetNewClosure())

    # Copy button formats messages and pushes to clipboard with visual feedback
    $capturedCopyBtn = $copyButton
    $copyButton.Add_Click({
        if ($capturedMsgList.Count -eq 0) { return }
        $lines = [System.Text.StringBuilder]::new()
        foreach ($msg in $capturedMsgList) {
            $ts = $msg.Time.ToString('HH:mm:ss')
            [void]$lines.AppendLine("[$ts] $($msg.Message)")
            if ($msg.Detail) { [void]$lines.AppendLine("  $($msg.Detail)") }
            if ($msg.Code)   { [void]$lines.AppendLine("  > $($msg.Code)") }
            if ($msg.Stack)  { [void]$lines.AppendLine("  $($msg.Stack)") }
            if ($msg.Target) { [void]$lines.AppendLine("  Target: $($msg.Target)") }
            if ($msg.Inner)  { [void]$lines.AppendLine("  Inner: $($msg.Inner)") }
        }
        try { [System.Windows.Clipboard]::SetText($lines.ToString().TrimEnd()) }
        catch { Write-Debug "Clipboard copy failed: $_"; return }

        # Flash "Copied!" then revert after 1.5s (fetch colors fresh for theme accuracy)
        $capturedCopyBtn.Content = 'Copied!'
        $originalBg   = $capturedCopyBtn.Background
        $currentColors = Get-ThemeColors
        try { $capturedCopyBtn.Background = ConvertTo-UiBrush $currentColors.Accent }
        catch { Write-Debug "Copy feedback accent failed: $_" }

        $timer          = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(1500)
        $timer.Tag      = @{ Btn = $capturedCopyBtn; Bg = $originalBg }
        $timer.Add_Tick({
            $this.Tag.Btn.Background = $this.Tag.Bg
            $this.Tag.Btn.Content    = 'Copy'
            $this.Stop()
        })
        $timer.Start()
    }.GetNewClosure())

    # Close button just dismisses the popup
    $closeButton.Add_Click({
        $capturedPopup.IsOpen = $false
    }.GetNewClosure())

    @{
        Popup        = $popup
        MessagePanel = $messagePanel
        HeaderText   = $headerText
        ClearButton  = $clearButton
    }
}
