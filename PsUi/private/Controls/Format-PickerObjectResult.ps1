function Format-PickerObjectResult {
    <#
    .SYNOPSIS
        Flattens object-picker output to a string (newline-joined for multi-select).
    #>
    [CmdletBinding()]
    param(
        [object]$Picked
    )

    if (!$Picked) { return $null }
    if ($Picked -is [array]) {
        return ($Picked | ForEach-Object { $_.RawValue }) -join "`r`n"
    }
    return $Picked.RawValue
}
