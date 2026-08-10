function Get-UiDataGridEmptyCellHatchBrush {
    <#
    .SYNOPSIS
        Builds the diagonal brush used by MarkEmptyCells.
    #>
    [CmdletBinding()]
    param(
        [switch]$SelectedVariant
    )

    # The pen's brush wont take a DynamicResource link when set from code, only the XAML parser resolves it correctly.
    $brushKey = if ($SelectedVariant) { 'SelectionTextBrush' } else { 'SecondaryTextBrush' }
    $opacity  = if ($SelectedVariant) { '0.65' } else { '0.45' }

    $xaml = @"
<DrawingBrush xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
              xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
              Stretch="Uniform" TileMode="Tile"
              Viewport="0,0,6,6" ViewportUnits="Absolute"
              Viewbox="0,0,6,6" ViewboxUnits="Absolute"
              Opacity="$opacity">
    <DrawingBrush.Drawing>
        <GeometryDrawing>
            <GeometryDrawing.Pen>
                <Pen Thickness="1" Brush="{DynamicResource $brushKey}"/>
            </GeometryDrawing.Pen>
            <GeometryDrawing.Geometry>
                <LineGeometry StartPoint="0,6" EndPoint="6,0"/>
            </GeometryDrawing.Geometry>
        </GeometryDrawing>
    </DrawingBrush.Drawing>
</DrawingBrush>
"@

    return [System.Windows.Markup.XamlReader]::Parse($xaml)
}
