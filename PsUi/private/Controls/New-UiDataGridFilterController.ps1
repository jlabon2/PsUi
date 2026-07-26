function New-UiDataGridFilterController {
    <#
    .SYNOPSIS
        Debounced live filter on the toolbar textbox, preserves sort and selection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox]$FilterBox
    )

    # Preserve ClearButton/watermark from New-FilterBoxWithClear... merge filter state in.
    $tagData = $FilterBox.Tag
    if (!$tagData) { $tagData = @{} }
    $tagData.DataGrid   = $DataGrid
    $tagData.FilterText = ''
    $FilterBox.Tag      = $tagData

    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($DataGrid.ItemsSource)
    if (!$view) { $view = $DataGrid.ItemsSource -as [System.ComponentModel.ICollectionView] }
    if (!$view) {
        Write-Debug "Filter controller: no ICollectionView available, bailing."
        return $FilterBox
    }

    $tagData.View = $view

    # Closure local cache for -ItemsSource rows (they skip the snapshot step that owned grids run, so they don't have a precomputed _SearchText to read from).
    # Without this cache, every keystroke rewalks every property on every row to build search text.
    $searchCache = [System.Collections.Generic.Dictionary[object,string]]::new()

    # Outside code (Add-UiDataGridEditHandling, helpers) invalidates after row mutations.
    $tagData.ClearSearchCache = { $searchCache.Clear() }.GetNewClosure()

    # Updating FilterText + Refresh() reruns this filter function without rebuilding it.
    $predicate = [Predicate[object]] {
        param($item)
        if ($null -eq $item) { return $false }
        $filterText = $tagData.FilterText
        if ([string]::IsNullOrEmpty($filterText)) { return $true }

        # Cached _SearchText comes from ConvertTo-UiDataGridSnapshot for owned grids. Items that skipped that step (-ItemsSource rows) fall through to the closure cache below so each row gets walked once instead of once per keystroke. Null equality (not falsy) so an empty string cache hit short circuits instead of rewalking.
        $rowSearchText = $null
        try {
            $cached = $item.PSObject.Properties['_SearchText']
            if ($cached) { $rowSearchText = [string]$cached.Value }
        }
        catch { }

        if ($null -eq $rowSearchText) {
            if (!$searchCache.TryGetValue($item, [ref]$rowSearchText)) {
                if ($item -is [string] -or $item -is [System.ValueType]) {
                    # Scalar rows have nothing useful to walk (a string's only adapted property is Length, an int has none) - filter against the value itself.
                    $rowSearchText = [string]$item
                }
                else {
                    $sb = [System.Text.StringBuilder]::new()
                    foreach ($prop in $item.PSObject.Properties) {
                        if ($prop.Name.StartsWith('_')) { continue }
                        $value = $null
                        try { $value = $prop.Value } catch { }
                        if ($null -ne $value) {
                            [void]$sb.Append([string]$value)
                            [void]$sb.Append(' ')
                        }
                    }
                    $rowSearchText = $sb.ToString()
                }
                $searchCache[$item] = $rowSearchText
            }
        }

        return ($rowSearchText -and $rowSearchText.IndexOf($filterText, [StringComparison]::OrdinalIgnoreCase) -ge 0)
    }.GetNewClosure()

    $view.Filter = $predicate

    # One timer for the life of the filter box. TextChanged just resets it.
    $debounceTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $debounceTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $debounceTimer.Tag = $FilterBox
    $debounceTimer.Add_Tick({
        $this.Stop()
        try {
            $filterBox = $this.Tag
            $state     = $filterBox.Tag
            # Clicking straight from a live cell edit into the filter box doesnt always commit the row, so its _SearchText hasnt rebuilt yet... flush any pending edit first or the fresh text filters against the stale index.
            if ($state.DataGrid) {
                try {
                    [void]$state.DataGrid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
                    [void]$state.DataGrid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
                }
                catch { Write-Debug "Filter pre-commit skipped: $_" }
            }
            $state.FilterText = $filterBox.Text.Trim()
            $state.View.Refresh()
        }
        catch { Write-Debug "Filter refresh failed: $_" }
    })
    $tagData.Timer = $debounceTimer

    # Ctrl+F from the grid focuses the filter box. Only fires when the grid has focus (cell editing, row selection, scrolling). Doesn't fight Esc cancel inside the grid.
    $filterBoxRef = $FilterBox
    $ctrlFHandler = {
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::F -and
            ($eventArgs.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
            [void]$filterBoxRef.Focus()
            $filterBoxRef.SelectAll()
            $eventArgs.Handled = $true
        }
    }.GetNewClosure()

    $DataGrid.Add_PreviewKeyDown($ctrlFHandler)

    # Empty text Esc passes through so parent handlers (Window.Close etc.) still get it.
    $escHandler = {
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape -and
            ![string]::IsNullOrEmpty($filterBoxRef.Text)) {
            $filterBoxRef.Text = ''
            $eventArgs.Handled = $true
        }
    }.GetNewClosure()
    $FilterBox.Add_PreviewKeyDown($escHandler)

    $FilterBox.Add_TextChanged({
        $state = $this.Tag

        # Watermark + clear button visibility (New-FilterBoxWithClear already handles these, but the multi handler order is undefined - redo here so it's not order dependent).
        $isEmpty = [string]::IsNullOrEmpty($this.Text)
        if ($state.ClearButton) {
            $state.ClearButton.Visibility = if ($isEmpty) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
        }
        if ($state.Watermark) {
            $state.Watermark.Visibility = if ($isEmpty) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        }

        # Stop + Start resets the 300ms window.
        $state.Timer.Stop()
        $state.Timer.Start()
    })

    # ItemsSource swap (Set-UiDataGridItems and friends) detaches the old CollectionView, taking the filter predicate and the CollectionChanged watcher with it. The swap handler below resolves again and reapplies both. Same pattern as Add-UiDataGridEmptyOverlay.
    $collectionChangedHandler = [System.Collections.Specialized.NotifyCollectionChangedEventHandler]{
        param($sender, $eventArgs)
        if ($eventArgs.Action -eq [System.Collections.Specialized.NotifyCollectionChangedAction]::Reset -or
            $eventArgs.Action -eq [System.Collections.Specialized.NotifyCollectionChangedAction]::Replace) {
            $searchCache.Clear()
        }
        # Remove has to evict too - without it a churny feed roots every row it ever filtered, and the remove+insert redraw pattern keeps matching the premutation text.
        elseif ($eventArgs.Action -eq [System.Collections.Specialized.NotifyCollectionChangedAction]::Remove -and $eventArgs.OldItems) {
            foreach ($oldItem in $eventArgs.OldItems) { [void]$searchCache.Remove($oldItem) }
        }
    }.GetNewClosure()

    $viewSubState = @{ View = $view }
    try { $view.add_CollectionChanged($collectionChangedHandler) }
    catch { Write-Debug "Filter controller CollectionChanged subscribe failed: $_" }

    $rebindFilter = {
        $newView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($DataGrid.ItemsSource)
        if (!$newView) { $newView = $DataGrid.ItemsSource -as [System.ComponentModel.ICollectionView] }
        if (!$newView) { return }
        if ($viewSubState.View) {
            try { $viewSubState.View.remove_CollectionChanged($collectionChangedHandler) } catch { }
            # Drop the predicate off the view being left behind - it closes over the grid, so a swapped out user owned view that outlives the window roots the whole DataGrid (the same leak Window.Closed guards). Harmless when new==old - the reassign below resets it.
            try { $viewSubState.View.Filter = $null } catch { }
        }
        $tagData.View      = $newView
        $viewSubState.View = $newView
        $newView.Filter    = $predicate
        $searchCache.Clear()
        try { $newView.add_CollectionChanged($collectionChangedHandler) } catch { }
    }.GetNewClosure()

    $itemsSourcePropDesc = [System.ComponentModel.DependencyPropertyDescriptor]::FromProperty(
        [System.Windows.Controls.ItemsControl]::ItemsSourceProperty,
        [System.Windows.Controls.DataGrid])
    $itemsSourceChangedHandler = [System.EventHandler]{
        param($sender, $eventArgs)
        & $rebindFilter
    }.GetNewClosure()

    # Cleanup hangs off Window.Closed. Initialized fallback covers grids that never realize (unrealized tabs etc).
    $cleanupRan = @{ Value = $false }
    $onWindowClosed = {
        if ($cleanupRan.Value) { return }
        $cleanupRan.Value = $true
        try { $debounceTimer.Stop() } catch { }
        try { $DataGrid.Remove_PreviewKeyDown($ctrlFHandler) } catch { Write-Debug "Filter Ctrl+F detach failed: $_" }
        try { $FilterBox.Remove_PreviewKeyDown($escHandler) } catch { Write-Debug "Filter Esc detach failed: $_" }
        try { $itemsSourcePropDesc.RemoveValueChanged($DataGrid, $itemsSourceChangedHandler) }
        catch { Write-Debug "Filter DPD detach failed: $_" }
        if ($viewSubState.View) {
            try { $viewSubState.View.remove_CollectionChanged($collectionChangedHandler) } catch { }
            # Clear the predicate too - it closes over the grid, so a user owned ItemsSource that outlives the window roots the whole DataGrid through its default view (and whatever binds that source next inherits a stale filter).
            try { $viewSubState.View.Filter = $null } catch { Write-Debug "Filter clear on close failed: $_" }
            $viewSubState.View = $null
        }
    }.GetNewClosure()

    $hookState = @{ Hooked = $false }
    $hookCleanup = {
        if ($hookState.Hooked) { return }
        $window = [System.Windows.Window]::GetWindow($DataGrid)
        if (!$window) { return }
        $hookState.Hooked = $true
        $itemsSourcePropDesc.AddValueChanged($DataGrid, $itemsSourceChangedHandler)
        $window.Add_Closed($onWindowClosed)
    }.GetNewClosure()

    $DataGrid.Add_Loaded({ & $hookCleanup }.GetNewClosure())
    $DataGrid.Add_Initialized({ & $hookCleanup }.GetNewClosure())

    # Grid can already be loaded when the controller attaches (attached post render).
    # Neither Loaded nor Initialized fires retroactively, so hook up immediately too.
    & $hookCleanup

    return $FilterBox
}
