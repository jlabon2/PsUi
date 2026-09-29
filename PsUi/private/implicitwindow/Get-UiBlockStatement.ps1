function Get-UiBlockStatement {
    <#
    .SYNOPSIS
        Reads the statements out of a script block, taking begin, process and end,
        so a block written with all three is not read as empty.
    #>
    [OutputType([System.Collections.Generic.List[object]])]
    param([System.Management.Automation.Language.ScriptBlockExpressionAst]$Block)

    $found = [System.Collections.Generic.List[object]]::new()
    foreach ($section in @($Block.ScriptBlock.BeginBlock, $Block.ScriptBlock.ProcessBlock, $Block.ScriptBlock.EndBlock)) {
        if (!$section) { continue }
        foreach ($statement in $section.Statements) { $found.Add($statement) }
    }

    return ,$found
}
