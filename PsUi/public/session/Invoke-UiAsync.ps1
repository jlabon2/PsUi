function Invoke-UiAsync {
    <#
    .SYNOPSIS
        Runs a scriptblock in the background without freezing the UI.
    .DESCRIPTION
        Runs the scriptblock off the UI thread so the window keeps responding while it works.
        Variables and functions from the calling scope come along automatically; pass extra
        ones with -Variables, or shut auto-capture off with -NoAutoCapture.
    .PARAMETER ScriptBlock
        Code to run in background.
    .PARAMETER OnComplete
        Code to run when done. Receives the result as parameter. Runs on every finish that wasn't
        cancelled, errors or not, so a run that wrote to the error stream and still returned data
        delivers that data here as well as reporting through OnError.
    .PARAMETER OnError
        Code to run when the background script wrote to the error stream. Receives the joined error
        text. A non-terminating error counts, so this can fire on a run that still produced results
        and still reaches OnComplete.
    .PARAMETER OnHost
        Per-record Write-Host handler for background output. Receives the emitted record.
        Background runspaces have no console-visible host of their own; hook this to route
        Write-Host somewhere useful (status text, log panel, existing output window).
    .PARAMETER Arguments
        Arguments to pass to the scriptblock (legacy compatibility).
    .PARAMETER Variables
        Hashtable of variables to pass to the background runspace.
    .PARAMETER Capture
        Variable names to capture from the runspace after execution completes.
        Captured variables are stored in the session and available to subsequent
        async calls. They reach the calling script's scope after close only when the
        window was opened with -ExportOnClose.
    .PARAMETER NoAutoCapture
        Disables automatic variable capture from the calling scope. Use when you want
        full control over what's passed in.
    .PARAMETER NoActiveExecutor
        Leaves the session's ActiveExecutor slot alone, so Stop-UiAsync and the status
        bar's AutoCancel keep targeting whatever was already running. For background
        maintenance work (count scans, prefetches) that shouldn't own Cancel.
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

        [scriptblock]$OnHost,

        [object[]]$Arguments,

        [hashtable]$Variables,

        [string[]]$Capture,

        [switch]$NoAutoCapture,

        [switch]$NoActiveExecutor
    )

    if ($Capture) {
        foreach ($varName in $Capture) {
            if (![PsUi.Constants]::IsValidIdentifier($varName)) {
                throw "Invalid variable name for -Capture: '$varName'. Names must start with a letter or underscore and contain only letters, numbers, underscores, or hyphens."
            }
        }
    }

    Write-Debug "Starting async execution, AutoCapture=$(!$NoAutoCapture)"

    $__executor = [PsUi.AsyncExecutor]::new()

    # Every callback the run raises (OnComplete included) is queued on this thread. Application.Current pins to whichever window came up FIRST and keeps pointing at that thread for the rest of the process, so a second window queues its completion onto a thread that already exited - BeginInvoke swallows it and OnComplete never fires, while the action itself still runs. Session window first, same order Invoke-OnUIThread uses.
    $execSession  = [PsUi.SessionManager]::Current
    $uiDispatcher = if ($execSession -and $execSession.Window) { $execSession.Window.Dispatcher }
                    elseif ([System.Windows.Application]::Current) { [System.Windows.Application]::Current.Dispatcher }
    if ($uiDispatcher) { $__executor.UiDispatcher = $uiDispatcher }

    # Store executor in session for Stop-UiAsync cancellation
    if ($execSession -and !$NoActiveExecutor) { $execSession.ActiveExecutor = $__executor }

    $__varsToInject = @{}

    # Auto-capture variables from ScriptBlock using AST (same as New-UiButton)
    if (!$NoAutoCapture) {
        $ast         = $ScriptBlock.Ast
        # PS automatic variables, plus state/session - the executor's reserved list refuses to inject those two names anyway, so capturing them is wasted work.
        # executor/varsToInject/functionsToInject are gone from this list: having a name here silently dropped a user's same-named variable from capture. The __ prefix on the locals is hygiene, not the fix - the scope walk starts at -Scope 1 and never saw function locals.
        $builtinVars = @(
            '_', 'PSItem', 'this', 'args', 'input', 'PSCmdlet', 'PSBoundParameters',
            'MyInvocation', 'ExecutionContext', 'null', 'true', 'false', 'PSScriptRoot',
            'PSCommandPath', 'PID', 'Host', 'PSVersionTable', 'Error', 'StackTrace',
            'HOME', 'PROFILE', 'PSCulture', 'PSUICulture', 'ShellId', 'NestedPromptLevel',
            'state', 'session'
        )

        $referencedVars = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Select-Object -Unique

        foreach ($varName in $referencedVars) {
            if ($varName -notin $builtinVars) {
                # Walk up the scope chain until hitting Global or an out-of-range index. Handles deeply nested modules/jobs where scope > 10.
                $scopeIndex = 1
                $foundValue = $false
                while (!$foundValue) {
                    try {
                        $val = Get-Variable -Name $varName -Scope $scopeIndex -ValueOnly -ErrorAction Stop
                        $__varsToInject[$varName] = $val
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
            $__varsToInject[$key] = $Variables[$key]
        }
    }

    # Add Arguments as $args if provided (legacy compatibility)
    if ($Arguments) { $__varsToInject['args'] = $Arguments }

    $__functionsToInject = @{}

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
                if ($funcDef -and !$__functionsToInject.ContainsKey($cmdName)) {
                    $__functionsToInject[$cmdName] = $funcDef
                }
            }
        }
    }

    Write-Debug "Injecting $($__varsToInject.Count) variable(s), $($__functionsToInject.Count) function(s)"

    # Capture session ID for restore on the UI thread when OnComplete fires
    $capturedSessionId = [PsUi.SessionManager]::CurrentSessionId

    $state = [hashtable]::Synchronized(@{
        Results       = [System.Collections.Generic.List[object]]::new()
        Errors        = [System.Collections.Generic.List[object]]::new()
        OnComplete    = $OnComplete
        OnError       = $OnError
        Executor      = $__executor
        SessionId     = $capturedSessionId
        OnHostHandler = $null
    })

    $__executor.add_OnPipelineOutput({
        param($obj)
        if ($null -ne $obj) {
            [void]$state.Results.Add($obj)
        }
    }.GetNewClosure())

    # Per-record Write-Host pass-through for context-menu and cell-button async actions. Background runspaces have no visible host. No fallback if $OnHost isn't attached.
    if ($OnHost) {
        $hostRef = $OnHost
        $hostHandler = {
            param($record)
            try { & $hostRef $record }
            catch { Write-Debug "OnHost handler failed: $_" }
        }.GetNewClosure()
        $state.OnHostHandler = $hostHandler
        $__executor.add_OnHost($hostHandler)
    }

    $__executor.add_OnError({
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

                if ($errorRecord.LineNumber -gt 0) { $details.Add("Line: $($errorRecord.LineNumber)") }
                if ($errorRecord.ScriptName) { $details.Add("Script: $($errorRecord.ScriptName)") }
                if ($errorRecord.Line) { $details.Add("Code: $($errorRecord.Line)") }
                if ($errorRecord.ScriptStackTrace) { $details.Add("`nStack Trace:`n$($errorRecord.ScriptStackTrace)") }

                $details -join "`n"
            }

            [void]$state.Errors.Add($formatted)
        }
    }.GetNewClosure())

    # Completion callback - runs on UI thread via AsyncExecutor's MarshalToUi
    # trap, NOT try/finally. A finally here means the teardown below never runs and every handler registered after this one goes with it, the status bar's own OnComplete sits right behind this. Same trap New-UiDataGrid uses. An inner try/catch with no finally is safe.
    $__executor.add_OnComplete({
        trap { Write-Warning "Invoke-UiAsync OnComplete error: $_"; continue }

        # Restore session context on UI thread so Set-UiValue and other functions work
        if ($state.SessionId -ne [Guid]::Empty) {
            [PsUi.SessionManager]::SetCurrentSession($state.SessionId)
        }

        if ($state.Errors.Count -gt 0 -and $state.OnError) {
            & $state.OnError ($state.Errors -join "`n`n")
        }

        # Not an elseif... one Write-Error would route the whole run to OnError and throw the pipeline output away, including the results from every row that worked.
        if ($state.OnComplete) {
            if ($state.Results.Count -eq 0)     { & $state.OnComplete $null }
            elseif ($state.Results.Count -eq 1) { & $state.OnComplete $state.Results[0] }
            else                                { & $state.OnComplete @($state.Results) }
        }

        # Drop OnHost before Dispose. Redundant with Dispose's own handler nulling - it stays because the add/remove pairing reads clearer than leaning on a Dispose side effect.
        if ($state.OnHostHandler -and $state.Executor) {
            try { $state.Executor.remove_OnHost($state.OnHostHandler) } catch { }
            $state.OnHostHandler = $null
        }
        if ($state.Executor) { $state.Executor.Dispose() }
    }.GetNewClosure())

    # Cancel() fires OnCancelled, not OnComplete, so the disposer above never runs on a Stop-UiAsync / AutoCancel cancel. The executor (its CTS + handler delegates) would sit rooted in ActiveExecutor until GC. Same teardown New-UiButton's cancel path does.
    $__executor.add_OnCancelled({
        if ($state.OnHostHandler -and $state.Executor) {
            try { $state.Executor.remove_OnHost($state.OnHostHandler) } catch { }
            $state.OnHostHandler = $null
        }
        if ($state.Executor) { $state.Executor.Dispose() }
    }.GetNewClosure())

    if ($Capture) {
        $__executor.CaptureVariables = [string[]]$Capture
    }

    Write-Debug "Dispatching to AsyncExecutor"
    $__executor.ExecuteAsync($ScriptBlock, $null, $__varsToInject, $__functionsToInject, $null)

    return [PSCustomObject]@{
        Executor = $__executor
        Cancel   = {
            $__executor.Cancel()
            $__executor.Dispose()
        }.GetNewClosure()
    }
}
