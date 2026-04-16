function Set-WindowOwner {
    <#
    .SYNOPSIS
        Sets the Owner property on a window from the current session context.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )

    # Get parent window from session if available
    $parentWindow = $null
    try {
        $session = Get-UiSession
        if ($session -and $session.Window) { $parentWindow = $session.Window }
    }
    catch { <# No session context #> }

    if (!$parentWindow) { return $false }

    # Update startup location to center on owner
    $Window.WindowStartupLocation = 'CenterOwner'

    try {
        $Window.Owner = $parentWindow
        return $true
    }
    catch {
        Write-Debug "Could not set Owner: $_"
        $Window.WindowStartupLocation = 'CenterScreen'
        return $false
    }
}
