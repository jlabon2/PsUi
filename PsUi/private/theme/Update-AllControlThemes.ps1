function Update-AllControlThemes {
    <#
    .SYNOPSIS
        Iteratively updates theme colors for all controls in a visual tree.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Control,
        [Parameter(Mandatory)]
        [hashtable]$Colors
    )

    if (!$Control) { return }

    # Use iterative approach with explicit stack to avoid PowerShell call depth limits
    $stack   = [System.Collections.Generic.Stack[object]]::new()
    $visited = [System.Collections.Generic.HashSet[int]]::new()

    $stack.Push($Control)

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        if ($null -eq $current) { continue }

        # Cycle detection using object identity hash
        $objectId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($current)
        if ($visited.Contains($objectId)) { continue }
        [void]$visited.Add($objectId)

        # Apply styling to this control
        Update-SingleControlTheme -Control $current -Colors $Colors

        # Queue children for processing based on container type
        $children = Get-ControlChildren -Control $current
        foreach ($child in $children) {
            if ($null -ne $child) {
                $stack.Push($child)
            }
        }
    }
}
