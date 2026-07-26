function Add-UiDataGridDefaultSort {
    <#
    .SYNOPSIS
        Applies -DefaultSort. Takes 'Name', 'Name -Descending', a hashtable, or an array of those.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [Parameter(Mandatory)]
        $Sort
    )

    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($DataGrid.ItemsSource)
    if (!$view) { return }

    $entries = if ($Sort -is [System.Collections.IList] -and $Sort -isnot [string]) { @($Sort) }
               else { @(, $Sort) }

    $descriptions = [System.Collections.Generic.List[System.ComponentModel.SortDescription]]::new()
    foreach ($entry in $entries) {
        
        $prop = $null
        $dir  = [System.ComponentModel.ListSortDirection]::Ascending

        if ($entry -is [string]) {
            
            $token = $entry.Trim()
            if ($token -match '^(?<p>.+?)\s+(?<d>-?(asc|ascending|desc|descending))$') {
                $prop = $Matches['p'].Trim()
                $tail = $Matches['d'].TrimStart('-').ToLowerInvariant()
                
                if ($tail.StartsWith('desc')) { $dir = [System.ComponentModel.ListSortDirection]::Descending }
            }
            else { $prop = $token }
        }
        elseif ($entry -is [System.Collections.IDictionary]) {
           
            $prop = [string]$entry['Property']
            if (!$prop) { $prop = [string]$entry['Name'] }
            $dirText = [string]$entry['Direction']
            
            if ($dirText -and $dirText.ToLowerInvariant().StartsWith('desc')) {  $dir = [System.ComponentModel.ListSortDirection]::Descending }
        }

        if (!$prop) {
            Write-Debug "DefaultSort: skipping unparseable entry $entry"
            continue
        }
        $descriptions.Add([System.ComponentModel.SortDescription]::new($prop, $dir))
    }

    if ($descriptions.Count -eq 0) { return }

    # SortDescriptions.Add annoyingly throws on mixed types in a column (Decimal vs Double, nulls).
    # Per entry catch so one bad column doesnt kill evertyhing. The insert lands BEFORE the notify whose refresh throws, so the catch must pull the entry back out- left in, every later view refresh rethrows it unhandled (verified: one Add-UiDataGridItem after a poisoned sort took the whole host down).
    $view.SortDescriptions.Clear()
    foreach ($sd in $descriptions) {
        try { $view.SortDescriptions.Add($sd) }
        catch {
            [void]$view.SortDescriptions.Remove($sd)
            Write-Warning "DefaultSort '$($sd.PropertyName)' skipped: $($_.Exception.Message)"
        }
    }
}
