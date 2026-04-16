function Invoke-ChartRedraw {
    <#
    .SYNOPSIS
        Redraws a chart container with new data. Must run on the UI thread.
    #>
    param(
        [System.Windows.Controls.DockPanel]$Container,
        $NewData
    )

    # Read chart config from container Tag
    $config = $Container.Tag
    if (!$config -or $config.ControlType -ne 'Chart') { return }

    # Walk the DockPanel to find the Viewbox containing our canvas
    $canvas = $null
    foreach ($child in $Container.Children) {
        if ($child -is [System.Windows.Controls.Viewbox]) {
            $canvas = $child.Child
            break
        }
    }
    if (!$canvas) { return }

    # Normalize raw data into consistent [{Label, Value}] format.
    # Handles OrderedDictionary from hydration, arrays, and already-normalized data.
    $collected = [System.Collections.Generic.List[object]]::new()
    if ($NewData -is [System.Collections.IList]) {
        foreach ($item in $NewData) { $collected.Add($item) }
    }
    elseif ($NewData -is [System.Collections.IDictionary]) {
        foreach ($key in $NewData.Keys) {
            $collected.Add(@{ Label = $key; Value = $NewData[$key] })
        }
    }
    elseif ($null -ne $NewData) {
        $collected.Add($NewData)
    }
    $chartData = ConvertTo-ChartData -RawData $collected -LabelProperty $config.LabelProperty -ValueProperty $config.ValueProperty

    # Clear existing chart content
    $canvas.Children.Clear()

    # Empty data shows a placeholder message
    if (!$chartData -or $chartData.Count -eq 0) {
        $placeholder = [System.Windows.Controls.TextBlock]@{
            Text      = 'No data'
            FontSize  = 18
            FontStyle = 'Italic'
            Opacity   = 0.4
        }
        $placeholder.SetResourceReference(
            [System.Windows.Controls.TextBlock]::ForegroundProperty,
            'ControlForegroundBrush'
        )
        [System.Windows.Controls.Canvas]::SetLeft($placeholder, ($canvas.Width / 2) - 30)
        [System.Windows.Controls.Canvas]::SetTop($placeholder, ($canvas.Height / 2) - 12)
        [void]$canvas.Children.Add($placeholder)

        # Null data for hydration - chart variable reads as $null when empty
        [PsUi.UiHydration]::SetData($Container, $null)
        return
    }

    # Grab current theme palette
    $palette = Get-ChartPalette

    # Dispatch to the appropriate chart renderer
    $renderParams = @{
        Canvas     = $canvas
        Data       = $chartData
        Palette    = $palette
        ShowValues = [bool]$config.ShowValues
        XAxisLabel = $config.XAxisLabel
        YAxisLabel = $config.YAxisLabel
    }

    switch ($config.ChartType) {
        'Bar'  { Add-BarChartElements @renderParams }
        'Line' { Add-LineChartElements @renderParams }
        'Pie'  { Add-PieChartElements @renderParams }
    }

    # Pie charts need their legend rebuilt with the new data
    if ($config.ChartType -eq 'Pie' -and $config.ShowLegend) {
        # Remove stale legend
        $oldLegend = $null
        foreach ($child in $Container.Children) {
            if ($child -is [System.Windows.Controls.WrapPanel]) {
                $oldLegend = $child
                break
            }
        }
        if ($oldLegend) { [void]$Container.Children.Remove($oldLegend) }

        # Insert new legend just before the Viewbox (last child fills remaining space)
        $legend = New-ChartLegend -Data $chartData -Palette $palette
        [System.Windows.Controls.DockPanel]::SetDock($legend, [System.Windows.Controls.Dock]::Bottom)
        $viewboxIndex = $Container.Children.Count - 1
        $Container.Children.Insert($viewboxIndex, $legend)
    }

    # Store as hashtables for hydration (survives cross-runspace injection)
    $storableData = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($item in $chartData) {
        $storableData.Add(@{ Label = $item.Label; Value = $item.Value })
    }
    [PsUi.UiHydration]::SetData($Container, $storableData)
}
