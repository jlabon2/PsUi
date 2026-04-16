function New-UiCredential {
    <#
    .SYNOPSIS
        Creates a credential input consisting of username and password fields.
    .DESCRIPTION
        Creates a pair of input fields for capturing credentials. The username field
        is a standard text input, while the password field is masked. In -Action blocks,
        the hydrated variable contains a PSCredential object.
    .PARAMETER Variable
        The variable name to register. The hydrated variable contains PSCredential.
    .PARAMETER Label
        Optional label displayed above the credential fields. Defaults to "Credentials".
    .PARAMETER UserLabel
        Label for the username field. Defaults to "Username".
    .PARAMETER PasswordLabel
        Label for the password field. Defaults to "Password".
    .PARAMETER DefaultUsername
        Default value for the username field.
    .PARAMETER EnabledWhen
        Conditional enabling based on another control's state. Accepts either:
        - A variable name string (e.g., 'evalVCSA') - enables when that control is truthy
        - A scriptblock (e.g., { $evalPhoton -or $evalAlma }) - enables when expression is true
        Truthy values: CheckBox=checked, TextBox=non-empty, ComboBox=has selection.
    .PARAMETER ClearIfDisabled
        When used with -EnabledWhen, clears the credential fields when the control becomes disabled.
        By default, values are preserved when disabled.
    .PARAMETER SubmitButton
        Name of a registered button to trigger when Enter is pressed in the password field.
        The button must be created with -Variable to register it for lookup.
        Works with both New-UiButton and New-UiActionCard buttons.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to apply to the container.
    .EXAMPLE
        New-UiCredential -Variable 'creds' -Label 'Remote Computer Credentials'
        # In -Action: $creds contains PSCredential
    .EXAMPLE
        New-UiCredential -Variable 'adminCreds' -DefaultUsername 'Administrator'
    .EXAMPLE
        New-UiCredential -Variable 'sshCreds' -Label 'SSH Credentials' -EnabledWhen 'useSSH'
        # Enabled only when the 'useSSH' toggle is checked
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Variable,

        [string]$Label = 'Credentials',

        [string]$UserLabel = 'Username',

        [string]$PasswordLabel = 'Password',

        [string]$DefaultUsername = '',

        [object]$EnabledWhen,

        [switch]$ClearIfDisabled,

        [Parameter()]
        [string]$SubmitButton,

        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiCredential'
    Write-Debug "Creating credential input '$Variable'"
    $colors  = Get-ThemeColors

    $container = [System.Windows.Controls.StackPanel]::new()
    $container.Orientation = 'Vertical'
    $container.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)

    if ($Label) {
        $groupLabel = [System.Windows.Controls.TextBlock]::new()
        $groupLabel.Text = $Label
        $groupLabel.FontWeight = 'SemiBold'
        $groupLabel.Foreground = ConvertTo-UiBrush $colors.ControlFg
        $groupLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        $groupLabel.Tag = 'ControlFgBrush'
        [PsUi.ThemeEngine]::RegisterElement($groupLabel)
        [void]$container.Children.Add($groupLabel)
    }

    $fieldsPanel = [System.Windows.Controls.Grid]::new()
    $fieldsPanel.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
    $fieldsPanel.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
    $fieldsPanel.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(1, 'Star')
    $fieldsPanel.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new(1, 'Star')

    $userContainer = [System.Windows.Controls.StackPanel]::new()
    $userContainer.Orientation = 'Vertical'
    $userContainer.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    [System.Windows.Controls.Grid]::SetColumn($userContainer, 0)

    $userLabelCtrl = [System.Windows.Controls.TextBlock]::new()
    $userLabelCtrl.Text = $UserLabel
    $userLabelCtrl.Foreground = ConvertTo-UiBrush $colors.ControlFg
    $userLabelCtrl.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
    $userLabelCtrl.Tag = 'ControlFgBrush'
    [PsUi.ThemeEngine]::RegisterElement($userLabelCtrl)
    [void]$userContainer.Children.Add($userLabelCtrl)

    $userBox = [System.Windows.Controls.TextBox]::new()
    $userBox.Text = $DefaultUsername
    $userBox.Height = 32
    Set-TextBoxStyle -TextBox $userBox
    [void]$userContainer.Children.Add($userBox)

    $passContainer = [System.Windows.Controls.StackPanel]::new()
    $passContainer.Orientation = 'Vertical'
    $passContainer.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($passContainer, 1)

    $passLabelCtrl = [System.Windows.Controls.TextBlock]::new()
    $passLabelCtrl.Text = $PasswordLabel
    $passLabelCtrl.Foreground = ConvertTo-UiBrush $colors.ControlFg
    $passLabelCtrl.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
    $passLabelCtrl.Tag = 'ControlFgBrush'
    [PsUi.ThemeEngine]::RegisterElement($passLabelCtrl)
    [void]$passContainer.Children.Add($passLabelCtrl)

    $passBox = [System.Windows.Controls.PasswordBox]::new()
    $passBox.Height = 32
    Set-TextBoxStyle -PasswordBox $passBox
    [void]$passContainer.Children.Add($passBox)

    [void]$fieldsPanel.Children.Add($userContainer)
    [void]$fieldsPanel.Children.Add($passContainer)
    [void]$container.Children.Add($fieldsPanel)

    # Tag wrapper for FormLayout unwrapping (when label exists)
    if ($Label) {
        Set-UiFormControlTag -Wrapper $container -Label $groupLabel -Control $fieldsPanel
    }

    # Wrapper that holds references to both controls for Get-UiValue
    $credentialWrapper = [PSCustomObject]@{
        PSTypeName   = 'PsUi.CredentialControl'
        UsernameBox  = $userBox
        PasswordBox  = $passBox
        VariableName = $Variable
    }

    # Store the wrapper in Variables (AddControlSafe requires FrameworkElement)
    # Validation and hydration check for PsUi.CredentialControl type
    Write-Debug "Storing credential wrapper as '$Variable'"
    $session.Variables[$Variable] = $credentialWrapper

    # Register conditional enabling if specified
    if ($EnabledWhen) {
        Register-UiCondition -TargetControl $container -Condition $EnabledWhen -ClearIfDisabled:$ClearIfDisabled
    }

    # Wire up Enter key on password field to trigger submit button
    if ($SubmitButton) {
        $btnName = $SubmitButton
        $passBox.Add_KeyDown({
            param($sender, $keyArgs)
            if ($keyArgs.Key -eq [System.Windows.Input.Key]::Return) {
                # Only trigger if password has content
                if ([string]::IsNullOrWhiteSpace($sender.Password)) { return }
                
                $sess = [PsUi.SessionManager]::Current
                if (!$sess) { return }
                
                # Look up registered button and trigger its click
                $btn = $sess.GetRegisteredButton($btnName)
                if ($btn -and $btn.IsEnabled) {
                    $btn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                    $keyArgs.Handled = $true
                }
            }
        }.GetNewClosure())
    }

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $container -Properties $WPFProperties
    }

    # Add to current parent
    Write-Debug "Adding credential fields to parent"
    [void]$session.CurrentParent.Children.Add($container)

    return $container
}
