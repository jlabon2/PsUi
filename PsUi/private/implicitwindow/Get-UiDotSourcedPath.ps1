function Get-UiDotSourcedPath {
    <#
    .SYNOPSIS
        Resolves the script's dot source lines to real paths, if possible, since a path
        built at runtime is not there in the text to read.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[string]])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Root,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$ScriptName
    )

    if (!$script:uiDotSourceFilter) {
        $script:uiDotSourceFilter = {
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot
        }
    }

    $paths = [System.Collections.Generic.List[string]]::new()

    if (!$ScriptName) { return ,$paths }
    $directory = Split-Path -Parent $ScriptName

    # An ampersand runs the file in a child scope and every function it defined dies in that scope, so the dot operator is the only one worth following.
    # Nested blocks are out since a dot source inside a function body defines into that function's scope, and those definitions die when it returns.
    foreach ($command in $Root.FindAll($script:uiDotSourceFilter, $false)) {
        if (!$command.CommandElements.Count) { continue }
        $target = $command.CommandElements[0]
        $text   = $null

        if ($target -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $text = $target.Value }
        elseif ($target -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { $text = $target.Value }
        elseif ($target -is [System.Management.Automation.Language.ParenExpressionAst]) {
            $pipeline = $target.Pipeline -as [System.Management.Automation.Language.PipelineAst]
            $call     = if ($pipeline) { $pipeline.PipelineElements[0] -as [System.Management.Automation.Language.CommandAst] } else { $null }

            if ($call -and $call.CommandElements.Count -eq 3 -and (Get-UiPlainCommandName -Command $call) -eq 'Join-Path') {
                $baseAst = $call.CommandElements[1]
                $base    = if ($baseAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $baseAst.Value } else { $baseAst.Extent.Text }
                $leaf    = $call.CommandElements[2] -as [System.Management.Automation.Language.StringConstantExpressionAst]
                if ($leaf) { $text = Join-Path $base $leaf.Value }
            }
        }

        # $PSScriptRoot is the one var we should worry about populating, since the owner frame already said which folder that is.
        if (!$text) { continue }
        $stripped = $text.Replace('${PSScriptRoot}', '').Replace('$PSScriptRoot', '')
        if ($stripped.Contains('$')) { continue }
        $text = $text.Replace('${PSScriptRoot}', $directory).Replace('$PSScriptRoot', $directory)

        if (![System.IO.Path]::IsPathRooted($text)) { $text = Join-Path $directory $text }
        if (Test-Path -LiteralPath $text -PathType Leaf) { [void]$paths.Add((Convert-Path -LiteralPath $text)) }
    }

    return ,$paths
}
