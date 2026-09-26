function Invoke-UiCallback {
    <#
    .SYNOPSIS
        Runs a user block for a UI thread handler, so the errors it writes get seen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        # Values in order, or a hashtable to splat by name
        $ArgumentList,

        # Each error turns into a '<Label> error: <message>' console warning
        [string]$Label,

        # Collects the errors instead for the handler to show its own way
        [System.Collections.IList]$ErrorList
    )

    if ($null -eq $ArgumentList) { $ArgumentList = @() }

    # Off the pipeline a written error reaches only $Error. Output lands in the list ahead of the redirect, which keeps a catch { $_ } record out of the errors. The errors written before a throw still count.
    $output = [System.Collections.Generic.List[object]]::new()
    & { & $ScriptBlock @ArgumentList | & { process { $output.Add($_) } } } 2>&1 | & {
        process {
            if ($null -ne $ErrorList) { [void]$ErrorList.Add($_) }
            else { Write-Warning "$Label error: $_" }
        }
    }
    $output
}
