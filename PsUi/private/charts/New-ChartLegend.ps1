function New-ChartLegend {
    <#
    .SYNOPSIS
        Creates a legend panel for pie charts.
    #>
    param($Data, $Palette)

    $legend = [System.Windows.Controls.WrapPanel]@{
        Orientation         = 'Horizontal'
        HorizontalAlignment = 'Center'
        Margin              = [System.Windows.Thickness]::new(0, 8, 0, 0)
    }

    for ($i = 0; $i -lt $Data.Count; $i++) {
        $item         = $Data[$i]
        $paletteEntry = $Palette[$i % $Palette.Count]

        $entry = [System.Windows.Controls.StackPanel]@{
            Orientation = 'Horizontal'
            Margin      = [System.Windows.Thickness]::new(8, 2, 8, 2)
        }

        $swatch = [System.Windows.Shapes.Rectangle]@{
            Width  = 14
            Height = 14
            Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
        }
        Set-ChartShapeFill -Shape $swatch -PaletteEntry $paletteEntry
        [void]$entry.Children.Add($swatch)

        $label = [System.Windows.Controls.TextBlock]@{
            Text     = $item.Label
            FontSize = 12
        }
        $label.SetResourceReference(
            [System.Windows.Controls.TextBlock]::ForegroundProperty,
            'ControlForegroundBrush'
        )
        [void]$entry.Children.Add($label)

        [void]$legend.Children.Add($entry)
    }

    return $legend
}
