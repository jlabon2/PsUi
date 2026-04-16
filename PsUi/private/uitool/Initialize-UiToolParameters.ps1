<#
.SYNOPSIS
    Initializes parameter controls for New-UiTool dynamically.
#>
function Initialize-UiToolParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Panel]$TargetPanel,

        [Parameter(Mandatory)]
        [array]$Parameters,

        [hashtable]$Descriptions = @{},

        [hashtable]$ThemeColors,

        [switch]$ShowParamType,

        [hashtable]$InputHelpers,

        [switch]$UseWrapLayout
    )

    if (!$ThemeColors) {
        $ThemeColors = Get-ThemeColors
    }
    if (!$InputHelpers) {
        $InputHelpers = @{ FilePicker = @(); FolderPicker = @() }
    }

    $isFirstParam = $true

    foreach ($param in $Parameters) {
        # When using wrap layout, each parameter goes into its own container
        $paramContainer = $null
        $paramBorder    = $null
        $addTarget      = $TargetPanel

        if ($UseWrapLayout) {
            # Wrap each parameter in a simple container with margin for spacing
            $paramContainer = [System.Windows.Controls.StackPanel]::new()
            $paramContainer.Orientation = 'Vertical'
            $paramContainer.Margin = [System.Windows.Thickness]::new(4,4,4,8)
            $addTarget = $paramContainer
        }
        else {
            # Add styled separator between parameters (not before first)
            if (!$isFirstParam) {
                # Create fade-style separator with gradient brush
                $borderColor = [System.Windows.Media.ColorConverter]::ConvertFromString($ThemeColors.Border)
                $transparentBorder = [System.Windows.Media.Color]::FromArgb(0, $borderColor.R, $borderColor.G, $borderColor.B)
                $gradient = [System.Windows.Media.LinearGradientBrush]::new()
                $gradient.StartPoint = [System.Windows.Point]::new(0, 0.5)
                $gradient.EndPoint   = [System.Windows.Point]::new(1, 0.5)
                [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($transparentBorder, 0))
                [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($borderColor, 0.1))
                [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($borderColor, 0.9))
                [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($transparentBorder, 1))

                $sep = [System.Windows.Controls.Border]@{
                    Height              = 1
                    Margin              = [System.Windows.Thickness]::new(0, 8, 0, 8)
                    Background          = $gradient
                    HorizontalAlignment = 'Stretch'
                    Tag                 = 'Separator_Fade'
                }
                $TargetPanel.Children.Add($sep) | Out-Null
            }
        }
        $isFirstParam = $false

        $varName = "param_$($param.Name)"
        $labelText = $param.Name
        if ($param.IsMandatory) { $labelText += " *" }
        $controlAlreadyRegistered = $false

        # Build a friendly type name for display
        $typeName = ''
        if ($param.IsSwitch) {
            $typeName = 'switch'
        }
        elseif ($param.Type) {
            $typeName = $param.Type.Name
            # Simplify common types
            switch ($typeName) {
                'String'   { $typeName = 'text' }
                'String[]' { $typeName = 'text[]' }
                'Int32'    { $typeName = 'int' }
                'Int64'    { $typeName = 'long' }
                'Double'   { $typeName = 'number' }
                'Single'   { $typeName = 'number' }
                'Boolean'  { $typeName = 'bool' }
                'DateTime' { $typeName = 'date' }
                'PSCredential' { $typeName = 'credential' }
                'SecureString' { $typeName = 'password' }
                'ScriptBlock'  { $typeName = 'script' }
            }
        }

        $labelPanel = [System.Windows.Controls.StackPanel]::new()
        $labelPanel.Orientation = 'Horizontal'
        $labelPanel.Margin = [System.Windows.Thickness]::new(0,0,0,4)

        $label = [System.Windows.Controls.TextBlock]::new()
        $label.Text = $labelText
        $label.FontWeight = [System.Windows.FontWeights]::SemiBold
        if ($ThemeColors.Foreground) {
            $label.Foreground = $ThemeColors.Foreground
        }
        $labelPanel.Children.Add($label) | Out-Null

        if ($typeName -and $ShowParamType) {
            $typeLabel = [System.Windows.Controls.TextBlock]::new()
            $typeLabel.Text = " [$typeName]"
            $typeLabel.FontStyle = [System.Windows.FontStyles]::Italic
            $typeLabel.Opacity = 0.6
            if ($ThemeColors.Foreground) {
                $typeLabel.Foreground = $ThemeColors.Foreground
            }
            $labelPanel.Children.Add($typeLabel) | Out-Null
        }

        $addTarget.Children.Add($labelPanel) | Out-Null

        $session = Get-UiSession
        $control = $null

        # ValidateSet → ComboBox
        if ($param.ValidateSet -and $param.ValidateSet.Count -gt 0) {
            $control = [System.Windows.Controls.ComboBox]::new()
            if (!$param.IsMandatory) {
                $control.Items.Add('') | Out-Null
            }
            foreach ($item in $param.ValidateSet) {
                $control.Items.Add($item) | Out-Null
            }

            if ($null -ne $param.DefaultValue) {
                $defaultIndex = $control.Items.IndexOf([string]$param.DefaultValue)
                if ($defaultIndex -ge 0) {
                    $control.SelectedIndex = $defaultIndex
                }
                else {
                    $control.SelectedIndex = 0
                }
            }
            else {
                $control.SelectedIndex = 0
            }
            Set-ComboBoxStyle -ComboBox $control
        }
        # Enum type → ComboBox with enum values
        elseif ($param.Type -and $param.Type.IsEnum) {
            $control = [System.Windows.Controls.ComboBox]::new()
            if (!$param.IsMandatory) {
                $control.Items.Add('') | Out-Null
            }
            foreach ($enumVal in [Enum]::GetNames($param.Type)) {
                $control.Items.Add($enumVal) | Out-Null
            }

            if ($null -ne $param.DefaultValue) {
                $defaultIndex = $control.Items.IndexOf([string]$param.DefaultValue)
                if ($defaultIndex -ge 0) {
                    $control.SelectedIndex = $defaultIndex
                }
                else {
                    $control.SelectedIndex = 0
                }
            }
            else {
                $control.SelectedIndex = 0
            }
            Set-ComboBoxStyle -ComboBox $control
        }
        # Switch → CheckBox
        elseif ($param.IsSwitch) {
            $control = [System.Windows.Controls.CheckBox]::new()
            $control.Content = $labelText

            # Mandatory switches must be checked and disabled
            if ($param.IsMandatory) {
                $control.IsChecked = $true
                $control.IsEnabled = $false
                $control.ToolTip = "This switch is required and cannot be disabled"
            }
            else {
                $control.IsChecked = $false
            }
            Set-CheckBoxStyle -CheckBox $control
        }
        # Bool → CheckBox
        elseif ($param.Type -eq [bool]) {
            $control = [System.Windows.Controls.CheckBox]::new()
            $control.Content = $labelText

            # Mandatory bools must be set
            if ($param.IsMandatory) {
                $control.IsChecked = $true
                $control.IsEnabled = $false
                $control.ToolTip = "This option is required and cannot be disabled"
            }
            else {
                $control.IsChecked = $false
            }
            Set-CheckBoxStyle -CheckBox $control
        }
        # Int/Double with ValidateRange → Slider (if ≤10 values) or TextBox with validation
        elseif ($param.ValidateRange -and ($param.Type -eq [int] -or $param.Type -eq [int16] -or $param.Type -eq [int32] -or $param.Type -eq [double] -or $param.Type -eq [float])) {
            $rangeSize = $param.ValidateRange.MaxRange - $param.ValidateRange.MinRange

            # Use slider only if range has 10 or fewer discrete values
            if ($rangeSize -le 10) {
                # Create a container for slider + value label
                $sliderPanel = [System.Windows.Controls.Grid]::new()
                $sliderPanel.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })
                $sliderPanel.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::Auto })

                $slider = [System.Windows.Controls.Slider]::new()
                $slider.Minimum = $param.ValidateRange.MinRange
                $slider.Maximum = $param.ValidateRange.MaxRange
                $slider.Value = $param.ValidateRange.MinRange
                $slider.TickFrequency = 1
                $slider.IsSnapToTickEnabled = $true
                $slider.VerticalAlignment = 'Center'
                [System.Windows.Controls.Grid]::SetColumn($slider, 0)
                Set-SliderStyle -Slider $slider

                # Value label showing current slider value
                $valueLabel = [System.Windows.Controls.TextBlock]::new()
                $valueLabel.Text = [string]$slider.Value
                $valueLabel.MinWidth = 40
                $valueLabel.TextAlignment = 'Right'
                $valueLabel.VerticalAlignment = 'Center'
                $valueLabel.Margin = [System.Windows.Thickness]::new(8,0,0,0)
                if ($ThemeColors.Foreground) {
                    $valueLabel.Foreground = $ThemeColors.Foreground
                }
                [System.Windows.Controls.Grid]::SetColumn($valueLabel, 1)

                # Update label when slider value changes
                $slider.Add_ValueChanged({
                    param($sender, $eventArgs)
                    $this.Tag.Text = [string][int]$eventArgs.NewValue
                }.GetNewClosure())
                $slider.Tag = $valueLabel

                [void]$sliderPanel.Children.Add($slider)
                [void]$sliderPanel.Children.Add($valueLabel)

                $control = $sliderPanel

                # Register the slider (not the panel) for value retrieval
                $session.AddControlSafe($varName, $slider)
                $controlAlreadyRegistered = $true
            }
            else {
                # Large range - use TextBox with validation hint
                $control = [System.Windows.Controls.TextBox]::new()
                Set-TextBoxStyle -TextBox $control
                $control.Height = 32
                $control.VerticalContentAlignment = 'Center'

                # Apply numeric input filter based on type
                $filterType = if ($param.Type -eq [int] -or $param.Type -eq [int16] -or $param.Type -eq [int32] -or $param.Type -eq [int64]) { 'Int' } else { 'Double' }
                Set-TextBoxInputFilter -TextBox $control -InputType $filterType

                # Store range info in Tag for potential validation
                $control.Tag = @{
                    Type     = 'NumericRange'
                    MinRange = $param.ValidateRange.MinRange
                    MaxRange = $param.ValidateRange.MaxRange
                    DataType = $param.Type
                }

                # Add placeholder/tooltip showing valid range
                $control.ToolTip = "Enter a number between $($param.ValidateRange.MinRange) and $($param.ValidateRange.MaxRange)"
            }
        }
        # DateTime → DatePicker
        elseif ($param.Type -eq [datetime]) {
            $control = [System.Windows.Controls.DatePicker]::new()
            $control.SelectedDate = if ($param.DefaultValue) { $param.DefaultValue } else { [datetime]::Today }
            Set-DatePickerStyle -DatePicker $control
        }
        # Default → TextBox
        else {
            $control = [System.Windows.Controls.TextBox]::new()
            Set-TextBoxStyle -TextBox $control
            $control.Height = 32
            $control.VerticalContentAlignment = 'Center'

            # Apply input filtering based on parameter type
            if ($param.Type -eq [int] -or $param.Type -eq [int16] -or $param.Type -eq [int32] -or $param.Type -eq [int64]) {
                Set-TextBoxInputFilter -TextBox $control -InputType 'Int'
            }
            elseif ($param.Type -eq [double] -or $param.Type -eq [float] -or $param.Type -eq [decimal]) {
                Set-TextBoxInputFilter -TextBox $control -InputType 'Double'
            }

            # Set default value if specified
            if ($null -ne $param.DefaultValue -and $param.DefaultValue -ne '') {
                $control.Text = [string]$param.DefaultValue
            }

            if ($param.Type -eq [System.Management.Automation.PSCredential]) {
                # PSCredential → Use New-UiCredential helper
                # Create the credential control directly in the target panel
                $credContainer = [System.Windows.Controls.StackPanel]::new()
                $credContainer.Orientation = 'Vertical'
                $credContainer.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)

                # Username field
                $userLabel = [System.Windows.Controls.TextBlock]::new()
                $userLabel.Text = 'Username'
                $userLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
                if ($ThemeColors.ControlFg) {
                    $userLabel.Foreground = ConvertTo-UiBrush $ThemeColors.ControlFg
                }
                [void]$credContainer.Children.Add($userLabel)

                $userBox = [System.Windows.Controls.TextBox]::new()
                Set-TextBoxStyle -TextBox $userBox
                $userBox.Height = 32
                $userBox.VerticalContentAlignment = 'Center'
                [void]$credContainer.Children.Add($userBox)

                # Password field with peek button
                $passLabel = [System.Windows.Controls.TextBlock]::new()
                $passLabel.Text = 'Password'
                $passLabel.Margin = [System.Windows.Thickness]::new(0, 8, 0, 4)
                if ($ThemeColors.ControlFg) {
                    $passLabel.Foreground = ConvertTo-UiBrush $ThemeColors.ControlFg
                }
                [void]$credContainer.Children.Add($passLabel)

                $peekResult = New-PasswordInputWithPeek
                $passBox    = $peekResult.PasswordBox
                [void]$credContainer.Children.Add($peekResult.Container)

                # Create credential wrapper for Get-UiValue
                $credWrapper = [PSCustomObject]@{
                    PSTypeName   = 'PsUi.CredentialControl'
                    UsernameBox  = $userBox
                    PasswordBox  = $passBox
                    VariableName = $varName
                }

                # Store directly in Variables (not AddControlSafe which requires FrameworkElement)
                $session.Variables[$varName] = $credWrapper
                $controlAlreadyRegistered = $true
                $control = $credContainer

                # Wire up change events for mandatory credential validation
                if ($param.IsMandatory) {
                    $userBox.Add_TextChanged({ Update-UiToolRunButtonState })
                    $passBox.Add_PasswordChanged({ Update-UiToolRunButtonState })
                }
            }
            elseif ($param.Type -eq [System.Security.SecureString]) {
                # Use password input with peek button
                $peekResult = New-PasswordInputWithPeek
                $control    = $peekResult.Container
                
                # Register the PasswordBox for value extraction, not the wrapper grid
                $session.AddControlSafe($varName, $peekResult.PasswordBox)
                $controlAlreadyRegistered = $true
            }
            elseif ($param.Type -eq [string[]]) {
                $control.AcceptsReturn = $true
                $control.TextWrapping = [System.Windows.TextWrapping]::Wrap
                $control.MinHeight = 60
                $control.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
                $control.VerticalContentAlignment = 'Top'
            }
        }

        # Apply common styling and check for input helpers
        if ($control) {
            $control.Margin = [System.Windows.Thickness]::new(0,0,0,4)

            # Helper buttons - file picker, folder picker, etc.
            $needsFilePicker     = $InputHelpers.FilePicker -contains $param.Name
            $needsFolderPicker   = $InputHelpers.FolderPicker -contains $param.Name
            $needsFilterBuilder  = $InputHelpers.FilterBuilder.ContainsKey($param.Name)
            $filterMode          = if ($needsFilterBuilder) { $InputHelpers.FilterBuilder[$param.Name] } else { 'Generic' }

            # Computer picker only works on domain-joined machines
            $needsComputerPicker = $false
            if ($InputHelpers.ComputerPicker -contains $param.Name) {
                try {
                    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
                    if ($cs.PartOfDomain) {
                        $needsComputerPicker = $true
                    }
                }
                catch { Write-Debug "Domain check failed: $_" }
            }

            # Only add helper to TextBox controls
            if (($needsFilePicker -or $needsFolderPicker -or $needsComputerPicker -or $needsFilterBuilder) -and $control -is [System.Windows.Controls.TextBox]) {
                # Create a wrapper grid: [TextBox][Button]
                $wrapperGrid = [System.Windows.Controls.Grid]::new()
                $wrapperGrid.Margin = $control.Margin
                $control.Margin = [System.Windows.Thickness]::new(0)

                # TextBox column (stretch)
                $col1 = [System.Windows.Controls.ColumnDefinition]::new()
                $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
                [void]$wrapperGrid.ColumnDefinitions.Add($col1)

                # Button column (auto)
                $col2 = [System.Windows.Controls.ColumnDefinition]::new()
                $col2.Width = [System.Windows.GridLength]::Auto
                [void]$wrapperGrid.ColumnDefinitions.Add($col2)

                # Add TextBox to first column
                [System.Windows.Controls.Grid]::SetColumn($control, 0)
                [void]$wrapperGrid.Children.Add($control)

                # Create helper button
                $helperBtn = [System.Windows.Controls.Button]::new()
                $helperBtn.Width = 32
                $helperBtn.Height = 32
                $helperBtn.Padding = [System.Windows.Thickness]::new(0)
                $helperBtn.Margin = [System.Windows.Thickness]::new(4, 0, 0, 0)
                $helperBtn.Cursor = [System.Windows.Input.Cursors]::Hand

                # Determine icon and tooltip based on helper type
                if ($needsFolderPicker) {
                    $iconCode = [PsUi.ModuleContext]::GetIcon('Folder')
                    $helperBtn.ToolTip = 'Browse for folder...'
                    $helperBtn.Tag = @{ Mode = 'Folder'; TextBox = $control }
                }
                elseif ($needsFilePicker) {
                    $iconCode = [PsUi.ModuleContext]::GetIcon('OpenFile')
                    $helperBtn.ToolTip = 'Browse for file...'
                    $helperBtn.Tag = @{ Mode = 'File'; TextBox = $control }
                }
                elseif ($needsComputerPicker) {
                    $iconCode = [PsUi.ModuleContext]::GetIcon('Desktop')
                    $helperBtn.ToolTip = 'Select computer...'
                    # Array parameters get multi-select in the picker
                    $isArray = $param.Type.IsArray -or $param.Type.Name -like '*`[`]*'
                    $helperBtn.Tag = @{ Mode = 'Computer'; TextBox = $control; ThemeColors = $ThemeColors; MultiSelect = $isArray }
                }
                elseif ($needsFilterBuilder) {
                    $iconCode = [PsUi.ModuleContext]::GetIcon('Filter')
                    $helperBtn.ToolTip = 'Build filter pattern...'
                    $capturedFilterMode = [string]$filterMode
                    $helperBtn.Tag = @{ Mode = 'Filter'; TextBox = $control; FilterMode = $capturedFilterMode; ThemeColors = $ThemeColors }
                }

                $iconBlock = [System.Windows.Controls.TextBlock]::new()
                $iconBlock.Text = $iconCode
                $iconBlock.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
                $iconBlock.FontSize = 14
                $iconBlock.HorizontalAlignment = 'Center'
                $iconBlock.VerticalAlignment = 'Center'
                $helperBtn.Content = $iconBlock

                # Style the button
                Set-ButtonStyle -Button $helperBtn

                # Click handler based on mode
                $helperBtn.Add_Click({
                    param($sender, $eventArgs)
                    $info = $sender.Tag
                    $result = $null

                    try {
                        switch ($info.Mode) {
                            'Folder'   { $result = Show-UiPathPicker -Mode 'Folder' }
                            'File'     { $result = Show-UiPathPicker -Mode 'File' }
                            'Computer' {
                                $multi = if ($info.MultiSelect) { $true } else { $false }
                                $picked = Show-WindowsObjectPicker -ObjectType Computer -MultiSelect:$multi
                                if ($picked) {
                                    # Extract RawValue from picker result objects
                                    if ($picked -is [array]) {
                                        $result = ($picked | ForEach-Object { $_.RawValue }) -join "`r`n"
                                    }
                                    else {
                                        $result = $picked.RawValue
                                    }
                                }
                            }
                            'Filter' {
                                $fMode = if ($info.FilterMode) { $info.FilterMode } else { 'Generic' }
                                # Get fresh colors at click time so theme changes are reflected
                                $currentColors = Get-ThemeColors
                                $result = Show-UiFilterBuilder -CurrentValue $info.TextBox.Text -Mode $fMode -ThemeColors $currentColors
                            }
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

                # Register the TextBox (not the wrapper) for value retrieval
                if (!$controlAlreadyRegistered) {
                    $session.AddControlSafe($varName, $control)
                    $controlAlreadyRegistered = $true
                }

                # Add wrapper to panel instead of control
                $addTarget.Children.Add($wrapperGrid) | Out-Null
            }
            else {
                # No picker - add control directly
                if (!$controlAlreadyRegistered) {
                    $session.AddControlSafe($varName, $control)
                }

                $addTarget.Children.Add($control) | Out-Null
            }

            # Wire up change events for mandatory validation
            if ($param.IsMandatory) {
                $actualControl = $control
                
                # For wrapper grids (SecureString peek), find the actual input control
                if ($control -is [System.Windows.Controls.Grid]) {
                    foreach ($child in $control.Children) {
                        if ($child -is [System.Windows.Controls.PasswordBox]) {
                            $actualControl = $child
                            break
                        }
                    }
                }

                # Add change handlers based on control type
                if ($actualControl -is [System.Windows.Controls.TextBox]) {
                    $actualControl.Add_TextChanged({ Update-UiToolRunButtonState })
                }
                elseif ($actualControl -is [System.Windows.Controls.PasswordBox]) {
                    $actualControl.Add_PasswordChanged({ Update-UiToolRunButtonState })
                }
                elseif ($actualControl -is [System.Windows.Controls.ComboBox]) {
                    $actualControl.Add_SelectionChanged({ Update-UiToolRunButtonState })
                }
            }
        }

        # Required indicator
        if ($param.IsMandatory) {
            $reqLabel = [System.Windows.Controls.TextBlock]::new()
            $reqLabel.Text = "Required"
            $reqLabel.FontSize = 11
            $reqLabel.Foreground = ConvertTo-UiBrush $ThemeColors.Error
            $reqLabel.Margin = [System.Windows.Thickness]::new(0,0,0,2)
            $addTarget.Children.Add($reqLabel) | Out-Null
        }

        # Description
        if ($Descriptions.ContainsKey($param.Name)) {
            $descLabel = [System.Windows.Controls.TextBlock]::new()
            $descLabel.Text = $Descriptions[$param.Name]
            $descLabel.FontSize = 11
            $descLabel.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $descLabel.Opacity = 0.7
            $descLabel.Margin = [System.Windows.Thickness]::new(0,0,0,4)
            if ($ThemeColors.Foreground) {
                $descLabel.Foreground = $ThemeColors.Foreground
            }
            $addTarget.Children.Add($descLabel) | Out-Null
        }

        # If using wrap layout, add the container to the target panel
        if ($UseWrapLayout -and $paramContainer) {
            $TargetPanel.Children.Add($paramContainer) | Out-Null
        }
    }

    # No parameters to configure
    if ($Parameters.Count -eq 0) {
        $emptyLabel = [System.Windows.Controls.TextBlock]::new()
        $emptyLabel.Text = "This command has no configurable parameters."
        $emptyLabel.FontStyle = [System.Windows.FontStyles]::Italic
        $emptyLabel.Opacity = 0.7
        $TargetPanel.Children.Add($emptyLabel) | Out-Null
    }
}
