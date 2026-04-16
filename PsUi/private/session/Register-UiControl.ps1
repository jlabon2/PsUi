<#
.SYNOPSIS
    Registers a WPF control in the current session.
#>
function Register-UiControl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        $Control
    )

    $session = Get-UiSession
    $session.Controls[$Name] = $Control
}
