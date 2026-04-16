function Show-UiDialog {
    <#
    .SYNOPSIS
        Shows a themed message dialog with configurable buttons.
    .DESCRIPTION
        Convenience wrapper around Show-UiMessageDialog. Automatically picks up
        theme colors when called from an async button action.
    .PARAMETER Message
        The message text to display in the dialog body.
    .PARAMETER Title
        Dialog window title. Defaults to 'Message'.
    .PARAMETER Type
        Icon type displayed beside the message: Info, Warning, Error, or Question.
    .PARAMETER Buttons
        Button layout: OK, OKCancel, YesNo, or YesNoCancel.
    .EXAMPLE
        Show-UiDialog -Message 'Operation complete.' -Title 'Done' -Type Info
    .EXAMPLE
        $answer = Show-UiDialog -Message 'Delete this item?' -Title 'Confirm' -Type Question -Buttons YesNo
        if ($answer -eq 'Yes') { Remove-Item $path }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [string]$Title = 'Message',
        
        [ValidateSet('Info', 'Warning', 'Error', 'Question')]
        [string]$Type = 'Info',
        
        [ValidateSet('OK', 'OKCancel', 'YesNo', 'YesNoCancel')]
        [string]$Buttons = 'OK'
    )

    Write-Debug "Title='$Title' Type='$Type' Buttons='$Buttons'"

    # Try to get injected theme colors (if running in async context)
    $themeColors = $null
    if (Test-Path variable:__WPFThemeColors) {
        $themeColors = $__WPFThemeColors
    }

    Write-Debug "Delegating to Show-UiMessageDialog"
    if ($themeColors) {
        $result = Show-UiMessageDialog -Title $Title -Message $Message -Buttons $Buttons -Icon $Type -ThemeColors $themeColors
    }
    else {
        $result = Show-UiMessageDialog -Title $Title -Message $Message -Buttons $Buttons -Icon $Type
    }
    Write-Debug "Result: $result"
    return $result
}