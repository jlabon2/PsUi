function Add-UiDataGridItem {
    <#
    .SYNOPSIS
        Appends a row to a New-UiDataGrid.
    .DESCRIPTION
        Appends a row to the grid identified by -Variable. Works on both -Items grids (PsUi
        owns the collection) and -ItemsSource grids (PsUi shares your collection). Hashtables
        convert to PSCustomObject. PowerShell added properties (Process.Company,
        Service.DisplayName, etc.) stay visible. Filter and sort apply to the new row.
    .PARAMETER Variable
        The -Variable name passed to the originating New-UiDataGrid.
    .PARAMETER Item
        The row object to append. Hashtables get converted to PSCustomObject. Everything else
        is added as is.
    .PARAMETER PassThru
        Return the row as it shows up. On -Items grids that's the copy PsUi displays.
        On -ItemsSource grids it's the object you passed in (hashtables come back as 
        the converted PSCustomObject). Changing a property on the returned row won't
        refresh the cell by itself, PSCustomObject rows raise no change notifications, 
        so rerun Set-UiDataGridItems (or remove and add it again) to show the new value.
    .EXAMPLE
        Add-UiDataGridItem -Variable queue -Item @{ User='john'; Status='Pending' }
    .EXAMPLE
        $row = Add-UiDataGridItem -Variable queue -Item $entry -PassThru
        $row.Status = 'Done'   # updates the object - set the grid again to redraw it
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Variable,

        [Parameter(Mandatory, Position = 1)]
        [object]$Item,

        [switch]$PassThru
    )

    $session = Get-UiSession
    if (!$session) { Write-Error 'Add-UiDataGridItem: no active PsUi session. Call it from a button action or inside a New-UiWindow.'; return }
    
    $collection = $session.GetListCollection($Variable)
    
    if ($null -eq $collection) {
        $keys = $session.GetAllListKeys() -join ', '
        Write-Error "DataGrid '$Variable' not found. Known list/grid variables: $keys"
        return
    }

    if (Test-UiDataGridOwned -Collection $collection) {
        # Snapshot preserves extended members (Process.Company, Service.DisplayName, etc.) and builds the cached _SearchText the filter looks at, and converts dictionaries so the row's WPF bindings can see properties.
        $snapped = @(ConvertTo-UiDataGridSnapshot -Items @($Item) -BuildSearchIndex)
        if ($snapped.Count -eq 0) { return }
        [void]$collection.Add($snapped[0])
        if ($PassThru) { return $snapped[0] }
    }
    else {
        # ItemsSource wrap. Your object lands in your collection through the mirror, so keep it exact, except IDictionary.
        # WPF binding paths can't see hashtable keys (the row rendered blank), and the help promises the conversion, so the PSCustomObject is what goes into grid AND mirror.
        # -PassThru returns what the grid actually holds.
        if ($Item -is [System.Collections.IDictionary]) { $Item = [PSCustomObject]$Item }
        [void]$collection.Add($Item)
        if ($PassThru) { return $Item }
    }
}
