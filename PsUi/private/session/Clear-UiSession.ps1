<#
.SYNOPSIS
    Clears the current WPF session context.
#>
function Clear-UiSession {
    [CmdletBinding()]
    param()
    
    if (![PsUi.ModuleContext]::IsInitialized) {
        throw "PsUi requires the C# backend to be compiled. Please ensure the module loaded correctly."
    }
    
    $currentId = [PsUi.SessionManager]::CurrentSessionId
    if ($currentId -ne [Guid]::Empty) {
        [PsUi.SessionManager]::DisposeSession($currentId)
    }
    
    $newId = [PsUi.SessionManager]::CreateSession()
    [PsUi.SessionManager]::SetCurrentSession($newId)

    # Keep the global session ID in sync so Get-UiSession finds the right session
    $Global:__PsUiSessionId = $newId.ToString()
}
