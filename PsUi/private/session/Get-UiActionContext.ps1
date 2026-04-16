# Cached reflection members to avoid repeated lookups (perf optimization for many buttons)
$script:SessionStateFieldInfo = $null
$script:SessionStatePropertyInfo = $null
$script:GetVariableMethodInfo = $null

<#
.SYNOPSIS
    Captures execution context from a scriptblock for async execution.
#>
function Get-UiActionContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [string[]]$LinkedVariables,
        [string[]]$LinkedFunctions,
        [string[]]$LinkedModules,
        [hashtable]$ExplicitVariables,

        # Caller's SessionState for scope lookup
        [System.Management.Automation.SessionState]$CallerSessionState
    )

    if (!$CallerSessionState) {
        try {
            $flags = [System.Reflection.BindingFlags]'Instance, NonPublic, Public'
            $prop = [System.Management.Automation.ScriptBlock].GetProperty('SessionState', $flags)
            if ($prop) {
                $CallerSessionState = $prop.GetValue($Action)
            }
        }
        catch {
            # SessionState extraction failed
        }
    }

    $autoDetectedVars = [System.Collections.Generic.List[string]]::new()
    try {
        $ast = $Action.Ast

        $varExpressions = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true)

        # Built-in/automatic variables to exclude from capture
        $excludeVars = @(
            '_', 'args', 'ConsoleFileName', 'Error', 'Event', 'EventArgs', 'EventSubscriber',
            'ExecutionContext', 'false', 'foreach', 'HOME', 'Host', 'input', 'IsCoreCLR',
            'IsLinux', 'IsMacOS', 'IsWindows', 'LastExitCode', 'Matches', 'MyInvocation',
            'NestedPromptLevel', 'null', 'PID', 'PROFILE', 'PSBoundParameters', 'PSCmdlet',
            'PSCommandPath', 'PSCulture', 'PSDebugContext', 'PSHOME', 'PSItem', 'PSScriptRoot',
            'PSSenderInfo', 'PSUICulture', 'PSVersionTable', 'PWD', 'Sender', 'ShellId',
            'StackTrace', 'switch', 'this', 'true',
            'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
            'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable',
            'OutBuffer', 'PipelineVariable', 'Confirm', 'WhatIf',
            'state', 'AsyncExecutor', 'env'
        )

        foreach ($varExpr in $varExpressions) {
            $varName = $varExpr.VariablePath.UserPath

            if ($excludeVars -contains $varName) { continue }

            # Skip scope-qualified variables
            if ($varExpr.VariablePath.IsScript -or
                $varExpr.VariablePath.IsGlobal -or
                $varExpr.VariablePath.IsLocal -or
                $varExpr.VariablePath.IsPrivate) { continue }

            # Skip assignment targets (left side of =)
            $astParent = $varExpr.Parent
            if ($astParent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                if ($astParent.Left -eq $varExpr) { continue }
            }

            if ($autoDetectedVars -contains $varName) { continue }

            $autoDetectedVars.Add($varName)
        }
    }
    catch {
        # AST variable detection failed
    }

    $allLinkedVariables = @($autoDetectedVars) + @($LinkedVariables) | Select-Object -Unique

    # TODO: Memory bloat risk? Each button stores references to captured variables in its .Tag property.
    # If a large object (e.g. 100MB dataset) is in scope when many buttons are created, all buttons
    # hold references preventing GC. Consider session-based ID lookup instead of direct Tag storage?
    
    $capturedVars = @{}

    if ($ExplicitVariables) {
        foreach ($key in $ExplicitVariables.Keys) {
            $capturedVars[$key] = $ExplicitVariables[$key]
        }
    }

    if ($allLinkedVariables -and $allLinkedVariables.Count -gt 0) {
        foreach ($name in $allLinkedVariables) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if ($capturedVars.ContainsKey($name)) { continue }  # Explicit takes precedence

            $found = $false
            $value = $null

            # Try SessionState.PSVariable first
            if ($CallerSessionState -and !$found) {
                try {
                    $var = $CallerSessionState.PSVariable.Get($name)
                    if ($null -ne $var) {
                        $value = $var.Value
                        $found = $true
                    }
                }
                catch {
                    # PSVariable.Get failed
                }
            }

            # Try internal session state (reflection is cached)
            if (!$found -and $CallerSessionState) {
                try {
                    $internal = $null
                    
                    # Cache the FieldInfo on first use
                    if ($null -eq $script:SessionStateFieldInfo) {
                        $script:SessionStateFieldInfo = $CallerSessionState.GetType().GetField(
                            '_sessionState',
                            [System.Reflection.BindingFlags]'Instance, NonPublic'
                        )
                    }
                    if ($script:SessionStateFieldInfo) {
                        $internal = $script:SessionStateFieldInfo.GetValue($CallerSessionState)
                    }

                    # Fallback to property if field not found
                    if (!$internal) {
                        if ($null -eq $script:SessionStatePropertyInfo) {
                            $script:SessionStatePropertyInfo = $CallerSessionState.GetType().GetProperty(
                                'Internal',
                                [System.Reflection.BindingFlags]'Instance, NonPublic'
                            )
                        }
                        if ($script:SessionStatePropertyInfo) {
                            $internal = $script:SessionStatePropertyInfo.GetValue($CallerSessionState)
                        }
                    }

                    if ($internal) {
                        # Cache the GetVariable method
                        if ($null -eq $script:GetVariableMethodInfo) {
                            $script:GetVariableMethodInfo = $internal.GetType().GetMethod('GetVariable', [Type[]]@([string]))
                        }
                        if ($script:GetVariableMethodInfo) {
                            $varObj = $script:GetVariableMethodInfo.Invoke($internal, @($name))
                            if ($null -ne $varObj) {
                                $value = $varObj.Value
                                $found = $true
                            }
                        }
                    }
                }
                catch { Write-Debug "Module variable capture failed: $_" }
            }

            # Fall back to global scope
            if (!$found) {
                $globalVar = Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
                if ($globalVar) {
                    $value = $globalVar.Value
                    $found = $true
                }
            }

            if ($found) {
                $capturedVars[$name] = $value
            }
        }
    }

    $capturedFuncs = @{}
    $autoDetectedFuncs = [System.Collections.Generic.List[string]]::new()
    try {
        $commandAsts = $Action.Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true)

        # Built-in cmdlets to exclude
        $excludeFuncs = @(
            'Write-Host', 'Write-Output', 'Write-Error', 'Write-Warning', 'Write-Verbose',
            'Write-Debug', 'Write-Information', 'Write-Progress',
            'Get-Item', 'Set-Item', 'Get-ChildItem', 'Get-Content', 'Set-Content',
            'Get-Process', 'Get-Service', 'Get-Date', 'Get-Random', 'Get-Location',
            'Get-Member', 'Get-Command', 'Get-Help', 'Get-Variable', 'Set-Variable',
            'New-Object', 'New-Item', 'Remove-Item', 'Copy-Item', 'Move-Item',
            'Select-Object', 'Where-Object', 'ForEach-Object', 'Sort-Object', 'Group-Object',
            'Measure-Object', 'Compare-Object', 'Tee-Object',
            'Format-Table', 'Format-List', 'Format-Wide', 'Format-Custom',
            'Out-Null', 'Out-String', 'Out-File', 'Out-Host', 'Out-Default',
            'Import-Module', 'Export-ModuleMember', 'Get-Module', 'Remove-Module',
            'Invoke-Command', 'Invoke-Expression', 'Invoke-RestMethod', 'Invoke-WebRequest',
            'Start-Process', 'Stop-Process', 'Start-Job', 'Stop-Job', 'Get-Job', 'Wait-Job',
            'Start-Sleep', 'Wait-Event',
            'Test-Path', 'Join-Path', 'Split-Path', 'Resolve-Path', 'Convert-Path',
            'Add-Member', 'Add-Type',
            'ConvertTo-Json', 'ConvertFrom-Json', 'ConvertTo-Csv', 'ConvertFrom-Csv',
            'Import-Csv', 'Export-Csv', 'Import-Clixml', 'Export-Clixml',
            'Read-Host', 'Clear-Host',
            'Get-UiSession', 'Get-UiTheme', 'Set-UiTheme',
            'Show-UiMessageDialog', 'Show-UiConfirmDialog', 'Show-UiInputDialog',
            'if', 'else', 'elseif', 'switch', 'foreach', 'for', 'while', 'do',
            'try', 'catch', 'finally', 'throw', 'return', 'break', 'continue', 'exit'
        )

        foreach ($cmdAst in $commandAsts) {
            $cmdName = $cmdAst.GetCommandName()
            if ([string]::IsNullOrWhiteSpace($cmdName)) { continue }
            if ($excludeFuncs -contains $cmdName) { continue }
            if ($autoDetectedFuncs -contains $cmdName) { continue }
            if ($capturedFuncs.ContainsKey($cmdName)) { continue }

            $cmd = Get-Command -Name $cmdName -ErrorAction SilentlyContinue
            if ($cmd) {
                if ($cmd.CommandType -eq 'Function' -or $cmd.CommandType -eq 'Filter') {
                    $autoDetectedFuncs.Add($cmdName)
                }
            }
            else {
                $autoDetectedFuncs.Add($cmdName)
            }
        }

    }
    catch {
        # AST function detection failed
    }

    $allLinkedFunctions = @($autoDetectedFuncs) + @($LinkedFunctions) | Select-Object -Unique

    if ($allLinkedFunctions -and $allLinkedFunctions.Count -gt 0) {
        foreach ($item in $allLinkedFunctions) {
            if ([string]::IsNullOrWhiteSpace($item)) { continue }

            $funcName = $null
            $funcDef  = $null
            $found    = $false

            if ($item -is [System.Management.Automation.CommandInfo]) {
                $funcName = $item.Name
                $funcDef  = $item.Definition
                $found    = $true
            }
            else {
                $funcName = $item.ToString()

                if ($capturedFuncs.ContainsKey($funcName)) { continue }

                # Try caller's SessionState
                if ($CallerSessionState -and !$found) {
                    try {
                        $cmd = $CallerSessionState.InvokeCommand.GetCommand(
                            $funcName,
                            [System.Management.Automation.CommandTypes]::Function
                        )
                        if ($cmd) {
                            $funcDef = $cmd.Definition
                            $found = $true
                        }
                    }
                    catch { Write-Debug "InvokeCommand lookup failed: $_" }
                }

                # Try internal session state
                if (!$found -and $CallerSessionState) {
                    try {
                        $internal = $null
                        $field = $CallerSessionState.GetType().GetField(
                            '_sessionState',
                            [System.Reflection.BindingFlags]'Instance, NonPublic'
                        )
                        if ($field) {
                            $internal = $field.GetValue($CallerSessionState)
                        }

                        if (!$internal) {
                            $prop = $CallerSessionState.GetType().GetProperty(
                                'Internal',
                                [System.Reflection.BindingFlags]'Instance, NonPublic'
                            )
                            if ($prop) {
                                $internal = $prop.GetValue($CallerSessionState)
                            }
                        }

                        if ($internal) {
                            $methods = $internal.GetType().GetMethods(
                                [System.Reflection.BindingFlags]'Instance, Public, NonPublic'
                            ) | Where-Object { $_.Name -eq 'GetFunction' }

                            foreach ($method in $methods) {
                                try {
                                    $params = $method.GetParameters()
                                    if ($params.Count -eq 1 -and $params[0].ParameterType -eq [string]) {
                                        $funcInfo = $method.Invoke($internal, @($funcName))
                                        if ($funcInfo -and $funcInfo.ScriptBlock) {
                                            $funcDef = $funcInfo.ScriptBlock.ToString()
                                            $found = $true
                                            break
                                        }
                                    }
                                }
                                catch { Write-Debug "GetFunction invoke failed: $_" }
                            }
                        }
                    }
                    catch { Write-Debug "Session state reflection failed: $_" }
                }

                # Try Action's module
                if (!$found -and $Action.Module) {
                    try {
                        $cmd = & $Action.Module {
                            param($functionName)
                            Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue
                        } $funcName
                        if ($cmd) {
                            $funcDef = $cmd.Definition
                            $found = $true
                        }
                    }
                    catch { Write-Debug "Action module lookup failed: $_" }
                }

                # Fall back to global
                if (!$found) {
                    $cmd = Get-Command -Name $funcName -CommandType Function -ErrorAction SilentlyContinue
                    if ($cmd) {
                        $funcDef = $cmd.Definition
                        $found = $true
                    }
                }
            }

            if ($found -and $funcDef) {
                $capturedFuncs[$funcName] = $funcDef
            }
        }
    }

    $resolvedModules = @($LinkedModules | Where-Object { $_ })

    # Auto-include the PsUi module
    $currentModule = $MyInvocation.MyCommand.Module
    if ($currentModule) {
        $modulePath = $currentModule.Path
        $resolvedModules = [string[]]@(@($modulePath) + @($resolvedModules) | Where-Object { $_ } | Select-Object -Unique)
    }

    # Credentials are injected at CLICK TIME in New-UiButton.ps1, not here (empty at button creation)

    [PSCustomObject]@{
        Action             = $Action
        CapturedVars       = $capturedVars
        CapturedFuncs      = $capturedFuncs
        LinkedModules      = $resolvedModules
        CallerSessionState = $CallerSessionState
        AutoDetectedVars   = $autoDetectedVars
        AutoDetectedFuncs  = $autoDetectedFuncs
    }
}
