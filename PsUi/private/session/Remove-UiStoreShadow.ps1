function Remove-UiStoreShadow {
    <#
    .SYNOPSIS
        Drops names an action got from scope when the store holds them too (the store takes precedence over the scope copy).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()]
        [hashtable]$Variables,

        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$AutoNames
    )

    if (!$Variables -or !$AutoNames) { return $Variables }
    $session = try { Get-UiSession } catch { $null }
    if (!$session -or $session.CapturedVariables.Count -eq 0) { return $Variables }

    # Only what the AST scan found. -Variables and -LinkedVariables don't go through AutoNames, so a name passed manually still beats out the store.
    $stored = @($session.CapturedVariables.Keys)
    foreach ($name in $AutoNames) {
        if (!$Variables.ContainsKey($name)) { continue }
        foreach ($key in $stored) { if ($key -eq $name) { $Variables.Remove($name); break } }
    }
    return $Variables
}
