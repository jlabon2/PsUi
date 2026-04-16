function Add-LineChartElements {
    <#
    .SYNOPSIS
        Renders line chart elements onto a canvas with hover effects.
    #>
    param($Canvas, $Data, $Palette, [bool]$ShowValues, $XAxisLabel, $YAxisLabel)

    $width  = $Canvas.Width
    $height = $Canvas.Height
    $margin = 50
    $count  = $Data.Count

    $maxValue = ($Data | Measure-Object -Property Value -Maximum).Maximum
    if (!$maxValue) { $maxValue = 1 }

    $chartWidth  = $width - ($margin * 2)
    $chartHeight = $height - ($margin * 2)
    $pointGap    = $chartWidth / [math]::Max(1, $count - 1)

    # For large datasets, reduce point markers and labels
    $showDots       = $count -le 100
    $showDataLabels = $count -le 20
    $labelInterval  = [math]::Max(1, [math]::Ceiling($count / 10))
    $labelWidth     = [math]::Max(20, $pointGap - 4)

    $paletteEntry = $Palette[0]

    # Draw Y-axis
    $yAxis = [System.Windows.Shapes.Line]@{
        X1 = $margin; Y1 = $margin; X2 = $margin; Y2 = $height - $margin
        StrokeThickness = 1
    }
    $yAxis.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, 'ControlForegroundBrush')
    [void]$Canvas.Children.Add($yAxis)

    # Draw X-axis
    $xAxis = [System.Windows.Shapes.Line]@{
        X1 = $margin; Y1 = $height - $margin; X2 = $width - $margin; Y2 = $height - $margin
        StrokeThickness = 1
    }
    $xAxis.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, 'ControlForegroundBrush')
    [void]$Canvas.Children.Add($xAxis)

    # Build polyline points first
    $points = [System.Windows.Media.PointCollection]::new()
    for ($i = 0; $i -lt $count; $i++) {
        $item = $Data[$i]
        $x    = $margin + ($i * $pointGap)
        $y    = $height - $margin - (($item.Value / $maxValue) * $chartHeight)
        [void]$points.Add([System.Windows.Point]::new($x, $y))
    }

    # Draw area fill under the line for visual depth
    if ($count -gt 1) {
        $areaFigure            = [System.Windows.Media.PathFigure]::new()
        $areaFigure.StartPoint = [System.Windows.Point]::new($margin, $height - $margin)
        $areaFigure.IsClosed   = $true

        foreach ($pt in $points) {
            [void]$areaFigure.Segments.Add([System.Windows.Media.LineSegment]::new($pt, $true))
        }
        [void]$areaFigure.Segments.Add([System.Windows.Media.LineSegment]::new(
            [System.Windows.Point]::new($points[$count - 1].X, $height - $margin), $true))

        $areaGeometry = [System.Windows.Media.PathGeometry]::new()
        [void]$areaGeometry.Figures.Add($areaFigure)

        $areaPath = [System.Windows.Shapes.Path]@{
            Data    = $areaGeometry
            Opacity = 0.15
        }
        Set-ChartShapeFill -Shape $areaPath -PaletteEntry $paletteEntry
        [void]$Canvas.Children.Add($areaPath)
    }

    # Draw the connecting line
    $polyline = [System.Windows.Shapes.Polyline]@{
        Points          = $points
        StrokeThickness = 2
        StrokeLineJoin  = 'Round'
    }
    if ($paletteEntry.ResourceKey) {
        $polyline.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, $paletteEntry.ResourceKey)
    }
    else {
        $polyline.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFrom($paletteEntry.Fallback)
    }
    [void]$Canvas.Children.Add($polyline)

    # Draw point markers and labels (after line so they appear on top)
    for ($i = 0; $i -lt $count; $i++) {
        $item = $Data[$i]
        $x    = $points[$i].X
        $y    = $points[$i].Y

        # Point marker with hover effect (skip for huge datasets)
        if ($showDots) {
            $dot = [System.Windows.Shapes.Ellipse]@{
                Width  = 8
                Height = 8
                Cursor = [System.Windows.Input.Cursors]::Hand
            }
            Set-ChartShapeFill -Shape $dot -PaletteEntry $paletteEntry
            $dot.Stroke          = [System.Windows.Media.Brushes]::White
            $dot.StrokeThickness = 1.5
            [System.Windows.Controls.Canvas]::SetLeft($dot, $x - 4)
            [System.Windows.Controls.Canvas]::SetTop($dot, $y - 4)

            # Tooltip with label and value
            $dot.ToolTip = "$($item.Label): $([math]::Round($item.Value, 2))"

            # Hover effect: grow the point
            $dot.Add_MouseEnter({
                param($sender, $eventArgs)
                $sender.Width  = 12
                $sender.Height = 12
                [System.Windows.Controls.Canvas]::SetLeft($sender, [System.Windows.Controls.Canvas]::GetLeft($sender) - 2)
                [System.Windows.Controls.Canvas]::SetTop($sender, [System.Windows.Controls.Canvas]::GetTop($sender) - 2)
            }.GetNewClosure())

            $dot.Add_MouseLeave({
                param($sender, $eventArgs)
                $sender.Width  = 8
                $sender.Height = 8
                [System.Windows.Controls.Canvas]::SetLeft($sender, [System.Windows.Controls.Canvas]::GetLeft($sender) + 2)
                [System.Windows.Controls.Canvas]::SetTop($sender, [System.Windows.Controls.Canvas]::GetTop($sender) + 2)
            }.GetNewClosure())

            [void]$Canvas.Children.Add($dot)
        }

        # X-axis labels at intervals in ViewBox for auto-shrinking
        if ($i % $labelInterval -eq 0) {
            $label = [System.Windows.Controls.TextBlock]@{
                Text       = $item.Label
                FontSize   = 13
                FontWeight = 'Medium'
            }
            $label.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'ControlForegroundBrush')

            $viewBox = [System.Windows.Controls.Viewbox]@{
                Width            = $labelWidth
                Height           = 20
                Stretch          = 'Uniform'
                StretchDirection = 'DownOnly'
                Child            = $label
            }
            [System.Windows.Controls.Canvas]::SetLeft($viewBox, $x - ($labelWidth / 2))
            [System.Windows.Controls.Canvas]::SetTop($viewBox, $height - $margin + 3)
            [void]$Canvas.Children.Add($viewBox)
        }

        # Value labels with slope-aware positioning to avoid line clipping
        if ($ShowValues -and $showDataLabels) {
            $valueLabel = [System.Windows.Controls.TextBlock]@{
                Text       = [string][math]::Round($item.Value, 1)
                FontSize   = 11
                FontWeight = 'Medium'
            }
            $valueLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'ControlForegroundBrush')

            # Determine slope direction by comparing to neighbors
            $prevValue  = if ($i -gt 0) { $Data[$i - 1].Value } else { $item.Value }
            $nextValue  = if ($i -lt $count - 1) { $Data[$i + 1].Value } else { $item.Value }
            $isLocalMax = $item.Value -ge $prevValue -and $item.Value -ge $nextValue
            $isLocalMin = $item.Value -le $prevValue -and $item.Value -le $nextValue
            $isRising   = $prevValue -lt $item.Value

            # Horizontal offset: first point right, last point left, peaks centered
            $labelX = if ($i -eq 0) { $x + 6 }
                      elseif ($i -eq $count - 1) { $x - 20 }
                      elseif ($isLocalMax -or $isLocalMin) { $x - 8 }
                      elseif ($isRising) { $x - 14 }
                      else { $x + 2 }

            # Vertical offset: local minima go well below the point to clear line segments
            $placeBelow = $isLocalMin -or ($i -eq $count - 1 -and $item.Value -lt $prevValue)
            $labelY = if ($placeBelow) { $y + 12 } else { $y - 14 }

            [System.Windows.Controls.Canvas]::SetLeft($valueLabel, $labelX)
            [System.Windows.Controls.Canvas]::SetTop($valueLabel, $labelY)
            [void]$Canvas.Children.Add($valueLabel)
        }
    }

    Add-ChartYAxisTicks -Canvas $Canvas -MaxValue $maxValue -ChartHeight $chartHeight -Margin $margin -Height $height
    Add-ChartAxisLabels -Canvas $Canvas -Width $width -Height $height -Margin $margin -XAxisLabel $XAxisLabel -YAxisLabel $YAxisLabel
}
