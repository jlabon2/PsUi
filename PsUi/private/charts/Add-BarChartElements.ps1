function Add-BarChartElements {
    <#
    .SYNOPSIS
        Renders bar chart elements onto a canvas with hover effects.
    #>
    param($Canvas, $Data, $Palette, [bool]$ShowValues, $XAxisLabel, $YAxisLabel)

    $width      = $Canvas.Width
    $height     = $Canvas.Height
    $margin     = 50
    $barSpacing = 4
    $count      = $Data.Count

    # Limit bar width for large datasets
    $maxBarWidth = 60
    $minBarWidth = 2

    $maxValue = ($Data | Measure-Object -Property Value -Maximum).Maximum
    if (!$maxValue) { $maxValue = 1 }

    $chartWidth  = $width - ($margin * 2)
    $chartHeight = $height - ($margin * 2)
    $rawBarWidth = ($chartWidth - ($barSpacing * ($count - 1))) / $count
    $barWidth    = [math]::Max($minBarWidth, [math]::Min($maxBarWidth, $rawBarWidth))

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

    # Calculate label width for ViewBox sizing
    $showDataLabels = $count -le 30
    $labelWidth     = if ($showDataLabels) { [math]::Max(10, $barWidth + $barSpacing - 2) } else { 0 }

    # Draw bars with hover effects
    for ($i = 0; $i -lt $count; $i++) {
        $item         = $Data[$i]
        $barHeight    = [math]::Max(1, ($item.Value / $maxValue) * $chartHeight)
        $x            = $margin + ($i * ($barWidth + $barSpacing))
        $y            = $height - $margin - $barHeight
        $paletteEntry = $Palette[$i % $Palette.Count]

        # Bar with rounded top corners for polish
        $bar = [System.Windows.Shapes.Rectangle]@{
            Width   = $barWidth
            Height  = $barHeight
            RadiusX = [math]::Min(3, $barWidth / 4)
            RadiusY = [math]::Min(3, $barWidth / 4)
            Cursor  = [System.Windows.Input.Cursors]::Hand
            Opacity = 0.9
        }
        Set-ChartShapeFill -Shape $bar -PaletteEntry $paletteEntry
        [System.Windows.Controls.Canvas]::SetLeft($bar, $x)
        [System.Windows.Controls.Canvas]::SetTop($bar, $y)

        # Tooltip with label and value
        $bar.ToolTip = "$($item.Label): $([math]::Round($item.Value, 2))"

        # Hover effect: brighten and scale
        $bar.Add_MouseEnter({
            param($sender, $eventArgs)
            $sender.Opacity = 1.0
            $sender.RenderTransform = [System.Windows.Media.ScaleTransform]::new(1.05, 1.05)
            $sender.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 1.0)
        }.GetNewClosure())

        $bar.Add_MouseLeave({
            param($sender, $eventArgs)
            $sender.Opacity = 0.9
            $sender.RenderTransform = $null
        }.GetNewClosure())

        [void]$Canvas.Children.Add($bar)

        # X-axis data label in ViewBox for auto-shrinking
        if ($showDataLabels) {
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
            [System.Windows.Controls.Canvas]::SetLeft($viewBox, $x + ($barWidth / 2) - ($labelWidth / 2))
            [System.Windows.Controls.Canvas]::SetTop($viewBox, $height - $margin + 3)
            [void]$Canvas.Children.Add($viewBox)
        }

        # Value label above bar
        if ($ShowValues -and $showDataLabels) {
            $valueLabel = [System.Windows.Controls.TextBlock]@{
                Text       = [string][math]::Round($item.Value, 1)
                FontSize   = 12
                FontWeight = 'Medium'
            }
            $valueLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'ControlForegroundBrush')
            [System.Windows.Controls.Canvas]::SetLeft($valueLabel, $x + ($barWidth / 2) - 10)
            [System.Windows.Controls.Canvas]::SetTop($valueLabel, $y - 16)
            [void]$Canvas.Children.Add($valueLabel)
        }
    }

    # Y-axis tick labels and axis labels
    Add-ChartYAxisTicks -Canvas $Canvas -MaxValue $maxValue -ChartHeight $chartHeight -Margin $margin -Height $height
    Add-ChartAxisLabels -Canvas $Canvas -Width $width -Height $height -Margin $margin -XAxisLabel $XAxisLabel -YAxisLabel $YAxisLabel
}
