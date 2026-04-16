function ConvertTo-ChartData {
    <#
    .SYNOPSIS
        Normalizes various data formats to a consistent chart data structure.
    #>
    param($RawData, $LabelProperty, $ValueProperty)

    $result = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($item in $RawData) {
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

            foreach ($prop in $labelProps) {
                if ($item.PSObject.Properties[$prop]) {
                    $label = $item.$prop
                    break
                }
            }

            foreach ($prop in $valueProps) {
                if ($item.PSObject.Properties[$prop]) {
                    $value = $item.$prop
                    break
                }
            }
        }

        if ($null -ne $label -and $null -ne $value) {
            $result.Add([PSCustomObject]@{
                Label = [string]$label
                Value = [double]$value
            })
        }
    }

    return $result
}
