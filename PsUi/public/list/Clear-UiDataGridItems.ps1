function Clear-UiDataGridItems {
    <#
    .SYNOPSIS
        Empties a New-UiDataGrid.
    .DESCRIPTION
        Empties the row collection on the grid identified by -Variable. Works on both -Items
        grids and -ItemsSource grids. On -ItemsSource grids your own collection gets cleared
        too. 
    .PARAMETER Variable
        The -Variable name passed to the originating New-UiDataGrid.
    .EXAMPLE
        Clear-UiDataGridItems -Variable queue
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Variable
    )

    $session = Get-UiSession
    
    if (!$session) { Write-Error 'Clear-UiDataGridItems: no active PsUi session. Call it from a button action or inside a New-UiWindow.'; return }
    
    $collection = $session.GetListCollection($Variable)
    
    if ($null -eq $collection) {
        $keys = $session.GetAllListKeys() -join ', '
        Write-Error "DataGrid '$Variable' not found. Known list/grid variables: $keys"
        return
    }

    $collection.Clear()
}
