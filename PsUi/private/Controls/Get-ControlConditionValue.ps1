function Get-ControlConditionValue {
    <#
    .SYNOPSIS
        Gets a control's current value or boolean state for condition evaluation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Control,

        [switch]$ReturnValue
    )

    $value    = $null
    $hasValue = $false

    switch ($Control.GetType().Name) {
        'CheckBox' {
            $value    = $Control.IsChecked -eq $true
            $hasValue = $value
        }
        'TextBox' {
            $value    = $Control.Text
            $hasValue = ![string]::IsNullOrWhiteSpace($value)
        }
        'PasswordBox' {
            $value    = $Control.SecurePassword
            $hasValue = $Control.SecurePassword.Length -gt 0
        }
        'ComboBox' {
            $value    = $Control.SelectedItem
            $hasValue = $Control.SelectedIndex -ge 0
        }
        'Slider' {
            $value    = $Control.Value
            $hasValue = $value -gt 0
        }
        'DatePicker' {
            $value    = $Control.SelectedDate
            $hasValue = $null -ne $value
        }
        'StackPanel' {
            # RadioGroup pattern - find the checked RadioButton
            $checked  = $Control.Children | Where-Object { $_.GetType().Name -eq 'RadioButton' -and $_.IsChecked -eq $true }
            $value    = if ($checked) { $checked.Content } else { $null }
            $hasValue = $null -ne $checked
        }
        default {
            # For unknown controls, try common properties
            if ($Control.PSObject.Properties['IsChecked']) {
                $value    = $Control.IsChecked -eq $true
                $hasValue = $value
            }
            elseif ($Control.PSObject.Properties['Text']) {
                $value    = $Control.Text
                $hasValue = ![string]::IsNullOrWhiteSpace($value)
            }
            else {
                $hasValue = $true
            }
        }
    }

    if ($ReturnValue) { return $value }
    return $hasValue
}
