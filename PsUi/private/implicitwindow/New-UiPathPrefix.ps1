function New-UiPathPrefix {
    <#
    .SYNOPSIS
        Builds the two assignment lines that give the window's runspace a $PSScriptRoot and a
        $PSCommandPath.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName
    )

    # Five characters PowerShell will take as a single quote, so all five get doubled or a folder name carrying one closes the string early
    if (!$script:uiQuoteCharacters) { $script:uiQuoteCharacters = [char]0x27, [char]0x2018, [char]0x2019, [char]0x201A, [char]0x201B }

    $values = @((Split-Path -Parent $ScriptName), $ScriptName)
    $quoted = @(foreach ($value in $values) {
        foreach ($quote in $script:uiQuoteCharacters) { $value = $value.Replace([string]$quote, "$quote$quote") }
        $value
    })
    $prefix = "`$PSScriptRoot = '$($quoted[0])'; `$PSCommandPath = '$($quoted[1])'; "

    # A parser that ever gets a sixth quote character robs a window of its $PSScriptRoot here rather than running whatever the folder is called.
    $tokens = $null
    $errors = $null
    $ast    = [System.Management.Automation.Language.Parser]::ParseInput($prefix, [ref]$tokens, [ref]$errors)
    if ($errors) { return '' }

    $statements = $ast.EndBlock.Statements
    if ($statements.Count -ne 2) { return '' }
    foreach ($statement in $statements) {
        if ($statement -isnot [System.Management.Automation.Language.AssignmentStatementAst]) { return '' }
    }
    if ($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) { return '' }

    $read = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value })
    if ($read.Count -ne 2 -or $read[0] -cne $values[0] -or $read[1] -cne $values[1]) { return '' }

    return $prefix
}
