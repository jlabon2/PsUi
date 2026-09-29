function Invoke-OnUIThread {
    <#
    .SYNOPSIS
        Runs a block on the window's UI thread and returns whatever it outputs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [switch]$Async,

        # The block's param() values in order. Passing any switches the call to the copy parsed from text further down.
        [object[]]$ArgumentList,

        # Session window's by default
        [System.Windows.Threading.Dispatcher]$Dispatcher
    )

    # Splatting $null hands the block one $null argument
    if ($null -eq $ArgumentList) { $ArgumentList = @() }

    if (!$Dispatcher) {
        $session = Get-UiSession

        if ($session -and $session.Window) { $Dispatcher = $session.Window.Dispatcher }
        if ($null -eq $Dispatcher) { $Dispatcher = [System.Windows.Application]::Current.Dispatcher }
    }

    # No UI thread to go to (or this is it)
    $runHere = $null -eq $Dispatcher -or $Dispatcher.CheckAccess()

    $packet = $null
    if (!$runHere) {
        if ($PSBoundParameters.ContainsKey('ArgumentList')) {
            # The block as written belongs to this runspace, which is parked in Wait() below, so the UI thread tries to hand it back and only runs it itself after 250ms, every call
            
            if (!$script:_uiThreadRunner) {
                # New-UiWindow and Out-Datagrid inject the private functions on the UI thread. Anywhere else defines them for the call.
                # Left alone, the block's warnings and errors go to the UI thread's own pipeline and a throw goes to Dispatcher.UnhandledException. This side never sees either.
                # Stops at the first failed line; noth preferences at Continue leave the calling script's in place
                $script:_uiThreadRunner = [Func[object, object]][scriptblock]::Create('
                    param($packet)
                    trap { $packet.Thrown = $_; continue }
                    if (!${function:Invoke-OnUIThread}) {
                        foreach ($entry in [PsUi.ModuleContext]::PrivateFunctions.GetEnumerator()) {
                            Set-Item -LiteralPath "function:$($entry.Key)" -Value ([scriptblock]::Create([string]$entry.Value))
                        }
                    }
                    $ErrorActionPreference = ''Continue''
                    $WarningPreference     = ''Continue''
                    & { $packet.Output = $packet.Invoker.Invoke($packet) } 2>&1 3>&1 | & { process { $packet.Records.Add($_) } }
                ')

                # A func of its own, so the output converts the way $operation.Result does on the path without -ArgumentList
                $script:_uiThreadInvoker = [Func[object, object]][scriptblock]::Create('param($packet) $argList = $packet.Arguments; & $packet.Work @argList')
            }

            $packet = @{
                Work      = [scriptblock]::Create($ScriptBlock.ToString())
                Arguments = $ArgumentList
                Invoker   = $script:_uiThreadInvoker
                Records   = [System.Collections.Generic.List[object]]::new()
            }
            $operation = $Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Normal, $script:_uiThreadRunner, $packet)
            if ($Async) { return }
        }
        elseif ($Async) {
            [void]$Dispatcher.BeginInvoke([Action]$ScriptBlock, $null)
            return
        }
        else {
            # BeginInvoke + Wait, since a direct Invoke deadlocks here
            $operation = $Dispatcher.BeginInvoke([Func[object]]$ScriptBlock, $null)
        }

        try { $null = $operation.Wait() }
        catch [System.AggregateException] {
            # OperationCanceledException means the UI thread isn't running
            $inner = $_.Exception.InnerException
            if ($inner -isnot [System.OperationCanceledException]) {
                if ($inner) { throw $inner }
                throw
            }
            $runHere = $true
        }

        # UI thread shut down first
        if ($operation.Status -eq 'Aborted') { $runHere = $true }
    }

    if ($runHere) {
        # The block's errors and warnings come straight out of this function, but a failed line still needs a trap or the try around a -NoAsync action ends the action there
        # Throws, Stops, pipeline stops and -First's early finish go up untouched. The untyped trap can't tell a Stop from the record under it and would silence the last two, so the three that aren't throws get typed traps
        $packet = @{ Thrown = $null }
        & {
            trap [System.Management.Automation.ActionPreferenceStopException] { break }
            trap [System.Management.Automation.PipelineStoppedException] { break }
            trap [System.Management.Automation.FlowControlException] { break }
            trap {
                # Thrown exception objects lack the throw flag but still point at the throw
                # Rethrown from a catch, it points at the line it rethrows and carries on like that line would
                $at      = $_.InvocationInfo
                $flagged = $_.Exception -is [System.Management.Automation.RuntimeException] -and $_.Exception.WasThrownFromThrowStatement
                $atThrow = $at -and $at.OffsetInLine -gt 0 -and $at.Line.Length -ge $at.OffsetInLine -and $at.Line.Substring($at.OffsetInLine - 1) -match '^throw\b'
                if ($flagged -or $atThrow) { break }
                $packet.Thrown = $_
                continue
            }
            & $ScriptBlock @ArgumentList
        }
    }
    else {
        if ($operation.Status -ne 'Completed') { return $null }
        if (!$packet) { return $operation.Result }

        # -WarningAction and -ErrorAction on the helper get their say here
        foreach ($record in $packet.Records) {
            if ($record -is [System.Management.Automation.WarningRecord]) { $PSCmdlet.WriteWarning($record.Message) }
            else { $PSCmdlet.WriteError($record) }
        }

        if (!$packet.Thrown) { return $packet.Output }
    }
    if (!$packet.Thrown) { return }

    # The trap's record points at the runner, the exception at the block
    $exception = $packet.Thrown.Exception
    $failure   = $packet.Thrown
    if ($exception -is [System.Management.Automation.IContainsErrorRecord]) {
        # On a failed property set the record carries ParentContainsErrorRecordException, this constructor puts the real exception back the way PS does
        $failure = [System.Management.Automation.ErrorRecord]::new($exception.ErrorRecord, $exception)
    }

    # A throw or a Stop ends the action. Any other failed line is an error the action carries on past, a method call included.
    $isThrow = $exception -is [System.Management.Automation.ActionPreferenceStopException] -or
        ($exception -is [System.Management.Automation.RuntimeException] -and $exception.WasThrownFromThrowStatement)
    if ($isThrow) { throw $failure }
    $PSCmdlet.WriteError($failure)
}
