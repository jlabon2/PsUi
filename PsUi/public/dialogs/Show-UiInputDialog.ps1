function Show-UiInputDialog {
    <#
    .SYNOPSIS
        Displays a themed input dialog for text entry with validation support.
    .DESCRIPTION
        Shows a custom WPF input dialog that respects the current theme.
    .PARAMETER Title
        Dialog window title.
    .PARAMETER Prompt
        Prompt text to display above the input field.
    .PARAMETER DefaultValue
        Default value to populate in the input field.
    .PARAMETER ValidatePattern
        Regular expression pattern to validate input against.
    .PARAMETER Password
        When specified, uses a PasswordBox for secure input (displays dots instead of characters).
    .EXAMPLE
        $name = Show-UiInputDialog -Title 'Enter Name' -Prompt 'Please enter your name:'
    .EXAMPLE
        $email = Show-UiInputDialog -Title 'Email' -Prompt 'Enter email address:' -ValidatePattern '^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$'
    .EXAMPLE
        $secret = Show-UiInputDialog -Title 'Secret' -Prompt 'Enter password:' -Password
    #>
    [CmdletBinding()]
    param(
        [string]$Title = 'Input',

        [Parameter(Mandatory)]
        [string]$Prompt,

        [string]$DefaultValue = '',

        [string]$ValidatePattern,

        [switch]$Password
    )

    Write-Debug "Title='$Title' Prompt='$Prompt' Password=$Password"

    # Create dialog window using shared helper
    $dlg = New-DialogWindow -Title $Title -Width 420 -AppIdSuffix 'InputDialog' -OverlayGlyph ([PsUi.ModuleContext]::GetIcon('Edit'))

    $window       = $dlg.Window
    $contentPanel = $dlg.ContentPanel
    $colors       = $dlg.Colors

    # Button panel at bottom
    $buttonPanel = [System.Windows.Controls.StackPanel]@{
        Orientation         = 'Horizontal'
        HorizontalAlignment = 'Right'
        Margin              = [System.Windows.Thickness]::new(0, 12, 0, 0)
    }
    [System.Windows.Controls.DockPanel]::SetDock($buttonPanel, 'Bottom')
    [void]$contentPanel.Children.Add($buttonPanel)

    # Input stack for prompt + input + error
    $inputStack = [System.Windows.Controls.StackPanel]@{
        Margin = [System.Windows.Thickness]::new(0)
    }
    [void]$contentPanel.Children.Add($inputStack)

    # Prompt text in scroll viewer
    $scrollViewer = [System.Windows.Controls.ScrollViewer]@{
        VerticalScrollBarVisibility   = 'Auto'
        HorizontalScrollBarVisibility = 'Disabled'
        Padding                       = [System.Windows.Thickness]::new(0, 0, 8, 0)
        MaxHeight                     = 400
    }

    $promptText = [System.Windows.Controls.TextBlock]@{
        Text         = $Prompt
        FontSize     = 13
        TextWrapping = 'Wrap'
        Foreground   = ConvertTo-UiBrush $colors.ControlFg
        Margin       = [System.Windows.Thickness]::new(0, 0, 0, 8)
    }
    $scrollViewer.Content = $promptText
    [void]$inputStack.Children.Add($scrollViewer)

    # Input control (TextBox or PasswordBox)
    if ($Password) {
        $inputBox = [System.Windows.Controls.PasswordBox]@{
            Height   = 26
            Padding  = [System.Windows.Thickness]::new(2, 0, 2, 0)
            FontSize = 12
        }
        Set-TextBoxStyle -PasswordBox $inputBox
    }
    else {
        $inputBox = [System.Windows.Controls.TextBox]@{
            Text    = $DefaultValue
            Height  = 26
            Padding = [System.Windows.Thickness]::new(2, 0, 2, 0)
        }
        Set-TextBoxStyle -TextBox $inputBox
    }
    [void]$inputStack.Children.Add($inputBox)

    # Validation error text (hidden by default)
    $errorText = [System.Windows.Controls.TextBlock]@{
        Foreground = ConvertTo-UiBrush $colors.Error
        FontSize   = 11
        Visibility = 'Collapsed'
        Margin     = [System.Windows.Thickness]::new(0, 4, 0, 0)
    }
    [void]$inputStack.Children.Add($errorText)

    # OK button with validation
    $okBtn = [System.Windows.Controls.Button]@{
        Content = 'OK'
        Width   = 80
        Height  = 28
        Margin  = [System.Windows.Thickness]::new(0, 0, 4, 0)
    }
    Set-ButtonStyle -Button $okBtn -Accent

    $validateAndClose = {
        $text = if ($inputBox -is [System.Windows.Controls.PasswordBox]) {
            $inputBox.Password
        }
        else {
            $inputBox.Text
        }

        # Run validation if pattern provided
        if ($ValidatePattern -and $text -notmatch $ValidatePattern) {
            $errorText.Text = 'Input does not match the required format'
            $errorText.Visibility = 'Visible'
            $inputBox.BorderBrush = ConvertTo-UiBrush $colors.Error
        }
        else {
            # For password mode, store the SecurePassword directly to avoid plaintext in memory
            if ($inputBox -is [System.Windows.Controls.PasswordBox]) {
                $window.Tag = $inputBox.SecurePassword.Copy()
            }
            else {
                $window.Tag = $text
            }
            $window.Close()
        }
    }

    $okBtn.Add_Click($validateAndClose)
    [void]$buttonPanel.Children.Add($okBtn)
    $okBtn.IsDefault = $true

    # Cancel button
    $cancelBtn = [System.Windows.Controls.Button]@{
        Content = 'Cancel'
        Width   = 80
        Height  = 28
        Margin  = [System.Windows.Thickness]::new(4, 0, 0, 0)
    }
    Set-ButtonStyle -Button $cancelBtn
    $cancelBtn.Add_Click({
        $window.Tag = $null
        $window.Close()
    })
    [void]$buttonPanel.Children.Add($cancelBtn)
    $cancelBtn.IsCancel = $true

    # Clear error on text change
    if ($inputBox -is [System.Windows.Controls.PasswordBox]) {
        $inputBox.Add_PasswordChanged({
            $errorText.Visibility = 'Collapsed'
            $inputBox.BorderBrush = ConvertTo-UiBrush $colors.Border
        }.GetNewClosure())
    }
    else {
        $inputBox.Add_TextChanged({
            $errorText.Visibility = 'Collapsed'
            $inputBox.BorderBrush = ConvertTo-UiBrush $colors.Border
        }.GetNewClosure())
    }

    # Standard window behavior with focus and select-all on input
    Initialize-UiWindowLoaded -Window $window -FocusElement $inputBox -SelectAll

    Set-UiDialogPosition -Dialog $window

    Write-Debug "Showing modal dialog"
    [void]$window.ShowDialog()

    $result = $window.Tag
    Write-Debug "Result: $(if ($null -eq $result) { '<null>' } elseif ($Password) { '<masked>' } else { $result })"
    return $result
}
