function Invoke-OnUIThread {
    <#
    .SYNOPSIS
        Marshals code execution to the UI dispatcher thread.
        Used to safely update WPF controls from background threads
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [switch]$Async
    )

    $session    = Get-UiSession
    $dispatcher = $null

    # Try session window first, then fall back to Application.Current
    if ($session -and $session.Window) { $dispatcher = $session.Window.Dispatcher }
    if ($null -eq $dispatcher) { $dispatcher = [System.Windows.Application]::Current.Dispatcher }

    if ($null -eq $dispatcher) { return & $ScriptBlock }

    if ($dispatcher.CheckAccess()) { return & $ScriptBlock }

    if ($Async) {
        [void]$dispatcher.BeginInvoke([Action]$ScriptBlock, $null)
        return
    }

    # BeginInvoke + Wait avoids the deadlock that a direct Invoke causes here
    $operation = $dispatcher.BeginInvoke([Func[object]]$ScriptBlock, $null)

    try {
        $operation.Wait()
    }
    catch [System.AggregateException] {
        # OperationCanceledException = dispatcher isn't running (tests, no UI window)
        $inner = $_.Exception.InnerException
        if ($inner -is [System.OperationCanceledException]) { return & $ScriptBlock }
        if ($inner) { throw $inner }
        throw
    }

    # Wait() may not surface every failure mode, so inspect status as well
    switch ($operation.Status) {
        'Completed' { return $operation.Result }
        'Faulted'   {
            $ex = $operation.Exception
            if ($ex.InnerException) { $ex = $ex.InnerException }
            throw $ex
        }
        'Aborted'   { return & $ScriptBlock }
        default     { return $null }
    }
}
