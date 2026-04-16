<#
.SYNOPSIS
    Gets the current WPF session context.
#>
function Get-UiSession {
    [CmdletBinding()]
    param()
    
    if (![PsUi.ModuleContext]::IsInitialized) {
        throw "PsUi requires the C# backend to be compiled. Please ensure the module loaded correctly."
    }
    
    # Check for runspace-injected session ID first (survives RunspacePool thread switches)
    if ($Global:__PsUiSessionId) {
        $injectedSession = [PsUi.SessionManager]::GetSession([Guid]$Global:__PsUiSessionId)
        if ($injectedSession) {
            return $injectedSession
        }
    }
    
    # Fall back to ThreadStatic lookup (works for UI thread and dedicated runspaces)
    $current = [PsUi.SessionManager]::Current
    if (!$current) {
        Write-Verbose "Get-UiSession: No active session found on this thread."
    }
    return $current
}
