function Show-UiPromptDialog {
    <#
    .SYNOPSIS
        Shows a multi-field prompt dialog.
    .DESCRIPTION
        Displays a themed dialog with dynamically generated input fields based on
        FieldDescription collection. Used to intercept $Host.UI.Prompt() calls.
    .PARAMETER Caption
        The caption/title of the dialog.
    .PARAMETER Message
        The message to display.
    .PARAMETER Descriptions
        Collection of FieldDescription objects defining fields to display.
    .EXAMPLE
        Show-UiPromptDialog -Caption "Input Required" -Message "Enter values" -Descriptions $fields
    #>
    [CmdletBinding()]
    param(
        [string]$Caption,
        [string]$Message,
        [System.Collections.ObjectModel.Collection[System.Management.Automation.Host.FieldDescription]]$Descriptions
    )

    Write-Debug "Caption='$Caption' FieldCount=$($Descriptions.Count)"

    $dialogTitle = if ($Caption) { $Caption } else { "Input Required" }
    $fieldControls = @{}

    # Create dialog window using shared helper with Edit icon
    $editIcon = [PsUi.ModuleContext]::GetIcon('Edit')
    $dlg = New-DialogWindow -Title $dialogTitle -Width 450 -MaxHeight 700 -AppIdSuffix 'PromptDialog' -OverlayGlyph $editIcon -TitleIcon $editIcon

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

    # Scrollable content area
    $scrollViewer = [System.Windows.Controls.ScrollViewer]@{
        VerticalScrollBarVisibility   = 'Auto'
        HorizontalScrollBarVisibility = 'Disabled'
    }

    $mainStack = [System.Windows.Controls.StackPanel]::new()

    # Optional message at top
    if ($Message) {
        $msgText = [System.Windows.Controls.TextBlock]@{
            Text         = $Message
            TextWrapping = 'Wrap'
            FontSize     = 13
            Foreground   = ConvertTo-UiBrush $colors.ControlFg
            Margin       = [System.Windows.Thickness]::new(0, 0, 0, 15)
        }
        [void]$mainStack.Children.Add($msgText)
    }

    # Build input fields from descriptions
    foreach ($field in $Descriptions) {
        $fieldName = $field.Name
        $fieldLabel = if ($field.Label) { $field.Label } else { $fieldName }
        $isSecure = $field.ParameterTypeName -like '*SecureString*' -or $field.ParameterTypeName -like '*Password*'

        $label = [System.Windows.Controls.TextBlock]@{
            Text       = $fieldLabel
            FontSize   = 12
            Foreground = ConvertTo-UiBrush $colors.ControlFg
            Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
        }
        [void]$mainStack.Children.Add($label)

        if ($field.HelpMessage) {
            $helpText = [System.Windows.Controls.TextBlock]@{
                Text       = $field.HelpMessage
                FontSize   = 10
                Foreground = ConvertTo-UiBrush $colors.SecondaryText
                Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
                FontStyle  = 'Italic'
            }
            [void]$mainStack.Children.Add($helpText)
        }

        if ($isSecure) {
            $inputControl = [System.Windows.Controls.PasswordBox]@{
                Height      = 28
                FontSize    = 12
                Background  = ConvertTo-UiBrush $colors.ControlBg
                Foreground  = ConvertTo-UiBrush $colors.ControlFg
                BorderBrush = ConvertTo-UiBrush $colors.Border
                Padding     = [System.Windows.Thickness]::new(2, 0, 2, 0)
                Margin      = [System.Windows.Thickness]::new(0, 0, 0, 10)
            }
        }
        else {
            $inputControl = [System.Windows.Controls.TextBox]@{
                Height   = 28
                FontSize = 12
                Padding  = [System.Windows.Thickness]::new(2, 0, 2, 0)
                Margin   = [System.Windows.Thickness]::new(0, 0, 0, 10)
            }
            Set-TextBoxStyle -TextBox $inputControl

            if ($field.DefaultValue) {
                $inputControl.Text = $field.DefaultValue.ToString()
            }
        }

        [void]$mainStack.Children.Add($inputControl)
        $fieldControls[$fieldName] = @{
            Control  = $inputControl
            IsSecure = $isSecure
            Type     = $field.ParameterTypeName
        }
    }

    $scrollViewer.Content = $mainStack
    [void]$contentPanel.Children.Add($scrollViewer)

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

    # Standard window behavior
    Initialize-UiWindowLoaded -Window $window

    # Focus first field
    $window.Add_Loaded({
        $firstField = $fieldControls.Values | Select-Object -First 1
        if ($firstField) { $firstField.Control.Focus() }
    }.GetNewClosure())

    Set-UiDialogPosition -Dialog $window

    Write-Debug "Showing modal dialog"
    [void]$window.ShowDialog()

    $result = [System.Collections.Generic.Dictionary[string,System.Management.Automation.PSObject]]::new()

    if ($window.Tag -eq 'OK') {
        foreach ($fieldName in $fieldControls.Keys) {
            $fieldInfo = $fieldControls[$fieldName]
            $control = $fieldInfo.Control

            if ($fieldInfo.IsSecure) {
                $value = $control.SecurePassword
            }
            else {
                $value = $control.Text
            }

            $result[$fieldName] = [PSObject]::AsPSObject($value)
        }
        Write-Debug "Result: $($result.Count) fields returned"
    }
    else {
        Write-Debug "Result: <cancelled>"
    }

    return $result
}
