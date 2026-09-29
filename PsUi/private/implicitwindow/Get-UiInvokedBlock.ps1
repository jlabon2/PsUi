function Get-UiInvokedBlock {
    <#
    .SYNOPSIS
        Resolves a call like '& $scriptBlock' back to the scriptblock assigned to '$scriptBlock'
        earlier within a parsed script. Reports which statement did the assigning, since the
        window has to take that line along with the call or the content it builds runs & $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.StatementAst]$Statement,

        [Parameter(Mandatory)]
        $Statements,

        [Parameter(Mandatory)]
        [int]$Limit
    )

    # Get-UiRepeatedCommand and Get-UiStatementCommandList write this same name, so whichever file gets there first sets it... all three set the same filter, so it doesn't matter which one wins out.
    if (!$script:uiCommandAstFilter) {
        $script:uiCommandAstFilter = {
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }
    }

    if (!$script:uiScriptBlockAstFilter) {
        $script:uiScriptBlockAstFilter = {
            param($node)
            $node -is [System.Management.Automation.Language.ScriptBlockExpressionAst]
        }
    }

    $found = [System.Collections.Generic.List[object]]::new()

    foreach ($command in $Statement.FindAll($script:uiCommandAstFilter, $true)) {
        if ($command.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Unknown) { continue }
        if (!$command.CommandElements.Count) { continue }
        $target = $command.CommandElements[0] -as [System.Management.Automation.Language.VariableExpressionAst]
        if (!$target) { continue }

        # Nearest assignment above the call is the one the run would have taken. Only a plain assignment counts, since anything cleverer holds a value no reader of the text can follow.
        for ($i = $Limit; $i -ge 0; $i--) {
            $assign = $Statements[$i] -as [System.Management.Automation.Language.AssignmentStatementAst]
            if (!$assign) { continue }

            $left = $assign.Left -as [System.Management.Automation.Language.VariableExpressionAst]
            if (!$left -or $left.VariablePath.UserPath -ne $target.VariablePath.UserPath) { continue }

            $blocks = @($assign.Right.FindAll($script:uiScriptBlockAstFilter, $true))
            if ($blocks.Count) { $found.Add([pscustomobject]@{ Index = $i; Block = $blocks[0] }) }

            break
        }
    }

    return ,$found
}
