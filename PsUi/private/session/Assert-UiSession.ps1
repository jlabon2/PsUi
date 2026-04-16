<#
.SYNOPSIS
    Validates the UI session and returns it, or throws if invalid.
#>
function Assert-UiSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CallerName
    )

    $session = Get-UiSession
    $sessionId = [PsUi.SessionManager]::CurrentSessionId
    Write-Debug "Called by $CallerName, SessionId=$sessionId, Session is null: $($null -eq $session), CurrentParent is null: $($null -eq $session.CurrentParent)"
    
    if (!$session -or !$session.CurrentParent) {
        throw "$CallerName must be called inside a New-UiWindow or New-UiPanel content block. No active parent container found."
    }

    return $session
}
