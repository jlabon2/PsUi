function Set-UiDataGridItems {
    <#
    .SYNOPSIS
        Replaces every row in a New-UiDataGrid.
    .DESCRIPTION
        Swaps the entire row set on the grid identified by -Variable. Works on both -Items
        grids (PsUi owns the collection) and -ItemsSource grids (PsUi shares your collection).
        One Reset for the whole swap, not one per row. PowerShell added properties stay
        visible. Filter and sort reapply.
    .PARAMETER Variable
        The -Variable name passed to the originating New-UiDataGrid.
    .PARAMETER Items
        The new rows. Pass @() (or $null) to wipe the grid - both mean "no rows", the same as
        anywhere else in PowerShell, so a filter that matched nothing clears the grid instead of
        throwing. Null elements inside the array are dropped: a null row is unrenderable.
    .PARAMETER PassThru
        Return the rows as they ended up in the grid. On -Items grids that's the copies PsUi
        displays. On -ItemsSource grids it's your array with null rows removed and any hashtable
        rows swapped for their converted PSCustomObjects. Changing a property on a returned row
        won't show in the cell on its own - PSCustomObject rows raise no change notifications, so
        rerun Set-UiDataGridItems to show the change.
    .EXAMPLE
        New-UiButton -Text 'Refresh' -Action {
            Set-UiDataGridItems -Variable procs -Items (Get-Process)
        }
    .EXAMPLE
        $liveRows = Set-UiDataGridItems -Variable procs -Items $batch -PassThru
        $liveRows[0].Status = 'Reviewed'   # updates the object. Set the grid again to show it
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Variable,

        # [AllowEmptyCollection()] is the magic that lets `-Items @()` through. Mandatory parameter binding rejects empty arrays by default, which makes the "wipe the grid" call site throw.
        # [AllowNull()] covers the other half: a Mandatory [object[]] also throws when the array holds a null ELEMENT. Owned grids drop it in the snapshot. The ItemsSource branch drops it in the prepare loop below (a null row rides into the shared collection otherwise - the grid filter hides it, but clear the filter and WPF tries to realize a null key and dies).
        [Parameter(Mandatory, Position = 1)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Items,

        [switch]$PassThru
    )

    $session = Get-UiSession
    if (!$session) { Write-Error 'Set-UiDataGridItems: no active PsUi session. Call it from a button action or inside a New-UiWindow.'; return }
    $collection = $session.GetListCollection($Variable)
    if ($null -eq $collection) {
        $keys = $session.GetAllListKeys() -join ', '
        Write-Error "DataGrid '$Variable' not found. Known list/grid variables: $keys"
        return
    }

    if (Test-UiDataGridOwned -Collection $collection) {
        # Snapshot keeps ETS members rendering and rebuilds the search index. Dictionaries go in RAW - the snapshot's own IDictionary branch converts them AND keeps _BaseObject on the caller's dict. Preconverting here handed it a throwaway PSCustomObject and edit writeback landed on that instead of the caller's object.
        $final = @(ConvertTo-UiDataGridSnapshot -Items $Items -BuildSearchIndex)
    }
    else {
        # ItemsSource wrap: feed raw items so the mirror holds the caller's objects - except dictionaries, which WPF binding paths can't read. IDictionary, not [hashtable]: [ordered]@{} fails the narrower check and rode this path in raw, rendering blank rows. Same rule as Add-UiDataGridItem's ItemsSource branch.
        $prepared = [System.Collections.Generic.List[object]]::new($Items.Count)
        foreach ($entry in $Items) {
            # Match the owned path - a null row is unrenderable, keep it out of the caller's mirror.
            if ($null -eq $entry) { continue }
            if ($entry -is [System.Collections.IDictionary]) { [void]$prepared.Add([PSCustomObject]$entry) }
            else                                             { [void]$prepared.Add($entry) }
        }
        $final = $prepared.ToArray()
    }

    # ReplaceAll = single Reset. Fallback path handles a stale DLL load (e.g., the .ps1 files were updated past a Build-PsUi.ps1 without restarting PS).
    $replaceAll = $collection.GetType().GetMethod('ReplaceAll')
    if ($replaceAll) {
        $typed = [System.Collections.Generic.List[object]]::new($final.Count)
        foreach ($entry in $final) { [void]$typed.Add($entry) }
        $collection.ReplaceAll($typed)
    }
    else {
        $collection.Clear()
        foreach ($entry in $final) { [void]$collection.Add($entry) }
    }

    if ($PassThru) { return $final }
}
