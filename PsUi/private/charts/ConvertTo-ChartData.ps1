function ConvertTo-ChartData {
    <#
    .SYNOPSIS
        Normalizes various data formats to a consistent chart data structure.
    #>
    param($RawData, $LabelProperty, $ValueProperty)

    $result = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($item in $RawData) {
        # A null data point has no PSObject.Properties, so indexing it below'll throw "cannot index into a null array". Both New-UiChart and Update-UiChart funnel raw -Data through here, so one skip covers both entry points.
        if ($null -eq $item) { continue }

        $label = $null
        $value = $null

        # Already normalized from hashtable processing
        if ($item -is [hashtable] -and $item.ContainsKey('Label') -and $item.ContainsKey('Value')) {
            $label = $item.Label
            $value = $item.Value
        }
        else {
            # Try explicit property names first, then common defaults
            $labelProps = if ($LabelProperty) { @($LabelProperty) } else { @('Label', 'Name', 'Key') }
            $valueProps = if ($ValueProperty) { @($ValueProperty) } else { @('Value', 'Count', 'Sum', 'Total') }

            # A raw hashtable's data keys live on IDictionary, not PSObject.Properties and that only carries the .NET Hashtable members (Keys, Count, ...). INspect directly so a plain @{ Name = 'apple'; Count = 5 } resolves instead of silently charting nothing.
            # Generic Dictionary hides .Contains behind an explicit implementation that only finds when the call is typed IDictionary. Capturing the cast into a variable loses it and the call throws again.
            $isDict = $item -is [System.Collections.IDictionary]

            foreach ($prop in $labelProps) {
                if ($isDict) {
                    if (([System.Collections.IDictionary]$item).Contains($prop)) { $label = $item[$prop]; break }
                }
                elseif ($item.PSObject.Properties[$prop]) {
                    $label = $item.$prop
                    break
                }
            }

            foreach ($prop in $valueProps) {
                if ($isDict) {
                    if (([System.Collections.IDictionary]$item).Contains($prop)) { $value = $item[$prop]; break }
                }
                elseif ($item.PSObject.Properties[$prop]) {
                    $value = $item.$prop
                    break
                }
            }
        }

        if ($null -ne $label -and $null -ne $value) {
            # '-as [double]' returns $null instead of erroring out on any other input, so one messed up data point won't bring down the whole chart down with it.
            # NaN/Infinity survive the cast though (a ratio on an empty set, x/0 in double math), so check for them too or the bar height and axis scaling go nuts.
            $numeric = $value -as [double]
            if ($null -ne $numeric -and ![double]::IsNaN($numeric) -and ![double]::IsInfinity($numeric)) {
                $result.Add([PSCustomObject]@{
                    Label = [string]$label
                    Value = $numeric
                })
            }
        }
    }

    return $result
}
