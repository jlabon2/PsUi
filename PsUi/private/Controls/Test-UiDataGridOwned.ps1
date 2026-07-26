function Test-UiDataGridOwned {
    <#
    .SYNOPSIS
        True when the grid owns its collection (vs a supplied -ItemsSource). 
        Prevents performing maniuplation that would later break an unowned observablecollection.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        $Collection
    )

    if ($null -eq $Collection) { return $false }
    return $Collection.GetType().ToString() -eq 'PsUi.GridOwnedCollection`1[System.Object]'
}
