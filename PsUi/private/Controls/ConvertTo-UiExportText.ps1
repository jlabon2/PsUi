function ConvertTo-UiExportText {
    <#
    .SYNOPSIS
        Flattens a value into a string suitable for export to CSV or other string formats.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    # A nested list or dictionary reads the way its own cell would, so a list of hashtables exports as @{a=1}, @{b=2} isntead of a type name per element.
    $element = {
        param($item)
        if ((Get-UiValueKind -Value $item) -in 'Dictionary', 'List', 'Sequence') { ConvertTo-DisplayValue -Value $item } else { [PsUi.ValueKind]::DisplayText($item) }
    }

    switch ([PsUi.ValueKind]::Of($Value)) {
        'List'       { return (@(foreach ($item in $Value) { & $element $item }) -join ', ') }
        'Dictionary' { return (@(foreach ($entry in $Value.GetEnumerator()) { "$($entry.Key)=$(& $element $entry.Value)" }) -join '; ') }
        'Sequence'   { return '[sequence]' }
        default      { return [PsUi.ValueKind]::DisplayText($Value) }
    }
}
