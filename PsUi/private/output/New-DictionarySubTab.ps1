function New-DictionarySubTab {
    <#
    .SYNOPSIS
        Creates a Key/Value DataGrid sub-tab for dictionary-type items.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IList]$GroupItems,

        [Parameter(Mandatory)]
        [string]$TypeName,

        [switch]$IsDictionaryEntry,

        [switch]$SingleSelect
    )

    # Create styled DataGrid (no sort for dictionaries)
    $selectParam = if ($SingleSelect) { @{ SingleSelect = $true } } else { @{} }
    $subGrid = New-StyledDataGrid -NoSort @selectParam
    $subGrid.AutoGenerateColumns = $false

    $keyCol = [System.Windows.Controls.DataGridTextColumn]::new()
    $keyCol.Header = 'Key'
    $keyCol.Binding = [System.Windows.Data.Binding]::new('Key')
    [void]$subGrid.Columns.Add($keyCol)

    $valCol = New-ExpandableValueColumn
    [void]$subGrid.Columns.Add($valCol)

    $list = [System.Collections.Generic.List[object]]::new()

    # The index holds the values, not the display string, or a long list indexes as [7 items] and none of its entries turn up in a search.
    if ($IsDictionaryEntry) {
        # One item per key/value pair
        foreach ($entry in $GroupItems) {
            $rawVal = $entry.Value
            $displayValue = ConvertTo-DisplayValue -Value $rawVal
            $isExpandable = [PsUi.ValueKind]::IsExpandable($rawVal)
            $list.Add([PSCustomObject]@{
                Key           = $entry.Key
                Value         = $displayValue
                _RawValue     = $rawVal
                _IsExpandable = $isExpandable
                _SearchText   = "$($entry.Key) $([PsUi.ValueKind]::IndexText($rawVal, 25, 512))"
            })
        }
    }
    else {
        foreach ($dict in $GroupItems) {
            # Only the first item of a mixed Other bucket picked this builder
            if ($dict -isnot [System.Collections.IDictionary]) { continue }
            foreach ($entry in $dict.GetEnumerator()) {
                $key    = $entry.Key
                $rawVal = $entry.Value
                $displayValue = ConvertTo-DisplayValue -Value $rawVal
                $isExpandable = [PsUi.ValueKind]::IsExpandable($rawVal)
                $list.Add([PSCustomObject]@{
                    Key           = $key
                    Value         = $displayValue
                    _RawValue     = $rawVal
                    _IsExpandable = $isExpandable
                    _SearchText   = "$key $([PsUi.ValueKind]::IndexText($rawVal, 25, 512))"
                })
            }
        }
    }

    $observable = [System.Collections.ObjectModel.ObservableCollection[object]]::new($list)
    $subGrid.ItemsSource = [System.Windows.Data.CollectionViewSource]::GetDefaultView($observable)

    # Store unfiltered items and observable for collection-based filtering
    $subGrid.Tag = @{
        UnfilteredItems = $list
        Observable      = $observable
    }

    Add-ArrayCellPopupHandler -DataGrid $subGrid
    Add-DictionaryValuePopupHandler -DataGrid $subGrid

    $subTab = [System.Windows.Controls.TabItem]::new()
    $subTab.Header = "$TypeName ($($GroupItems.Count))"
    Set-TabItemStyle -TabItem $subTab
    $subTab.Content = Add-UiDataGridEmptyOverlay -HostControl $subGrid -DataGrid $subGrid -Message 'No entries to display.'
    $subTab.Tag = 'Dictionary'

    return @{
        Tab      = $subTab
        DataGrid = $subGrid
    }
}
