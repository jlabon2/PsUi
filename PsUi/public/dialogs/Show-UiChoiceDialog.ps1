function Show-UiChoiceDialog {
    <#
    .SYNOPSIS
        Shows a choice dialog for PromptForChoice scenarios (Confirm, ShouldProcess).
    .DESCRIPTION
        Displays a themed dialog with multiple choice buttons. Used to intercept
        -Confirm prompts and $PSCmdlet.ShouldProcess() calls in async button actions.
        This is a wrapper around Show-UiMessageDialog with custom buttons.
        If any choice has a HelpMessage, a Help (?) button is added.
    .PARAMETER Caption
        The caption/title of the dialog.
    .PARAMETER Message
        The message to display.
    .PARAMETER Choices
        Collection of ChoiceDescription objects defining available choices.
    .PARAMETER DefaultChoice
        Index of the default choice (0-based).
    .EXAMPLE
        Show-UiChoiceDialog -Caption "Confirm" -Message "Delete file?" -Choices $choices -DefaultChoice 1
    #>
    [CmdletBinding()]
    param(
        [string]$Caption,
        [string]$Message,
        [System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription]]$Choices,
        [int]$DefaultChoice = 0
    )

    Write-Debug "Caption='$Caption' ChoiceCount=$($Choices.Count) DefaultChoice=$DefaultChoice"

    # Build help text from choices that have HelpMessage
    $helpLines = [System.Collections.Generic.List[string]]::new()
    foreach ($choice in $Choices) {
        if ($choice.HelpMessage) {
            $label = $choice.Label -replace '&', ''
            $helpLines.Add("$label - $($choice.HelpMessage)")
        }
    }
    $hasHelp  = $helpLines.Count -gt 0
    $helpText = $helpLines -join "`n"

    # Convert ChoiceDescription collection to CustomButtons format
    $customButtons = [System.Collections.Generic.List[object]]::new()
    $choiceIndex = 0
    
    foreach ($choice in $Choices) {
        # Parse the label - format is "&Yes" where & indicates accelerator key
        $label = $choice.Label -replace '&', ''
        
        $buttonDef = @{
            Label = $label
            Value = $choiceIndex
            IsDefault = ($choiceIndex -eq $DefaultChoice)
            IsAccent = ($choiceIndex -eq $DefaultChoice)
        }
        
        $customButtons.Add($buttonDef)
        $choiceIndex++
    }

    # Add Help button if any choice has HelpMessage
    if ($hasHelp) {
        $customButtons.Add(@{
            Label = "?"
            Value = "Help"
            IsDefault = $false
            IsAccent = $false
        })
    }

    # Loop to handle Help button
    while ($true) {
        Write-Debug "Showing choice dialog"
        $dialogParams = @{
            Title         = if ($Caption) { $Caption } else { 'Confirm' }
            Message       = if ($Message) { $Message } else { 'Are you sure you want to perform this action?' }
            Icon          = 'Question'
            CustomButtons = $customButtons
        }
        $result = Show-UiMessageDialog @dialogParams

        # If Help was clicked, show help and loop back
        if ($result -eq "Help") {
            Write-Debug "Help button clicked, showing help"
            $null = Show-UiMessageDialog -Title "Help" -Message $helpText.TrimEnd() -Icon Info -Buttons OK
            continue
        }

        if ($null -eq $result) {
            Write-Debug "Result: $DefaultChoice (default)"
            return $DefaultChoice
        }
        Write-Debug "Result: $result"
        return $result
    }
}
