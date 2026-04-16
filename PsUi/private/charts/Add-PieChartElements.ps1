function Add-PieChartElements {
    <#
    .SYNOPSIS
        Renders pie chart elements onto a canvas with hover effects.
    #>
    param($Canvas, $Data, $Palette, [bool]$ShowValues)

    $width   = $Canvas.Width
    $height  = $Canvas.Height
    $centerX = $width / 2
    $centerY = $height / 2
    $radius  = [math]::Min($width, $height) / 2 - 30

    $total = ($Data | Measure-Object -Property Value -Sum).Sum
    if (!$total) { $total = 1 }

    $startAngle = -90

    for ($i = 0; $i -lt $Data.Count; $i++) {
        $item         = $Data[$i]
        $sweepAngle   = ($item.Value / $total) * 360
        $paletteEntry = $Palette[$i % $Palette.Count]
        $pct          = [math]::Round(($item.Value / $total) * 100, 1)

        # Create the pie slice with hover effects
        $slice = New-ChartPieSlice -CenterX $centerX -CenterY $centerY -Radius $radius -StartAngle $startAngle -SweepAngle $sweepAngle -PaletteEntry $paletteEntry
        $slice.Cursor  = [System.Windows.Input.Cursors]::Hand
        $slice.Opacity = 0.92
        $slice.ToolTip = "$($item.Label): $([math]::Round($item.Value, 2)) ($pct%)"

        # Calculate explode direction for hover effect
        $midAngle = $startAngle + ($sweepAngle / 2)
        $midRad   = $midAngle * [math]::PI / 180

        # Hover effect: "explode" slice outward slightly
        $slice.Add_MouseEnter({
            param($sender, $eventArgs)
            $sender.Opacity = 1.0
            # Move slice outward by 6 pixels in direction of its center
            $offsetX = 6 * [math]::Cos($midRad)
            $offsetY = 6 * [math]::Sin($midRad)
            $sender.RenderTransform = [System.Windows.Media.TranslateTransform]::new($offsetX, $offsetY)
        }.GetNewClosure())

        $slice.Add_MouseLeave({
            param($sender, $eventArgs)
            $sender.Opacity = 0.92
            $sender.RenderTransform = $null
        }.GetNewClosure())

        [void]$Canvas.Children.Add($slice)

        # Percentage label at outer edge for consistent contrast
        if ($ShowValues) {
            $labelRadius = $radius + 16
            $labelX      = $centerX + ($labelRadius * [math]::Cos($midRad))
            $labelY      = $centerY + ($labelRadius * [math]::Sin($midRad))

            $valueLabel = [System.Windows.Controls.TextBlock]@{
                Text       = "$pct%"
                FontSize   = 14
                FontWeight = 'SemiBold'
            }
            $valueLabel.SetResourceReference(
                [System.Windows.Controls.TextBlock]::ForegroundProperty,
                'ControlForegroundBrush'
            )
            [System.Windows.Controls.Canvas]::SetLeft($valueLabel, $labelX - 12)
            [System.Windows.Controls.Canvas]::SetTop($valueLabel, $labelY - 8)
            [void]$Canvas.Children.Add($valueLabel)
        }

        $startAngle += $sweepAngle
    }
}
