function Invoke-UiHotkeyAction {
    <#
    .SYNOPSIS
        Executes a registered hotkey action.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $action  = $Context.Action
    $noAsync = $Context.NoAsync

    if (!$action) {
        Write-Warning "Hotkey action is null"
        return
    }

    $sessionToken = Push-UiSession -SessionId $Context.SessionId

    if ($noAsync) {
        try { $null = Invoke-UiCallback -ScriptBlock $action -Label 'Hotkey action' }
        catch { Write-Warning "Hotkey action error: $_" }
    }
    else {
        # Run async using standard pattern
        $null = Invoke-UiAsync -ScriptBlock $action
    }

    Pop-UiSession -Token $sessionToken
}
