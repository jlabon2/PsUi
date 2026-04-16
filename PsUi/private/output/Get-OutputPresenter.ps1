function Get-OutputPresenter {
    <#
    .SYNOPSIS
        Determines the best presentation type (DataGrid, RichTextBox, etc.) for output data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Data
    )

    $result = @{
        Type = 'Empty'
        Info = @{}
    }

    # Null or empty
    if ($null -eq $Data) {
        $result.Type = 'Empty'
        return $result
    }

    # Strings
    if ($Data -is [string]) {
        $result.Type = 'Text'
        $result.Info.Length = $Data.Length
        return $result
    }

    # Hashtables/dictionaries (check before IEnumerable since hashtables are also IEnumerable)
    if ($Data -is [System.Collections.IDictionary]) {
        $result.Type = 'Dictionary'
        $result.Info.Count = $Data.Count
        return $result
    }

    # Arrays/collections
    if ($Data -is [System.Collections.IEnumerable] -and $Data -isnot [string]) {
        $dataArray = @($Data)

        if ($dataArray.Count -eq 0) {
            $result.Type = 'Empty'
            return $result
        }

        # Sample first few items instead of checking all - this offers good balance of performance/accuracy
        $allStrings = $true
        $sampleSize = [Math]::Min(10, $dataArray.Count)
        for ($i = 0; $i -lt $sampleSize; $i++) {
            if ($dataArray[$i] -isnot [string]) {
                $allStrings = $false
                break
            }
        }

        if ($allStrings) {
            $result.Type = 'Text'
            $result.Info.LineCount = $dataArray.Count
            return $result
        }

        # Collection of objects
        $result.Type = 'Collection'
        $result.Info.Count = $dataArray.Count

        # Get properties from first non-null item
        $firstItem = $dataArray | Where-Object { $null -ne $_ } | Select-Object -First 1
        if ($firstItem) {
            $properties = @($firstItem.PSObject.Properties.Name)
            $result.Info.Properties = $properties
            $result.Info.PropertyCount = $properties.Count
        }

        return $result
    }

    # Single objects with properties
    $properties = @($Data.PSObject.Properties)
    if ($properties.Count -gt 0) {
        $result.Type = 'SingleObject'
        $result.Info.Properties = @($properties.Name)
        $result.Info.PropertyCount = $properties.Count
        return $result
    }

    # Fallback to text representation
    $result.Type = 'Text'
    $result.Info.IsConverted = $true
    return $result
}
