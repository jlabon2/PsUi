function New-ColumnVisibilityPopup {
    <#
    .SYNOPSIS
        Popup for toggling DataGrid column visibility. Rebuilds on Add_Opened when the column set changes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        # Scriptblock returning @{ All=...; Default=...; Populated=... } from current grid state.
        # Letting the popup pull rather than push removes the construction time snapshot bug that left the picker empty when -ItemsSource grids started with no rows.
        [Parameter(Mandatory)]
        [scriptblock]$PropertiesProvider,

        [scriptblock]$ItemsProvider
    )

    $colors = Get-ThemeColors

    # Sized to match toolbar icon buttons (32x28, 6px gap).
    $colButton = [System.Windows.Controls.Button]@{
        Content = [System.Windows.Controls.TextBlock]@{
            Text                = [PsUi.ModuleContext]::GetIcon('AllApps')
            FontFamily          = [PsUi.ModuleContext]::ActiveIconFontFamily
            FontSize            = 14
            HorizontalAlignment = 'Center'
            VerticalAlignment   = 'Center'
        }
        Padding = [System.Windows.Thickness]::new(0)
        Width   = 32
        Height  = 28
        ToolTip = 'Show/Hide Columns'
        Margin  = [System.Windows.Thickness]::new(0)
    }

    Set-ButtonStyle -Button $colButton -IconOnly

    $popup = [System.Windows.Controls.Primitives.Popup]@{
        PlacementTarget    = $colButton
        Placement          = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
        StaysOpen          = $false
        AllowsTransparency = $true
    }

    $popupBorder = [System.Windows.Controls.Border]@{
        Background      = ConvertTo-UiBrush $colors.ControlBg
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
        Padding         = [System.Windows.Thickness]::new(8)
        CornerRadius    = [System.Windows.CornerRadius]::new(4)
        Tag             = 'PopupBorder'
        MaxHeight       = 400
        Effect          = [System.Windows.Media.Effects.DropShadowEffect]@{
            BlurRadius  = 10
            ShadowDepth = 2
            Opacity     = 0.3
        }
    }

    $scrollViewer = [System.Windows.Controls.ScrollViewer]@{
        VerticalScrollBarVisibility   = 'Auto'
        HorizontalScrollBarVisibility = 'Disabled'
    }

    $checkStack = [System.Windows.Controls.StackPanel]@{ Orientation = 'Vertical' }

    $headerLabel = [System.Windows.Controls.TextBlock]@{
        Text       = 'Visible Columns'
        FontWeight = [System.Windows.FontWeights]::SemiBold
        FontSize   = 12
        Foreground = ConvertTo-UiBrush $colors.ControlFg
        Margin     = [System.Windows.Thickness]::new(0, 0, 0, 8)
    }
    [void]$checkStack.Children.Add($headerLabel)

    $buttonPanel = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Horizontal'
        Margin      = [System.Windows.Thickness]::new(0, 0, 0, 4)
    }

    $selectAllBtn = [System.Windows.Controls.Button]@{
        Content  = 'All'
        FontSize = 11
        Padding  = [System.Windows.Thickness]::new(6, 2, 6, 2)
        Margin   = [System.Windows.Thickness]::new(0, 0, 4, 0)
        ToolTip  = 'Show all columns'
    }
    Set-ButtonStyle -Button $selectAllBtn

    $unselectAllBtn = [System.Windows.Controls.Button]@{
        Content  = 'None'
        FontSize = 11
        Padding  = [System.Windows.Thickness]::new(6, 2, 6, 2)
        Margin   = [System.Windows.Thickness]::new(0, 0, 4, 0)
        ToolTip  = 'Hide all columns (except primary)'
    }
    Set-ButtonStyle -Button $unselectAllBtn

    $defaultOnlyBtn = [System.Windows.Controls.Button]@{
        Content  = 'Default'
        FontSize = 11
        Padding  = [System.Windows.Thickness]::new(6, 2, 6, 2)
        Margin   = [System.Windows.Thickness]::new(0, 0, 4, 0)
        ToolTip  = 'Show only default columns'
    }
    Set-ButtonStyle -Button $defaultOnlyBtn

    $populatedBtn = [System.Windows.Controls.Button]@{
        Content  = 'Has Data'
        FontSize = 11
        Padding  = [System.Windows.Thickness]::new(6, 2, 6, 2)
        ToolTip  = 'Show only columns with values'
    }
    Set-ButtonStyle -Button $populatedBtn

    [void]$buttonPanel.Children.Add($selectAllBtn)
    [void]$buttonPanel.Children.Add($unselectAllBtn)
    [void]$buttonPanel.Children.Add($defaultOnlyBtn)
    [void]$buttonPanel.Children.Add($populatedBtn)
    [void]$checkStack.Children.Add($buttonPanel)

    $separator = [System.Windows.Controls.Border]@{
        Height     = 1
        Background = ConvertTo-UiBrush $colors.Border
        Margin     = [System.Windows.Thickness]::new(0, 4, 0, 8)
    }
    [void]$checkStack.Children.Add($separator)

    # Dynamic checkboxes live in this sub panel. Cleared/refilled per rebuild so the header and bulk action buttons above stay put.
    $checkboxStack = [System.Windows.Controls.StackPanel]@{ Orientation = 'Vertical' }
    [void]$checkStack.Children.Add($checkboxStack)

    $emptyPlaceholder = [System.Windows.Controls.TextBlock]@{
        Text       = '(no columns yet)'
        FontStyle  = [System.Windows.FontStyles]::Italic
        FontSize   = 11
        Foreground = ConvertTo-UiBrush $colors.SecondaryText
        Margin     = [System.Windows.Thickness]::new(0, 4, 0, 4)
    }

    # State the bulk action buttons close over. Checkboxes is a stable List instance, rebuild changes it in place via Clear() and Add() so the closures see the current contents.
    $state = @{
        Signature      = $null
        Checkboxes     = [System.Collections.Generic.List[System.Windows.Controls.CheckBox]]::new()
        PopulatedSet   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        CountSignature = $null
    }

    # Past ~10k cells the grid gets sluggish. Confirm before showing that many columns.
    # Threshold and clause come from Get-UiGridFloodWarning, shared with New-UiDataGrid's construction time prompt so the two can't drift. Resolve to plain values here so the closure captures them (GetNewClosure wouldn't carry the private function resolution).
    $flood              = Get-UiGridFloodWarning
    $cellCountThreshold = $flood.CellThreshold
    $floodClause        = $flood.Clause
    $confirmFlood = {
        param([int]$cols, [int]$rows)
        $cellCount = $cols * $rows
        if ($cellCount -le $cellCountThreshold) { return $true }
        try {
            $msg = ("This will show {0} columns across {1} rows. $floodClause " +
                    "Use 'Default' for a smaller starting set, or flip columns on one at a time.") -f $cols, $rows
            $dialogArgs = @{
                Title       = 'Show all columns?'
                Message     = $msg
                ConfirmText = 'Show all'
                CancelText  = 'Cancel'
            }
            return [bool](Show-UiConfirmDialog @dialogArgs)
        }
        catch {
            Write-Debug "Flood confirm dialog failed: $_"
            return $true
        }
    }.GetNewClosure()

    $getRowCount = {
        if (!$ItemsProvider) { return 0 }
        try {
            $items = & $ItemsProvider
            if ($items) { return @($items).Count }
        }
        catch { Write-Debug "Row count lookup failed: $_" }
        return 0
    }.GetNewClosure()

    # Checkboxes carry property names, but explicit column definitions can render a different Header (Name='Status', Header='Service Status').
    # SortMemberPath holds the property the column sorts by so it wins. Header is the fallback for pathless columns.
    $findColumn = {
        param($propertyName)
        foreach ($col in $DataGrid.Columns) {
            if ($col.SortMemberPath -eq $propertyName) { return $col }
        }
        foreach ($col in $DataGrid.Columns) {
            if ($col.Header -eq $propertyName) { return $col }
        }
        return $null
    }.GetNewClosure()

    # Defined at function body on purpose as nested GetNewClosure captures only the immediate parent scope, so a handler built inside $rebuild sees $DataGrid = $null at click time.
    # One instance attaches across every checkbox. $this IS the firing CheckBox. Attached to both Checked and Unchecked, $this.IsChecked says which way it just flipped.
    $onToggle = {
        $col = & $findColumn $this.Tag.Name
        if ($col) {
            $col.Visibility = if ($this.IsChecked) { [System.Windows.Visibility]::Visible }
                              else { [System.Windows.Visibility]::Collapsed }
        }
        $skip = ($DataGrid.Tag -is [hashtable]) -and
                ($DataGrid.Tag.ContainsKey('StretchLastColumn')) -and
                (!$DataGrid.Tag.StretchLastColumn)
        Set-LastDataColumnStar -DataGrid $DataGrid -Skip:$skip
    }.GetNewClosure()

    # Clears the dynamic checkbox stack and refills from the props snapshot.
    # Called from Add_Opened when the column signature changes.
    $rebuild = {
        param($props)
        $checkboxStack.Children.Clear()
        $state.Checkboxes.Clear()
        $state.PopulatedSet.Clear()

        if ($props.Populated) {
            foreach ($prop in $props.Populated) { [void]$state.PopulatedSet.Add([string]$prop) }
        }

        $allProps = if ($props.All) { @($props.All) } else { @() }
        if ($allProps.Count -eq 0) {
            [void]$checkboxStack.Children.Add($emptyPlaceholder)
            # Nothing for the bulk action buttons to act on - dim them.
            $selectAllBtn.IsEnabled   = $false
            $unselectAllBtn.IsEnabled = $false
            $defaultOnlyBtn.IsEnabled = $false
            $populatedBtn.IsEnabled   = $false
            return
        }

        $defaults = if ($props.Default) { @($props.Default) } else { @() }

        # Labels start without counts, first popup open triggers the count scan. Computing upfront stalled the window on large grids (50 cols x 10k rows).
        $isFirst = $true
        foreach ($propName in $allProps) {

            # TextBlock content so the lazy compute can drop in the (filled/total) Run later.
            $tb       = [System.Windows.Controls.TextBlock]::new()
            $nameRun  = [System.Windows.Documents.Run]::new($propName)
            $countRun = [System.Windows.Documents.Run]::new('')
            $countRun.Foreground = ConvertTo-UiBrush $colors.SecondaryText
            $countRun.FontSize   = 11
            [void]$tb.Inlines.Add($nameRun)
            [void]$tb.Inlines.Add($countRun)

            $checkBox = [System.Windows.Controls.CheckBox]@{
                Content    = $tb
                FontSize   = 12
                Foreground = ConvertTo-UiBrush $colors.ControlFg
                Margin     = [System.Windows.Thickness]::new(0, 2, 0, 2)
                MinWidth   = 150
            }

            $isDefault = $defaults -contains $propName

            $matchedColumn = & $findColumn $propName
            $isVisible     = if ($matchedColumn) { $matchedColumn.Visibility -eq [System.Windows.Visibility]::Visible } else { $true }
            $checkBox.IsChecked = $isVisible

            # Frozen columns can't be hidden, hiding one would shift the freeze boundary.
            $frozenCount = [int]$DataGrid.FrozenColumnCount
            $isFrozen    = $matchedColumn -and $frozenCount -gt 0 -and $matchedColumn.DisplayIndex -lt $frozenCount

            # Tag carries the bits the lazy compute handler needs - property name, default flag, count run.
            $checkBox.Tag = @{ Name = $propName; IsDefault = $isDefault; CountRun = $countRun }

            # Lock the primary column (first one) and any frozen column. Excluded from $state.Checkboxes so Select All / Unselect All / Default Only / Has Data don't touch them.
            if ($isFirst -or $isFrozen) {
                $checkBox.IsEnabled = $false
                $checkBox.IsChecked = $true
                $checkBox.ToolTip   = if ($isFrozen) { 'Frozen column - cannot be hidden' } else { 'Primary column cannot be hidden' }
            }
            else { [void]$state.Checkboxes.Add($checkBox) }
            $isFirst = $false

            # Shared handler from function body - see the $onToggle comment for why nested closures fail here.
            $checkBox.Add_Checked($onToggle)
            $checkBox.Add_Unchecked($onToggle)

            Set-CheckBoxStyle -CheckBox $checkBox
            [void]$checkboxStack.Children.Add($checkBox)
        }

        # Buttons need at least one unlocked checkbox to act on. A single column grid (primary only) lands here with $state.Checkboxes empty.
        $haveCheckboxes = $state.Checkboxes.Count -gt 0
        $selectAllBtn.IsEnabled   = $haveCheckboxes
        $unselectAllBtn.IsEnabled = $haveCheckboxes
        $defaultOnlyBtn.IsEnabled = $haveCheckboxes
        $populatedBtn.IsEnabled   = $haveCheckboxes
    }.GetNewClosure()

    $selectAllBtn.Add_Click({
        $rows  = & $getRowCount
        $count = $state.Checkboxes.Count
        if (!(& $confirmFlood $count $rows)) { return }
        foreach ($checkbox in $state.Checkboxes) {
            $checkbox.IsChecked = $true
        }
    }.GetNewClosure())

    $unselectAllBtn.Add_Click({
        foreach ($checkbox in $state.Checkboxes) {
            $checkbox.IsChecked = $false
        }
    }.GetNewClosure())

    $defaultOnlyBtn.Add_Click({
        foreach ($checkbox in $state.Checkboxes) {
            $checkbox.IsChecked = $checkbox.Tag.IsDefault
        }
    }.GetNewClosure())

    # With ItemsProvider, recompute per click. Without one, fall back to the latest rebuild's set.
    $populatedBtn.Add_Click({
        $currentItems = $null
        $set = $state.PopulatedSet
        if ($ItemsProvider) {
            try {
                $currentItems = & $ItemsProvider
                $props        = & $PropertiesProvider
                if ($currentItems -and $props -and $props.All) {
                    # Get-PopulatedProperties comma-wraps its return, so the HashSet[string] arrives as a single object instead of unrolling. Feed it straight into the constructor.
                    $fresh = Get-PopulatedProperties -Items $currentItems -PropertyNames @($props.All)
                    $set = [System.Collections.Generic.HashSet[string]]::new(
                        $fresh,
                        [System.StringComparer]::OrdinalIgnoreCase
                    )
                }
            }
            catch { Write-Debug "Has Data live recompute failed: $_" }
        }

        $rowCount = if ($currentItems) { @($currentItems).Count } else { 0 }
        if (!(& $confirmFlood $set.Count $rowCount)) { return }

        foreach ($checkbox in $state.Checkboxes) {
            $propName = $checkbox.Tag.Name
            $checkbox.IsChecked = $set.Contains($propName)
        }
    }.GetNewClosure())

    $scrollViewer.Content = $checkStack
    $popupBorder.Child    = $scrollViewer
    $popup.Child          = $popupBorder
    $colButton.Tag        = $popup

    # Each Open rereads the column set via PropertiesProvider. Keyed by signature: only rebuild the checkbox stack when the column list actually changed. Lazy count cache is signature bound so it invalidates with the columns.
    $popup.Add_Opened({
        $props = $null
        try { $props = & $PropertiesProvider }
        catch { Write-Debug "PropertiesProvider failed: $_"; return }
        if (!$props) { return }

        $all = if ($props.All) { @($props.All) } else { @() }
        # NUL separator + count prefix so two different column sets can't collide as strings.
        $sig = $all.Count.ToString() + "`0" + ($all -join "`0")

        if ($sig -ne $state.Signature) {
            & $rebuild $props
            $state.Signature      = $sig
            $state.CountSignature = $null
        }

        # Lazy populated count fill. Only runs once per signature. Reruns after a rebuild.
        if ($state.CountSignature -eq $sig) { return }
        if (!$ItemsProvider)                { $state.CountSignature = $sig; return }
        if ($state.Checkboxes.Count -eq 0)  { $state.CountSignature = $sig; return }

        # Mark the signature first so a second Open while the async scan is in flight doesn't kick a duplicate runspace.
        $state.CountSignature = $sig

        try {
            $items = & $ItemsProvider
            if (!$items) { return }
            $arr   = @($items)
            $total = $arr.Count
            if ($total -eq 0) { return }

            $propNames = foreach ($cb in $state.Checkboxes) { [string]$cb.Tag.Name }

            # Counts one property's populated cells over $arr. A non null value counts unless it's whitespace, the '[Access Denied]' sentinel, or an empty collection.
            $tally = {
                param($propName)
                $count = 0
                foreach ($row in $arr) {
                    if ($null -eq $row) { continue }
                    try {
                        $value = $row.$propName
                        if ($null -ne $value) {
                            if ($value -is [string]) {
                                if (![string]::IsNullOrWhiteSpace($value) -and $value -ne '[Access Denied]') { $count++ }
                            }
                            elseif ($value -is [System.Collections.ICollection]) {
                                if ($value.Count -gt 0) { $count++ }
                            }
                            else { $count++ }
                        }
                    }
                    catch { }
                }
                return $count
            }.GetNewClosure()

            # Small grids count inline - instant, and it dodges the runspace pool warmup that otherwise leaves the first picker open sitting on ' (...)' for a few seconds. Only the genuinely big grid (the 50 col x 10k row case that blocks ~2s) pays for the async scan.
            if (($total * @($propNames).Count) -le 40000) {
                foreach ($cb in $state.Checkboxes) {
                    if ($cb.Tag.CountRun) { $cb.Tag.CountRun.Text = " ($(& $tally ([string]$cb.Tag.Name))/$total)" }
                }
                return
            }

            # 50 cols x 10k rows is the bad case - blocks the UI for ~2s on the open. Push to a background runspace and marshal the count Runs back to the UI thread on completion.
            foreach ($cb in $state.Checkboxes) {
                if ($cb.Tag.CountRun) { $cb.Tag.CountRun.Text = ' (...)' }
            }

            $countRuns = @{}
            foreach ($cb in $state.Checkboxes) {
                if ($cb.Tag.CountRun) { $countRuns[[string]$cb.Tag.Name] = $cb.Tag.CountRun }
            }

            # Local copy for the OnError closure - the signature was marked before the async, so a failed scan has to clear it or the picker shows ' (...)' forever with no retry.
            $stateRef = $state

            # -Variables, not -Arguments: the AsyncExecutor injects Arguments as ${Global:args} and the script's automatic $args shadows it. A param() block binds nothing either (called with no arguments). Named globals are the only delivery that lands.
            Invoke-UiAsync -ScriptBlock {
                $result = @{}
                foreach ($propName in $countProps) {
                    $count = 0
                    foreach ($row in $countRows) {
                        if ($null -eq $row) { continue }
                        try {
                            $value = $row.$propName
                            if ($null -ne $value) {
                                if ($value -is [string]) {
                                    if (![string]::IsNullOrWhiteSpace($value) -and $value -ne '[Access Denied]') { $count++ }
                                }
                                elseif ($value -is [System.Collections.ICollection]) {
                                    if ($value.Count -gt 0) { $count++ }
                                }
                                else { $count++ }
                            }
                        }
                        catch { }
                    }
                    $result[$propName] = $count
                }
                @{ Counts = $result; Total = $countRows.Count }
            } -Variables @{ countRows = $arr; countProps = $propNames } -NoAutoCapture -NoActiveExecutor -OnComplete {
                param($payload)
                if (!$payload -or !$payload.Counts) { return }
                $total = $payload.Total
                foreach ($name in $payload.Counts.Keys) {
                    $run = $countRuns[$name]
                    if ($run) { $run.Text = " ($($payload.Counts[$name])/$total)" }
                }
            }.GetNewClosure() -OnError {
                param($err)
                Write-Debug "Lazy column count scan failed: $err"
                # Drop the ' (...)' so it doesn't hang there, and unmark the signature so the next open retries instead of trusting a scan that never delivered.
                foreach ($run in $countRuns.Values) { if ($run) { $run.Text = '' } }
                $stateRef.CountSignature = $null
            }.GetNewClosure()
        }
        catch {
            Write-Debug "Lazy column count failed: $_"
            # Failed before completion - allow a retry on the next open.
            $state.CountSignature = $null
        }
    }.GetNewClosure())

    $colButton.Add_Click({
        try { $popup.IsOpen = !$popup.IsOpen }
        catch { Write-Verbose "Failed to toggle popup: $_" }
    }.GetNewClosure())

    return @{ Button = $colButton; Popup = $popup }
}
