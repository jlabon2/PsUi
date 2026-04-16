function Show-UiCredentialDialog {
    <#
    .SYNOPSIS
        Shows a credential dialog for Get-Credential scenarios.
    .DESCRIPTION
        Displays a themed credential dialog with username and password fields.
        Returns a PSCredential object. Uses actual PasswordBox for secure input.
    .PARAMETER Caption
        The caption/title of the dialog.
    .PARAMETER Message
        The message to display.
    .PARAMETER UserName
        Pre-filled username (optional).
    .PARAMETER TargetName
        The target resource name (shown in message if no message provided).
    .EXAMPLE
        Show-UiCredentialDialog -Caption "Credentials Required" -Message "Enter credentials for server"
    #>
    [CmdletBinding()]
    param(
        [string]$Caption,
        [string]$Message,
        [string]$UserName,
        [string]$TargetName
    )

    Write-Debug "Caption='$Caption' UserName='$UserName' TargetName='$TargetName'"

    $dialogTitle = if ($Caption) { $Caption } else { "Credential Required" }

    # Create dialog window using shared helper with Key icon
    $keyIcon = [PsUi.ModuleContext]::GetIcon('Key')
    $dlg = New-DialogWindow -Title $dialogTitle -Width 420 -AppIdSuffix 'CredentialDialog' -OverlayGlyph $keyIcon -TitleIcon $keyIcon

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

    # Main content stack
    $mainStack = [System.Windows.Controls.StackPanel]::new()

    # Message text
    $displayMessage = if ($Message) { $Message }
        elseif ($TargetName) { "Enter credentials for: $TargetName" }
        else { "Enter your credentials" }

    $scrollViewer = [System.Windows.Controls.ScrollViewer]@{
        VerticalScrollBarVisibility   = 'Auto'
        HorizontalScrollBarVisibility = 'Disabled'
        Padding                       = [System.Windows.Thickness]::new(0, 0, 8, 0)
        MaxHeight                     = 300
    }

    $msgText = [System.Windows.Controls.TextBlock]@{
        Text         = $displayMessage
        TextWrapping = 'Wrap'
        FontSize     = 13
        Foreground   = ConvertTo-UiBrush $colors.ControlFg
        Margin       = [System.Windows.Thickness]::new(0, 0, 0, 15)
    }
    $scrollViewer.Content = $msgText
    [void]$mainStack.Children.Add($scrollViewer)

    # Username field
    $userLabel = [System.Windows.Controls.TextBlock]@{
        Text       = "Username:"
        FontSize   = 12
        Foreground = ConvertTo-UiBrush $colors.ControlFg
        Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
    }
    [void]$mainStack.Children.Add($userLabel)

    $userTextBox = [System.Windows.Controls.TextBox]@{
        Text     = $UserName
        Height   = 28
        FontSize = 12
        Padding  = [System.Windows.Thickness]::new(2, 0, 2, 0)
        Margin   = [System.Windows.Thickness]::new(0, 0, 0, 10)
    }
    Set-TextBoxStyle -TextBox $userTextBox
    [void]$mainStack.Children.Add($userTextBox)

    # Password field
    $passLabel = [System.Windows.Controls.TextBlock]@{
        Text       = "Password:"
        FontSize   = 12
        Foreground = ConvertTo-UiBrush $colors.ControlFg
        Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
    }
    [void]$mainStack.Children.Add($passLabel)

    $passwordBox = [System.Windows.Controls.PasswordBox]@{
        Height   = 28
        FontSize = 12
        Padding  = [System.Windows.Thickness]::new(2, 0, 2, 0)
        Margin   = [System.Windows.Thickness]::new(0)
    }
    Set-TextBoxStyle -PasswordBox $passwordBox
    [void]$mainStack.Children.Add($passwordBox)

    # Caps lock warning (Hidden, not Collapsed, to reserve space)
    $capsWarning = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Horizontal'
        Margin      = [System.Windows.Thickness]::new(0, 6, 0, 0)
        Visibility  = 'Hidden'
    }
    $capsIcon = [System.Windows.Controls.TextBlock]@{
        Text              = [PsUi.ModuleContext]::GetIcon('Alert')
        FontFamily        = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize          = 12
        Foreground        = ConvertTo-UiBrush $colors.Warning
        Margin            = [System.Windows.Thickness]::new(0, 0, 6, 0)
        VerticalAlignment = 'Center'
    }
    $capsText = [System.Windows.Controls.TextBlock]@{
        Text              = 'Caps Lock is on'
        FontSize          = 11
        Foreground        = ConvertTo-UiBrush $colors.Warning
        VerticalAlignment = 'Center'
    }
    [void]$capsWarning.Children.Add($capsIcon)
    [void]$capsWarning.Children.Add($capsText)
    [void]$mainStack.Children.Add($capsWarning)

    # Caps lock indicator update logic
    $updateCapsLock = {
        param($warningPanel)
        $isCapsOn = [System.Windows.Input.Keyboard]::IsKeyToggled([System.Windows.Input.Key]::CapsLock)
        $warningPanel.Visibility = if ($isCapsOn) { 'Visible' } else { 'Hidden' }
    }

    $capturedCapsWarning = $capsWarning
    $passwordBox.Add_GotFocus({
        & $updateCapsLock $capturedCapsWarning
    }.GetNewClosure())

    $passwordBox.Add_PreviewKeyDown({
        & $updateCapsLock $capturedCapsWarning
    }.GetNewClosure())

    $window.Add_ContentRendered({
        & $updateCapsLock $capturedCapsWarning
    }.GetNewClosure())

    [void]$contentPanel.Children.Add($mainStack)

    # OK button (accent)
    $okBtn = [System.Windows.Controls.Button]@{
        Content   = "OK"
        Width     = 80
        Height    = 28
        Margin    = [System.Windows.Thickness]::new(4, 0, 0, 0)
        IsDefault = $true
    }
    Set-ButtonStyle -Button $okBtn -Accent
    $okBtn.Add_Click({ $window.Tag = 'OK'; $window.Close() })
    [void]$buttonPanel.Children.Add($okBtn)

    # Cancel button
    $cancelBtn = [System.Windows.Controls.Button]@{
        Content  = "Cancel"
        Width    = 80
        Height   = 28
        Margin   = [System.Windows.Thickness]::new(4, 0, 0, 0)
        IsCancel = $true
    }
    Set-ButtonStyle -Button $cancelBtn
    $cancelBtn.Add_Click({ $window.Tag = $null; $window.Close() })
    [void]$buttonPanel.Children.Add($cancelBtn)

    # Focus username box (not password - causes async issues)
    Initialize-UiWindowLoaded -Window $window -FocusElement $userTextBox

    Set-UiDialogPosition -Dialog $window

    Write-Debug "Showing modal dialog"
    [void]$window.ShowDialog()

    if ($window.Tag -eq 'OK') {
        $username = $userTextBox.Text
        if ([string]::IsNullOrWhiteSpace($username)) { return $null }

        $securePassword = $passwordBox.SecurePassword

        try {
            $credential = [System.Management.Automation.PSCredential]::new($username, $securePassword)
            Write-Debug "Result: Credential for '$username'"
            return $credential
        }
        catch {
            Write-Debug "Result: <error creating credential>"
            return $null
        }
    }

    Write-Debug "Result: <cancelled>"
    return $null
}
