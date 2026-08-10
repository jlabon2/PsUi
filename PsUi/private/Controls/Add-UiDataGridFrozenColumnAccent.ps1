function Add-UiDataGridFrozenColumnAccent {
    <#
    .SYNOPSIS
        Vertical 2px accent line between the last frozen column and the scrolling region.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [Parameter(Mandatory)]
        [int]$FrozenColumns
    )

    if ($FrozenColumns -le 0 -or $DataGrid.Columns.Count -eq 0) { return }

    $resolveRightmost = {
        # Highest visible DisplayIndex inside the frozen range, not the exact edge index. Filtering on Visibility keeps the accent off a hidden column. Taking the max keeps it drawing when HideEmptyColumns collapsed the edge column itself.
        $DataGrid.Columns | Where-Object {
            $_.DisplayIndex -le ($FrozenColumns - 1) -and
            $_.Visibility -eq [System.Windows.Visibility]::Visible
        } | Sort-Object DisplayIndex -Descending | Select-Object -First 1
    }.GetNewClosure()

    $rightmost = & $resolveRightmost
    if (!$rightmost) { return }

    $thickness = [System.Windows.Thickness]::new(0, 0, 2, 0)

    # Brush in the grid's Resources stays themeable. Stuffing it in a Style freezes it and severs the DynamicResource link to AccentColor.
    $resourceKey = '__FrozenColumnFadedAccent'
    if (!$DataGrid.Resources.Contains($resourceKey)) {
        $faded = [System.Windows.Markup.XamlReader]::Parse(@'
<SolidColorBrush xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 Color="{DynamicResource AccentColor}"
                 Opacity="0.5"/>
'@)
        $DataGrid.Resources.Add($resourceKey, $faded)
    }

    # Reapply when columns reorder so the accent follows the new frozen edge.
    $applyAccent = {
        param($targetCol)
        if (!$targetCol) { return }

        $cellAccentRef   = [System.Windows.DynamicResourceExtension]::new($resourceKey)
        $headerAccentRef = [System.Windows.DynamicResourceExtension]::new($resourceKey)

        # Base the new style on whatever cell style is already there so the theme's hover and selection states don't get wiped along with the border setters.
        $baseCellStyle = $targetCol.CellStyle
        if (!$baseCellStyle) { $baseCellStyle = $DataGrid.CellStyle }

        $cellStyle = if ($baseCellStyle) { [System.Windows.Style]::new([System.Windows.Controls.DataGridCell], $baseCellStyle) }
                     else { [System.Windows.Style]::new([System.Windows.Controls.DataGridCell]) }

        [void]$cellStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.DataGridCell]::BorderThicknessProperty, $thickness))
        [void]$cellStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.DataGridCell]::BorderBrushProperty, $cellAccentRef))

        # Negative top/bottom margin bleeds the accent over the row gridlines so the line draws solid, not dashed. Costs a remeasure on every container recycle (negative margin invalidates the layout slot). Padding and Border background don't reach past the cell.
        [void]$cellStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.FrameworkElement]::MarginProperty, [System.Windows.Thickness]::new(0, -1.5, 0, -1.5)))

        # Selected cells get the row's highlight brush. Clear the negative margins too - otherwise they bleed onto adjacent cells when selected and the seam shows.
        $selectedTrigger          = [System.Windows.Trigger]::new()
        $selectedTrigger.Property = [System.Windows.Controls.DataGridCell]::IsSelectedProperty
        $selectedTrigger.Value    = $true
        [void]$selectedTrigger.Setters.Add([System.Windows.Setter]::new([System.Windows.FrameworkElement]::MarginProperty, [System.Windows.Thickness]::new(0)))
        [void]$cellStyle.Triggers.Add($selectedTrigger)

        $targetCol.CellStyle = $cellStyle

        $baseHeaderStyle = $targetCol.HeaderStyle
        if (!$baseHeaderStyle) { $baseHeaderStyle = $DataGrid.ColumnHeaderStyle }

        $headerStyle = if ($baseHeaderStyle) { [System.Windows.Style]::new([System.Windows.Controls.Primitives.DataGridColumnHeader], $baseHeaderStyle) }
                       else { [System.Windows.Style]::new([System.Windows.Controls.Primitives.DataGridColumnHeader]) }

        [void]$headerStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Primitives.DataGridColumnHeader]::BorderThicknessProperty, $thickness))
        [void]$headerStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Primitives.DataGridColumnHeader]::BorderBrushProperty, $headerAccentRef))

        $targetCol.HeaderStyle = $headerStyle
    }.GetNewClosure()

    & $applyAccent $rightmost

    # Reorder retargets the accent. Strip styles off the previous rightmost on the way through so the line doesn't double up if the user drags the frozen edge column elsewhere.
    $previousRightmost = @{ Col = $rightmost }
    $DataGrid.add_ColumnReordered({
        param($sender, $eventArgs)
        $newRightmost = & $resolveRightmost
        if (!$newRightmost -or $newRightmost -eq $previousRightmost.Col) { return }

        if ($previousRightmost.Col) {
            try { $previousRightmost.Col.CellStyle = $null } catch { }
            try { $previousRightmost.Col.HeaderStyle = $null } catch { }
        }
        & $applyAccent $newRightmost
        $previousRightmost.Col = $newRightmost
    }.GetNewClosure())
}
