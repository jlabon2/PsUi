<#
.SYNOPSIS
    Creates a Key/Value DataGrid sub-tab for dictionary-type items.
#>
function New-DictionarySubTab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IList]$GroupItems,
        
        [Parameter(Mandatory)]
        [string]$TypeName,
        
        [Parameter(Mandatory)]
        [hashtable]$Colors,
        
        [switch]$IsDictionaryEntry
    )
    
    # Create styled DataGrid (no sort for dictionaries)
    $subGrid = New-StyledDataGrid -NoSort
    $subGrid.AutoGenerateColumns = $false
    
    $keyCol = [System.Windows.Controls.DataGridTextColumn]::new()
    $keyCol.Header = 'Key'
    $keyCol.Binding = [System.Windows.Data.Binding]::new('Key')
    [void]$subGrid.Columns.Add($keyCol)
    
    $valCol = New-ExpandableValueColumn -Colors $Colors
    [void]$subGrid.Columns.Add($valCol)
    
    $list = [System.Collections.Generic.List[object]]::new()
    
    if ($IsDictionaryEntry) {
        # DictionaryEntry items - each item is a key/value pair
        foreach ($entry in $GroupItems) {
            $rawVal = $entry.Value
            $displayValue = ConvertTo-DisplayValue -Value $rawVal
            $isExpandable = ($rawVal -is [System.Collections.IDictionary]) -or ($rawVal -is [array])
            $list.Add([PSCustomObject]@{
                Key           = $entry.Key
                Value         = $displayValue
                _RawValue     = $rawVal
                _IsExpandable = $isExpandable
                _SearchText   = "$($entry.Key) $displayValue"
            })
        }
    }
    else {
        # IDictionary items - each item is a full dictionary, enumerate its keys
        foreach ($dict in $GroupItems) {
            foreach ($key in $dict.Keys) {
                $rawVal = $dict[$key]
                $displayValue = ConvertTo-DisplayValue -Value $rawVal
                $isExpandable = ($rawVal -is [System.Collections.IDictionary]) -or ($rawVal -is [array])
                $list.Add([PSCustomObject]@{
                    Key           = $key
                    Value         = $displayValue
                    _RawValue     = $rawVal
                    _IsExpandable = $isExpandable
                    _SearchText   = "$key $displayValue"
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
    
    Add-DictionaryValuePopupHandler -DataGrid $subGrid
    
    $subTab = [System.Windows.Controls.TabItem]::new()
    $subTab.Header = "$TypeName ($($GroupItems.Count))"
    Set-TabItemStyle -TabItem $subTab
    $subTab.Content = $subGrid
    $subTab.Tag = 'Dictionary'
    
    return @{
        Tab      = $subTab
        DataGrid = $subGrid
    }
}
