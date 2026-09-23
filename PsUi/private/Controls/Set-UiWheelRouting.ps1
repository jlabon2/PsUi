function Set-UiWheelRouting {
    <#
    .SYNOPSIS
        Sets the wheel routing for a control, and whether the page gets it back at the end of the scroll.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Control,

        [ValidateSet('Page', 'Edge', 'Capture')]
        [string]$Mode = 'Page'
    )

    # Edge and a Capture dropdown share this handler, which reads the mode off the sender.
    $handUp = {
        param($sender, $eventArgs)
        trap { Write-Debug "Wheel hand up on $($sender.GetType().Name): $_"; continue }
        if ($eventArgs.Handled) { return }

        # Once the dropdown is open it scrolls itself, whatever the mode.
        if ($sender -is [System.Windows.Controls.ComboBox] -and $sender.IsDropDownOpen) { return }

        # WPF only steps a ComboBox selection when the box holds keybord focus, so Capture moves it here instead.
        if ($sender -is [System.Windows.Controls.ComboBox] -and !$sender.Resources.Contains('__WheelEdge')) {
            $eventArgs.Handled = $true
            $step = if ($eventArgs.Delta -lt 0) { 1 } else { -1 }
            $next = $sender.SelectedIndex + $step
            if ($next -ge 0 -and $next -lt $sender.Items.Count) { $sender.SelectedIndex = $next }
            return
        }

        # Breadth first, so the template's own ScrollViewer turns up before any inside an item, and zero children means the template hasn't been applied yet
        $scrollViewer = $null
        $queue        = [System.Collections.Generic.Queue[System.Windows.DependencyObject]]::new()
        $queue.Enqueue($sender)
        while ($queue.Count -gt 0 -and !$scrollViewer) {
            $node       = $queue.Dequeue()
            $childCount = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($node)
            for ($i = 0; $i -lt $childCount; $i++) {
                $child = [System.Windows.Media.VisualTreeHelper]::GetChild($node, $i)
                if ($child -is [System.Windows.Controls.ScrollViewer]) { $scrollViewer = $child; break }
                $queue.Enqueue($child)
            }
        }

        $passUp = $null -eq $scrollViewer
        if ($scrollViewer) {
            $atTop    = $scrollViewer.VerticalOffset -le 0
            $atBottom = $scrollViewer.VerticalOffset -ge ($scrollViewer.ScrollableHeight - 0.5)
            $passUp   = ($eventArgs.Delta -gt 0 -and $atTop) -or ($eventArgs.Delta -lt 0 -and $atBottom)
        }
        if (!$passUp) { return }

        $eventArgs.Handled    = $true
        $newEvent             = [System.Windows.Input.MouseWheelEventArgs]::new($eventArgs.MouseDevice, $eventArgs.Timestamp, $eventArgs.Delta)
        $newEvent.RoutedEvent = [System.Windows.UIElement]::MouseWheelEvent
        $newEvent.Source      = $sender

        # WPF marks the wheel handled on a ScrollViewer even at its end, so the climb skips any ancestor already there and takes the nearest one that can still move.
        $target = $null
        $climb  = [System.Windows.Media.VisualTreeHelper]::GetParent($sender)
        while ($climb) {
            if ($climb -is [System.Windows.Controls.ScrollViewer]) {
                $canMove = if ($eventArgs.Delta -lt 0) {
                    $climb.VerticalOffset -lt ($climb.ScrollableHeight - 0.5)
                }
                else { $climb.VerticalOffset -gt 0 }
                if ($canMove) { $target = $climb; break }
            }
            $climb = [System.Windows.Media.VisualTreeHelper]::GetParent($climb)
        }
        if (!$target) { $target = $sender.Parent -as [System.Windows.UIElement] }
        if (!$target) { $target = [System.Windows.Media.VisualTreeHelper]::GetParent($sender) -as [System.Windows.UIElement] }
        if ($target) { $target.RaiseEvent($newEvent) }
    }

    # New-UiTab walks up from the hit element and stands down when it finds __WheelCapture.
    if ($Mode -eq 'Capture') {
        if ($Control -is [System.Windows.Controls.ComboBox] -and !$Control.Resources.Contains('__WheelCapture')) {
            $Control.Add_PreviewMouseWheel($handUp)
        }
        $Control.Resources['__WheelCapture'] = $true
        return
    }

    # The style function runs again on every theme switch, and once a control keeps the wheel a later Page or Edge call leaves it alone.
    if ($Control.Resources.Contains('__WheelCapture')) { return }

    if ($Mode -eq 'Edge') {
        $Control.Resources['__WheelCapture'] = $true
        $Control.Resources['__WheelEdge']    = $true
        $Control.Add_PreviewMouseWheel($handUp)
        return
    }

    if ($Control.Resources.Contains('__WheelPassthrough')) { return }
    $Control.Resources['__WheelPassthrough'] = $true

    $Control.Add_PreviewMouseWheel({
        param($sender, $eventArgs)
        trap { Write-Debug "Wheel routing on $($sender.GetType().Name): $_"; continue }
        if ($eventArgs.Handled) { return }

        # Capture or Edge applied later can't detach this handler, so it checks the flag and gets out of the way.
        if ($sender.Resources.Contains('__WheelCapture')) { return }

        if ($sender -is [System.Windows.Controls.ComboBox] -and $sender.IsDropDownOpen) { return }

        $eventArgs.Handled    = $true
        $newEvent             = [System.Windows.Input.MouseWheelEventArgs]::new($eventArgs.MouseDevice, $eventArgs.Timestamp, $eventArgs.Delta)
        $newEvent.RoutedEvent = [System.Windows.UIElement]::MouseWheelEvent
        $newEvent.Source      = $sender

        # Parent reads null for a control that only exists inside a template, so fall back to the visual one.
        $target = $sender.Parent -as [System.Windows.UIElement]
        if (!$target) { $target = [System.Windows.Media.VisualTreeHelper]::GetParent($sender) -as [System.Windows.UIElement] }
        if ($target) { $target.RaiseEvent($newEvent) }
    })
}
