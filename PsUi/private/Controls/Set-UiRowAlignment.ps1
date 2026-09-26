function Set-UiRowAlignment {
    <#
    .SYNOPSIS
        Lines the rest of a row up with the labeled boxes in it after every resize.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Panel]$Panel
    )

    # Only grids and horizontal panels put controls side by side
    $horizontal = [System.Windows.Controls.Orientation]::Horizontal
    $holdsRows  = $Panel -is [System.Windows.Controls.Grid] -or
        ($Panel -is [System.Windows.Controls.StackPanel] -and $Panel.Orientation -eq $horizontal) -or
        ($Panel -is [System.Windows.Controls.WrapPanel] -and $Panel.Orientation -eq $horizontal)
    if (!$holdsRows -or $Panel.Resources.Contains('__PsUiRowAlignment')) { return }

    # Button bars wait for something labeled to attach them on load
    $hasLabeled = $false
    foreach ($child in $Panel.Children) {
        $tag   = if ($child -is [System.Windows.FrameworkElement]) { $child.Tag } else { $null }
        $isRow = $child -is [System.Windows.Controls.Panel] -and $child -isnot [System.Windows.Controls.Grid] -and
            $child.Resources.Contains('__PsUiRowAlignment')
        if ($isRow -or ($tag -is [hashtable] -and $tag.FormControl -and $tag.Control)) {
            $hasLabeled = $true
            break
        }
    }
    if (!$hasLabeled) { return }
    $Panel.Resources['__PsUiRowAlignment'] = $true

    # Responsive windows only line up their content panel when something on it asks
    if ($Panel -isnot [System.Windows.Controls.Grid]) {
        $alignRows    = ${function:Set-UiRowAlignment}
        $hook         = @{}
        $hook.Handler = [System.Windows.RoutedEventHandler]{
            param($sender, $loadedArgs)
            trap { Write-Debug "Set-UiRowAlignment parent hook: $_"; continue }
            $sender.Remove_Loaded($hook.Handler)
            if ($sender.Parent -is [System.Windows.Controls.Panel]) { & $alignRows -Panel $sender.Parent }
        }.GetNewClosure()
        $Panel.Add_Loaded($hook.Handler)
    }

    $state = @{
        Panel    = $Panel
        Original = [System.Collections.Generic.Dictionary[object, object]]::new()
        Hooked   = [System.Collections.Generic.HashSet[object]]::new()
        Watched  = [System.Collections.Generic.HashSet[object]]::new()
        Shifts   = [System.Collections.Generic.Dictionary[object, object]]::new()
        Pending  = $false
    }

    # Local values of everything moved, for when its row stops mixing
    $state.Remember = {
        param($element)
        if ($state.Original.ContainsKey($element)) { return }
        $state.Original[$element] = @{
            VA     = $element.ReadLocalValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty)
            Margin = $element.ReadLocalValue([System.Windows.FrameworkElement]::MarginProperty)
            Shift  = $element.ReadLocalValue([System.Windows.UIElement]::RenderTransformProperty)
            Top    = $element.Margin.Top
        }
    }.GetNewClosure()

    # The nested row's first labeled control stands in for it
    $state.Inner = {
        param($row)
        foreach ($inner in $row.Children) {
            if ($inner -isnot [System.Windows.FrameworkElement] -or $inner.Visibility -ne 'Visible') { continue }
            $tag = $inner.Tag
            if ($tag -is [hashtable] -and $tag.FormControl -and $tag.Control) { return $inner }
        }
    }

    $state.Pass = {
        param([bool]$fromResize)
        trap { Write-Debug "Set-UiRowAlignment: $_"; continue }
        $panel    = $state.Panel
        $origin   = [System.Windows.Point]::new(0, 0)
        $isGrid   = $panel -is [System.Windows.Controls.Grid]
        $vaProp   = [System.Windows.FrameworkElement]::VerticalAlignmentProperty
        $marginDp = [System.Windows.FrameworkElement]::MarginProperty
        $shiftDp  = [System.Windows.UIElement]::RenderTransformProperty
        $unset    = [System.Windows.DependencyProperty]::UnsetValue
        $keep     = [System.Collections.Generic.HashSet[object]]::new()
        $sources  = [System.Collections.Generic.Dictionary[object, object]]::new()

        # [ordered] would read int keys as positions
        $rows    = [System.Collections.Generic.Dictionary[int, object]]::new()
        $inputs  = [System.Text.StringBuilder]::new()
        $stale   = $false
        $lastKey = $null
        $line    = 0
        foreach ($child in $panel.Children) {
            if ($child -isnot [System.Windows.FrameworkElement]) { continue }

            # Collapsing a child reshapes its row, and a panel with a set height never changes size to say so
            if ($state.Watched.Add($child)) { $child.Add_IsVisibleChanged($state.OnChildSize) }
            if ($child.Visibility -ne 'Visible') { continue }
            if (!$child.IsMeasureValid -or !$child.IsArrangeValid) { $stale = $true }

            $slot = [System.Windows.Controls.Primitives.LayoutInformation]::GetLayoutSlot($child)
            $key  = if ($isGrid) { [System.Windows.Controls.Grid]::GetRow($child) }
            else { [int][Math]::Round($slot.Y) }
            if (!$rows.ContainsKey($key)) {
                $rows[$key] = [System.Collections.Generic.List[object]]::new()
            }
            $rows[$key].Add($child)

            # Line numbers, not Y, since a push moves every line under it
            if ($key -ne $lastKey) {
                $line++
                $lastKey = $key
            }

            $source = $child
            $isRow  = $child -is [System.Windows.Controls.Panel] -and $child -isnot [System.Windows.Controls.Grid] -and
                $child.Resources.Contains('__PsUiRowAlignment')
            if ($isRow) { $source = & $state.Inner $child }
            $tag     = if ($source) { $source.Tag } else { $null }
            $caption = 0
            if ($tag -is [hashtable] -and $tag.FormControl -and $tag.Control) {
                $sources[$child] = $source
                if ($tag.Label) { $caption = [int]$tag.Label.ActualHeight }
            }
            $margin  = $child.Margin
            $ownSize = [int]($child.DesiredSize.Height - $margin.Top - $margin.Bottom)
            [void]$inputs.Append($line).Append(',').Append([int]$slot.X).Append(',')
            [void]$inputs.Append($ownSize).Append(',').Append($caption).Append(';')

            # Nested rows and placed controls stay but still shift inside the row.
            if ($sources.ContainsKey($child) -and ($isRow -or $child.Resources.Contains('__PsUiPlacedByUser'))) {
                [void]$inputs.Append([int]$source.TranslatePoint($origin, $panel).Y).Append(';')
            }
        }

        # Widths another SizeChanged handler just set haven't laid out yet
        if ($fromResize -and $stale) { return }

        $seen = $inputs.ToString()
        if ($seen -eq $state.Seen) { return }
        $state.Seen = $seen

        foreach ($members in $rows.Values) {
            $labeled  = [System.Collections.Generic.List[object]]::new()
            $siblings = [System.Collections.Generic.List[object]]::new()
            foreach ($child in $members) {
                $source  = if ($sources.ContainsKey($child)) { $sources[$child] } else { $null }
                $tag     = if ($source) { $source.Tag } else { $null }
                $showing = $source -and $tag.Label -and $tag.Control -is [System.Windows.FrameworkElement]

                # The status bar collapses captions and leaves just the box
                $node = if ($showing) { $tag.Label } else { $null }
                while ($node -and ![object]::ReferenceEquals($node, $child)) {
                    if ($node.Visibility -ne 'Visible') { $showing = $false }
                    $node = $node.Parent
                }
                if (!$showing) {
                    $siblings.Add($child)
                    continue
                }

                # New-UiCredential lines up on its first text box
                $box = $tag.Control
                if ($box -is [System.Windows.Controls.Panel]) {
                    $queue = [System.Collections.Generic.Queue[object]]::new()
                    $queue.Enqueue($box)
                    $field = $null
                    while ($queue.Count -and !$field) {
                        $node = $queue.Dequeue()
                        if ($node -is [System.Windows.Controls.TextBox] -or $node -is [System.Windows.Controls.PasswordBox]) {
                            $field = $node
                        }
                        elseif ($node -is [System.Windows.Controls.Panel]) {
                            foreach ($inner in $node.Children) { $queue.Enqueue($inner) }
                        }
                        elseif ($node -is [System.Windows.Controls.Decorator] -and $node.Child) { $queue.Enqueue($node.Child) }
                    }
                    if ($field -and $field.ActualHeight -gt 0) { $box = $field }
                }

                # Not laid out yet
                if ($box.ActualHeight -le 0) { continue }

                # Box top before any push
                $pushed = 0
                if ($state.Original.ContainsKey($child)) { $pushed = $child.Margin.Top - $state.Original[$child].Top  }
                $fixed = ![object]::ReferenceEquals($source, $child) -or $child.Resources.Contains('__PsUiPlacedByUser')
                $entry = @{
                    Child   = $child
                    Source  = $source
                    X       = [System.Windows.Controls.Primitives.LayoutInformation]::GetLayoutSlot($child).X
                    Height  = $box.ActualHeight
                    Natural = $box.TranslatePoint($origin, $panel).Y - $pushed
                    Fixed   = $fixed
                    Tallest = 0
                }

                # Whatever lines up on a box pinned low or central, even one inside a nested row, stops at the row bottom
                if ($fixed -and "$($child.VerticalAlignment) $($source.VerticalAlignment)" -match 'Bottom|Center') {
                    $ownSlot      = [System.Windows.Controls.Primitives.LayoutInformation]::GetLayoutSlot($child)
                    $entry.Bottom = $ownSlot.Y + $ownSlot.Height
                }
                $labeled.Add($entry)
            }
            if (!$labeled.Count) { continue }

            # Placed boxes and nested rows never drag the row after them
            $movable = [System.Collections.Generic.List[object]]::new()
            foreach ($entry in $labeled) {
                $entry.Top = $entry.Natural
                if (!$entry.Fixed) { $movable.Add($entry) }
            }

            # Boxes more than 4px apart drop to the lowest. Radio groups sit 2px low on their own.
            $lowest  = $null
            $highest = [double]::MaxValue
            foreach ($entry in $movable) {
                if (!$lowest -or $entry.Natural -gt $lowest.Natural) { $lowest = $entry }
                $highest = [Math]::Min($highest, $entry.Natural)
            }
            if (!$lowest -or $lowest.Natural - $highest -le 4) { $movable.Clear() }
            foreach ($entry in $movable) {
                if ([object]::ReferenceEquals($entry, $lowest)) { continue }

                # Shorter boxes go on the lowest one's middle, and beside a text area the tops line up instead
                $push = $lowest.Natural - $entry.Natural
                if ($entry.Height -lt $lowest.Height -and $lowest.Height -le $entry.Height * 1.5 + 8) {
                    $push += ($lowest.Height - $entry.Height) / 2
                }
                if ($push -le 0.5) { continue }

                $child = $entry.Child
                & $state.Remember $child
                $margin    = $child.Margin
                $wantTop   = $state.Original[$child].Top + $push
                $entry.Top = $entry.Natural + $push
                [void]$keep.Add($child)
                if ([Math]::Abs($margin.Top - $wantTop) -gt 0.5) {
                    $child.Margin = [System.Windows.Thickness]::new($margin.Left, $wantTop, $margin.Right, $margin.Bottom)
                }
            }

            # Leftmost box
            $first = $labeled[0]
            foreach ($entry in $labeled) {
                if ($entry.X -lt $first.X) { $first = $entry }
            }

            # Each control sits on the nearest labeled box to its left, or on the first one when it leads the row
            $placements = [System.Collections.Generic.List[object]]::new()
            foreach ($sibling in $siblings) {
                if ($sibling.Resources.Contains('__PsUiPlacedByUser')) { continue }

                # Cards and expanders stay put, since an expander opens downward from its header
                if ($sibling -is [System.Windows.Controls.Border] -and $sibling.Child -is [System.Windows.Controls.Panel]) { continue }

                # New-UiProgress -Label's caption is already level
                if ($sibling -is [System.Windows.Controls.StackPanel] -and $sibling.Children.Count -gt 1) {
                    $bar = $sibling.Children[1]
                    if ($bar -is [System.Windows.Controls.Grid] -and $bar.Children.Count) { $bar = $bar.Children[0] }
                    
                    $captioned = $bar -is [System.Windows.Controls.ProgressBar] -and $bar.Tag -is [hashtable] -and [object]::ReferenceEquals($bar.Tag.LabelBlock, $sibling.Children[0])
                    if ($captioned) { continue }
                }

                $slot = [System.Windows.Controls.Primitives.LayoutInformation]::GetLayoutSlot($sibling)
                $ref  = $null
                
                foreach ($entry in $labeled) {
                    if ($entry.X -lt $slot.X -and (!$ref -or $entry.X -gt $ref.X)) { $ref = $entry }
                }
                if (!$ref) { $ref = $first }

                # Stretch gives a child the whole line as its ActualHeight
                $height = $sibling.ActualHeight
                if ("$($sibling.VerticalAlignment)" -eq 'Stretch' -and [double]::IsNaN($sibling.Height)) {
                    $height = $sibling.DesiredSize.Height - $sibling.Margin.Top - $sibling.Margin.Bottom
                }

                # Skips spacers and a grid or group box tall enough to set the line height itself
                if ($height -le 0.5 -or $height -gt $ref.Height * 1.5 + 8) { continue }
                $ref.Tallest = [Math]::Max($ref.Tallest, $height)
                $placements.Add(@{
                    Sibling = $sibling
                    SlotY   = $slot.Y
                    Ref     = $ref
                    Height  = $height
                })
            }

            # Never less than a 28px line or a lone small glyph floats
            foreach ($placement in $placements) {
                $ref     = $placement.Ref
                $lineH   = [Math]::Max($ref.Tallest, 28)
                $band    = $ref.Height
                $sibling = $placement.Sibling
                $margin  = $sibling.Margin
                if ($ref.Height -gt $lineH * 1.5 + 8) { $band = $lineH }
                $targetTop = $ref.Top + ($band - $placement.Height) / 2
                $marginTop = [Math]::Max(0, $targetTop - $placement.SlotY)
                $shiftY    = 0

                # RenderTransform cause a margin counts toward the row height the box follows
                if ($ref.Bottom) {
                    $ownTop    = if ($state.Original.ContainsKey($sibling)) { $state.Original[$sibling].Top } else { $margin.Top }
                    $room      = $ref.Bottom - $placement.SlotY - $placement.Height - $margin.Bottom
                    $shiftY    = [Math]::Max(0, [Math]::Min($marginTop, $room)) - $ownTop
                    $marginTop = $ownTop
                }
                [void]$keep.Add($sibling)
                if ($state.Hooked.Add($sibling)) { $sibling.Add_SizeChanged($state.OnChildSize) }

                $shift   = if ($state.Shifts.ContainsKey($sibling)) { $state.Shifts[$sibling] } else { $null }
                $shifted = if ($shift) { $shift.Y } else { 0 }
                $settled = "$($sibling.VerticalAlignment)" -eq 'Top' -and [Math]::Abs($margin.Top - $marginTop) -le 0.5 -and [Math]::Abs($shifted - $shiftY) -le 0.5

                if ($settled) { continue }
                & $state.Remember $sibling
                $sibling.VerticalAlignment = 'Top'
                $sibling.Margin = [System.Windows.Thickness]::new($margin.Left, $marginTop, $margin.Right, $margin.Bottom)
                if (!$shift -and $shiftY) {
                    $shift                   = [System.Windows.Media.TranslateTransform]::new()
                    $state.Shifts[$sibling]  = $shift
                    $sibling.RenderTransform = $shift
                }
                if ($shift) { $shift.Y = $shiftY }
            }

            # When a taller controls sets the row height, a caption that wraps moves the box without its StackPanel changing size
            foreach ($entry in $labeled) {
                if (!$state.Hooked.Add($entry.Source)) { continue }
                $entry.Source.Add_SizeChanged($state.OnChildSize)
                $entry.Source.Tag.Label.Add_SizeChanged($state.OnChildSize)
            }
        }

        # Whatever left a mixed row gets its own values back
        foreach ($moved in @($state.Original.Keys)) {
            if ($keep.Contains($moved)) { continue }
            $saved = $state.Original[$moved]
            [void]$state.Original.Remove($moved)
            if ([object]::ReferenceEquals($saved.VA, $unset)) { $moved.ClearValue($vaProp) }
            else { $moved.SetValue($vaProp, $saved.VA) }
            if ([object]::ReferenceEquals($saved.Margin, $unset)) { $moved.ClearValue($marginDp) }
            else { $moved.SetValue($marginDp, $saved.Margin) }
            if (!$state.Shifts.Remove($moved)) { continue }
            if ([object]::ReferenceEquals($saved.Shift, $unset)) { $moved.ClearValue($shiftDp) }
            else { $moved.SetValue($shiftDp, $saved.Shift) }
        }
    }.GetNewClosure()

    # Set-ResponsiveConstraints sets child widths from SizeChanged too, and those lay out after every handler has run
    $state.Deferred = {
        $state.Pending = $false
        & $state.Pass
    }.GetNewClosure()
    $state.Schedule = {
        trap { Write-Debug "Set-UiRowAlignment schedule: $_"; continue }
        if ($state.Pending) { return }
        $state.Pending = $true
        $afterLayout   = [System.Windows.Threading.DispatcherPriority]::Loaded
        [void]$state.Panel.Dispatcher.BeginInvoke($afterLayout, [Action]$state.Deferred)
    }.GetNewClosure()
    $state.OnChildSize = {
        param($sender, $changeArgs)
        & $state.Schedule
    }.GetNewClosure()

    # Straight away too for a panel without a window
    $Panel.Add_SizeChanged({
        param($sender, $sizeArgs)
        & $state.Pass $true
        & $state.Schedule
    }.GetNewClosure())

    # The panel has usually been laid out by the time a labeled control attachs it on load
    & $state.Schedule
}
