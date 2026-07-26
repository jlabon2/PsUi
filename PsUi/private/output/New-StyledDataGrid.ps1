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

        [switch]$NoContextMenu,

        [switch]$NoStarResizeUnlock
    )

    $dataGrid = [System.Windows.Controls.DataGrid]::new()

    # Apply theme styling
    Set-DataGridStyle -Grid $dataGrid

    # Add standard context menu unless suppressed
    if (!$NoContextMenu) {
        New-DataGridContextMenu -DataGrid $dataGrid
    }

    # Standard config
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

    # If the last column ends up starred, WPF locks column resizing once the grid overflows. Unlock it here unless the star was suppressed.
    if (!$NoStarResizeUnlock) { Add-UiDataGridStarResizeUnlock -DataGrid $dataGrid }

    return $dataGrid
}
