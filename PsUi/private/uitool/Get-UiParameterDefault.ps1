function Get-UiParameterDefault {
    <#
    .SYNOPSIS
        Reads a param default off its AST without running it. Throws on anything it won't touch.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )

    switch ($Ast.GetType().Name) {
        'ParenExpressionAst'   { return ,(Get-UiParameterDefault -Ast $Ast.Pipeline) }
        'CommandExpressionAst' { return ,(Get-UiParameterDefault -Ast $Ast.Expression) }
        'PipelineAst' {
            if ($Ast.PipelineElements.Count -eq 1) {
                return ,(Get-UiParameterDefault -Ast $Ast.PipelineElements[0])
            }
        }
        'CommandAst' {
            # Never calls Get-Date, since the script is free to shadow it
            if ($Ast.CommandElements.Count -eq 1 -and $Ast.GetCommandName() -eq 'Get-Date') {
                return [datetime]::Now
            }
        }
        'MemberExpressionAst' {
            $member = $Ast.Member.Value
            if ($Ast.Static) {
                $type = $Ast.Expression.TypeName.GetReflectionType()
                if ($type -eq [datetime] -and $member -in 'Now', 'Today', 'UtcNow') {
                    return [datetime]::$member
                }
                if ($type -and $type.IsEnum -and $member) { return [Enum]::Parse($type, $member, $true) }

                # Plain bool,since the checkbox and the run both test -is [bool]
                if ($type -eq [switch] -and $member -eq 'Present') { return $true }
            }
            elseif ($member -eq 'Date') {
                $target = Get-UiParameterDefault -Ast $Ast.Expression
                if ($target -is [datetime]) { return $target.Date }
            }
        }
        'InvokeMemberExpressionAst' {
            $method = $Ast.Member.Value
            if (!$Ast.Static -and $method -match '^Add(Years|Months|Days|Hours|Minutes|Seconds|Milliseconds)$' -and $Ast.Arguments.Count -eq 1) {
                $target = Get-UiParameterDefault -Ast $Ast.Expression
                $amount = Get-UiParameterDefault -Ast $Ast.Arguments[0]
                if ($target -is [datetime] -and $amount -is [ValueType]) { return $target.$method($amount) }
            }
        }
        'ConvertExpressionAst' {
            $type = $Ast.Type.TypeName.GetReflectionType()
            if ($type -eq [switch]) { return [bool](Get-UiParameterDefault -Ast $Ast.Child) }
            if ($type -and ($type.IsPrimitive -or $type.IsEnum -or $type -in [string], [datetime], [decimal])) {
                return ,((Get-UiParameterDefault -Ast $Ast.Child) -as $type)
            }
        }
        'VariableExpressionAst' {
            if ($Ast.VariablePath.DriveName -eq 'env') {
                return [System.Environment]::GetEnvironmentVariable(($Ast.VariablePath.UserPath -replace '^env:', ''))
            }
        }
        'ScriptBlockExpressionAst' {
            # The box shows the body and the run turns the text back into a block.
            $body = $Ast.Extent.Text.Trim()
            return $body.Substring(1, $body.Length - 2).Trim()
        }
    }

    # SafeGetValue throws on anything past literals and arrays or hashtables of them (Import-PowerShellDataFile trusts it with a .psd1)
    ,$Ast.SafeGetValue()
}
