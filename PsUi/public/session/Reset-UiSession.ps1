function Reset-UiSession {
    <#
    .SYNOPSIS
        Resets the PsUi module state after a crash or error.
    .DESCRIPTION
        Clears all active sessions, resets the ThemeEngine, shuts down the runspace
        pool. Use this when a script crashes mid-execution and you can't run New-UiWindow
        again in the same console. Or don't want to restart the console for whatever reason.
    .EXAMPLE
        Reset-UiSession
        # Now you can run New-UiWindow again
    #>
    [CmdletBinding()]
    param()
    
    if (![PsUi.ModuleContext]::IsInitialized) {
        Write-Warning "PsUi module not initialized. Nothing to reset."
        return
    }

    $sessionCount = [PsUi.SessionManager]::ActiveSessionCount

    [PsUi.SessionManager]::Reset()
    [PsUi.ThemeEngine]::Reset()
    [PsUi.RunspacePoolManager]::Shutdown()
    
    if ($sessionCount -gt 0) {
        Write-Host "Reset complete. Cleared $sessionCount orphaned session(s)." -ForegroundColor Green
    }
    else {
        Write-Host "Reset complete. No orphaned sessions found." -ForegroundColor Gray
    }
}
