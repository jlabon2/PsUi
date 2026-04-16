function New-ObjectSubTab {
    <#
    .SYNOPSIS
        Creates a DataGrid sub-tab for displaying object collections.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$GroupItems,
        
        [Parameter(Mandatory)]
        [string]$TypeName,
        
        [Parameter(Mandatory)]
        [hashtable]$Colors,
        
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
    $itemList = [System.Collections.Generic.List[object]]::new($GroupItems.Count)
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
    $observable = [System.Collections.ObjectModel.ObservableCollection[object]]::new($itemList)
    $subGrid.ItemsSource = [System.Windows.Data.CollectionViewSource]::GetDefaultView($observable)
    
    $allProps = [System.Collections.Generic.List[object]]::new()
    $defaultProps = [System.Collections.Generic.List[object]]::new()
    
    if ($GroupItems.Count -gt 0) {
        $firstItem = $GroupItems[0]
        $columnResult = Add-DataGridColumns -DataGrid $subGrid -FirstItem $firstItem -Colors $Colors -IncludeActionStatus:$IncludeActionStatus
        $allProps = $columnResult.AllProperties
        $defaultProps = $columnResult.DefaultProperties
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
    
    $subTab.Content = $subGrid
    
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
        foreach ($item in $items) {
            $props = $item.PSObject.Properties
            if ($props['_SearchText']) { continue }
            $sb = [System.Text.StringBuilder]::new()
            foreach ($prop in $props) {
                if ($prop.Name.StartsWith('_')) { continue }
                $propVal = $prop.Value
                if ($propVal) { [void]$sb.Append($propVal.ToString()); [void]$sb.Append(' ') }
            }
            $props.Add([System.Management.Automation.PSNoteProperty]::new('_SearchText', $sb.ToString()))
        }
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
            try { $pt.PowerShell.EndInvoke($pt.AsyncResult) } catch { Write-Debug "Suppressed async EndInvoke cleanup error: $_" }
            $pt.PowerShell.Dispose()
            $pt.Runspace.Close()
            $pt.Tab.Tag = 'Indexed'
            
            # Enable filter box if this tab is currently selected
            $filterBox = $pt.SubTabControl.Tag
            if ($filterBox -and $pt.SubTabControl.SelectedItem -eq $pt.Tab) {
                $filterBox.IsEnabled = $true
                $filterBox.ToolTip = 'Filter results'
                if ($filterBox.Tag.Watermark) { $filterBox.Tag.Watermark.Text = 'Filter...' }
            }
        }
    })
    $pollTimer.Start()
    
    return @{
        Tab      = $subTab
        DataGrid = $subGrid
    }
}
