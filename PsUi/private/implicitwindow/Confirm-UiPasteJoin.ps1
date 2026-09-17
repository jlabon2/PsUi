function Confirm-UiPasteJoin {
    <#
    .SYNOPSIS
        Asks before pulling queued lines into the window. Stops asking once told yes to all or
        no to all.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    if ($script:uiPasteJoinNever) { return $false }
    if ($script:uiPasteJoinAlways) { return $true }

    # These lines are coming off the prompt without the user having pressed Enter on any of them, so they get shown before they run.
    $shown   = ($Text -split "`n" | ForEach-Object { "    $_" }) -join [Environment]::NewLine
    $message = 'These pasted lines are queued behind a PsUi command and use PsUi to build controls of their own.' + [Environment]::NewLine + $shown + [Environment]::NewLine + 'Put them in the same window?'

    $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'A window for all pasted PsUi lines.')
        [System.Management.Automation.Host.ChoiceDescription]::new('Yes to &All', 'Yes, and stop asking for the rest of this session.')
        [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'A window for the single line alone. The queued lines run after it closes, each opening a window of its own.')
        [System.Management.Automation.Host.ChoiceDescription]::new('No to A&ll', 'No, and stop asking for the rest of this session.')
    )

    # Ctrl+C at the prompt drops the whole paste. A stop never reaches a catch from script and unwinds straight through the finally block.
    # So the queue is read up front, and $answered tells the finally whether the prompt ever came back.
    $queue    = Get-UiPromptKeyQueue
    $answered = $false
    try {
        $answer   = Read-UiPasteChoice -Message $message -Choices $choices
        $answered = $true
    }
    finally {
        if (!$answered) {
            if ($queue) { $queue.Clear() }

            # A paste longer than one PSReadLine burst leaves its tail in the console buffer. ISE has no buffer to flush and throws.
            try { $Host.UI.RawUI.FlushInputBuffer() } catch { }
        }
    }
    if ($answer -eq 1) { $script:uiPasteJoinAlways = $true }
    if ($answer -eq 3) { $script:uiPasteJoinNever = $true }

    # A -1 sets neither sticky flag and returns false, so the queue is left exactly as it was.
    return $answer -eq 0 -or $answer -eq 1
}
