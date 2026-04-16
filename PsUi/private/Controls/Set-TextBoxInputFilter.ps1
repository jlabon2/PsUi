function Set-TextBoxInputFilter {
    <#
    .SYNOPSIS
        Applies input type filtering to a TextBox control.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox]$TextBox,
        
        [Parameter(Mandatory)]
        [ValidateSet('Int', 'Double', 'Phone', 'Alphanumeric', 'Path', 'Email')]
        [string]$InputType
    )
    
    $capturedType = $InputType
    
    # Character-level input restriction
    $TextBox.Add_PreviewTextInput({
        param($sender, $eventArgs)
        $newText = $sender.Text.Insert($sender.SelectionStart, $eventArgs.Text)
        
        $valid = switch ($capturedType) {
            'Int'          { $newText -match '^-?\d*$' }
            'Double'       { $newText -match '^-?\d*\.?\d*$' }
            'Phone'        { $eventArgs.Text -match '^[\d\s\-\(\)\+]+$' }
            'Alphanumeric' { $eventArgs.Text -match '^[a-zA-Z0-9]+$' }
            'Path'         { $eventArgs.Text -notmatch '[<>"|?*]' }
            'Email'        { $eventArgs.Text -notmatch '[\s]' }
        }
        
        $eventArgs.Handled = !$valid
    }.GetNewClosure())
    
    # Paste operations
    [System.Windows.DataObject]::AddPastingHandler($TextBox, {
        param($sender, $eventArgs)
        if (!$eventArgs.DataObject.ContainsText()) { return }
        
        $pastedText = $eventArgs.DataObject.GetText()
        
        $valid = switch ($capturedType) {
            'Int'          { $pastedText -match '^-?\d+$' }
            'Double'       { $pastedText -match '^-?\d*\.?\d+$' }
            'Phone'        { $pastedText -match '^[\d\s\-\(\)\+]+$' }
            'Alphanumeric' { $pastedText -match '^[a-zA-Z0-9]+$' }
            'Path'         { $pastedText -notmatch '[<>"|?*]' }
            'Email'        { $pastedText -notmatch '[\s]' }
        }
        
        if (!$valid) { $eventArgs.CancelCommand() }
    }.GetNewClosure())
}
