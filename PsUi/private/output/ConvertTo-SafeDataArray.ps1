function ConvertTo-SafeDataArray {
    <#
    .SYNOPSIS
        Converts data array to a safe format for DataGrid display. Protects against
        properties that throw exceptions on access.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$DataArray
    )

    # Sample first few items to check if conversion is needed
    $needsSafeConversion = $false
    $sampleSize = [Math]::Min(5, $DataArray.Count)

    for ($i = 0; $i -lt $sampleSize; $i++) {
        $sample = $DataArray[$i]
        if ($null -eq $sample) { continue }
        if ($sample -is [string] -or $sample -is [ValueType]) { continue }
        if ($sample -is [System.Collections.IDictionary]) { continue }
        if ($sample -is [System.Management.Automation.PSCustomObject]) { continue }

        # Test a few properties on this sample
        try {
            $propCount = 0
            foreach ($prop in $sample.PSObject.Properties) {
                $null = $prop.Value
                $propCount++
                if ($propCount -ge 3) { break }
            }
        }
        catch {
            $needsSafeConversion = $true
            break
        }
    }

    # Return original if no conversion needed (wrap in , to preserve array)
    if (!$needsSafeConversion) { return ,$DataArray }

    # Build safe copies with exception-protected property access
    $safeDataArray = @(foreach ($item in $DataArray) {
        try {
            if ($null -eq $item) { continue }
            if ($item -is [string] -or $item -is [ValueType]) { $item; continue }
            if ($item -is [System.Collections.IDictionary]) { $item; continue }
            if ($item -is [System.Management.Automation.PSCustomObject]) { $item; continue }

            $safeProps = [ordered]@{}
            foreach ($prop in $item.PSObject.Properties) {
                try { $safeProps[$prop.Name] = $prop.Value }
                catch { $safeProps[$prop.Name] = '[Access Denied]' }
            }
            [PSCustomObject]$safeProps
        }
        catch { $item }
    })

    if ($safeDataArray.Count -gt 0) { return $safeDataArray }
    return $DataArray
}
