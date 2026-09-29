function Test-UiRefWritesThrough {
    <#
    .SYNOPSIS
        Whether writing to this [ref] reaches the variable behind it.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # Untyped, or binding unwraps the [ref] and hands over its value instead.
        [Parameter(Mandatory)]
        [AllowNull()]
        $Reference
    )

    if ($Reference -isnot [System.Management.Automation.PSReference]) { return $false }

    # [ref]$someVar stores the PSVariable itself so a write reaches the variable, while [ref]$state.List stores the value and the write stops at the [ref].
    # If the lookup ever fails, return true, since an engine change should go quiet rather than warn about every [ref].
    try {
        $valueField = [System.Management.Automation.PSReference].GetField('_value', [System.Reflection.BindingFlags]'Instance,NonPublic')
        if (!$valueField) { return $true }
        return ($valueField.GetValue($Reference) -is [System.Management.Automation.PSVariable])
    }
    catch { Write-Debug "Ref backing check failed: $_"; return $true }
}
