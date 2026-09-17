function Get-UiScriptHelperName {
    <#
    .SYNOPSIS
        Reads every function the calling script defines, dot sourced files included, and figures
        out which of them build controls and which open a window of their own. A function that
        only stores a block it was handed counts as neither, since nothing written inside that
        block has run. Without this, a function named something like Add-ServerRows is just a
        ame PsUi cannot place.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Root,

        [Parameter(Mandatory)]
        $Commands,

        [Parameter(Mandatory)]
        $Stoppers,

        [Parameter(Mandatory)]
        $Deferrers,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$ScriptName
    )

    if (!$script:uiFunctionAstFilter) {
        $script:uiFunctionAstFilter = {
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }
    }

    if (!$script:uiVariableAstFilter) {
        $script:uiVariableAstFilter = {
            param($node)
            $node -is [System.Management.Automation.Language.VariableExpressionAst]
        }
    }

    # These go back renamed. $builders is Builders, $openers is Stoppers because the read stops in front of one, and $storers is BlockStorers.
    $builders = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $openers  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $storers  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    $definitions = [System.Collections.Generic.List[object]]::new()
    $definitions.AddRange($Root.FindAll($script:uiFunctionAstFilter, $true))

    $pending = [System.Collections.Generic.Queue[string]]::new()
    $visited = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in (Get-UiDotSourcedPath -Root $Root -ScriptName $ScriptName)) { $pending.Enqueue($path) }

    # Twelve files parsed is past any real helper tree, and the cap keeps a deep dot source chain from parsing half the disk on the way to one control.
    while ($pending.Count -gt 0 -and $visited.Count -lt 12) {
        $path = $pending.Dequeue()
        if (!$visited.Add($path)) { continue }
        $parsed = $null
        try { $parsed = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null) } catch { $parsed = $null }
        if (!$parsed) { continue }
        $definitions.AddRange($parsed.FindAll($script:uiFunctionAstFilter, $true))
        foreach ($next in (Get-UiDotSourcedPath -Root $parsed -ScriptName $path)) { $pending.Enqueue($next) }
    }

    # A function that takes a scriptblock and never invokes it is storing it, so nothing written inside the block it was handed has run.
    foreach ($definition in $definitions) {
        if (!$definition.Name -or !$definition.Body) { continue }

        $blockNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($parameter in @($definition.Body.ParamBlock.Parameters) + @($definition.Parameters)) {
            if ($parameter -and $parameter.StaticType -eq [scriptblock]) { [void]$blockNames.Add($parameter.Name.VariablePath.UserPath) }
        }

        if (!$blockNames.Count) { continue }

        $runsIt = $false
        foreach ($use in $definition.Body.FindAll($script:uiVariableAstFilter, $true)) {
            if (!$blockNames.Contains($use.VariablePath.UserPath)) { continue }
            if ($use.Parent -is [System.Management.Automation.Language.CommandAst]) { $runsIt = $true; break }
            $member = $use.Parent -as [System.Management.Automation.Language.InvokeMemberExpressionAst]
            if ($member -and $member.Expression -eq $use) { $runsIt = $true; break }
        }
        if (!$runsIt) { [void]$storers.Add($definition.Name) }
    }

    # One AST walk per function, the passes below are string compares.
    $bodies = [System.Collections.Generic.List[object]]::new()
    foreach ($definition in $definitions) {
        if (!$definition.Name -or !$definition.Body) { continue }
        $runs = [System.Collections.Generic.List[string]]::new()

        foreach ($block in @($definition.Body.BeginBlock, $definition.Body.ProcessBlock, $definition.Body.EndBlock)) {
            if (!$block) { continue }
            foreach ($statement in $block.Statements) {
                $runs.AddRange((Get-UiStatementCommandList -Statement $statement -Deferrers $Deferrers -BlockStorers $storers))
            }
        }
        $bodies.Add(@{ Name = $definition.Name; Runs = $runs })
    }

    # Add-Rows calling Add-Row calling New-UiLabel is two hops, so keep going until a pass turns up nothing new.
    $grew = $true
    while ($grew) {
        $grew = $false
        foreach ($body in $bodies) {
            if (!$openers.Contains($body.Name)) {
                foreach ($name in $body.Runs) {
                    if ($Stoppers.Contains($name) -or $openers.Contains($name)) {
                        [void]$openers.Add($body.Name)
                        $grew = $true
                        break
                    }
                }
            }
            if (!$builders.Contains($body.Name)) {
                foreach ($name in $body.Runs) {
                    if ($Commands.Contains($name) -or $builders.Contains($name)) {
                        [void]$builders.Add($body.Name)
                        $grew = $true
                        break
                    }
                }
            }
        }
    }

    # A window opener is never also a window builder. Counting it as both would pull the window it opens into the content that was supposed to stop in front of it.
    foreach ($name in $openers) { [void]$builders.Remove($name) }

    return @{ Builders = $builders; Stoppers = $openers; BlockStorers = $storers }
}
