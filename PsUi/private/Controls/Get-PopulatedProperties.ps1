function Get-PopulatedProperties {
    <#
    .SYNOPSIS
        Property names with at least one non-empty value across items. Drives default column visibility.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Items,

        [string[]]$PropertyNames
    )

    $populated = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($item in $Items) {

        if ($null -eq $item) { continue }

        $propsToCheck = if ($PropertyNames) { $PropertyNames }
                        else { $item.PSObject.Properties.Name  }

        foreach ($propName in $propsToCheck) {

            if ($populated.Contains($propName)) { continue }
            if ($propName.StartsWith('_')) { continue }

            # PSObject.Properties[name] resolves the member without invoking its getter, so a missing member is an explicit skip instead of a silent $null read. The read stays in the try but getters can still throw (eg Process.MainModule on elevated procs).
            $prop = $item.PSObject.Properties[$propName]
            if (!$prop) { continue }

            $value = $null
            try   { $value = $prop.Value }
            catch { continue }

            $hasValue = $false
            if ($null -ne $value) {
                if ($value -is [string]) {

                    # '[Access Denied]' is the string ConvertTo-SafeDataArray implants when the source property threw.
                    # Treating it as a real value means columns full of "Access Denied" show up as populated; which defeats HasData.
                    $hasValue = ![string]::IsNullOrWhiteSpace($value) -and $value -ne '[Access Denied]'
                }
                elseif ($value -is [System.Collections.ICollection]) { $hasValue = $value.Count -gt 0 }
                else { $hasValue = $true }
            }

            if ($hasValue) { [void]$populated.Add($propName) }
        }

        if ($PropertyNames -and $populated.Count -eq $PropertyNames.Count) { break }
    }

    # Return the HashSet itself. @() and [string[]] still use it fine, and can now makeuse of Contains().
    return ,$populated
}
