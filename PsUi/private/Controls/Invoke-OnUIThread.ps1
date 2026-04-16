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

    $session = Get-UiSession
    $dispatcher = $null
    
    # Try session window first, then fall back to Application.Current
    if ($session -and $session.Window) { $dispatcher = $session.Window.Dispatcher }
    if ($null -eq $dispatcher) { $dispatcher = [System.Windows.Application]::Current.Dispatcher }
    
    # No dispatcher - run directly
    if ($null -eq $dispatcher) { return & $ScriptBlock }

    # Already on UI thread - execute directly
    if ($dispatcher.CheckAccess()) { return & $ScriptBlock }
    
    # Not on UI thread - marshal to UI thread dispatcher
    if ($Async) {
        # Fire and forget
        [void]$dispatcher.BeginInvoke([Action]$ScriptBlock, $null)
    }
    else {
        # Use BeginInvoke + Wait to avoid deadlock
        # Direct Invoke would block the calling thread and prevent the dispatcher from processing the request
        $operation = $dispatcher.BeginInvoke([Func[object]]$ScriptBlock, $null)
        
        # Wait for completion without blocking dispatcher
        $operation.Wait()
        
        if ($operation.Status -eq 'Completed') { return $operation.Result }
    }
}