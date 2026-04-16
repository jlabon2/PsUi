function Get-PopulatedProperties {
    <#
    .SYNOPSIS
        Returns property names that have at least one non-empty value across items.
        We use this to optimize which columns to show by default in data grids from Show-UIOutput.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Items,

        [string[]]$PropertyNames
    )

    $populated = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Iterate through each item and check specified properties to ensure we are using only populated ones
    foreach ($item in $Items) {
        
        if ($null -eq $item) { continue }

        # If specific properties requested, only check those
        $propsToCheck = if ($PropertyNames) { $PropertyNames }
                        else { $item.PSObject.Properties.Name  }

        foreach ($propName in $propsToCheck) {
            
            # Skip if already known to be populated
            if ($populated.Contains($propName)) { continue }

            # Skip internal properties
            if ($propName.StartsWith('_')) { continue }

            $value = $item.$propName

            # Empty strings, null, and empty collections don't count
            $hasValue = $false
            if ($null -ne $value) {
                if ($value -is [string]) { $hasValue = ![string]::IsNullOrWhiteSpace($value) }
                elseif ($value -is [System.Collections.ICollection]) { $hasValue = $value.Count -gt 0 } 
                else { $hasValue = $true }
            }

            if ($hasValue) { [void]$populated.Add($propName) }
        }

        # Early exit if all properties are populated
        if ($PropertyNames -and $populated.Count -eq $PropertyNames.Count) { break }
    }

    return @($populated)
}
