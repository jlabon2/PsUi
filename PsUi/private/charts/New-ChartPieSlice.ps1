function New-ChartPieSlice {
    <#
    .SYNOPSIS
        Creates a pie slice path geometry with stroke outline.
    #>
    param($CenterX, $CenterY, $Radius, $StartAngle, $SweepAngle, $PaletteEntry)

    $startRad = $StartAngle * [math]::PI / 180
    $endRad   = ($StartAngle + $SweepAngle) * [math]::PI / 180

    $startX = $CenterX + ($Radius * [math]::Cos($startRad))
    $startY = $CenterY + ($Radius * [math]::Sin($startRad))
    $endX   = $CenterX + ($Radius * [math]::Cos($endRad))
    $endY   = $CenterY + ($Radius * [math]::Sin($endRad))

    $isLargeArc = $SweepAngle -gt 180

    $pathFigure            = [System.Windows.Media.PathFigure]::new()
    $pathFigure.StartPoint = [System.Windows.Point]::new($CenterX, $CenterY)
    $pathFigure.IsClosed   = $true

    # Line from center to arc start
    $lineToStart = [System.Windows.Media.LineSegment]::new([System.Windows.Point]::new($startX, $startY), $true)
    [void]$pathFigure.Segments.Add($lineToStart)

    # Arc segment
    $arcSegment                = [System.Windows.Media.ArcSegment]::new()
    $arcSegment.Point          = [System.Windows.Point]::new($endX, $endY)
    $arcSegment.Size           = [System.Windows.Size]::new($Radius, $Radius)
    $arcSegment.IsLargeArc     = $isLargeArc
    $arcSegment.SweepDirection = [System.Windows.Media.SweepDirection]::Clockwise
    [void]$pathFigure.Segments.Add($arcSegment)

    $pathGeometry = [System.Windows.Media.PathGeometry]::new()
    [void]$pathGeometry.Figures.Add($pathFigure)

    # Slice with subtle stroke for separation between segments
    $path = [System.Windows.Shapes.Path]@{
        Data            = $pathGeometry
        StrokeThickness = 1.5
    }
    $path.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, 'ControlBackgroundBrush')

    # Apply fill with resource binding
    Set-ChartShapeFill -Shape $path -PaletteEntry $PaletteEntry

    return $path
}
