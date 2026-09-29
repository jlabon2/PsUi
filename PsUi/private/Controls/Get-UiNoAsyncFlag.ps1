function Get-UiNoAsyncFlag {
    <#
    .SYNOPSIS
        Reads NoAsync off a column or menu item definition, still also usable with the old Sync parameter.
    #>
    [CmdletBinding()]
    param(
        $Definition
    )

    if ($null -eq $Definition) { return $false }

    # Sync was the name before this, and a definition built by hand carries whichever the script author wrote. The new name wins when a table somehow has both.
    if ($Definition.Contains('NoAsync')) { return [bool]$Definition['NoAsync'] }
    if ($Definition.Contains('Sync'))    { return [bool]$Definition['Sync'] }
    return $false
}
