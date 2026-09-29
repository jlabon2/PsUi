function Read-UiPasteChoice {
    <#
    .SYNOPSIS
        Uses $Host.UI.PromptForChoice to ask whether the text still in PSReadLine's queue should
        join the text already in the window. Yes is the default choice. A host with no way to
        ask comes back as -1, which Confirm-UiPasteJoin reads as a no.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [System.Management.Automation.Host.ChoiceDescription[]]$Choices
    )

    try { return $Host.UI.PromptForChoice('Pasted lines', $Message, $Choices, 0) }
    catch { return -1 }
}
