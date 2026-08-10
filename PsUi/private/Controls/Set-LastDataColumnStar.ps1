function Set-LastDataColumnStar {
    <#
    .SYNOPSIS
        Stretches the rightmost visible bound column to fill the viewport. Safe to rerun.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [switch]$Skip
    )

    if ($Skip) { return }

    $decoratedSet = $null
    if ($DataGrid.Resources.Contains('__EmptyCellDecoratedColumns')) {  $decoratedSet = $DataGrid.Resources['__EmptyCellDecoratedColumns'] }

    $frozenCount  = [int]$DataGrid.FrozenColumnCount
    $visibleBound = [System.Collections.Generic.List[object]]::new()
    foreach ($col in $DataGrid.Columns) {
        if ($col.Visibility -ne [System.Windows.Visibility]::Visible) { continue }
        if ($frozenCount -gt 0 -and $col.DisplayIndex -lt $frozenCount) { continue }
        $isBound = $col -is [System.Windows.Controls.DataGridTextColumn] -or
                   $col -is [System.Windows.Controls.DataGridCheckBoxColumn] -or
                   $col -is [System.Windows.Controls.DataGridComboBoxColumn]
        if (!$isBound -and $decoratedSet -and $decoratedSet.Contains($col)) { $isBound = $true }
        if ($isBound) { [void]$visibleBound.Add($col) }
    }
    if ($visibleBound.Count -eq 0) { return }

    $anyAssigned = $false
    foreach ($col in $visibleBound) { if ($col.DisplayIndex -ge 0) { $anyAssigned = $true; break } }
    $rightmost = if ($anyAssigned) { $visibleBound | Sort-Object DisplayIndex | Select-Object -Last 1 }
                 else { $visibleBound[$visibleBound.Count - 1] }

    # Reset stale Stars from prior runs (column hidden, frozen, or no longer rightmost).
    $explicitSet = $null
    if ($DataGrid.Resources.Contains('__ExplicitWidthColumns')) {  $explicitSet = $DataGrid.Resources['__ExplicitWidthColumns'] }
    foreach ($col in $DataGrid.Columns) {
        if ($col -ne $rightmost -and $col.Width.IsStar) {
            if ($explicitSet -and $explicitSet.Contains($col)) { continue }
            $col.Width = [System.Windows.Controls.DataGridLength]::Auto
        }
    }

    # Rightmost column already has a pixel width set - someone pinned it, leave it alone.
    if (!$rightmost.Width.IsAuto) { return }

    $rightmost.Width = [System.Windows.Controls.DataGridLength]::new(  1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
}
