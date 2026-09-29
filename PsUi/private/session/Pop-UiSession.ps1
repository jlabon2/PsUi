function Pop-UiSession {
    <#
    .SYNOPSIS
        Puts back the session Push-UiSession replaced, unless the thread has moved on since.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [hashtable]$Token
    )

    if (!$Token) { return }

    $pushedOpen = [bool][PsUi.SessionManager]::GetSession($Token.SessionId)
    $priorOpen  = [bool][PsUi.SessionManager]::GetSession($Token.PriorId)

    # Current but not pushed means the action opened a nonmodal child
    if ($pushedOpen -and [PsUi.SessionManager]::CurrentSessionId -ne $Token.SessionId) { return }

    if (!$pushedOpen) {
        $current = [PsUi.SessionManager]::Current
        if (!$priorOpen -or ($current -and $current.Created -ge $Token.PushedAt)) { return }
    }

    # Once the replaced window has closed (a parent button closing its child) the thread stays where the push put it since the dead id would leave Get-UiSession returning $null
    if ($Token.PriorId -ne [Guid]::Empty -and !$priorOpen) { return }

    [PsUi.SessionManager]::SetCurrentSession($Token.PriorId)
    if ($Token.HadGlobal) { $Global:__PsUiSessionId = $Token.PriorGlobal }
    else { Remove-Variable -Name __PsUiSessionId -Scope Global -ErrorAction SilentlyContinue }
}
