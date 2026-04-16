<#
.SYNOPSIS
    Initializes a new WPF session context for window state management.
#>
function Initialize-UiSession {
    [CmdletBinding()]
    param()

    if (![PsUi.ModuleContext]::IsInitialized) {
        throw "PsUi requires the C# backend to be compiled. Please ensure the module loaded correctly."
    }
    
    $sessionId = [PsUi.SessionManager]::CreateSession()
    [PsUi.SessionManager]::SetCurrentSession($sessionId)
    
    # Also update the global variable so Get-UiSession finds the new session
    # This is critical for child windows which create their own sessions
    $Global:__PsUiSessionId = $sessionId.ToString()
    
    Write-Debug "Created new session: $sessionId, ThreadId: $([System.Threading.Thread]::CurrentThread.ManagedThreadId)"
    
    return [PsUi.SessionManager]::Current
}
