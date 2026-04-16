function New-StyledDataGrid {
    <#
    .SYNOPSIS
        Creates a themed DataGrid with standard configuration and context menu.
    #>
    [CmdletBinding()]
    param(
        [switch]$AutoGenerateColumns,

        [switch]$SingleSelect,

        [switch]$NoSort,

        [switch]$NoContextMenu
    )

    $dataGrid = [System.Windows.Controls.DataGrid]::new()

    # Apply theme styling
    Set-DataGridStyle -Grid $dataGrid

    # Add standard context menu unless suppressed
    if (!$NoContextMenu) {
        New-DataGridContextMenu -DataGrid $dataGrid
    }

    # Standard configuration
    $dataGrid.AutoGenerateColumns      = [bool]$AutoGenerateColumns
    $dataGrid.HorizontalScrollBarVisibility = 'Auto'
    $dataGrid.VerticalScrollBarVisibility   = 'Auto'
    $dataGrid.FlowDirection            = [System.Windows.FlowDirection]::LeftToRight
    $dataGrid.CanUserSortColumns       = !$NoSort
    $dataGrid.CanUserResizeColumns     = $true

    if ($SingleSelect) {
        $dataGrid.SelectionMode = 'Single'
    }
    else {
        $dataGrid.SelectionMode = 'Extended'
    }

    return $dataGrid
}
