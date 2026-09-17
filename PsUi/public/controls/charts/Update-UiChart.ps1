function Update-UiChart {
    <#
    .SYNOPSIS
        Updates an existing chart with new data.
    .DESCRIPTION
        Pushes new data to a chart created with New-UiChart. Works from async
        button actions - the update lands on the UI thread on its own.

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
            $diskData = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
                Select-Object @{N='Label';E={$_.DeviceID}}, @{N='Value';E={[math]::Round($_.Size/1GB)}}
            Update-UiChart -Variable 'diskChart' -Data $diskData
        }
    .EXAMPLE
        # Pipeline objects with custom property names
        New-UiChart -Type Pie -Variable 'procChart' -Title 'Processes by vendor'
        New-UiButton -Text 'Scan' -NoOutput -Action {
            $procs = Get-Process | Where-Object Company | Group-Object Company |
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
    # Queue the chart rebuild onto the UI thread via Invoke-OnUIThread
    $containerRef  = $proxy.Control
    $dataRef       = $collected
    $labelOverride = $LabelProperty
    $valueOverride = $ValueProperty
    Invoke-OnUIThread {
        # Names given here replace the ones the chart was built with, since the Tag is the only place Invoke-ChartRedraw reads them from.
        $config = $containerRef.Tag
        if ($config -and $config.ControlType -eq 'Chart') {
            if ($labelOverride) { $config.LabelProperty = $labelOverride }
            if ($valueOverride) { $config.ValueProperty = $valueOverride }
        }

        # Raw rows go over, because Invoke-ChartRedraw runs ConvertTo-ChartData itself with those Tag names. Converting here as well handed it Label/Value rows that a custom -LabelProperty second pass dropped to zero, and the chart read 'No data'.
        Invoke-ChartRedraw -Container $containerRef -NewData $dataRef
    }
}
