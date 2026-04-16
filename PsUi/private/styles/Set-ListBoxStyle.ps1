function Set-ListBoxStyle {
    <#
    .SYNOPSIS
        Applies theme styling to a ListBox control.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListBox]$ListBox
    )

    # Try to apply XAML style
    $styleApplied = $false
    try {
        if ($null -ne [System.Windows.Application]::Current) {
            $style = [System.Windows.Application]::Current.TryFindResource('ModernListBoxStyle')
            if ($null -ne $style) {
                $ListBox.Style = $style
                $styleApplied = $true
            }
        }
    }
    catch {
        Write-Verbose "Failed to apply ModernListBoxStyle from resources: $_"
    }

    # Warn if XAML style not found (indicates ThemeEngine initialization issue)
    if (!$styleApplied) {
        Write-Warning "XAML style 'ModernListBoxStyle' not found. Ensure ThemeEngine.LoadStyles() was called."
    }

    # Prevent ListBox from "stealing" scroll events when mouse hovers over it
    # Bubble unhandled scroll to parent ScrollViewer
    $ListBox.AddHandler(
        [System.Windows.UIElement]::PreviewMouseWheelEvent,
        [System.Windows.Input.MouseWheelEventHandler]{
            param($sender, $eventArgs)

            # Only bubble if we can't scroll in the direction the user wants
            $scrollViewer = $null
            $child = [System.Windows.Media.VisualTreeHelper]::GetChild($sender, 0)
            if ($child -is [System.Windows.Controls.Border]) {
                $scrollViewer = [System.Windows.Media.VisualTreeHelper]::GetChild($child, 0)
            }

            $shouldBubble = $false
            if ($null -eq $scrollViewer -or $scrollViewer -isnot [System.Windows.Controls.ScrollViewer]) {
                $shouldBubble = $true
            }
            else {
                # Bubble scroll events when we hit the top or bottom
                $atTop    = $scrollViewer.VerticalOffset -le 0
                $atBottom = $scrollViewer.VerticalOffset -ge ($scrollViewer.ScrollableHeight - 0.5)

                if ($eventArgs.Delta -gt 0 -and $atTop) { $shouldBubble = $true }
                if ($eventArgs.Delta -lt 0 -and $atBottom) { $shouldBubble = $true }
            }

            if ($shouldBubble) {
                $eventArgs.Handled = $true
                $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($sender)
                while ($null -ne $parent) {
                    if ($parent -is [System.Windows.UIElement]) {
                        $newEvent = [System.Windows.Input.MouseWheelEventArgs]::new($eventArgs.MouseDevice, $eventArgs.Timestamp, $eventArgs.Delta)
                        $newEvent.RoutedEvent = [System.Windows.UIElement]::MouseWheelEvent
                        $parent.RaiseEvent($newEvent)
                        break
                    }
                    $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($parent)
                }
            }
        }
    )

    try {
        [PsUi.ThemeEngine]::RegisterElement($ListBox)
    }
    catch {
        Write-Verbose "Failed to register ListBox with ThemeEngine: $_"
    }
}