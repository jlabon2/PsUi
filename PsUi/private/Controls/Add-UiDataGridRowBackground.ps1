function Add-UiDataGridRowBackground {
    <#
    .SYNOPSIS
        Colors rows via -RowBackground, evaluated once per item so scroll stays fast.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [Parameter(Mandatory)]
        [scriptblock]$RowBackground
    )

    # Sort/filter don't touch the source, so a scrolled row is a dictionary lookup instead of rerunning the scriptblock.
    # Matters once -RowBackground is anything heavier than a property read.
    $rowBgRef = $RowBackground
    $brushMap = [System.Collections.Generic.Dictionary[object,object]]::new()

    $evaluate = {
        param($item)
        try {
            # InvokeWithContext, not positional invoke - $_ doesn't survive the trip across the module boundary by itself (same fix as Add-UiDataGridRowDetails). Last output wins, like a return.
            $vars = [System.Collections.Generic.List[psvariable]]::new()
            $vars.Add([psvariable]::new('_', $item))
            $vars.Add([psvariable]::new('row', $item))
            $result = $rowBgRef.InvokeWithContext($null, $vars)
            $value  = if ($result.Count -gt 0) { $result[$result.Count - 1] } else { $null }
            if ($null -ne $value) {
                if ($value -is [System.Windows.Media.Brush]) { return $value }
                return (ConvertTo-UiBrush $value)
            }
        }
        catch { Write-Debug "RowBackground scriptblock failed: $_" }
        return $null
    }.GetNewClosure()

    # Track the live source so subscriptions swap when ItemsSource is replaced at runtime.
    # LoadingRow handles initial fill lazily, no eager prefill.
    $subState = @{ Source = $null; Handler = $null }

    $DataGrid.Add_LoadingRow({
        param($sender, $eventArgs)
        $row  = $eventArgs.Row
        $item = $row.Item

        if ($null -eq $item) {
            $row.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
            return
        }

        # Virtualization recycle reuses the brush already computed for this row.
        # Rare case when a newly added row whose CollectionChanged subscriber hasn't run yet (WPF can race the layout pass ahead of the multicast on -ItemsSource), or a source that doesn't implement INotifyCollectionChanged so the subscirber never runs. Compute inline and cache so the next time the row scrolls into view, the lookup is a single dictionary read.
        $brush = $null
        if (!$brushMap.TryGetValue($item, [ref]$brush)) {
            $brush = & $evaluate $item
            $brushMap[$item] = $brush
        }

        if ($null -ne $brush) { $row.Background = $brush }
        else { $row.ClearValue([System.Windows.Controls.Control]::BackgroundProperty) }
    }.GetNewClosure())

    # Source sync. Sort/filter don't fire CollectionChanged on the source, so this only runs for real Add/Remove/Replace/Reset.
    $buildHandler = {
        # Rebind to locals: nested .GetNewClosure() captures only this invocation's locals, not what $buildHandler itself captured - $brushMap/$evaluate were $null inside the running handler, so Remove bookkeeping leaked and Reset never cleared the cache.
        $mapRef  = $brushMap
        $evalRef = $evaluate
        # Cast to the delegate type so add_/remove_CollectionChanged see the same instance - the raw scriptblock rides PS's conversion cache and the detach can miss under GC.
        $handler = [System.Collections.Specialized.NotifyCollectionChangedEventHandler]{
            param($sender, $eventArgs)
            switch ($eventArgs.Action) {
                ([System.Collections.Specialized.NotifyCollectionChangedAction]::Add) {
                    foreach ($newItem in $eventArgs.NewItems) { $mapRef[$newItem] = & $evalRef $newItem }
                }
                ([System.Collections.Specialized.NotifyCollectionChangedAction]::Remove) {
                    foreach ($oldItem in $eventArgs.OldItems) { [void]$mapRef.Remove($oldItem) }
                }
                ([System.Collections.Specialized.NotifyCollectionChangedAction]::Replace) {
                    foreach ($oldItem in $eventArgs.OldItems) { [void]$mapRef.Remove($oldItem) }
                    foreach ($newItem in $eventArgs.NewItems) { $mapRef[$newItem] = & $evalRef $newItem }
                }
                ([System.Collections.Specialized.NotifyCollectionChangedAction]::Reset) {
                    # Clear only. LoadingRow refills on miss - prefilling here runs the user scriptblock once per source row on the UI thread, and a ReplaceAll with 50k rows turns that into a freeze.
                    $mapRef.Clear()
                }
            }
        }.GetNewClosure()
        return $handler
    }.GetNewClosure()

    $resolveSource = {
        $view = $DataGrid.ItemsSource -as [System.ComponentModel.ICollectionView]
        if ($view) { return $view.SourceCollection }
        return $DataGrid.ItemsSource
    }.GetNewClosure()

    $attach = {
        $newSource = & $resolveSource
        # ReferenceEquals, not -eq: PS enumerates a collection LHS, so -eq never compares references (a source tested against itself came back falsy, and a source holding two null rows compared truthy against $null).
        if ([object]::ReferenceEquals($newSource, $subState.Source)) { return }

        # Detach the old subscription before swapping. Leaving it hooked leaks the grid via the source's event multicast, and the new source goes silent on Add/Remove.
        if ($subState.Source -and $subState.Handler) {
            try { $subState.Source.remove_CollectionChanged($subState.Handler) }
            catch { Write-Debug "RowBackground old-source detach failed: $_" }
        }

        $brushMap.Clear()
        $subState.Source  = $newSource
        $subState.Handler = $null

        if ($newSource -is [System.Collections.Specialized.INotifyCollectionChanged]) {
            $handler = & $buildHandler
            try {
                $newSource.add_CollectionChanged($handler)
                $subState.Handler = $handler
            }
            catch { Write-Debug "RowBackground source subscribe failed: $_" }
        }
    }.GetNewClosure()

    & $attach

    # Watch ItemsSource swaps. DPD.AddValueChanged parks a strong ref to the grid in WPF's internal table, which has never once released anything voluntarily - cleanup MUST land on Window.Closed. Not Unloaded: tab switches fire Unloaded too, and the user is coming back to that grid.
    $itemsSourcePropDesc = [System.ComponentModel.DependencyPropertyDescriptor]::FromProperty(
        [System.Windows.Controls.ItemsControl]::ItemsSourceProperty,
        [System.Windows.Controls.DataGrid])

    $itemsSourceChangedHandler = [System.EventHandler]{
        param($sender, $eventArgs)
        & $attach
    }.GetNewClosure()

    $onWindowClosed = {
        try { $itemsSourcePropDesc.RemoveValueChanged($DataGrid, $itemsSourceChangedHandler) }
        catch { Write-Debug "RowBackground DPD detach failed: $_" }
        if ($subState.Source -and $subState.Handler) {
            try { $subState.Source.remove_CollectionChanged($subState.Handler) }
            catch { Write-Debug "RowBackground source detach failed: $_" }
            $subState.Source  = $null
            $subState.Handler = $null
        }
    }.GetNewClosure()

    $initHooked = @{ Value = $false }
    $hookWindow = {
        if ($initHooked.Value) { return }
        $window = [System.Windows.Window]::GetWindow($DataGrid)
        if (!$window) { return }
        $initHooked.Value = $true
        $itemsSourcePropDesc.AddValueChanged($DataGrid, $itemsSourceChangedHandler)
        $window.Add_Closed($onWindowClosed)
    }.GetNewClosure()

    # Initialized fires before Loaded. A grid parented at construction hooks immediately. Loaded covers grids that get a parent later (deferred Content assignment etc).
    $DataGrid.Add_Initialized({ & $hookWindow }.GetNewClosure())
    $DataGrid.Add_Loaded({ & $hookWindow }.GetNewClosure())
}
