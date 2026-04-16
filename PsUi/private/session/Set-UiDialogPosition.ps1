function Set-UiDialogPosition {
    <#
    .SYNOPSIS
        Sets dialog owner and centers it on the parent PsUi window.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Dialog
    )

    # Try to get the parent window from current session
    # Check ActiveDialogParent first (set by Show-StreamingOutput), then fall back to main Window
    $parentWindow = $null
    try {
        $session = [PsUi.SessionManager]::Current
        if ($session) {
            # Prefer the active output window if set
            if ($session.ActiveDialogParent) {
                $parentWindow = $session.ActiveDialogParent
            }
            elseif ($session.Window) {
                $parentWindow = $session.Window
            }
        }
    }
    catch {
        Write-Debug "Could not get session window: $_"
    }

    # If no session window, try Application.Current.MainWindow
    if (!$parentWindow) {
        try {
            $app = [System.Windows.Application]::Current
            if ($app -and $app.MainWindow) {
                $parentWindow = $app.MainWindow
            }
        }
        catch {
            Write-Debug "Could not get MainWindow: $_"
        }
    }

    if ($parentWindow) {
        # Set owner for proper modal behavior and window management
        try {
            $Dialog.Owner = $parentWindow
        }
        catch {
            Write-Debug "Could not set dialog owner: $_"
        }

        # Center on parent (handles multi-monitor correctly)
        [PsUi.WindowManager]::CenterOnParent($Dialog, $parentWindow)
    }
}
