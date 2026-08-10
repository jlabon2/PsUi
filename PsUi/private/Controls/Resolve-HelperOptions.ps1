function Resolve-HelperOptions {
    <#
    .SYNOPSIS
        Walks a HelperOptions hashtable and returns a splat-ready copy. Nulls and empty strings get stripped so the picker sees its defaults instead of explicit nothings.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Options
    )

    $resolved = @{}
    if (!$Options) { return $resolved }

    foreach ($key in $Options.Keys) {
        $val = Resolve-HelperOptionValue $Options[$key]
        if ($null -eq $val) { continue }
        if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { continue }
        $resolved[$key] = $val
    }
    return $resolved
}
