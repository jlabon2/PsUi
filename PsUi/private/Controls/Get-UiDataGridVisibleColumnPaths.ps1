function Get-UiDataGridVisibleColumnPaths {
    <#
    .SYNOPSIS
        SortMemberPath (or Binding.Path) for every visible bound column, in onscreen order.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid
    )

    $paths = [System.Collections.Generic.List[string]]::new()

    # DisplayIndex sort so a user dragged column order matches export output.
    foreach ($col in ($DataGrid.Columns | Sort-Object DisplayIndex)) {

        if ($col.Visibility -ne [System.Windows.Visibility]::Visible) { continue }

        $path = if ($col.SortMemberPath) { [string]$col.SortMemberPath }
                elseif ($col -is [System.Windows.Controls.DataGridBoundColumn] -and $col.Binding -and $col.Binding.Path) { [string]$col.Binding.Path.Path }
                elseif ($col.ClipboardContentBinding -and $col.ClipboardContentBinding.Path) { [string]$col.ClipboardContentBinding.Path.Path }
                else { $null }

        if (!$path)                { continue }
        if ($path.StartsWith('_')) { continue }
        [void]$paths.Add($path)
    }

    return $paths
}
