function ConvertTo-WpfKey {
    <#
    .SYNOPSIS
        Converts a key string to a WPF key enum, handling short aliases (Esc, Enter, Del, Backspace, PgUp/PgDn).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$KeyName
    )

    $mapped = switch -Regex ($KeyName) {
        '^Esc(ape)?$'    { 'Escape' }
        '^Enter$'        { 'Return' }
        '^Del(ete)?$'    { 'Delete' }
        '^Ins(ert)?$'    { 'Insert' }
        '^Back(space)?$' { 'Back' }
        '^PgUp$'         { 'PageUp' }
        '^PgDown$'       { 'PageDown' }
        '^PgDn$'         { 'PageDown' }
        default          { $KeyName }
    }

    try {
        $key = [System.Windows.Input.Key]$mapped
        return $key
    }
    catch { return $null }
}
