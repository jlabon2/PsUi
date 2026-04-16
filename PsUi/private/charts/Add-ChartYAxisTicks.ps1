function Add-ChartYAxisTicks {
    <#
    .SYNOPSIS
        Adds Y-axis scale labels to a chart.
    #>
    param($Canvas, $MaxValue, $ChartHeight, $Margin, $Height)

    $tickCount = 4
    for ($t = 0; $t -le $tickCount; $t++) {
        $tickValue = [math]::Round(($MaxValue / $tickCount) * $t, 1)
        $tickY     = $Height - $Margin - (($t / $tickCount) * $ChartHeight)

        $tickLabel = [System.Windows.Controls.TextBlock]@{
            Text                = [string]$tickValue
            FontSize            = 12
            FontWeight          = 'Medium'
            TextAlignment       = 'Right'
            Width               = 36
        }
        $tickLabel.SetResourceReference(
            [System.Windows.Controls.TextBlock]::ForegroundProperty,
            'ControlForegroundBrush'
        )
        [System.Windows.Controls.Canvas]::SetLeft($tickLabel, $Margin - 40)
        [System.Windows.Controls.Canvas]::SetTop($tickLabel, $tickY - 6)
        [void]$Canvas.Children.Add($tickLabel)
    }
}
