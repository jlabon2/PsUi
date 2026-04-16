function Stop-UiAsync {
    <#
    .SYNOPSIS
        Cancels the currently running async operation.
    .DESCRIPTION
        Stops the active background script running in the current session.
        If no async operation is running, this function does nothing.
        The cancelled script's OnComplete handler will not fire.
    .EXAMPLE
        New-UiButton -Text 'Cancel' -Action { Stop-UiAsync } -NoAsync
        # Cancel button that stops any running async operation
    .EXAMPLE
        Register-UiHotkey -Key 'Escape' -Action { Stop-UiAsync } -NoAsync
        # Escape key cancels the current operation
    #>
    [CmdletBinding()]
    param()

    $session = [PsUi.SessionManager]::Current
    if (!$session) {
        Write-Debug "No session - nothing to cancel"
        return
    }

    $executor = $session.ActiveExecutor
    if (!$executor) {
        Write-Debug "No active executor - nothing to cancel"
        return
    }

    Write-Debug "Cancelling active async operation"
    $executor.Cancel()
    
    # Note: ActiveExecutor gets cleared by the executor's completion handlers
}
