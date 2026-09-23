function Get-UiDataGridCellValue {
    <#
    .SYNOPSIS
        Grabs the true value of a cell in a DataGrid row by its property path,
        or the row itself if the path is '.'.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Row,

        [Parameter(Mandatory)]
        [string]$Path
    )

    # Comma on every exit, or a list comes out as its elements.
    if ($null -eq $Row) { return $null }
    if ($Path -eq '.') { return ,$Row }

    # The dictionary grid's Value column shows a rendering and keeps the value itself in _RawValue, so a long list exports whole rather than as [7 items].
    if ($Path -eq 'Value') {
        $raw = $Row.PSObject.Properties['_RawValue']
        if ($raw) { return ,$raw.Value }
    }

    return ,$Row.$Path
}
