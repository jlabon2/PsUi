function New-UiInput {
    <#
    .SYNOPSIS
        Creates a labeled text input field.
    .DESCRIPTION
        Creates a TextBox or PasswordBox with a label above it.
        When -Secure or -Password is used, input is masked and the hydrated
        variable contains a SecureString instead of plain text.
    .PARAMETER Label
        Label shown above the input.
    .PARAMETER Variable
        Variable name to store the value.
    .PARAMETER Default
        Initial value.
    .PARAMETER InputType
        Type of input validation to apply. Restricts character entry based on type:
        - String: No restrictions (default)
        - Int: Only digits and optional leading minus sign
        - Double: Digits, single decimal point, and optional leading minus sign
        - Email: Standard text (validation on blur/submit recommended)
        - Phone: Digits, spaces, dashes, parentheses, and plus sign
        - Alphanumeric: Only letters and numbers
        - Path: Valid file path characters
    .PARAMETER Password
        Mask input as password. Hydrated variable contains SecureString.
        By default, includes a peek button (eye icon) to reveal password while held.
    .PARAMETER Secure
        Alias for -Password. Mask input; hydrated variable contains SecureString.
    .PARAMETER NoPeek
        Hide the peek button on password fields. By default, password fields show
        an eye icon that reveals the password while held. Use this to disable it.
        Only valid with -Password or -Secure.
    .PARAMETER Required
        Mark the field as required with an asterisk.
    .PARAMETER Validate
        ScriptBlock for custom validation. Receives the input value as $args[0].
        Return $true if valid, $false or throw to indicate invalid.
        Used with -ErrorMessage to show a custom error message.
    .PARAMETER ValidatePattern
        Regex pattern the input must match. Shows error if input doesn't match.
        For simple pattern validation, prefer this over -Validate.
    .PARAMETER ErrorMessage
        Custom error message shown when validation fails.
        Defaults to "Input is invalid" for -Validate or "Input does not match required format" for -ValidatePattern.
    .PARAMETER ValidateOnChange
        Validate on each keystroke instead of only when focus leaves the control.
        Can feel aggressive; use sparingly for fields needing immediate feedback.
    .PARAMETER Placeholder
        Placeholder/watermark text shown when textbox is empty.
    .PARAMETER EnabledWhen
        Conditional enabling based on another control's state. Accepts either:
        - A control proxy (e.g., $toggleControl) - enables when that control is truthy
        - A scriptblock (e.g., { $toggle -and $userName }) - enables when expression is true
        Truthy values: CheckBox=checked, TextBox=non-empty, ComboBox=has selection.
    .PARAMETER ClearIfDisabled
        When used with -EnabledWhen, clears the input value when the control becomes disabled.
        By default, values are preserved when disabled.
    .PARAMETER ReadOnly
        Makes the input read-only. Users can select and copy text but not edit it.
        Useful for displaying status or computed values that can be updated via Set-UiValue.
    .PARAMETER SubmitButton
        Name of a registered button to trigger when Enter is pressed in this input.
        The button must be created with -Variable to register it for lookup.
        Works with both New-UiButton and New-UiActionCard buttons.
    .PARAMETER FullWidth
        Stretches the control to fill available width instead of fixed sizing.
    .PARAMETER HelperButton
        Adds a picker button next to the input. Supports FilePicker, FolderPicker,
        ComputerPicker, UserPicker, GroupPicker, etc.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
        Allows setting any valid WPF property not explicitly exposed as a parameter.
        Invalid properties will generate warnings but not stop execution.
        Supports attached properties using dot notation (e.g., "Grid.Row").
    .EXAMPLE
        New-UiInput -Label "Age" -Variable "userAge" -InputType Int
        # Only allows integer input
    .EXAMPLE
        New-UiInput -Label "Price" -Variable "itemPrice" -InputType Double
        # Allows decimal numbers
    .EXAMPLE
        New-UiInput -Label "Password" -Variable "userPassword" -Secure
        # Password field with peek button; $userPassword contains SecureString
    .EXAMPLE
        New-UiInput -Label "Password" -Variable "userPassword" -Password -NoPeek
        # Password field without peek button
    .EXAMPLE
        New-UiInput -Label "Search" -Variable "searchTerm" -SubmitButton "searchBtn"
        New-UiButton -Text "Search" -Variable "searchBtn" -Action { Write-Host "Searching for $searchTerm" }
        # Pressing Enter in the input triggers the Search button
    .EXAMPLE
        New-UiInput -Label "Email" -Variable "userEmail" -ValidatePattern '^[\w.+-]+@[\w.-]+\.\w+$' -ErrorMessage 'Enter a valid email address'
        # Shows red border and error text if email format is wrong
    .EXAMPLE
        New-UiInput -Label "Port" -Variable "portNum" -InputType Int -Validate { param($val) [int]$val -ge 1 -and [int]$val -le 65535 } -ErrorMessage 'Port must be 1-65535'
        # Custom validation with scriptblock
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$Variable,

        [string]$Default,

        [ValidateSet('String', 'Int', 'Double', 'Email', 'Phone', 'Alphanumeric', 'Path')]
        [string]$InputType = 'String',

        [switch]$Password,

        [switch]$Secure,

        [switch]$NoPeek,

        [switch]$Required,

        [scriptblock]$Validate,

        [string]$ValidatePattern,

        [string]$ErrorMessage,

        [switch]$ValidateOnChange,

        [string]$Placeholder,

        [switch]$FullWidth,

        [ValidateSet('None', 'FilePicker', 'FolderPicker', 'AdvancedFolderPicker', 'ComputerPicker', 'UserPicker', 'GroupPicker', 'UserGroupPicker')]
        [string]$HelperButton = 'None',

        [Parameter()]
        [object]$EnabledWhen,

        [switch]$ClearIfDisabled,

        [switch]$ReadOnly,

        [Parameter()]
        [string]$SubmitButton,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    # Treat -Secure same as -Password for control creation
    $isSecure = $Password -or $Secure

    # -NoPeek only makes sense for password fields
    if ($NoPeek -and !$isSecure) {
        throw "-NoPeek can only be used with -Password or -Secure"
    }

    $session = Assert-UiSession -CallerName 'New-UiInput'
    Write-Debug "Label='$Label', Variable='$Variable', InputType='$InputType', Secure=$isSecure"

    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent
    Write-Debug "Parent: $($parent.GetType().Name)"

    $stack = [System.Windows.Controls.StackPanel]@{
        Margin = [System.Windows.Thickness]::new(4, 4, 4, 8)
    }

    # Label row - contains label on left, error message on right
    $labelRow = [System.Windows.Controls.DockPanel]@{
        Margin        = [System.Windows.Thickness]::new(0, 0, 0, 4)
        LastChildFill = $false
    }

    $labelText  = if ($Required) { "$Label *" } else { $Label }
    $labelBlock = [System.Windows.Controls.TextBlock]@{
        Text       = $labelText
        FontSize   = 12
        Foreground = ConvertTo-UiBrush $colors.ControlFg
        Tag        = 'ControlFgBrush'
    }
    [PsUi.ThemeEngine]::RegisterElement($labelBlock)
    [System.Windows.Controls.DockPanel]::SetDock($labelBlock, 'Left')
    [void]$labelRow.Children.Add($labelBlock)

    # Error text sits to the right of the label (hidden until validation fails)
    $errorText = [System.Windows.Controls.TextBlock]@{
        Foreground = ConvertTo-UiBrush $colors.Error
        FontSize   = 11
        FontStyle  = 'Italic'
        Visibility = 'Hidden'
        Margin     = [System.Windows.Thickness]::new(8, 0, 0, 0)
        Tag        = 'ErrorBrush'
    }
    [PsUi.ThemeEngine]::RegisterElement($errorText)
    [System.Windows.Controls.DockPanel]::SetDock($errorText, 'Right')
    [void]$labelRow.Children.Add($errorText)

    [void]$stack.Children.Add($labelRow)

    if ($isSecure) {
        # Use the shared password input helper
        $peekResult       = New-PasswordInputWithPeek -DefaultValue $Default -NoPeek:$NoPeek -Height 28
        $inputControl     = $peekResult.PasswordBox
        $inputContainer   = $peekResult.Container
    }
    else {
        # Create TextBox via ControlFactory (handles placeholder natively)
        $inputControl = [PsUi.ControlFactory]::CreateTextBox($Placeholder)
        $inputControl.Text = $Default

        # Set up context menu and theme (each TextBox needs its own instance)
        Set-TextBoxStyle -TextBox $inputControl

        # Apply input type filtering (character-level restriction)
        if ($InputType -ne 'String') {
            Set-TextBoxInputFilter -TextBox $inputControl -InputType $InputType
        }
        
        # Apply read-only mode if requested
        if ($ReadOnly) { $inputControl.IsReadOnly = $true }
        
        # For TextBox, use input directly as container
        $inputContainer = $inputControl
    }

    # Override: Explicit sizing for consistent input appearance across themes
    $inputControl.Height = 28
    $inputControl.FontSize = 12
    $inputControl.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
    $inputControl.Padding = [System.Windows.Thickness]::new(2, 0, 2, 0)

    # Add helper button if requested (TextBox only, not secure inputs)
    if ($HelperButton -ne 'None' -and !$isSecure) {
        # Create wrapper grid: [Input][Button]
        $wrapperGrid = [System.Windows.Controls.Grid]::new()

        # Input column (stretch)
        $col1 = [System.Windows.Controls.ColumnDefinition]::new()
        $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        [void]$wrapperGrid.ColumnDefinitions.Add($col1)

        # Button column (auto)
        $col2 = [System.Windows.Controls.ColumnDefinition]::new()
        $col2.Width = [System.Windows.GridLength]::Auto
        [void]$wrapperGrid.ColumnDefinitions.Add($col2)

        # Add input container to first column
        [System.Windows.Controls.Grid]::SetColumn($inputContainer, 0)
        [void]$wrapperGrid.Children.Add($inputContainer)

        # Create helper button
        $helperBtn = [System.Windows.Controls.Button]::new()
        $helperBtn.Width = 28
        $helperBtn.Height = 28
        $helperBtn.Margin = [System.Windows.Thickness]::new(4, 0, 0, 0)
        $helperBtn.Padding = [System.Windows.Thickness]::new(0)
        $helperBtn.Cursor = [System.Windows.Input.Cursors]::Hand

        # Set icon and tooltip based on helper type
        $iconCode = switch ($HelperButton) {
            'FilePicker'          { [PsUi.ModuleContext]::GetIcon('OpenFile') }
            'FolderPicker'        { [PsUi.ModuleContext]::GetIcon('Folder') }
            'AdvancedFolderPicker' { [PsUi.ModuleContext]::GetIcon('FolderOpen') }
            'ComputerPicker'      { [PsUi.ModuleContext]::GetIcon('Desktop') }
            'UserPicker'      { [PsUi.ModuleContext]::GetIcon('Contact') }
            'GroupPicker'     { [PsUi.ModuleContext]::GetIcon('People') }
            'UserGroupPicker' { [PsUi.ModuleContext]::GetIcon('People') }
        }
        $helperBtn.ToolTip = switch ($HelperButton) {
            'FilePicker'          { 'Browse for file...' }
            'FolderPicker'        { 'Browse for folder...' }
            'AdvancedFolderPicker' { 'Browse for folder...' }
            'ComputerPicker'      { 'Select computer...' }
            'UserPicker'      { 'Select user...' }
            'GroupPicker'     { 'Select group...' }
            'UserGroupPicker' { 'Select user or group...' }
        }

        $iconBlock = [System.Windows.Controls.TextBlock]::new()
        $iconBlock.Text = $iconCode
        $iconBlock.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $iconBlock.FontSize = 14
        $iconBlock.HorizontalAlignment = 'Center'
        $iconBlock.VerticalAlignment = 'Center'
        $helperBtn.Content = $iconBlock

        Set-ButtonStyle -Button $helperBtn

        # Sync enabled state with input
        $enabledBinding = [System.Windows.Data.Binding]::new('IsEnabled')
        $enabledBinding.Source = $inputControl
        [void]$helperBtn.SetBinding([System.Windows.UIElement]::IsEnabledProperty, $enabledBinding)

        # Store info for click handler
        $helperBtn.Tag = @{
            Mode    = $HelperButton
            TextBox = $inputControl
        }

        # Click handler
        $helperBtn.Add_Click({
            param($sender, $eventArgs)
            $info = $sender.Tag
            $result = $null

            try {
                switch ($info.Mode) {
                    'FilePicker'          { $result = Show-UiPathPicker -Mode 'File' }
                    'FolderPicker'        { $result = Show-UiFolderPicker -Simple }
                    'AdvancedFolderPicker' { $result = Show-UiFolderPicker }
                    'ComputerPicker'  { $picked = Show-WindowsObjectPicker -ObjectType Computer; if ($picked) { $result = $picked.RawValue } }
                    'UserPicker'      { $picked = Show-WindowsObjectPicker -ObjectType User; if ($picked) { $result = $picked.RawValue } }
                    'GroupPicker'     { $picked = Show-WindowsObjectPicker -ObjectType Group; if ($picked) { $result = $picked.RawValue } }
                    'UserGroupPicker' { $picked = Show-WindowsObjectPicker -ObjectType User, Group; if ($picked) { $result = $picked.RawValue } }
                }

                if ($result) {
                    $info.TextBox.Text = $result
                }
            }
            catch {
                Write-Warning "Helper button error: $_"
            }
        }.GetNewClosure())

        [System.Windows.Controls.Grid]::SetColumn($helperBtn, 1)
        [void]$wrapperGrid.Children.Add($helperBtn)

        [void]$stack.Children.Add($wrapperGrid)
        $controlElement = $wrapperGrid
    }
    else {
        [void]$stack.Children.Add($inputContainer)
        $controlElement = $inputContainer
    }

    # Wire up validation if configured
    $hasValidation = $Validate -or $ValidatePattern

    if ($hasValidation) {
        # Pre-compute brushes to avoid repeated conversions in event handlers
        $borderBrush = ConvertTo-UiBrush $colors.Border
        $errorBrush  = ConvertTo-UiBrush $colors.Error

        # Build context for validation handlers
        $validationContext = @{
            Input           = $inputControl
            ErrorText       = $errorText
            Validate        = $Validate
            ValidatePattern = $ValidatePattern
            ErrorMessage    = $ErrorMessage
            BorderBrush     = $borderBrush
            ErrorBrush      = $errorBrush
            IsSecure        = $isSecure
        }

        # Validation runner - checks input and updates UI
        $runValidation = {
            param($ctx)
            $inputValue = if ($ctx.IsSecure) { $ctx.Input.Password } else { $ctx.Input.Text }

            # Skip validation on empty values (use -Required for emptiness check)
            if ([string]::IsNullOrEmpty($inputValue)) {
                $ctx.ErrorText.Visibility = 'Hidden'
                $ctx.Input.BorderBrush = $ctx.BorderBrush
                return
            }

            $isValid      = $true
            $errorMessage = $null

            # Run scriptblock validation
            if ($ctx.Validate) {
                try {
                    $result = & $ctx.Validate $inputValue
                    # Treat any falsy value (including $null, 0, empty string) as validation failure
                    if (!$result) { $isValid = $false }
                }
                catch {
                    $isValid      = $false
                    $errorMessage = $_.Exception.Message
                }
            }

            # Run pattern validation
            if ($isValid -and $ctx.ValidatePattern) {
                if ($inputValue -notmatch $ctx.ValidatePattern) {
                    $isValid = $false
                }
            }

            # Update UI based on validation result
            if ($isValid) {
                $ctx.ErrorText.Visibility = 'Hidden'
                $ctx.Input.BorderBrush = $ctx.BorderBrush
            }
            else {
                # Figure out what message to show
                $msg = $errorMessage
                if (!$msg) {
                    if ($ctx.ErrorMessage) {
                        $msg = $ctx.ErrorMessage
                    }
                    elseif ($ctx.ValidatePattern) {
                        $msg = "Doesn't match required format"
                    }
                    else {
                        $msg = 'Invalid input'
                    }
                }
                $ctx.ErrorText.Text       = $msg
                $ctx.ErrorText.Visibility = 'Visible'
                $ctx.Input.BorderBrush    = $ctx.ErrorBrush
            }
        }

        # Wire up validation event based on mode
        if ($ValidateOnChange) {
            # Validate on every keystroke
            if ($isSecure) {
                $inputControl.Add_PasswordChanged({
                    param($sender, $eventArgs)
                    & $runValidation $validationContext
                }.GetNewClosure())
            }
            else {
                $inputControl.Add_TextChanged({
                    param($sender, $eventArgs)
                    & $runValidation $validationContext
                }.GetNewClosure())
            }
        }
        else {
            # Validate when focus leaves the control
            $inputControl.Add_LostFocus({
                param($sender, $eventArgs)
                & $runValidation $validationContext
            }.GetNewClosure())
        }

        # Clear error state when user starts typing (provides immediate feedback that we noticed)
        if (!$ValidateOnChange) {
            if ($isSecure) {
                $inputControl.Add_PasswordChanged({
                    param($sender, $eventArgs)
                    $validationContext.ErrorText.Visibility = 'Hidden'
                    $validationContext.Input.BorderBrush = $validationContext.BorderBrush
                }.GetNewClosure())
            }
            else {
                $inputControl.Add_TextChanged({
                    param($sender, $eventArgs)
                    $validationContext.ErrorText.Visibility = 'Hidden'
                    $validationContext.Input.BorderBrush = $validationContext.BorderBrush
                }.GetNewClosure())
            }
        }
    }

    # Tag wrapper for FormLayout unwrapping in New-UiGrid
    Set-UiFormControlTag -Wrapper $stack -Label $labelBlock -Control $controlElement

    # FullWidth in WrapPanel contexts
    Set-FullWidthConstraint -Control $stack -Parent $parent -FullWidth:$FullWidth

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $stack -Properties $WPFProperties
    }

    Write-Debug "Adding to $($parent.GetType().Name)"
    [void]$parent.Children.Add($stack)

    # Register control in all session registries (with theme support for TextBox)
    $isTextBox = $inputControl -is [System.Windows.Controls.TextBox]
    
    # Get initial value - PasswordBox uses .Password, TextBox uses .Text
    $initialValue = if ($isSecure) { $null } else { $inputControl.Text }
    Register-UiControlComplete -Name $Variable -Control $inputControl -InitialValue $initialValue -RegisterTheme:$isTextBox

    # Wire up conditional enabling if specified
    if ($EnabledWhen) {
        Register-UiCondition -TargetControl $inputControl -Condition $EnabledWhen -ClearIfDisabled:$ClearIfDisabled
    }

    # Wire up Enter key to trigger submit button
    if ($SubmitButton) {
        $btnName = $SubmitButton
        $inputControl.Add_KeyDown({
            param($sender, $keyArgs)
            if ($keyArgs.Key -eq [System.Windows.Input.Key]::Return) {
                # Only trigger if input has actual content
                $inputValue = if ($sender -is [System.Windows.Controls.PasswordBox]) {
                    $sender.Password
                }
                else {
                    $sender.Text
                }
                if ([string]::IsNullOrWhiteSpace($inputValue)) { return }
                
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
}
