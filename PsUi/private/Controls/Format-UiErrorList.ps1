function Format-UiErrorList {
    <#
    .SYNOPSIS
        Joins errors for one dialog. More than 10 and it'll give a count at the end.
    #>
    [CmdletBinding()]
    param(
        [System.Collections.IList]$Errors,

        # Goes last such as the message of the throw that ended the action
        [string]$Trailing
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt [Math]::Min(10, $Errors.Count); $i++) { $lines.Add("$($Errors[$i])") }
    if ($Errors.Count -gt 10) { $lines.Add("And $($Errors.Count - 10) more.") }
    if ($Trailing) { $lines.Add($Trailing) }
    $lines -join "`n`n"
}
