function Set-UiCapturedVariable {
    <#
    .SYNOPSIS
        Stores a value that later actions in the window receive as a variable.
    .DESCRIPTION
        Typically, an asyc action in PsUi does not return variables created during the action.
        This captures a value for later use in other actions. Every async action after this
        gets it back as a variable of that name, -EnabledWhen controls follow it, and
        New-UiWindow -ExportOnClose hands it to your script. Use it where -Capture can't,
        such as a -NoAsync action, a hotkey or the -Content block.
    .PARAMETER Name
        The variable name later actions see without the $.
    .PARAMETER Value
        The value to store. $null is allowed.
    .EXAMPLE
        New-UiButton -Text 'Run' -NoOutput -Action {
            Start-Sleep -Seconds 2
            Set-UiCapturedVariable -Name 'lastRun' -Value (Get-Date)
        }
        New-UiButton -Text 'Last run' -Action { Write-Host "Last run: $lastRun" }

        The first button records when it finished, and the second reads it back as $lastRun.
    .EXAMPLE
        New-UiButton -Text 'Sign in' -NoAsync -Action {
            $account = Show-UiCredentialDialog -Caption 'Sign in' -Message 'Mail account'
            if ($account) { Set-UiCapturedVariable 'account' $account }
        }
        New-UiButton -Text 'Check mail' -EnabledWhen 'account' -Action {
            Write-Host "Checking mail for $($account.UserName)"
        }

        A -NoAsync action has no runspace for -Capture to read from, so it stores the
        credential itself. Check mail stays disabled until then.
    .NOTES
        A stored value beats a control or a script variable of the same name, and loses to one
        passed through -Variables or -LinkedVariables.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [AllowNull()]
        [object]$Value
    )

    # The store takes any name but hydration only writes valid ones
    if (![PsUi.Constants]::IsValidIdentifier($Name) -or [PsUi.Constants]::IsReservedVariable($Name)) {
        Write-Error "Set-UiCapturedVariable: '$Name' can't reach an action as a variable. Use letters, digits and underscores, and avoid PowerShell's automatic variables and PsUi's own 'state' and 'session'."
        return
    }

    $session = Get-UiSession
    if (!$session) { Write-Warning "Set-UiCapturedVariable: No active UI session found."; return }

    $session.SetCapturedVariable($Name, $Value)
}
