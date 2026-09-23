function ConvertTo-DisplayValue {
    <#
    .SYNOPSIS
        One dictionary value as the string its grid cell shows.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Value
    )

    # Switch on the kind string, not the value, since switch enumerates a list and runs clauses meant for the whole list once per element
    switch (Get-UiValueKind -Value $Value) {
        'Dictionary' {
            # Count and GetEnumerator rather than .Count and .Keys, since a hashtable carrying a key by either name answers with the key
            $keyCount = [PsUi.ValueKind]::Count($Value)
            if ($keyCount -gt 3) { return "@{...} ($keyCount keys)" }

            $pairs = [System.Collections.Generic.List[string]]::new()
            foreach ($entry in $Value.GetEnumerator()) {
                $key = $entry.Key
                $val = $entry.Value

                # This renders as a PS literal, so a null reads $null here rather than the (null) a whole cell gets.
                $shown = switch (Get-UiValueKind -Value $val) {
                    'Null'       { '$null' }
                    'Bool'       { "`$$val" }
                    'Text'       { "'$val'" }
                    'Dictionary' { '@{...}' }
                    'List'       { "[$([PsUi.ValueKind]::Count($val)) items]" }
                    'Sequence'   { '[sequence]' }
                    default      { [PsUi.ValueKind]::DisplayText($val) }
                }
                $pairs.Add("$key=$shown")
            }
            return "@{$($pairs -join '; ')}"
        }

        'List' {
            # Short lists spelled out and long ones counted, same as the hashtable part, and counted first so a long list isn't copied just to count it
            $count = [PsUi.ValueKind]::Count($Value)
            if ($count -eq 0) { return '[empty]' }
            if ($count -gt 3) { return "[$count items]" }

            # Elements go through the switch rather than a raw join, or a list of hashtables spells out a type name per element.
            # Unquoted, unlike the pairs above, since a list of strings reads better as web, prod than as 'web', 'prod'.
            $shown = foreach ($item in $Value) {
                switch (Get-UiValueKind -Value $item) {
                    'Null'       { '(null)' }
                    'Dictionary' { '@{...}' }
                    'List'       { '[...]' }
                    'Sequence'   { '[sequence]' }
                    default      { [PsUi.ValueKind]::DisplayText($item) }
                }
            }
            return ($shown -join ', ')
        }

        # One pass is all there is, so the cell says what it is without reading it
        'Sequence' { return '[sequence]' }

        'Null' { return '(null)' }

        # DisplayText rather than the value itself, or a type whose own ToString is its type name reads as that
        default { return [PsUi.ValueKind]::DisplayText($Value) }
    }
}
