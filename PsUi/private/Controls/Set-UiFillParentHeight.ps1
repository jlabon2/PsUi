function Set-UiFillParentHeight {
    <#
    .SYNOPSIS
        Sizes a control to claim the rest of the window's vertical space.
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

    $Control.Add_Loaded({
        param($sender, $eventArgs)

        # Recatpure vars since nested GetNewClosure doesnt capture closure inherited vars.
        $ctl = $ctlRef
        $pnt = $parentRef
        $max = $maxOuter
        $min = $minOuter

        # Width tracker (Grid only)
        $widthHandler = $null
        if ($pnt) {
            $widthHandler = {
                param($sizeSender, $sizeArgs)
                if ($sizeSender.ActualWidth -gt 50) { $ctl.Width = $sizeSender.ActualWidth }
            }.GetNewClosure()
            $pnt.add_SizeChanged($widthHandler)
            if ($pnt.ActualWidth -gt 50) { $ctl.Width = $pnt.ActualWidth }
        }

        # Shrink so the natural content height doesn't push past the ScrollViewer, otherwise the math'll go in the neg
        $ctl.Height = 200

        # Walk outwards to the outter ScrollViewer, not the inner
        $sv = $null
        $walker = [System.Windows.Media.VisualTreeHelper]::GetParent($ctl)
        while ($walker) {
            if ($walker -is [System.Windows.Controls.ScrollViewer]) { $sv = $walker }
            if ($walker -is [System.Windows.Window]) { break }
            $walker = [System.Windows.Media.VisualTreeHelper]::GetParent($walker)
        }
        if (!$sv) { return }

        $svLocal  = $sv
        $ctlLocal = $ctl
        $maxL     = $max
        $minL     = $min

        $siblingCache = @{ Items = $null; ChildCount = -1 }
        $computeState = @{ FirstDone = $false }

        $computeHeight = {
            if (!$ctlLocal -or !$svLocal) { return }
            if (!$ctlLocal.IsVisible) { return }

            $vh = $svLocal.ViewportHeight
            if ($vh -le 0) { return }

            $offset = 80.0
            try {
                $pt = $ctlLocal.TranslatePoint([System.Windows.Point]::new(0, 0), $svLocal)
                $offset = [double]$pt.Y
            }
            catch { Write-Debug 'Set-UiFillParentHeight: TranslatePoint failed' }

            # Cached sibling list. Recompute when parent.Children.Count changes.
            $parentPanel = $ctlLocal.Parent
            if ($parentPanel -is [System.Windows.Controls.Panel]) {
                
                $cnt = $parentPanel.Children.Count
                
                if ($siblingCache.ChildCount -ne $cnt) {
                    $sibs  = [System.Collections.Generic.List[object]]::new()
                    $myIdx = $parentPanel.Children.IndexOf($ctlLocal)
                    if ($myIdx -ge 0) {
                        for ($i = $myIdx + 1; $i -lt $cnt; $i++) {
                            [void]$sibs.Add($parentPanel.Children[$i])
                        }
                    }
                    $siblingCache.Items = $sibs
                    $siblingCache.ChildCount = $cnt
                }
            }

            $siblingsBelow = 0.0
            if ($siblingCache.Items) {
                foreach ($sib in $siblingCache.Items) {
                    $h = [double]$sib.ActualHeight
                    if ($h -le 0) { $h = [double]$sib.DesiredSize.Height }
                    if ($sib -is [System.Windows.FrameworkElement]) {
                        $h += [double]$sib.Margin.Top + [double]$sib.Margin.Bottom
                    }
                    $siblingsBelow += $h
                }
            }

            $target = $vh - $offset - $siblingsBelow - 10
            if ($target -gt $maxL) { $target = $maxL }
            if ($target -lt $minL) { $target = $minL }

            $current = [double]$ctlLocal.ActualHeight
            Write-Debug "Set-UiFillParentHeight: vh=$vh offset=$offset siblings=$siblingsBelow max=$maxL min=$minL target=$target current=$current"

            # 5px deadband prevents bounce - setting Height fires LayoutUpdated which can reenter via SizeChanged. First compute always applies regardless of deadband. The shrink height seed isn't a real measurement, and long headers above the grid can leave target coincidentally near it.
            $shouldApply = $target -gt 0 -and (!$computeState.FirstDone -or [double]::IsNaN($current) -or [Math]::Abs($target - $current) -gt 5)
            if ($shouldApply) {
                try {
                    $ctlLocal.Height = $target
                    $computeState.FirstDone = $true
                }
                catch { Write-Debug "Set-UiFillParentHeight: Height assign failed: $($_.Exception.Message)" }
            }
        }.GetNewClosure()

        # Initial compute at Loaded priority. Checks after the current layout settles (~5ms), tight enough that the computed shrink doesn't give a jarring 'flash' kind of an effect
        [void]$ctlLocal.Dispatcher.BeginInvoke(  [System.Windows.Threading.DispatcherPriority]::Loaded, [Action]{ & $computeHeight }.GetNewClosure())

        # Crude but workable brute force retry timer for TabItem. Doesn't seem to always catch the right timing, so retry a few times until the first compute succeeds or 20 tries (~1 second) have elapsed, with 50ms inbetween. May need to be tweaked later on.
        $retryTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $retryTimer.Interval = [TimeSpan]::FromMilliseconds(50)
        $retryState = @{ Count = 0; Timer = $retryTimer }
        $retryTimer.Add_Tick({
            $retryState.Count++
            & $computeHeight
            if ($computeState.FirstDone -or $retryState.Count -ge 20) {
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

        # Walk the visual tree to the window.
        $window = $null
        $walker = $ctlLocal
        while ($walker) {
            if ($walker -is [System.Windows.Window]) { $window = $walker; break }
            $walker = [System.Windows.Media.VisualTreeHelper]::GetParent($walker)
        }

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

        # Unloaded cleanup
        $unloadedHolder = @{ Sb = $null }
        $unloadedHolder.Sb = {
            param($s, $a)
            try { $svLocal.remove_SizeChanged($svHandlerSb) } catch {}
            if ($retryState.Timer)                 { try { $retryState.Timer.Stop() } catch {} }
            if ($window -and $stateHandlerSb)      { try { $window.remove_StateChanged($stateHandlerSb) } catch {} }
            if ($window -and $windowSizeHandlerSb) { try { $window.remove_SizeChanged($windowSizeHandlerSb) } catch {} }
            if ($pnt -and $widthHandler)           { try { $pnt.remove_SizeChanged($widthHandler) } catch {} }
            try { $ctlLocal.remove_Unloaded($unloadedHolder.Sb) } catch {}
        }.GetNewClosure()
        $ctlLocal.add_Unloaded($unloadedHolder.Sb)
    }.GetNewClosure())
}
