function New-ObjectSubTab {
    <#
    .SYNOPSIS
        Creates a DataGrid sub-tab for displaying rows of objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$GroupItems,

        [Parameter(Mandatory)]
        [string]$TypeName,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TabControl]$SubTabControl,

        [switch]$SingleSelect,

        [switch]$IncludeActionStatus
    )

    $subTab = [System.Windows.Controls.TabItem]::new()
    $subTab.Header = "$TypeName ($($GroupItems.Count))"
    Set-TabItemStyle -TabItem $subTab

    $selectParam = if ($SingleSelect) { @{ SingleSelect = $true } } else { @{} }
    $subGrid = New-StyledDataGrid @selectParam

    # Build items in a List first (avoids UI notifications during population)
    # WPF binds CLR members only, so an unwrapped DirectoryInfo renders Mode and every other PS* column blank.
    # [psobject] not [object], since an [object] typed Add unwraps it again and every collection these rows touch has to match.
    $itemList = [System.Collections.Generic.List[psobject]]::new($GroupItems.Count)
    foreach ($item in $GroupItems) {
        if ($IncludeActionStatus) {
            $props = $item.PSObject.Properties
            if (!$props['_ActionStatus']) {
                $props.Add([System.Management.Automation.PSNoteProperty]::new('_ActionStatus', ''))
            }
        }
        $itemList.Add($item)
    }

    # Create ObservableCollection (single notification vs per-item)
    # [object] here undoes all of that on the first keystroke, since the filter clears this collection and adds the rows back.
    # It is also why $grid.Items.IndexOf and $grid.SelectedItem = $row never match from PS, so reach for SelectedIndex or this collection.
    $observable = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new($itemList)
    $subGrid.ItemsSource = [System.Windows.Data.CollectionViewSource]::GetDefaultView($observable)

    $allProps = [System.Collections.Generic.List[object]]::new()
    $defaultProps = [System.Collections.Generic.List[object]]::new()

    if ($GroupItems.Count -gt 0) {
        $firstItem = $GroupItems[0]
        $columnResult = Add-DataGridColumns -DataGrid $subGrid -FirstItem $firstItem -IncludeActionStatus:$IncludeActionStatus
        $allProps = $columnResult.AllProperties
        $defaultProps = $columnResult.DefaultProperties

        Set-LastDataColumnStar -DataGrid $subGrid
    }

    # Pre-compute populated properties for "Has Data" filtering
    $populatedProps = Get-PopulatedProperties -Items $GroupItems -PropertyNames $allProps

    $subGrid.Tag = @{
        AllProperties       = $allProps
        DefaultProperties   = $defaultProps
        PopulatedProperties = $populatedProps
        UnfilteredItems     = $itemList
        Observable          = $observable
    }

    Add-ArrayCellPopupHandler -DataGrid $subGrid
    Add-DictionaryValuePopupHandler -DataGrid $subGrid

    # The New-UiDataGrid overlay, with the filter rewriting its message when a search empties the grid.
    $subTab.Content = Add-UiDataGridEmptyOverlay -HostControl $subGrid -DataGrid $subGrid -Message 'No items to display.'

    # Mark tab as indexing, then start background search index
    $subTab.Tag = 'Indexing'
    $items = @($observable)
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace

    # Build search text for each item in background
    [void]$ps.AddScript({
        param($items)

        # Process.CommandLine runs about 30ms a row on 7, so that one column costs eight seconds over 264 processes with the search box dead until it lands.
        # It prices a few rows first, then indexes every row against the same set, so a match means the same thing on row 1 and row 300.
        # Ten rows rather than one, since Name, Path and StartTime are cheap everywhere and are exactly what people search on.
        $budgetMs   = 750
        $sampleRows = [math]::Min(10, $items.Count)
        $spent      = @{}
        $sampled    = @{}
        $skip       = [System.Collections.Generic.HashSet[string]]::new()
        $probe      = [System.Diagnostics.Stopwatch]::new()

        # The sample spreads first to last, because one type bucket can mix property sets and a property no sampled row carries never gets evaluated.
        # The stride has to reach the last row, so it divides by (sampleRows - 1).
        $lastRow = $items.Count - 1
        for ($sampleIdx = 0; $sampleIdx -lt $sampleRows; $sampleIdx++) {
            $rowIdx = if ($sampleRows -gt 1) { [int][math]::Floor($sampleIdx * $lastRow / ($sampleRows - 1)) } else { 0 }
            foreach ($prop in $items[$rowIdx].PSObject.Properties) {
                $probeName = $prop.Name
                if ($probeName.StartsWith('_') -or $skip.Contains($probeName)) { continue }

                # The first read of a property compiles its getter, so a property new to the sample gets a warm up read that never counts.
                # If that warm up read alone projects past twenty budgets, it gets skipped, compile time or not.
                if (!$sampled.ContainsKey($probeName)) {
                    $probe.Restart()
                    try { $null = $prop.Value } catch { [void]$skip.Add($probeName); continue }
                    $probe.Stop()
                    if (($probe.Elapsed.TotalMilliseconds * $items.Count) -gt ($budgetMs * 20)) { [void]$skip.Add($probeName); continue }
                }
                $probe.Restart()
                try {
                    $sample = $prop.Value
                    if ($sample) { [void]$sample.ToString() }
                }
                catch {
                    [void]$skip.Add($probeName)
                    continue
                }
                $probe.Stop()
                $spent[$probeName]   = $spent[$probeName] + $probe.Elapsed.TotalMilliseconds
                $sampled[$probeName] = $sampled[$probeName] + 1

                # Two readings both over four budgets is enough to stop, since one on its own can just be a GC pause.
                if ($sampled[$probeName] -ge 2 -and (($spent[$probeName] / $sampled[$probeName]) * $items.Count) -gt ($budgetMs * 4)) {
                    [void]$skip.Add($probeName)
                }
            }
        }

        # The cost is projected over the whole set, or a flat per read cap drops a 20ms property on 20 rows that only costs 400ms to index.
        foreach ($probeName in @($spent.Keys)) {
            if ($skip.Contains($probeName)) { continue }
            if ((($spent[$probeName] / $sampled[$probeName]) * $items.Count) -gt $budgetMs) { [void]$skip.Add($probeName) }
        }

        foreach ($item in $items) {
            $props = $item.PSObject.Properties
            if ($props['_SearchText']) { continue }
            $sb = [System.Text.StringBuilder]::new()
            foreach ($prop in $props) {
                $propName = $prop.Name
                if ($propName.StartsWith('_') -or $skip.Contains($propName)) { continue }

                # No sampled row carried this one, so it gets the warm up read and the price check here before it goes in.
                if (!$sampled.ContainsKey($propName)) {
                    $probe.Restart()
                    try { $null = $prop.Value } catch { [void]$skip.Add($propName); continue }
                    $probe.Stop()
                    if (($probe.Elapsed.TotalMilliseconds * $items.Count) -gt ($budgetMs * 20)) { [void]$skip.Add($propName); continue }
                    $probe.Restart()
                    try {
                        $propVal = $prop.Value
                        if ($propVal) { [void]$propVal.ToString() }
                    }
                    catch {
                        [void]$skip.Add($propName)
                        continue
                    }
                    $probe.Stop()
                    $sampled[$propName] = 1
                    if (($probe.Elapsed.TotalMilliseconds * $items.Count) -gt $budgetMs) { [void]$skip.Add($propName); continue }
                }
                else { $propVal = $prop.Value }
                # ToString on a list is just its type name, so a search for a value inside an array column never matches.
                # [PsUi.ValueKind] rather than Get-UiValueKind, since this block runs in a runspace without the module and the assembly is loaded process wide.
                # The pricing above reads the property and calls ToString, so it never measures this call and the 25 and 512 caps are what bound it.
                if ($propVal) {
                    [void]$sb.Append([PsUi.ValueKind]::IndexText($propVal, 25, 512))
                    [void]$sb.Append(' ')
                }
            }
            $props.Add([System.Management.Automation.PSNoteProperty]::new('_SearchText', $sb.ToString()))
        }

        # The names that priced out, so the filter box can say what it won't match.
        $skip
    }).AddArgument($items)

    $asyncResult = $ps.BeginInvoke()

    $pollTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $pollTimer.Interval = [TimeSpan]::FromMilliseconds(50)
    $pollTimer.Tag = @{
        AsyncResult   = $asyncResult
        PowerShell    = $ps
        Runspace      = $runspace
        Tab           = $subTab
        SubTabControl = $SubTabControl
    }
    $pollTimer.Add_Tick({
        $pt = $this.Tag
        if ($pt.AsyncResult.IsCompleted) {
            $this.Stop()
            $skipped = @()
            try { $skipped = @($pt.PowerShell.EndInvoke($pt.AsyncResult)) } catch { Write-Debug "Suppressed async EndInvoke cleanup error: $_" }
            $pt.Tab.Resources['__SkippedColumns'] = $skipped
            $pt.PowerShell.Dispose()
            $pt.Runspace.Close()
            $pt.Tab.Tag = 'Indexed'

            # Only the tab on screen drives the box, or an index landing behind another tab would switch it on for the wrong one.
            $filterBox = $pt.SubTabControl.Tag
            if ($filterBox -and $pt.SubTabControl.SelectedItem -eq $pt.Tab) {
                Set-UiSubTabToolbarState -Tab $pt.Tab -FilterBox $filterBox
            }
        }
    })
    $pollTimer.Start()

    return @{
        Tab      = $subTab
        DataGrid = $subGrid
    }
}
