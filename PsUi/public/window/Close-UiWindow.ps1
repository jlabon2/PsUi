function Close-UiWindow {
    <#
    .SYNOPSIS
        Closes the window your code is running in (or the window that opened it).
    .DESCRIPTION
        Works anywhere PsUi calls code. The window goes the way it would from its own close button.
        -OnClosed, a -Modal child returns $false, and -ExportOnClose still hands back what
        the window captured. From an async action the window closes when the action ends,and a
        canceled action leaves it open.
    .PARAMETER Window
        Which window to close. Also taken by position (eg Close-UiWindow Main).

        - Current: the window the code is running in. Default.
        - Parent: the window that opened this child window. The child closes with it.
        - Main: the New-UiWindow window at the top and every child window with it.
    .PARAMETER Prompt
        Confirms first, with Yes and No buttons. No leaves the window open. -Prompt:$false turns the
        question off even with -Message so -Prompt:$unsaved asks only when $unsaved is true.
    .PARAMETER Message
        The prompt to ask. The default is 'Close this window?'. Using -Message implies -Prompt.
    .NOTES
        An error the action hits after the call goes with the window, the output window and all. Call
        Close-UiWindow last, and give the commands that can fail -ErrorAction Stop.
    .EXAMPLE
        New-UiButton -Text 'Close' -NoAsync -Action { Close-UiWindow }
    .EXAMPLE
        Register-UiHotkey -Key 'Escape' -NoAsync -Action { Close-UiWindow -Prompt }

        Escape asks 'Close this window?' and closes the window on Yes.
    .EXAMPLE
        New-UiWindow -Title 'Pick a server' -ExportOnClose -Content {
            New-UiDropdown -Label 'Server' -Variable 'server' -Items @('web01', 'web02')
            New-UiButton -Text 'OK' -NoOutput -Capture 'picked' -Action {
                $picked = $server
                Close-UiWindow
            }
        }
        Write-Host "You picked $picked"

        The OK action runs in the background, so the window waits for it to end and $picked
        still makes it back to the script.
    .EXAMPLE
        New-UiButton -Text 'Finish' -NoAsync -Action {
            Close-UiWindow -Window Main -Message 'All done. Close the wizard?'
        }

        A button in a child window that asks, then closes the child and the window behind it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Current', 'Parent', 'Main')]
        [string]$Window = 'Current',

        [switch]$Prompt,

        [string]$Message = 'Close this window?'
    )

    $session = Get-UiSession
    if (!$session -or !$session.Window) {
        Write-Warning 'Close-UiWindow: No PsUi window here to close.'
        return
    }

    # Window.Owner only reads on the UI thread
    $closeBlock = {
        param($fromWindow, $which, $askFirst, $question, $executor)

        $target = $fromWindow
        if ($which -eq 'Parent') { $target = $fromWindow.Owner }
        if ($which -eq 'Main') { while ($target.Owner) { $target = $target.Owner } }
        if (!$target) {
            Write-Warning "Close-UiWindow: '$($fromWindow.Title)' wasn't opened from another window, so it has no parent to close."
            return
        }

        $closeTarget = {
            # Close() drops the PresentationSource and leaves Visibility at Visible
            $source = [System.Windows.PresentationSource]::FromVisual($target)
            if (!$source -and $target.Visibility -eq 'Visible') { return }
            if ($askFirst -and !(Show-UiConfirmDialog -Title $target.Title -Message $question)) {
                return
            }

            # The main window's X does this too. A ReadKey dialog still waiting holds the close up otherwise.
            if (!$target.Owner) { [PsUi.KeyCaptureDialog]::CloseCurrentDialog() }
            $target.Close()
        }.GetNewClosure()

        # Not shown yet means -Content is still running, or has a dialog up. Closing it or any owner then breaks its Show, which hangs New-UiWindow on the main window
        $closeWhenShown = {
            $source = [System.Windows.PresentationSource]::FromVisual($fromWindow)
            if (!$source -and $fromWindow.Visibility -ne 'Visible') {
                $fromWindow.Add_ContentRendered($closeTarget)
            }
            else { & $closeTarget }
        }.GetNewClosure()

        # Hooked here because this copy lives in the window's runspace, and the action's is gone by OnComplete
        if ($executor) { $executor.add_OnComplete($closeWhenShown) }
        else { & $closeWhenShown }
    }

    $askFirst = $PSBoundParameters.ContainsKey('Message')
    if ($PSBoundParameters.ContainsKey('Prompt')) { $askFirst = $Prompt.IsPresent }

    $arguments = @($session.Window, $Window, $askFirst, $Message, $null)

    # -NoAsync actions and -Content
    if ($session.Window.Dispatcher.CheckAccess()) {
        & $closeBlock @arguments
        return
    }

    # The close waits for OnComplete, which fires after the -Capture values are saved
    $executor = $Global:AsyncExecutor
    if ($executor) {
        if (!$executor.IsRunning) { return }
        $arguments[4] = $executor
    }

    $invokeParams = @{
        Dispatcher   = $session.Window.Dispatcher
        ScriptBlock  = $closeBlock
        ArgumentList = $arguments
    }
    $null = Invoke-OnUIThread @invokeParams
}
