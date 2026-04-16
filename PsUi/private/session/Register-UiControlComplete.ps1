<#
.SYNOPSIS
    Registers a WPF control in all session registries.
#>
function Register-UiControlComplete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        $Control,

        [object]$InitialValue,

        [switch]$RegisterTheme
    )

    $session = Get-UiSession
    Write-Debug "Registering '$Name', Control type: $($Control.GetType().Name)"
    
    $session.Variables[$Name] = $Control
    $session.Controls[$Name] = $Control

    $sessionObj = [PsUi.SessionManager]::Current
    Write-Debug "SessionManager.Current is null: $($null -eq $sessionObj)"
    
    if ($sessionObj) {
        try {
            $sessionObj.AddControlSafe($Name, $Control)
            Write-Debug "AddControlSafe succeeded for '$Name'"
        }
        catch {
            Write-Warning "AddControlSafe failed for '$Name': $_"
        }
    }
    else {
        Write-Warning "[Register-UiControlComplete] SessionManager.Current is NULL - cannot register '$Name' for hydration!"
    }

    if ($RegisterTheme) {
        try {
            [PsUi.ThemeEngine]::RegisterElement($Control)
        }
        catch { Write-Debug "ThemeEngine registration failed: $_" }
    }
}
