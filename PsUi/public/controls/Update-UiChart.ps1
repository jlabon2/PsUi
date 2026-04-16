function Update-UiChart {
    <#
    .SYNOPSIS
        Updates an existing chart with new data.
    .DESCRIPTION
        Pushes new data to a chart created with New-UiChart. Works from async
        button actions - the redraw is automatically dispatched to the UI thread.

        This is the explicit update path. Charts also update automatically when
        you assign new data to the chart variable inside a button action:

            $myChart = [ordered]@{ "A" = 10; "B" = 20 }

    .PARAMETER Variable
        The variable name of the chart to update (matches -Variable on New-UiChart).
    .PARAMETER Data
        New chart data in any supported format:
        - Ordered hashtable: [ordered]@{ "Label" = Value; ... }
        - Array of hashtables: @(@{ Label = "x"; Value = 1 }, ...)
        - Objects with Label/Value or Name/Count properties
    .PARAMETER LabelProperty
        Property name to use as labels when Data contains objects.
    .PARAMETER ValueProperty
        Property name to use as values when Data contains objects.
    .EXAMPLE
        New-UiButton -Text 'Refresh' -Action {
            $diskData = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
                Select-Object @{N='Label';E={$_.DeviceID}}, @{N='Value';E={[math]::Round($_.Size/1GB)}}
            Update-UiChart -Variable 'diskChart' -Data $diskData
        }
    .EXAMPLE
        # Pipeline objects with custom property names
        New-UiButton -Text 'Scan' -Action {
            $procs = Get-Process | Group-Object Company |
                Sort-Object Count -Descending | Select-Object -First 8
            Update-UiChart -Variable 'procChart' -Data $procs -LabelProperty Name -ValueProperty Count
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
    elseif ($Data -is [array]) {
        foreach ($item in $Data) { $collected.Add($item) }
    }
    else {
        $collected.Add($Data) 
    }
    $chartData = ConvertTo-ChartData -RawData $collected -LabelProperty $LabelProperty -ValueProperty $ValueProperty

    # Marshal the redraw to the UI thread via Invoke-OnUIThread
    $containerRef = $proxy.Control
    $dataRef      = $chartData
    Invoke-OnUIThread {
        Invoke-ChartRedraw -Container $containerRef -NewData $dataRef
    }
}
