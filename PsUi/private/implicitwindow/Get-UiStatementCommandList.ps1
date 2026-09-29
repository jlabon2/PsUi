function Get-UiStatementCommandList {
    <#
    .SYNOPSIS
        Lists the command names a single statement runs as it executes. A block PsUi keeps for
        a click does not count, and neither does the body of a function defined here, which is
        what puts the window's boundaries in the right place.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[string]])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.StatementAst]$Statement,

        [Parameter(Mandatory)]
        $Deferrers,

        $BlockStorers
    )

    # Get-UiRepeatedCommand and Get-UiInvokedBlock write this same name, so whichever file gets there first sets it and all three read that one delegate.
    # A change to the body reaches both of them.
    if (!$script:uiCommandAstFilter) {
        $script:uiCommandAstFilter = {
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }
    }

    $names = [System.Collections.Generic.List[string]]::new()

    foreach ($command in $Statement.FindAll($script:uiCommandAstFilter, $true)) {
        $name = Get-UiPlainCommandName -Command $command
        if (!$name) { continue }

        $deferred = $false
        $defined  = $false
        $node     = $command.Parent

        while ($node) {
            if ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                $defined = $true
                break
            }
            if ($node -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                if (Test-UiDeferredBlock -Block $node -Deferrers $Deferrers -BlockStorers $BlockStorers) { $deferred = $true }
            }
            if ($node -eq $Statement) { break }
            $node = $node.Parent
        }

        # A function body is a ScriptBlockAst and nothing in it runs here..
        if ($defined -or $deferred) { continue }
        [void]$names.Add($name)
    }

    return ,$names
}
