function Test-UiDeferredBlock {
    <#
    .SYNOPSIS
        Determines whether a scriptblock runs where it is or if something store it for later.
        -Content { } and .ForEach({ }) run now, -Action { } waitsfor a click, and $build = { } never runs at all.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ScriptBlockExpressionAst]$Block,

        [Parameter(Mandatory)]
        $Deferrers,

        $BlockStorers
    )

    # These take a definition block that runs while the window builds.
    # RowContextMenu and ResultActions read like click handlers but aren't, since the block builds the items rather than answering a click.
    $immediate = 'Content', 'Columns', 'RowContextMenu', 'CustomButtons', 'ResultActions'

    # Parentheses around the block change nothing about what runs.
    $node = $Block
    while ($node.Parent -is [System.Management.Automation.Language.CommandExpressionAst] -or $node.Parent -is [System.Management.Automation.Language.PipelineAst] -or $node.Parent -is [System.Management.Automation.Language.ParenExpressionAst]) { $node = $node.Parent }
    $parent = $node.Parent

    # .ForEach and .Where run the block once per item before the statement is finished, so a control in one is already being shown
    $invoke = $parent -as [System.Management.Automation.Language.InvokeMemberExpressionAst]
    if ($invoke) {
        $member = $invoke.Member -as [System.Management.Automation.Language.StringConstantExpressionAst]

        if (!$member) { return $true }
        if ($invoke.Expression -ne $node) { return $member.Value -notin 'ForEach', 'Where' }

        $runs = 'Invoke', 'InvokeReturnAsIs', 'InvokeWithContext'
        while ($true) {
            if ($member.Value -in $runs) { return $false }
            if ($member.Value -ne 'GetNewClosure') { return $true }
            $next = $invoke.Parent -as [System.Management.Automation.Language.InvokeMemberExpressionAst]
            if (!$next -or $next.Expression -ne $invoke) { return $true }

            $invoke = $next
            $member = $invoke.Member -as [System.Management.Automation.Language.StringConstantExpressionAst]
            if (!$member) { return $true }
        }
    }

    # -Content:{ } hangs the block off the parameter instead of the command.
    $colon = $parent -as [System.Management.Automation.Language.CommandParameterAst]
    if ($colon) {
        $runner = $colon.Parent -as [System.Management.Automation.Language.CommandAst]
        if (!$runner) { return $true }
        $colonName = Get-UiPlainCommandName -Command $runner
        if (!$colonName) { return $false }
        if ($BlockStorers -and $BlockStorers.Contains($colonName)) { return $true }
        if (!$Deferrers.Contains($colonName)) { return $false }
        return $colon.ParameterName -notin $immediate
    }

    # Stored in a variable, a hashtable or an array, so it runs later.
    $runner = $parent -as [System.Management.Automation.Language.CommandAst]
    if (!$runner) { return $true }

    # No name means it runs the block on the spot.
    $name = Get-UiPlainCommandName -Command $runner
    if (!$name) { return $false }

    # A helper the script wrote itself is judged by what its own body does with the block.
    if ($BlockStorers -and $BlockStorers.Contains($name)) { return $true }
    if (!$Deferrers.Contains($name)) { return $false }

    return (Get-UiBoundBlockParameter -Command $runner -Block $Block) -notin $immediate
}
