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

    if ($noAsync) {
        # Run synchronously on UI thread
        try {
            & $action
        }
        catch {
            Write-Warning "Hotkey action failed (error occured): $_"
        }
    }
    else {
        # Run async using standard pattern
        Invoke-UiAsync -ScriptBlock $action
    }
}
