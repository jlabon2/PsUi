function Assert-UiSession {
    <#
    .SYNOPSIS
        Returns the session or throws. With no session at all, an implicit window gets built first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CallerName
    )

    $session   = Get-UiSession
    $sessionId = [PsUi.SessionManager]::CurrentSessionId

    Write-Debug "Called by $CallerName, SessionId=$sessionId, Session is null: $($null -eq $session), CurrentParent is null: $($null -eq $session.CurrentParent)"

    # No session means no window was explictly called.
    if (!$session) {
        $callerCmdlet = (Get-Variable -Scope 1 -Name PSCmdlet -ErrorAction SilentlyContinue).Value
        $ending       = $false
        if ($callerCmdlet) {
            $ending = Invoke-UiImplicitWindow -CallerName $CallerName -CallerState $callerCmdlet.SessionState
        }

        # Window popped up and the user closed it. A script file exits clean, but a block typed at a prompt has nothing to exit, so its pipeline stops instead.
        if ($ending -eq 'Exit') { exit 0 }
        if ($ending) { throw [System.Management.Automation.PipelineStoppedException]::new() }
    }

    if (!$session -or !$session.CurrentParent) {
        throw "$CallerName must be called inside a New-UiWindow or New-UiPanel content block. No active parent container found."
    }

    return $session
}
