function Set-UiFillParentHeight {
    <#
    .SYNOPSIS
        Gives a -Fill control its share of the window's leftover height.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Control,

        # DataGrid/Tree/List already stretch via their own templates and don't need this
        [System.Windows.Controls.Panel]$TrackParentWidth,

        [double]$MaxHeight = [double]::PositiveInfinity,

        # Minimum on the computed height. Prevents siblings above from pushing the control below a usable amount
        [double]$MinHeight = 50
    )

    $ctlRef    = $Control
    $parentRef = $TrackParentWidth
    $maxOuter  = $MaxHeight
    $minOuter  = $MinHeight

    # The page ScrollViewer measures at infinite height, so a virtualizing tree realizes every node on its first pass keeps them.
    # 2500 expanded nodes take 2.4s to first frame without this line and 0.7s with it.
    $Control.Height = 200

    $Control.Add_Loaded({
        param($sender, $eventArgs)

        # Recatpure vars since nested GetNewClosure doesnt capture closure inherited vars.
        $ctl = $ctlRef
        $pnt = $parentRef
        $max = $maxOuter
        $min = $minOuter

        # Width tracker (Grid only). The control's own margin comes off the parent's width or its right edge gets clipped.
        $widthHandler = $null
        if ($pnt) {
            $widthHandler = {
                param($sizeSender, $sizeArgs)
                $room = $sizeSender.ActualWidth - $ctl.Margin.Left - $ctl.Margin.Right
                if ($room -gt 50) { $ctl.Width = $room }
            }.GetNewClosure()
            $pnt.add_SizeChanged($widthHandler)
            $room = $pnt.ActualWidth - $ctl.Margin.Left - $ctl.Margin.Right
            if ($room -gt 50) { $ctl.Width = $room }
        }

        # Shrink so the natural content height doesn't push past the ScrollViewer, otherwise the math'll go in the neg
        $ctl.Height = 200

        # Walk out to the outter ScrollViewer, not the inner one. Its presenter and the window get picked up on the way.
        $sv        = $null
        $presenter = $null
        $window    = $null
        $lastSeen  = $null
        $walker    = [System.Windows.Media.VisualTreeHelper]::GetParent($ctl)
        while ($walker) {
            if ($walker -is [System.Windows.Controls.ScrollContentPresenter]) { $lastSeen = $walker }
            if ($walker -is [System.Windows.Controls.ScrollViewer]) { $sv = $walker; $presenter = $lastSeen }
            if ($walker -is [System.Windows.Window]) { $window = $walker; break }
            $walker = [System.Windows.Media.VisualTreeHelper]::GetParent($walker)
        }
        if (!$sv -or !$presenter) { return }

        $svLocal        = $sv
        $presenterLocal = $presenter
        $ctlLocal       = $ctl

        # Loaded can fire twice without Unloaded so old hooks come off first
        $group = $presenterLocal.Tag
        if ($group -is [hashtable] -and $group.FillMembers) {
            foreach ($old in @($group.FillMembers)) {
                if ([object]::ReferenceEquals($old.Control, $ctlLocal)) { & $old.Cleanup $false }
            }
            $group = $presenterLocal.Tag
        }

        # One group on the presenter's Tag for every -Fill control on the page because each one left to itsel takes whatever roomn is left
        if ($group -isnot [hashtable] -or !$group.ContainsKey('FillMembers')) {
            $group = @{ FillMembers = [System.Collections.Generic.List[object]]::new() }
            $group.Compute = {
                trap { Write-Debug "Set-UiFillParentHeight: $($_.Exception.Message)"; continue }

                # Window still sizing itself
                if ($window -and $window.SizeToContent -ne 'Manual') { return }

                # ScrollViewer.ViewportHeight and ExtentHeight don't catch up until LayoutUpdated, which runs after SizeChanged
                $vh = $presenterLocal.ViewportHeight
                if ($vh -le 0) { return }

                # Only the selected tab is in the tree
                $live = [System.Collections.Generic.List[object]]::new()
                foreach ($member in $group.FillMembers) {
                    $fill = $member.Control
                    if (!$fill.IsVisible -or !$presenterLocal.IsAncestorOf($fill)) { continue }
                    $top     = $fill.TranslatePoint([System.Windows.Point]::new(0, 0), $presenterLocal).Y + $presenterLocal.VerticalOffset
                    $current = [double]$fill.ActualHeight
                    $desired = $fill.DesiredSize.Height - $fill.Margin.Top - $fill.Margin.Bottom
                    $shown   = if ($desired -gt 0) { [Math]::Min($current, $desired) } else { $current }
                    $live.Add(@{ Member = $member; Top = $top; Current = $current; Shown = $shown; Nested = $false; Row = $null; AutoGrid = $null })
                }
                if (!$live.Count) { return }

                # Nested members don't get their own row so the parent gets the share and the child gets its own height
                if ($live.Count -gt 1) {
                    $liveControls = [System.Collections.Generic.HashSet[object]]::new()
                    foreach ($entry in $live) { [void]$liveControls.Add($entry.Member.Control) }
                    foreach ($entry in $live) {
                        $up = [System.Windows.Media.VisualTreeHelper]::GetParent($entry.Member.Control)
                        while ($up -and ![object]::ReferenceEquals($up, $presenterLocal)) {
                            if ($liveControls.Contains($up)) { $entry.Nested = $true; break }
                            $up = [System.Windows.Media.VisualTreeHelper]::GetParent($up)
                        }
                    }

                    # Members in Auto rows split their own grid's spare room
                    $autoGrids = [System.Collections.Generic.List[object]]::new()
                    foreach ($entry in $live) {
                        if (!$entry.Nested) { continue }
                        $grid = [System.Windows.Media.VisualTreeHelper]::GetParent($entry.Member.Control) -as [System.Windows.Controls.Grid]
                        if (!$grid -or !$grid.RowDefinitions.Count) { continue }
                        $index = [Math]::Min([System.Windows.Controls.Grid]::GetRow($entry.Member.Control), $grid.RowDefinitions.Count - 1)
                        if (!$grid.RowDefinitions[$index].Height.IsAuto) { continue }
                        $owner = $null
                        foreach ($known in $autoGrids) { if ([object]::ReferenceEquals($known.Grid, $grid)) { $owner = $known } }
                        if (!$owner) {
                            $owner = @{ Grid = $grid; Rows = @{}; Share = $null }
                            $autoGrids.Add($owner)
                        }
                        $owner.Rows[$index] = [Math]::Max([double]$owner.Rows[$index], $entry.Shown)
                        $entry.AutoGrid     = $owner
                    }
                }

                # Side by side members share one row
                $ordered = [System.Collections.Generic.List[object]]::new()
                foreach ($entry in $live) {
                    if ($entry.Nested) { continue }
                    $at = 0
                    while ($at -lt $ordered.Count -and $ordered[$at].Top -le $entry.Top) { $at++ }
                    $ordered.Insert($at, $entry)
                }
                $rows = [System.Collections.Generic.List[object]]::new()
                $row  = $null
                foreach ($entry in $ordered) {
                    $bottom = $entry.Top + $entry.Shown
                    if ($null -eq $row -or $entry.Top -ge $row.Bottom - 0.5) {
                        $row = @{ Top = $entry.Top; Bottom = $bottom; Height = 0.0; Min = 0.0; Max = 0.0; Share = 0.0 }
                        $rows.Add($row)
                    }
                    $entry.Row  = $row
                    $row.Bottom = [Math]::Max($row.Bottom, $bottom)
                    $row.Height = [Math]::Max($row.Height, $entry.Shown)
                    $row.Min    = [Math]::Max($row.Min, $entry.Member.Min)
                    $row.Max    = [Math]::Max($row.Max, $entry.Member.Max)
                }

                $total = 0.0
                foreach ($row in $rows) { $total += $row.Height }
                if ($live.Count -eq 1) { $total = $live[0].Current }
                $total = $total + $vh - $presenterLocal.ExtentHeight

                # Rows share one height unless a MinHeight or MaxHeight holds one back
                $level = $total / $rows.Count
                $held  = $false
                foreach ($row in $rows) { if ($level -lt $row.Min -or $level -gt $row.Max) { $held = $true } }

                if ($held -and $rows.Count -gt 1) {
                    $low  = 0.0
                    $high = [Math]::Max($total, 0.0)
                    while ($high - $low -gt 0.001) {
                        $level = ($low + $high) / 2
                        $sum   = 0.0
                        foreach ($row in $rows) { $sum += [Math]::Min([Math]::Max($level, $row.Min), $row.Max) }
                        if ($sum -lt $total) { $low = $level } else { $high = $level }
                    }

                    $free = 0
                    $left = $total
                    foreach ($row in $rows) {
                        $row.Share = if ($low -lt $row.Min) { $row.Min } elseif ($low -gt $row.Max) { $row.Max } else { $null }
                        if ($null -eq $row.Share) { $free++ } else { $left -= $row.Share }
                    }
                    foreach ($row in $rows) { if ($null -eq $row.Share) { $row.Share = $left / $free } }
                }
                elseif ($rows.Count -eq 1) { $rows[0].Share = $total }
                else { foreach ($row in $rows) { $row.Share = $level } }

                # Capped from its old top
                $shift = 0.0
                foreach ($row in $rows) {
                    $row.Top += $shift
                    $shift   += $row.Share - $row.Height
                }

                $source = [System.Windows.PresentationSource]::FromVisual($presenterLocal)
                $scale  = if ($source) { $source.CompositionTarget.TransformToDevice.M22 } else { 1.0 }

                # Nested members last so Auto rows split their grid's next Height
                $order = [System.Collections.Generic.List[object]]::new()
                foreach ($entry in $live) { if (!$entry.Nested) { $order.Add($entry) } }
                foreach ($entry in $live) { if ($entry.Nested) { $order.Add($entry) } }

                foreach ($entry in $order) {
                    $member  = $entry.Member
                    $current = $entry.Current
                    $top     = $entry.Top
                    if ($entry.AutoGrid) {
                        $owner = $entry.AutoGrid
                        if ($null -eq $owner.Share) {
                            $grid = $owner.Grid
                            $room = $grid.Height
                            if ([double]::IsNaN($room)) {
                                $room = [System.Windows.Controls.Primitives.LayoutInformation]::GetLayoutSlot($grid).Height - $grid.Margin.Top - $grid.Margin.Bottom
                            }
                            $sum = 0.0
                            foreach ($height in $owner.Rows.Values) { $sum += $height }
                            foreach ($definition in $grid.RowDefinitions) { $room -= $definition.ActualHeight }
                            $owner.Share = ($sum + $room) / $owner.Rows.Count
                        }
                        $target = $owner.Share
                        if (!$member.ParentHooked) { & $member.HookParent }
                    }
                    elseif ($entry.Nested) {
                        $slot   = [System.Windows.Controls.Primitives.LayoutInformation]::GetLayoutSlot($member.Control)
                        $target = $slot.Height - $member.Control.Margin.Top - $member.Control.Margin.Bottom
                        if (!$member.ParentHooked) { & $member.HookParent }
                    }
                    else {
                        $target = $entry.Row.Share
                        $top    = $entry.Row.Top

                        # Without this cap every resize adds the same spare room again
                        if ($target -gt $vh - $top) { $target = $vh - $top }
                    }

                    $target = [Math]::Floor($target * $scale) / $scale
                    if ($target -gt $member.Max) { $target = $member.Max }
                    if ($target -lt $member.Min) { $target = $member.Min }

                    Write-Debug "Set-UiFillParentHeight: vh=$vh extent=$($presenterLocal.ExtentHeight) top=$top max=$($member.Max) min=$($member.Min) target=$target current=$current members=$($live.Count)"
                    $member.FirstDone = $true
                    if ($target -le 0 -or [Math]::Abs($target - $current) -lt 0.01) { continue }
                    $member.Control.Height = $target
                }
            }.GetNewClosure()
            $presenterLocal.Tag = $group
        }

        $member = @{
            Control      = $ctlLocal
            Min          = $min
            Max          = $max
            FirstDone    = $false
            Cleanup      = $null
            HookParent   = $null
            ParentHooked = $false
            HookedParent = $null
        }
        $group.FillMembers.Add($member)
        $computeHeight = $group.Compute

        # Initial compute at Loaded priority. Checks after the current layout settles (~5ms), tight enough that the computed shrink doesn't give a jarring 'flash' kind of an effect
        [void]$ctlLocal.Dispatcher.BeginInvoke(  [System.Windows.Threading.DispatcherPriority]::Loaded, [Action]{ & $computeHeight }.GetNewClosure())

        # Crude but workable brute force retry timer for TabItem. Doesn't seem to always catch the right timing, so retry a few times until the first compute succeeds or 20 tries (~1 second) have elapsed, with 50ms inbetween. May need to be tweaked later on.
        $retryTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $retryTimer.Interval = [TimeSpan]::FromMilliseconds(50)
        $retryState = @{ Count = 0; Timer = $retryTimer }
        $retryTimer.Add_Tick({
            $retryState.Count++
            & $computeHeight
            if ($member.FirstDone -or $retryState.Count -ge 20) {
                $retryState.Timer.Stop()
            }
        }.GetNewClosure())
        $retryTimer.Start()

        # SizeChanged handler, held as a variable so the Unloaded cleanup can detach
        $svHandlerSb = {
            param($sizeSender, $sizeArgs)
            Write-Debug "Set-UiFillParentHeight: SV.SizeChanged fired (new H=$($sizeSender.ActualHeight))"
            & $computeHeight
        }.GetNewClosure()
        $svLocal.add_SizeChanged($svHandlerSb)

        # Second pass for nested members
        $parentHandlerSb   = { param($sizeSender, $sizeArgs) & $computeHeight }.GetNewClosure()
        $member.HookParent = {
            $member.ParentHooked = $true
            $hookParent = [System.Windows.Media.VisualTreeHelper]::GetParent($ctlLocal)
            if ($hookParent -isnot [System.Windows.FrameworkElement]) { return }
            $hookParent.add_SizeChanged($parentHandlerSb)
            $member.HookedParent = $hookParent
        }.GetNewClosure()

        # Window.SizeChanged shrinks when content is taller than viewport, ScrollViewer.ActualHeight stalls and its own SizeChanged event never seems to fire
        $windowSizeHandlerSb = $null
        if ($window) {
            $windowSizeHandlerSb = {
                param($wSender, $wArgs)
                Write-Debug "Set-UiFillParentHeight: Window.SizeChanged fired (new $($wArgs.NewSize.Width)x$($wArgs.NewSize.Height))"
                $compute = $computeHeight
                if ($compute) { & $compute }
            }.GetNewClosure()
            $window.add_SizeChanged($windowSizeHandlerSb)
        }

        # Window.StateChanged for max/restore btns
        $stateHandlerSb = $null
        if ($window) {
            $stateHandlerSb = {
                param($wSender, $wArgs)
                $compute = $computeHeight
                if (!$compute) { return }
                [void]$wSender.Dispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::Loaded,
                    [Action]{ if ($compute) { & $compute } }.GetNewClosure())
            }.GetNewClosure()
            $window.add_StateChanged($stateHandlerSb)
        }

        # Visibility moves every share
        $visibleHandlerSb = {
            param($visSender, $visArgs)
            $compute = $computeHeight
            [void]$visSender.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::Loaded,
                [Action]{ & $compute }.GetNewClosure())
        }.GetNewClosure()
        $ctlLocal.add_IsVisibleChanged($visibleHandlerSb)

        # A closing New-UiWindow shuts down its UI thread before Unloaded arrives so Closed runs the same cleanup.
        $hooks   = @{ Unloaded = $null; Closed = $null }
        $cleanup = {
            param([bool]$Resplit)
            trap { Write-Debug "Set-UiFillParentHeight cleanup: $($_.Exception.Message)"; continue }
            $retryState.Timer.Stop()
            $svLocal.remove_SizeChanged($svHandlerSb)
            $ctlLocal.remove_IsVisibleChanged($visibleHandlerSb)
            $ctlLocal.remove_Unloaded($hooks.Unloaded)
            if ($window) {
                $window.remove_SizeChanged($windowSizeHandlerSb)
                $window.remove_StateChanged($stateHandlerSb)
                $window.remove_Closed($hooks.Closed)
            }
            if ($pnt -and $widthHandler) { $pnt.remove_SizeChanged($widthHandler) }
            if ($member.HookedParent) { $member.HookedParent.remove_SizeChanged($parentHandlerSb) }

            [void]$group.FillMembers.Remove($member)
            if (!$group.FillMembers.Count) {
                if ([object]::ReferenceEquals($presenterLocal.Tag, $group)) { $presenterLocal.Tag = $null }
                return
            }
            if (!$Resplit) { return }
            $compute = $group.Compute
            [void]$presenterLocal.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::Loaded,
                [Action]{ & $compute }.GetNewClosure())
        }.GetNewClosure()
        $member.Cleanup = $cleanup

        $hooks.Unloaded = { param($unloadSender, $unloadArgs) & $cleanup $true }.GetNewClosure()
        $ctlLocal.add_Unloaded($hooks.Unloaded)
        if ($window) {
            $hooks.Closed = { param($closeSender, $closeArgs) & $cleanup $false }.GetNewClosure()
            $window.add_Closed($hooks.Closed)
        }
    }.GetNewClosure())
}
