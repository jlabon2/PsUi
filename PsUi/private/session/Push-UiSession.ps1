function Push-UiSession {
    <#
    .SYNOPSIS
        Makes one session current on this thread and hands back what it replaced, for Pop-UiSession.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # Nullable so a click without an id can pass its $null straight through where just [Guid] throws
        [Nullable[Guid]]$SessionId
    )

    # If the id is missing or its window already closed, the thread keeps what it has
    if ($null -eq $SessionId -or $SessionId -eq [Guid]::Empty) { return $null }
    if ($null -eq [PsUi.SessionManager]::GetSession($SessionId)) { return $null }

    $token = @{
        SessionId   = $SessionId
        PriorId     = [PsUi.SessionManager]::CurrentSessionId
        HadGlobal   = Test-Path variable:Global:__PsUiSessionId
        PriorGlobal = $Global:__PsUiSessionId
        PushedAt    = [DateTime]::Now
    }

    # Get-UiSession reads the global before the thread's id
    [PsUi.SessionManager]::SetCurrentSession($SessionId)
    $Global:__PsUiSessionId = $SessionId.ToString()
    return $token
}
