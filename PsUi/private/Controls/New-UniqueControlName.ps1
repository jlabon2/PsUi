function New-UniqueControlName {
    <#
    .SYNOPSIS
        Generates a unique control name using a prefix and short GUID suffix.
        Used pretty much everywhere to ensure unique naming of dynamically created controls
    #>
    [CmdletBinding()]
    param(
        [string]$Prefix = 'ctrl'
    )

    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
    return "${Prefix}_$suffix"
}
