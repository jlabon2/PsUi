function New-UiGrid {
    <#
    .SYNOPSIS
        Creates a Grid layout container with simplified column/row management.
    .DESCRIPTION
        Provides a declarative Grid control that auto-flows children into cells.
        Supports column sizing via simple syntax, FormLayout for label unwrapping,
        and AutoLayout for simple single-column stacking.
    .PARAMETER Columns
        Column definitions in flexible formats:
        - Integer: Number of equal-width columns (e.g., 3)
        - String: Comma-separated definitions (e.g., 'Auto,*' or 'Auto, *, 100')
        - Array: Array of definitions (e.g., @('Auto', '*', '2*', '100'))
        Valid definitions: 'Auto', '*' (star), '2*' (weighted star), or number (fixed pixels).
    .PARAMETER Rows
        Row definitions in same flexible formats as Columns.
        If omitted, rows are created automatically as needed.
    .PARAMETER AutoLayout
        Simple single-column layout where each control gets its own row.
        Does not unwrap label+control pairs - controls handle their own labels.
        This is the recommended layout for mixed control types (inputs, toggles, sliders).
    .PARAMETER FormLayout
        Optimized for label+control pairs. Automatically uses a 2-column layout with
        auto-width labels on the left and stretching controls on the right.
        Note: May not work well with controls that have complex internal labels.
    .PARAMETER RowSpacing
        Vertical spacing between rows in pixels. Default is 4.
    .PARAMETER ColumnSpacing
        Horizontal spacing between columns in pixels. Default is 8.
    .PARAMETER Content
        ScriptBlock containing child controls.
    .PARAMETER FillParent
        Makes the grid fill its parent's available vertical space. Use this
        when star-sized rows need to divide height evenly (e.g. dashboard grids).
        Works by reading the parent's ActualHeight and subtracting sibling heights.
    .PARAMETER FullWidth
        Stretches the grid to fill available width.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the Grid.
    .EXAMPLE
        New-UiGrid -Columns 2 -Rows '*,*' -FillParent -Content {
            New-UiChart -Type Bar -Data $sales -Title "Sales"
            New-UiChart -Type Line -Data $trend -Title "Trend"
            New-UiChart -Type Pie -Data $share -Title "Share"
            New-UiChart -Type Bar -Data $revenue -Title "Revenue"
        }
        # Dashboard: 4 equal cells that fill the tab
    .EXAMPLE
        New-UiGrid -Columns 3 -Content {
            New-UiLabel -Text "A"
            New-UiLabel -Text "B"
            New-UiLabel -Text "C"
            New-UiLabel -Text "D"  # Wraps to row 1, col 0
        }
    .EXAMPLE
        New-UiGrid -FormLayout -Content {
            New-UiInput -Label "Username" -Variable "user"
            New-UiInput -Label "Password" -Variable "pass"
        }
        # Creates a clean 2-column form with labels auto-sized on the left
    .EXAMPLE
        New-UiGrid -AutoLayout -Content {
            New-UiInput -Label "Name" -Variable "name"
            New-UiDropdown -Label "Role" -Variable "role" -Items @('Admin', 'User')
            New-UiToggle -Label "Active" -Variable "active"
            New-UiSlider -Label "Volume" -Variable "vol" -ShowValueLabel
        }
        # Each control gets its own row, labels handled internally
    .EXAMPLE
        New-UiGrid -Columns 'Auto, *, 100' -Content {
            New-UiLabel -Text "Name:"
            New-UiInput -Variable "name"
            New-UiButton -Text "..."
        }
    .EXAMPLE
        New-UiGrid -Columns 2 -Rows '*, Auto' -Content {
            # Content area spanning top
            New-UiLabel -Text "Main content here"
            # Button row at bottom with fixed height
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        $Columns = 2,

        [Parameter()]
        $Rows,

        [Parameter(Mandatory)]
        [scriptblock]$Content,

        [switch]$AutoLayout,

        [switch]$FormLayout,

        [int]$RowSpacing = 4,

        [int]$ColumnSpacing = 8,

        [switch]$FullWidth,

        [switch]$FillParent,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    # Helper to parse column/row definitions from various input formats
    function ConvertTo-GridDefinitions {
        param($Spec, [string]$Type)

        # Integer = that many equal-width columns/rows
        if ($Spec -is [int]) {
            return @('*') * $Spec
        }

        # Comma-separated string like 'Auto,*' or 'Auto, *, 100'
        if ($Spec -is [string]) {
            return $Spec -split '\s*,\s*' | Where-Object { $_ }
        }

        # Array passed directly
        if ($Spec -is [array]) {
            return $Spec
        }

        # Fallback
        return @('*')
    }

    $session = Assert-UiSession -CallerName 'New-UiGrid'
    $parent   = $session.CurrentParent
    $oldParent = $parent
    Write-Debug "AutoLayout: $($AutoLayout.IsPresent), FormLayout: $($FormLayout.IsPresent), Columns: $Columns, Parent: $($parent.GetType().Name)"

    # AutoLayout: single stretching column, each child = one row
    if ($AutoLayout) {
        $Columns = '*'
    }
    # Default FormLayout to 2-column Auto/* if no columns specified
    elseif ($FormLayout -and $Columns -eq 2 -and $Columns -isnot [array] -and $Columns -isnot [string]) {
        $Columns = 'Auto,*'
    }

    # Parse column definitions
    $columnSpecs = ConvertTo-GridDefinitions -Spec $Columns -Type 'Column'

    $grid = [System.Windows.Controls.Grid]@{
        Margin = [System.Windows.Thickness]::new(4)
    }

    # Helper to parse a single size definition (Auto, *, 2*, 100)
    function ConvertTo-GridLength {
        param([string]$Def)

        switch -Regex ($Def) {
            '^Auto$' {
                return [System.Windows.GridLength]::Auto
            }
            '^(\d+)\*$' {
                $weight = [double]$matches[1]
                return [System.Windows.GridLength]::new($weight, [System.Windows.GridUnitType]::Star)
            }
            '^\*$' {
                return [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            }
            '^\d+$' {
                return [System.Windows.GridLength]::new([double]$Def, [System.Windows.GridUnitType]::Pixel)
            }
            default {
                Write-Warning "Unknown grid definition '$Def', using Star"
                return [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            }
        }
    }

    # Create column definitions
    $columnDefs = [System.Collections.Generic.List[object]]::new()
    foreach ($colSpec in $columnSpecs) {
        $colDefinition = [System.Windows.Controls.ColumnDefinition]::new()
        $colDefinition.Width = ConvertTo-GridLength -Def $colSpec
        $columnDefs.Add($colDefinition)
    }

    foreach ($col in $columnDefs) {
        [void]$grid.ColumnDefinitions.Add($col)
    }
    Write-Debug "Created $($columnDefs.Count) column definitions"

    $columnCount = $columnDefs.Count

    # Parse and create row definitions if specified
    if ($Rows) {
        $rowSpecs = ConvertTo-GridDefinitions -Spec $Rows -Type 'Row'
        foreach ($rowSpec in $rowSpecs) {
            $rowDefinition = [System.Windows.Controls.RowDefinition]::new()
            $rowDefinition.Height = ConvertTo-GridLength -Def $rowSpec
            [void]$grid.RowDefinitions.Add($rowDefinition)
        }
    }

    # Save previous context to support nested grids
    $previousGridContext = $script:GridContext

    # Store grid state for child placement (using script scope since session is C# object)
    $script:GridContext = @{
        Grid         = $grid
        ColumnCount  = $columnCount
        CurrentRow   = 0
        CurrentCol   = 0
        AutoLayout   = $AutoLayout.IsPresent
        FormLayout   = $FormLayout.IsPresent
        RowSpacing   = $RowSpacing
        ColSpacing   = $ColumnSpacing
    }

    # Set grid as current parent so children add to it
    $session.CurrentParent = $grid
    Write-Debug "Entering content block"

    # Execute content - restore state outside try/finally for PS 5.1 closure compatibility
    try {
        Invoke-UiContent -Content $Content -CallerName 'New-UiGrid' -ErrorAction Stop
    }
    catch {
        # Restore state before re-throwing
        $session.CurrentParent = $oldParent
        $script:GridContext = $previousGridContext
        throw
    }
    
    # Restore state after successful content execution
    $session.CurrentParent = $oldParent
    $script:GridContext = $previousGridContext
    Write-Debug "Content block complete"

    Write-Debug "POST-PROCESS: Starting"
    Write-Debug "POST-PROCESS: grid is null = $($null -eq $grid)"
    
    # AutoLayout skips unwrapping - each child stays as-is
    $skipUnwrap = $AutoLayout
    
    try {
        $childrenToProcess = @($grid.Children)
        $unwrappedChildren = [System.Collections.Generic.List[object]]::new()

        foreach ($child in $childrenToProcess) {
            Write-Debug "Processing child: $($child.GetType().FullName)"
            
            # Check for FormControl tag (preferred method)
            $formTag = $null
            if (!$skipUnwrap -and $child -is [System.Windows.Controls.StackPanel]) {
                $tagValue = $child.Tag
                if ($tagValue -is [hashtable] -and $tagValue.FormControl -eq $true) {
                    $formTag = $tagValue
                }
            }
            
            # Fallback: detect label+control wrapper by structure (for backward compat)
            $isLabelWrapper = $false
            if (!$skipUnwrap -and !$formTag -and $child -is [System.Windows.Controls.StackPanel]) {
                if ($child.Children.Count -eq 2 -and $child.Children[0] -is [System.Windows.Controls.TextBlock]) {
                    $isLabelWrapper = $true
                }
            }

            if ($formTag) {
                # Use tagged references (no index assumptions)
                try {
                    $labelBlock = $formTag.Label
                    $control    = $formTag.Control

                    # Disconnect label from its parent (may be nested in a DockPanel)
                    $labelParent = $labelBlock.Parent
                    if ($labelParent -is [System.Windows.Controls.Panel]) {
                        [void]$labelParent.Children.Remove($labelBlock)
                    }

                    # Disconnect control from its parent
                    $controlParent = $control.Parent
                    if ($controlParent -is [System.Windows.Controls.Panel]) {
                        [void]$controlParent.Children.Remove($control)
                    }

                    # Remove the wrapper from grid (no longer needed)
                    [void]$grid.Children.Remove($child)

                    # Add label and control as separate items
                    [void]$unwrappedChildren.Add($labelBlock)
                    [void]$unwrappedChildren.Add($control)
                    Write-Debug "Unwrapped via FormControl tag"
                }
                catch {
                    Write-Debug "Error unwrapping via tag: $($_.Exception.Message)"
                    throw
                }
            }
            elseif ($isLabelWrapper) {
                # Legacy fallback: extract by index
                try {
                    $labelBlock = $child.Children[0]
                    $control    = $child.Children[1]

                    # Remove from wrapper (must remove in reverse order)
                    $child.Children.RemoveAt(1)
                    $child.Children.RemoveAt(0)

                    # Skip if control is invalid (can happen with child window sessions)
                    if ($null -ne $control -and $control -isnot [System.Windows.UIElement]) {
                        Write-Debug "Invalid control extracted: $($control.GetType().FullName)"
                        continue
                    }

                    # Remove wrapper from grid
                    [void]$grid.Children.Remove($child)

                    # Add label and control as separate items
                    [void]$unwrappedChildren.Add($labelBlock)
                    [void]$unwrappedChildren.Add($control)
                    Write-Debug "Unwrapped via legacy index detection"
                }
                catch {
                    Write-Debug "Error unwrapping label/control: $($_.Exception.Message)"
                    throw
                }
            }
            else {
                try {
                    [void]$unwrappedChildren.Add($child)
                    # Remove so we can re-add in order
                    [void]$grid.Children.Remove($child)
                }
                catch {
                    Write-Debug "Error processing child removal: $($_.Exception.Message)"
                    throw
                }
            }
        }
    }
    catch {
        Write-Debug "Post-process (unwrap) error: $($_.Exception.Message)"
        throw
    }

    # Now place all children (unwrapped) into the grid with auto-flow
    Write-Debug "Unwrapped children: $($unwrappedChildren.Count)"
    $ctx = @{
        Row = 0
        Col = 0
    }

    foreach ($child in $unwrappedChildren) {
        if ($null -eq $child) {
            Write-Debug "Skipping null child during placement"
            continue
        }
        if ($child -isnot [System.Windows.UIElement]) {
            Write-Debug "Skipping non-UIElement child: $($child.GetType().FullName)"
            continue
        }

        try {
            # Add child to grid
            [void]$grid.Children.Add($child)

            # Auto-place this child (all unwrapped children need placement)
            [System.Windows.Controls.Grid]::SetRow($child, $ctx.Row)
            [System.Windows.Controls.Grid]::SetColumn($child, $ctx.Col)

            # For labels in first column, vertically center them
            if ($ctx.Col -eq 0 -and $child -is [System.Windows.Controls.TextBlock]) {
                $child.VerticalAlignment = 'Center'
            }

            # Apply spacing via margin when supported
            $isFrameworkElement = $child -is [System.Windows.FrameworkElement]
            $existingMargin = if ($isFrameworkElement) { $child.Margin } else { [System.Windows.Thickness]::new() }
            $leftMargin   = if ($ctx.Col -gt 0) { $ColumnSpacing / 2 } else { 0 }
            $rightMargin  = if ($ctx.Col -lt ($columnCount - 1)) { $ColumnSpacing / 2 } else { 0 }
            $topMargin    = if ($ctx.Row -gt 0) { $RowSpacing / 2 } else { 0 }
            $bottomMargin = $RowSpacing / 2

            if ($isFrameworkElement) {
                $child.Margin = [System.Windows.Thickness]::new(
                    $existingMargin.Left + $leftMargin,
                    $existingMargin.Top + $topMargin,
                    $existingMargin.Right + $rightMargin,
                    $existingMargin.Bottom + $bottomMargin
                )
            }
        }
        catch {
            Write-Debug "Placement error: $($_.Exception.Message)"
            Write-Debug "Child type: $($child.GetType().FullName); Row=$($ctx.Row), Col=$($ctx.Col)"
            throw
        }

        # Advance to next cell
        $ctx.Col++
        if ($ctx.Col -ge $columnCount) {
            $ctx.Col = 0
            $ctx.Row++

            # Add row definition if needed
            if ($ctx.Row -ge $grid.RowDefinitions.Count) {
                $newRow = [System.Windows.Controls.RowDefinition]@{
                    Height = [System.Windows.GridLength]::Auto
                }
                [void]$grid.RowDefinitions.Add($newRow)
            }
        }
    }

    Write-Debug "Placement phase complete"
    # FullWidth mode — WrapPanel parents need explicit Width since they size to content
    if ($FullWidth -or $parent -is [System.Windows.Controls.WrapPanel]) {
        $grid.HorizontalAlignment = 'Stretch'
        if ($parent -is [System.Windows.Controls.WrapPanel]) {
            $grid.Width = $parent.ActualWidth
            if ($grid.Width -eq 0) { $grid.Width = 800 }

            # Track parent resizes so the grid width stays in sync with the tab/window
            $gridWidthRef  = $grid
            $parentWidthRef = $parent
            $parentWidthRef.Add_SizeChanged({
                param($sender, $sizeArgs)
                $newWidth = $sender.ActualWidth
                if ($newWidth -gt 50) { $gridWidthRef.Width = $newWidth }
            }.GetNewClosure())
        }
    }

    # Apply custom WPF properties
    if ($WPFProperties) {
        Set-UiProperties -Control $grid -Properties $WPFProperties
    }

    [void]$parent.Children.Add($grid)
    Write-Debug "Grid added to parent with $($grid.Children.Count) children"

    # FillParent: walk up the visual tree to find the ScrollViewer that wraps
    # all window content. The ScrollViewer's ViewportHeight is the real visible
    # area — everything inside it measures with infinite height, so star rows
    # collapse to Auto without an explicit Height on the grid.
    # Strategy: shrink the grid to a small initial height so the ScrollViewer
    # content fits the viewport, then fire a DispatcherTimer (100ms) to read
    # TranslatePoint and ViewportHeight once layout has stabilized.
    if ($FillParent -and $parent -is [System.Windows.Controls.Panel]) {
        $gridRef   = $grid
        $parentRef = $parent

        # Width: WrapPanel tracks horizontal size correctly, keep it in sync on resize
        $parentRef.Add_SizeChanged({
            param($sizeSender, $sizeArgs)
            $newWidth = $sizeSender.ActualWidth
            if ($newWidth -gt 50) { $gridRef.Width = $newWidth }
        }.GetNewClosure())

        # Height: discover the ScrollViewer after the visual tree is built
        $gridRef.Add_Loaded({
            param($loadSender, $loadArgs)

            # Set width immediately (may have been 0 at creation time)
            if ($parentRef.ActualWidth -gt 50) { $gridRef.Width = $parentRef.ActualWidth }

            # Shrink the grid so its natural content height doesn't push it
            # below the ScrollViewer viewport (which makes TranslatePoint > ViewportHeight)
            $gridRef.Height = 200

            # Walk up the visual tree to find the window's ScrollViewer
            $sv = $null
            $walker = $parentRef
            while ($walker) {
                $nextUp = [System.Windows.Media.VisualTreeHelper]::GetParent($walker)
                if (!$nextUp) { break }
                if ($nextUp -is [System.Windows.Controls.ScrollViewer]) { $sv = $nextUp; break }
                $walker = $nextUp
            }
            if (!$sv) { return }

            # Capture references for closures — keep names short to avoid nested scope issues
            $gr = $gridRef

            # Compute height: viewport minus the grid's Y offset within the ScrollViewer
            $computeHeight = {
                $vh = $sv.ViewportHeight
                if ($vh -le 0) { return }

                $offset = 80.0
                try {
                    $pt = $gr.TranslatePoint([System.Windows.Point]::new(0, 0), $sv)
                    $offset = $pt.Y
                }
                catch { Write-Debug 'TranslatePoint failed during auto-size' }

                $target = $vh - $offset - 10
                $current = $gr.ActualHeight

                # Only update if meaningfully different (prevents infinite layout cycles)
                if ($target -gt 50 -and ([double]::IsNaN($current) -or [Math]::Abs($target - $current) -gt 5)) {
                    $gr.Height = $target
                }
            }.GetNewClosure()

            # DispatcherTimer is the most reliable deferred-execution pattern
            # in PowerShell closures. BeginInvoke [Action] casting can fail silently.
            $heightFn = $computeHeight
            $timer    = [System.Windows.Threading.DispatcherTimer]::new()
            $timer.Interval = [TimeSpan]::FromMilliseconds(100)
            $tRef = $timer
            $timer.Add_Tick({
                $tRef.Stop()
                & $heightFn
            }.GetNewClosure())
            $timer.Start()

            # Recalculate whenever the viewport resizes (window drag, maximize, etc.)
            $resizeFn = $computeHeight
            $sv.Add_SizeChanged({
                param($sizeSender, $sizeArgs)
                & $resizeFn
            }.GetNewClosure())
        }.GetNewClosure())
    }
}
