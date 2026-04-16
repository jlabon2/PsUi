function Add-ChartAxisLabels {
    <#
    .SYNOPSIS
        Adds X and Y axis labels to a chart.
    #>
    param($Canvas, $Width, $Height, $Margin, $XAxisLabel, $YAxisLabel)

    # X-axis label centered, just below the data labels
    if ($XAxisLabel) {
        $xLabel = [System.Windows.Controls.TextBlock]@{
            Text       = $XAxisLabel
            FontSize   = 14
            FontWeight = 'Medium'
        }
        $xLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'ControlForegroundBrush')
        [System.Windows.Controls.Canvas]::SetLeft($xLabel, ($Width / 2) - 25)
        [System.Windows.Controls.Canvas]::SetTop($xLabel, $Height - $Margin + 22)
        [void]$Canvas.Children.Add($xLabel)
    }

    # Y-axis label rotated, positioned closer to tick values
    if ($YAxisLabel) {
        $yLabel = [System.Windows.Controls.TextBlock]@{
            Text            = $YAxisLabel
            FontSize        = 14
            FontWeight      = 'Medium'
            RenderTransform = [System.Windows.Media.RotateTransform]::new(-90)
        }
        $yLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'ControlForegroundBrush')
        [System.Windows.Controls.Canvas]::SetLeft($yLabel, 4)
        [System.Windows.Controls.Canvas]::SetTop($yLabel, ($Height / 2) + 20)
        [void]$Canvas.Children.Add($yLabel)
    }
}
