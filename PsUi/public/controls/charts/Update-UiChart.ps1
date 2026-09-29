function Update-UiChart {
    <#
    .SYNOPSIS
        Updates an existing chart with new data.
    .DESCRIPTION
        Pushes new data to a chart created with New-UiChart. Works from async
        button actions since the update runs on the UI thread on its own.

        This is the explicit update path. Charts also update automatically when
        you assign an ordered hashtable of new data to the chart variable inside a
        button action.

    .PARAMETER Variable
        The variable name of the chart to update (matches -Variable on New-UiChart).
    .PARAMETER Data
        New chart data in any supported format:
        - Ordered hashtable: [ordered]@{ "Label" = Value; ... }
        - Array of hashtables: @(@{ Label = "x"; Value = 1 }, ...)
        - Objects with Label/Value or Name/Count properties (Key also resolves for
          labels, Sum and Total for values)
    .PARAMETER LabelProperty
        Property name to use as labels when Data contains objects. It sticks to the chart, so
        a later update that omits it keeps using this name.
    .PARAMETER ValueProperty
        Property name to use as values when Data contains objects. Sticks the same way.
    .EXAMPLE
        New-UiChart -Type Bar -Variable 'diskChart' -Title 'Disk size (GB)'
        New-UiButton -Text 'Refresh' -NoOutput -Action {
            $diskData = [ordered]@{}
            foreach ($disk in Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3") {
                $diskData[$disk.DeviceID] = [math]::Round($disk.Size / 1GB)
            }
            Update-UiChart -Variable 'diskChart' -Data $diskData
        }
    .EXAMPLE
        # Pipeline objects with custom property names
        New-UiChart -Type Pie -Variable 'procChart' -Title 'Processes by vendor'
        New-UiButton -Text 'Scan' -NoOutput -Action {
            $procs = Get-Process | Where-Object Company | Group-Object Company | Sort-Object Count -Descending
            Update-UiChart -Variable 'procChart' -Data $procs[0..7] -LabelProperty Name -ValueProperty Count
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Variable,

        [Parameter(Mandatory)]
        $Data,

        [string]$LabelProperty,

        [string]$ValueProperty
    )

    $session = Get-UiSession
    if (!$session) {
        Write-Warning "No active UI session."
        return
    }

    $proxy = $session.GetSafeVariable($Variable)
    if (!$proxy) {
        Write-Warning "Chart variable '$Variable' not found in session."
        return
    }

    # Normalize data to consistent [{Label, Value}] format
    $collected = [System.Collections.Generic.List[object]]::new()
    if ($Data -is [System.Collections.IDictionary]) {
        foreach ($key in $Data.Keys) {
            $collected.Add(@{ Label = $key; Value = $Data[$key] })
        }
    }
    elseif ($Data -is [System.Collections.IList]) {
        foreach ($item in $Data) { $collected.Add($item) }
    }
    else {
        $collected.Add($Data)
    }

    $chart     = $proxy.Control
    $builtWith = Invoke-OnUIThread -ArgumentList $chart -ScriptBlock {
        param($chart)
        $config = $chart.Tag
        if ($config -and $config.ControlType -eq 'Chart') { @{ Label = $config.LabelProperty; Value = $config.ValueProperty } }
    }
    $labelName = if ($LabelProperty) { $LabelProperty } else { $builtWith.Label }
    $valueName = if ($ValueProperty) { $ValueProperty } else { $builtWith.Value }

    # The rows get read in the runspace that built them since a ScriptProperty read from the UI thread waits 250ms a row.
    # Invoke-ChartRedraw converts again with the Tag names... only a hashtable carrying Label and Value keys survives that pass
    $points = [System.Collections.Generic.List[object]]::new()
    foreach ($point in (ConvertTo-ChartData -RawData $collected -LabelProperty $labelName -ValueProperty $valueName)) {
        $points.Add(@{ Label = $point.Label; Value = $point.Value })
    }

    $redraw = @($chart, $points, $LabelProperty, $ValueProperty)
    Invoke-OnUIThread -ArgumentList $redraw -ScriptBlock {
        param($containerRef, $dataRef, $labelOverride, $valueOverride)

        # Names given here replace the ones the chart was built with, since the Tag is the only place Invoke-ChartRedraw reads them from.
        $config = $containerRef.Tag
        if ($config -and $config.ControlType -eq 'Chart') {
            if ($labelOverride) { $config.LabelProperty = $labelOverride }
            if ($valueOverride) { $config.ValueProperty = $valueOverride }
        }

        Invoke-ChartRedraw -Container $containerRef -NewData $dataRef
    }
}
