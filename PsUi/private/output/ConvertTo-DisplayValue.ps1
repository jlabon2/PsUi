function ConvertTo-DisplayValue {
    <#
    .SYNOPSIS
        Converts hashtables and arrays to readable display strings for DataGrid cells.
        Complex values are expandable via popup on click.
    #>
    param(
        [Parameter(Mandatory)]
        $Value
    )

    switch ($Value) {
        { $_ -is [System.Collections.IDictionary] } {
            # Use get_Count() to avoid confusing with a 'Count' key in the hashtable
            $keyCount = $Value.get_Count()

            # Nested hashtable - show as @{Key=Value; ...} or abbreviated
            if ($keyCount -le 3) {
                $pairs = [System.Collections.Generic.List[string]]::new()
                foreach ($key in $Value.Keys) {
                    $val = $Value[$key]
                    switch ($val) {
                        { $_ -is [bool] }   { $pairs.Add("$key=`$$val") }
                        { $_ -is [string] } { $pairs.Add("$key='$val'") }
                        default             { $pairs.Add("$key=$val") }
                    }
                }
                return "@{$($pairs -join '; ')}"
            }
            return "@{...} ($keyCount keys)"
        }
        { $_ -is [array] } { return $Value -join ', ' }
        default { return $Value }
    }
}
