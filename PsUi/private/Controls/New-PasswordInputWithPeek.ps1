function New-PasswordInputWithPeek {
    <#
    .SYNOPSIS
        Creates a password input with optional peek button.
    #>
    [CmdletBinding()]
    param(
        [string]$DefaultValue = '',

        [switch]$NoPeek,

        [int]$Height = 32
    )

    $colors = Get-ThemeColors

    $passBox = [System.Windows.Controls.PasswordBox]@{
        Password = $DefaultValue
        Height   = $Height
    }
    Set-TextBoxStyle -PasswordBox $passBox

    # Without peek button, just return the password box directly
    if ($NoPeek) { return @{ Container = $passBox; PasswordBox = $passBox } }

    $peekWrapper = [System.Windows.Controls.Grid]::new()

    $inputCol = [System.Windows.Controls.ColumnDefinition]::new()
    $inputCol.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    [void]$peekWrapper.ColumnDefinitions.Add($inputCol)

    $btnCol = [System.Windows.Controls.ColumnDefinition]::new()
    $btnCol.Width = [System.Windows.GridLength]::Auto
    [void]$peekWrapper.ColumnDefinitions.Add($btnCol)

    [System.Windows.Controls.Grid]::SetColumn($passBox, 0)
    [void]$peekWrapper.Children.Add($passBox)

    # Create reveal TextBox (hidden initially, overlays PasswordBox)
    $revealBox = [System.Windows.Controls.TextBox]@{
        Height           = $Height
        Visibility       = 'Collapsed'
        IsReadOnly       = $true
        IsHitTestVisible = $false
        Focusable        = $false
    }
    Set-TextBoxStyle -TextBox $revealBox
    [System.Windows.Controls.Grid]::SetColumn($revealBox, 0)
    [void]$peekWrapper.Children.Add($revealBox)

    $peekBtn = [System.Windows.Controls.Border]@{
        Width           = 28
        Height          = $Height
        Margin          = [System.Windows.Thickness]::new(4, 0, 0, 0)
        Cursor          = [System.Windows.Input.Cursors]::Hand
        ToolTip         = 'Hold to reveal password'
        Background      = ConvertTo-UiBrush $colors.ButtonBg
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
        CornerRadius    = [System.Windows.CornerRadius]::new(3)
        Tag             = 'ButtonBgBrush'
    }
    [PsUi.ThemeEngine]::RegisterElement($peekBtn)

    $eyeIcon = [System.Windows.Controls.TextBlock]@{
        Text                = [PsUi.ModuleContext]::GetIcon('DarkEye')
        FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize            = 14
        Foreground          = ConvertTo-UiBrush $colors.ButtonFg
        HorizontalAlignment = 'Center'
        VerticalAlignment   = 'Center'
        IsHitTestVisible    = $false
        Tag                 = 'ButtonFgBrush'
    }
    [PsUi.ThemeEngine]::RegisterElement($eyeIcon)
    $peekBtn.Child = $eyeIcon

    # Store control refs on the button so handlers can access them via $sender.DataContext.
    # .GetNewClosure() breaks in New-UiWindow because private functions get re-injected as
    # strings into a fresh runspace, so captured variables don't survive the round-trip.
    $peekBtn.DataContext = @{
        PasswordBox = $passBox
        RevealBox   = $revealBox
    }

    # Mouse down: reveal password text in the overlay TextBox
    $peekBtn.Add_MouseLeftButtonDown({
        param($sender, $eventArgs)
        $state = $sender.DataContext
        $pwb   = $state.PasswordBox
        if ($null -eq $pwb) { return }

        # Read .Password directly -- SecureString marshaling needs try/finally which crashes
        # inside string-injected handlers. A brief peek doesn't benefit from SecureString anyway.
        $state.RevealBox.Text         = $pwb.Password
        $state.PasswordBox.Visibility = [System.Windows.Visibility]::Collapsed
        $state.RevealBox.Visibility   = [System.Windows.Visibility]::Visible
    })

    # Mouse up: hide password
    $peekBtn.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        $state = $sender.DataContext
        $state.PasswordBox.Visibility = [System.Windows.Visibility]::Visible
        $state.RevealBox.Visibility   = [System.Windows.Visibility]::Collapsed
        $state.RevealBox.Text         = ''
    })

    # Mouse leave: also hide (handles drag-off-button while holding)
    $peekBtn.Add_MouseLeave({
        param($sender, $eventArgs)
        $state = $sender.DataContext
        if ($state.RevealBox.Visibility -eq [System.Windows.Visibility]::Visible) {
            $state.PasswordBox.Visibility = [System.Windows.Visibility]::Visible
            $state.RevealBox.Visibility   = [System.Windows.Visibility]::Collapsed
            $state.RevealBox.Text         = ''
        }
    })

    [System.Windows.Controls.Grid]::SetColumn($peekBtn, 1)
    [void]$peekWrapper.Children.Add($peekBtn)

    return @{
        Container   = $peekWrapper
        PasswordBox = $passBox
    }
}
