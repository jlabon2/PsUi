function Reset-UiSession {
    <#
    .SYNOPSIS
        Resets the PsUi module state after a crash or error.
    .DESCRIPTION
        Clears all active sessions, resets the ThemeEngine, and restores the module
        to a clean state. Use this when a script crashes mid-execution and you can't
        run New-UiWindow again in the same console.
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
