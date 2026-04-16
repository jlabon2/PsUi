function Invoke-UiAsync {
    <#
    .SYNOPSIS
        Runs a scriptblock in the background without freezing the UI.
    .DESCRIPTION
        Uses the AsyncExecutor RunspacePool for fast, efficient background execution.
        Automatically captures variables and functions from the caller's scope.
    .PARAMETER ScriptBlock
        Code to run in background.
    .PARAMETER OnComplete
        Code to run when done. Receives the result as parameter.
    .PARAMETER OnError
        Code to run on error. Receives the error as parameter.
    .PARAMETER Arguments
        Arguments to pass to the scriptblock (legacy compatibility).
    .PARAMETER Variables
        Hashtable of variables to pass to the background runspace.
    .PARAMETER Capture
        Variable names to capture from the runspace after execution completes.
        Captured variables are stored in the session and available to subsequent
        async calls, and persist in global scope after the window closes.
    .PARAMETER AutoCapture
        Automatically capture variables used in ScriptBlock from caller scope. Default: $true
    .PARAMETER NoAutoCapture
        Disables automatic variable capture from caller scope. Use when you want
        full control over what's passed in.
    .EXAMPLE
        Invoke-UiAsync -ScriptBlock { 
            Get-ChildItem C:\ -Recurse 
        } -OnComplete { 
            param($result)
            Write-Host "Found $($result.Count) items"
        }
    .EXAMPLE
        $path = "C:\Temp"
        Invoke-UiAsync -ScriptBlock { 
            Get-ChildItem $path   # $path is auto-captured
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [scriptblock]$OnComplete,
        
        [scriptblock]$OnError,
        
        [object[]]$Arguments,
        
        [hashtable]$Variables,
        
        [string[]]$Capture,
        
        [switch]$NoAutoCapture
    )

    if ($Capture) {
        foreach ($varName in $Capture) {
            if (![PsUi.Constants]::IsValidIdentifier($varName)) {
                throw "Invalid variable name for -Capture: '$varName'. Names must start with a letter or underscore and contain only letters, numbers, underscores, or hyphens."
            }
        }
    }

    Write-Debug "Starting async execution, AutoCapture=$(!$NoAutoCapture)"

    $executor = [PsUi.AsyncExecutor]::new()
    
    # Set dispatcher for proper UI thread marshaling
    if ([System.Windows.Application]::Current) {
        $executor.UiDispatcher = [System.Windows.Application]::Current.Dispatcher
    }
    
    # Store executor in session for Stop-UiAsync cancellation
    $execSession = [PsUi.SessionManager]::Current
    if ($execSession) { $execSession.ActiveExecutor = $executor }
    
    $varsToInject = @{}
    
    # Auto-capture variables from ScriptBlock using AST (same as New-UiButton)
    if (!$NoAutoCapture) {
        $ast         = $ScriptBlock.Ast
        $builtinVars = @(
            '_', 'PSItem', 'this', 'args', 'input', 'PSCmdlet', 'PSBoundParameters', 
            'MyInvocation', 'ExecutionContext', 'null', 'true', 'false', 'PSScriptRoot',
            'PSCommandPath', 'PID', 'Host', 'PSVersionTable', 'Error', 'StackTrace',
            'HOME', 'PROFILE', 'PSCulture', 'PSUICulture', 'ShellId', 'NestedPromptLevel',
            'state', 'session', 'executor', 'varsToInject', 'functionsToInject'
        )
        
        $referencedVars = $ast.FindAll({ 
            param($node) 
            $node -is [System.Management.Automation.Language.VariableExpressionAst] 
        }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Select-Object -Unique
        
        foreach ($varName in $referencedVars) {
            if ($varName -notin $builtinVars) {
                # Dynamically walk up the scope chain until we hit Global
                # This handles deeply nested modules/jobs where scope > 10
                $scopeIndex = 1
                $foundValue = $false
                while (!$foundValue) {
                    try {
                        $val = Get-Variable -Name $varName -Scope $scopeIndex -ValueOnly -ErrorAction Stop
                        $varsToInject[$varName] = $val
                        $foundValue = $true
                    }
                    catch [System.Management.Automation.ItemNotFoundException] {
                        # Variable not found at this scope, try next
                        $scopeIndex++
                    }
                    catch [System.ArgumentOutOfRangeException] {
                        # We've gone past Global scope, variable doesn't exist
                        break
                    }
                    catch {
                        # Other error (e.g., scope doesn't exist), stop searching
                        break
                    }
                }
            }
        }
    }

    if ($Variables) {
        Write-Debug "Adding $($Variables.Count) explicit variable(s)"
        foreach ($key in $Variables.Keys) {
            $varsToInject[$key] = $Variables[$key]
        }
    }
    
    # Add Arguments as $args if provided (legacy compatibility)
    if ($Arguments) {
        $varsToInject['args'] = $Arguments
    }

    $functionsToInject = @{}
    
    if (!$NoAutoCapture) {
        $commandAsts = $ast.FindAll({ 
            param($node) 
            $node -is [System.Management.Automation.Language.CommandAst] 
        }, $true)
        
        $calledCommands = $commandAsts | ForEach-Object {
            $cmdElement = $_.CommandElements[0]
            if ($cmdElement -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $cmdElement.Value
            }
        } | Select-Object -Unique
        
        foreach ($cmdName in $calledCommands) {
            if (!$cmdName) { continue }
            
            $cmdInfo = Get-Command -Name $cmdName -ErrorAction SilentlyContinue
            
            if ($cmdInfo -and $cmdInfo.CommandType -eq 'Function') {
                $funcDef = $cmdInfo.Definition
                if ($funcDef -and !$functionsToInject.ContainsKey($cmdName)) {
                    $functionsToInject[$cmdName] = $funcDef
                }
            }
        }
    }
    
    Write-Debug "Injecting $($varsToInject.Count) variable(s), $($functionsToInject.Count) function(s)"

    # Capture session ID so we can restore it on the UI thread when OnComplete fires
    $capturedSessionId = [PsUi.SessionManager]::CurrentSessionId
    
    $state = [hashtable]::Synchronized(@{
        Results    = [System.Collections.Generic.List[object]]::new()
        Errors     = [System.Collections.Generic.List[object]]::new()
        OnComplete = $OnComplete
        OnError    = $OnError
        Executor   = $executor
        SessionId  = $capturedSessionId
    })

    $executor.add_OnPipelineOutput({
        param($obj)
        if ($null -ne $obj) {
            [void]$state.Results.Add($obj)
        }
    }.GetNewClosure())
    
    $executor.add_OnError({
        param($errorRecord)
        # $errorRecord is now PSErrorRecord - format nicely for collection
        if ($null -ne $errorRecord) {
            # Use the ToDetailedString method if available, otherwise build our own
            $formatted = if ($errorRecord.PSObject.Methods.Match('ToDetailedString')) {
                $errorRecord.ToDetailedString()
            }
            else {
                # Fallback for backwards compatibility
                $details = [System.Collections.Generic.List[string]]::new()
                $details.Add("ERROR: $($errorRecord.Message)")
                
                if ($errorRecord.LineNumber -gt 0) { 
                    $details.Add("Line: $($errorRecord.LineNumber)") 
                }
                
                if ($errorRecord.ScriptName) { 
                    $details.Add("Script: $($errorRecord.ScriptName)") 
                }
                
                if ($errorRecord.Line) { 
                    $details.Add("Code: $($errorRecord.Line)") 
                }
                
                if ($errorRecord.ScriptStackTrace) { 
                    $details.Add("`nStack Trace:`n$($errorRecord.ScriptStackTrace)") 
                }
                
                $details -join "`n"
            }
            
            [void]$state.Errors.Add($formatted)
        }
    }.GetNewClosure())
    
    # Completion callback - runs on UI thread via AsyncExecutor's MarshalToUi
    $executor.add_OnComplete({
        try {
            # Restore session context on UI thread so Set-UiValue and other functions work
            if ($state.SessionId -ne [Guid]::Empty) {
                [PsUi.SessionManager]::SetCurrentSession($state.SessionId)
            }
            
            if ($state.Errors.Count -gt 0 -and $state.OnError) {
                & $state.OnError ($state.Errors -join "`n`n")
            }
            elseif ($state.OnComplete) {
                if ($state.Results.Count -eq 0)     { & $state.OnComplete $null }
                elseif ($state.Results.Count -eq 1) { & $state.OnComplete $state.Results[0] }
                else                                { & $state.OnComplete @($state.Results) }
            }
        }
        catch { Write-Warning "Invoke-UiAsync OnComplete error: $_" }
        finally {
            if ($state.Executor) { $state.Executor.Dispose() }
        }
    }.GetNewClosure())

    if ($Capture) {
        $executor.CaptureVariables = [string[]]$Capture
    }

    Write-Debug "Dispatching to AsyncExecutor"
    $executor.ExecuteAsync($ScriptBlock, $null, $varsToInject, $functionsToInject, $null)

    return [PSCustomObject]@{
        Executor = $executor
        Cancel   = { 
            $executor.Cancel()
            $executor.Dispose()
        }.GetNewClosure()
    }
}
