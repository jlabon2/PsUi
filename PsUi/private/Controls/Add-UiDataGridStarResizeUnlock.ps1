function Add-UiDataGridStarResizeUnlock {
    <#
    .SYNOPSIS
        Keeps the rightmost star sized column resizable when the grid overflows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid
    )

    # WPF locks column resize once a Star column gets clamped to zero past the viewport, the remaining drag delta has nowhere to go.
    # ScrollChanged ties the star to its pixel width on overflow, PreviewMouseLeftButtonDown catches the mid drag transition, MouseUp restores the star on slack.

    # Attach once. A second call (grid built through New-StyledDataGrid, then attached again by the calling script) added duplicate Loaded closures and a second real Window.Closed hook per grid.
    if ($DataGrid.Resources.Contains('__StarResize_Attached')) { return }
    $DataGrid.Resources['__StarResize_Attached'] = $true

    # Fires once the template is applied. That's when DG_ScrollViewer resolves.
    # ScrollChanged reaches the grid via $gridRef, a plain closure local off $sender, since the handler runs as a delegate on the ScrollViewer.
    $DataGrid.Add_Loaded({
        param($sender, $eventArgs)
        if ($sender.Resources.Contains('__StarResize_ScrollViewer')) { return }

        $sv = $null
        if ($sender.Template) { $sv = $sender.Template.FindName('DG_ScrollViewer', $sender) }

        if (!$sv) {
            $stack = [System.Collections.Generic.Stack[object]]::new()
            $stack.Push($sender)
            while ($stack.Count -gt 0 -and !$sv) {
                $node  = $stack.Pop()
                $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($node)
                for ($i = 0; $i -lt $count; $i++) {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($node, $i)
                    if ($child -is [System.Windows.Controls.ScrollViewer]) { $sv = $child; break }
                    $stack.Push($child)
                }
            }
        }

        if (!$sv) {
            Write-Debug "ResizeUnlock: ScrollViewer not found - reactive arm disabled"
            return
        }

        $sender.Resources['__StarResize_ScrollViewer'] = $sv
        $gridRef = $sender

        $scrollChangedDelegate = [System.Windows.Controls.ScrollChangedEventHandler]{
            param($svSender, $svArgs)

            $isOverflow = [double]$svArgs.ExtentWidth -gt [double]$svArgs.ViewportWidth + 1

            if ($isOverflow) {
                # Overflow path: find a live star and pin it. Once pinned this branch does nothing on later fires (no star left to find).
                $starCol = $null
                foreach ($col in $gridRef.Columns) {
                    if ($col.Width.IsStar) { $starCol = $col; break }
                }
                if (!$starCol) { return }

                # Changing Width inline during ScrollChanged screws up WPF's layout state. The event fires in the middle of a layout pass and Width affects layout.
                # Defer to Background so it runs after layout settles.
                # PS's CheckActionPreference NREs on normal try block exit off pipeline. The IsStar check in the deferred action is the only way ahead needed.
                $colToPin = $starCol
                $grid     = $gridRef
                $extent   = [double]$svArgs.ExtentWidth
                $viewport = [double]$svArgs.ViewportWidth

                [void]$gridRef.Dispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::Background,
                    [Action]{
                        if ($colToPin.Width.IsStar) {
                            $pinned = [Math]::Max(0, [double]$colToPin.ActualWidth)
                            $colToPin.Width = [System.Windows.Controls.DataGridLength]::new(
                                $pinned, [System.Windows.Controls.DataGridLengthUnitType]::Pixel)
                            # Record the pinned column + width so the slack branch can restore the star later. A user drag changes the width and the marker gets dropped.
                            $grid.Resources['__StarResize_OriginalStar'] = @{ Col = $colToPin; PinnedWidth = $pinned }
                            Write-Debug "ResizeUnlock: deferred auto-pin to Pixel($pinned) on overflow (extent=$extent, viewport=$viewport)"
                        }
                    }.GetNewClosure())
            }
            else {
                # A pinned but untouched column gets restored to Star so the row fills the viewable area again.
                if (!$gridRef.Resources.Contains('__StarResize_OriginalStar')) { return }

                $entry  = $gridRef.Resources['__StarResize_OriginalStar']
                $col    = $entry.Col
                $width  = $col.Width

                if ($width.IsStar) {
                    # Something else already restored the star (mouseup). Clean up the marker.
                    $gridRef.Resources.Remove('__StarResize_OriginalStar')
                    return
                }

                # Pixel drift from PinnedWidth means the user resized it manually. Good for them.
                # Honour their width and stop watching.
                if (!$width.IsAbsolute -or [Math]::Abs([double]$width.Value - [double]$entry.PinnedWidth) -gt 1) {
                    $gridRef.Resources.Remove('__StarResize_OriginalStar')
                    return
                }

                # Safe to restore the star. Defer via Background like the pin path, changing Width inside ScrollChanged is the same dangerous reentry.
                $colToStar = $col
                $grid      = $gridRef
                [void]$gridRef.Dispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::Background,
                    [Action]{
                        if (!$colToStar.Width.IsStar) {
                            $colToStar.Width = [System.Windows.Controls.DataGridLength]::new(
                                1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
                            Write-Debug "ResizeUnlock: slack returned - re-stared previously-pinned column"
                        }
                        $grid.Resources.Remove('__StarResize_OriginalStar')
                    }.GetNewClosure())
            }
        }.GetNewClosure()

        $sv.add_ScrollChanged($scrollChangedDelegate)

        # Stash the ScrollViewer + delegate so Window.Closed can detach. ScrollChanged on an unrelated ScrollViewer would otherwise keep the grid rooted through the routed event multicast.
        $sender.Resources['__StarResize_State'] = @{
            ScrollViewer    = $sv
            ScrollDelegate  = $scrollChangedDelegate
        }
    })

    # Catches the case where a user resize is what pushes the grid into overflow. The reactive arm only fires once WPF has already rejected the drag.
    $downHandler = [System.Windows.Input.MouseButtonEventHandler]{
        param($sender, $eventArgs)

        $node = $eventArgs.OriginalSource
        if ($node -isnot [System.Windows.Controls.Primitives.Thumb]) { return }

        $header = $node
        while ($header -and $header -isnot [System.Windows.Controls.Primitives.DataGridColumnHeader]) {
            $header = [System.Windows.Media.VisualTreeHelper]::GetParent($header)
        }
        
        if (!$header) { return }

        Write-Debug "ResizeUnlock: MouseDown on header thumb for column '$($header.Column.Header)'"

        $starCol = $null
        foreach ($col in $sender.Columns) { if ($col.Width.IsStar) { $starCol = $col; break }  }
        if (!$starCol) {
            Write-Debug "ResizeUnlock: no star column at MouseDown (already pinned by reactive arm)"
            return
        }

        $pinned = [Math]::Max(0, [double]$starCol.ActualWidth)
        $sender.Resources['__StarResize_Gesture'] = @{
            StarColumn    = $starCol
            ResizedColumn = $header.Column
            PinnedWidth   = $pinned
        }

        $starCol.Width = [System.Windows.Controls.DataGridLength]::new( $pinned, [System.Windows.Controls.DataGridLengthUnitType]::Pixel)

        # Same marker the reactive arm writes. Without it, a gesture that never restores the star (click with no drag, resize that stays in overflow) left the ScrollChanged slack branch with nothing to restore and the pin would be permanent.
        $sender.Resources['__StarResize_OriginalStar'] = @{ Col = $starCol; PinnedWidth = $pinned }
        Write-Debug "ResizeUnlock: preempted star to Pixel($pinned) on resize gesture"
    }

    $upHandler = [System.Windows.Input.MouseButtonEventHandler]{
        param($sender, $eventArgs)

        if (!$sender.Resources.Contains('__StarResize_Gesture')) { return }
        $gesture = $sender.Resources['__StarResize_Gesture']
        $sender.Resources.Remove('__StarResize_Gesture')

        # Star column's own gripper. A real drag changed the width, so keep it and stop tracking. A bare click or doubleclick (no drag) left the width at the pin value. That pin was never a user choice, so put the star back.
        if ($gesture.ResizedColumn -eq $gesture.StarColumn) {
            $width = $gesture.StarColumn.Width
            $moved = !$width.IsAbsolute -or [Math]::Abs([double]$width.Value - [double]$gesture.PinnedWidth) -gt 1
            if (!$moved) {
                $gesture.StarColumn.Width = [System.Windows.Controls.DataGridLength]::new( 1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
                Write-Debug "ResizeUnlock: no-drag click on star gripper - restored star"
            }
            $sender.Resources.Remove('__StarResize_OriginalStar')
            return
        }

        $sumOthers = 0.0
        foreach ($col in $sender.Columns) {
            if ($col -eq $gesture.StarColumn) { continue }
            if ($col.Visibility -ne [System.Windows.Visibility]::Visible) { continue }
            $sumOthers += [double]$col.ActualWidth
        }

        $viewport = if ($sender.Resources.Contains('__StarResize_ScrollViewer')) { [double]$sender.Resources['__StarResize_ScrollViewer'].ViewportWidth  }
        else { [double]$sender.ActualWidth - 20 }

        if ($sumOthers -lt $viewport - 1) {
            $gesture.StarColumn.Width = [System.Windows.Controls.DataGridLength]::new(  1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
            $sender.Resources.Remove('__StarResize_OriginalStar')
            Write-Debug "ResizeUnlock: re-stared previous column on MouseUp (slack restored)"
        }
    }

    # Guard against double register on Loaded refires (tab virtualization etc.). Mirrors the ScrollViewer guard up top.
    if (!$DataGrid.Resources.Contains('__StarResize_Handlers')) {
        $DataGrid.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent, $downHandler, $true)
        $DataGrid.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonUpEvent,   $upHandler,   $true)
        $DataGrid.Resources['__StarResize_Handlers'] = $true
    }

    # Drop the down/up handlers and the ScrollChanged sub on Window.Closed so the grid doesn't stay rooted via the routed event registrations after teardown.
    # Window.Closed, not DataGrid.Unloaded, because tabs and expanders fire Unloaded on every show/hide and the gesture would lose its arm mid resize.
    $detachState = @{ Done = $false }
    $hookWindow = {
        if ($detachState.Done) { return }
        $window = [System.Windows.Window]::GetWindow($DataGrid)
        if (!$window) { return }
        # Rebind to locals... PS .GetNewClosure() only captures the imediate parent scope, so the inner Closed scriptblock needs the handler refs copied into this body.
        $grid      = $DataGrid
        $localDown = $downHandler
        $localUp   = $upHandler
        $window.Add_Closed({
            try { $grid.RemoveHandler([System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent, $localDown) } catch { Write-Debug "StarResize down detach: $_" }
            try { $grid.RemoveHandler([System.Windows.UIElement]::PreviewMouseLeftButtonUpEvent,   $localUp)   } catch { Write-Debug "StarResize up detach: $_" }
            if ($grid.Resources.Contains('__StarResize_State')) {
                $state = $grid.Resources['__StarResize_State']
                try { $state.ScrollViewer.remove_ScrollChanged($state.ScrollDelegate) }
                catch { Write-Debug "StarResize ScrollChanged detach: $_" }
            }
        }.GetNewClosure())
        $detachState.Done = $true
    }.GetNewClosure()

    # Initialized covers grids that get torn down without ever entering Loaded. Loaded is the normal path.
    # Whichever fires first wins via $detachState.Done.
    $DataGrid.Add_Initialized({ & $hookWindow }.GetNewClosure())
    $DataGrid.Add_Loaded({ & $hookWindow }.GetNewClosure())
}
