function Register-SingleControlCondition {
    <#
    .SYNOPSIS
        Wires a single control proxy as the enabling condition.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$TargetControl,

        [Parameter(Mandatory)]
        [PsUi.ThreadSafeControlProxy]$SourceProxy,

        [switch]$ClearIfDisabled
    )

    $sourceControl = $SourceProxy.Control

    # Set initial enabled state based on current truthy value
    $TargetControl.IsEnabled = Get-ControlConditionValue -Control $sourceControl

    $clearTarget = New-ClearTargetAction -TargetControl $TargetControl -ClearIfDisabled:$ClearIfDisabled

    # Wire up change events based on control type
    switch ($sourceControl.GetType().Name) {
        'CheckBox' {
            $sourceControl.Add_Checked({
                param($checkBox, $args)
                $TargetControl.IsEnabled = $true
            }.GetNewClosure())
            $sourceControl.Add_Unchecked({
                param($checkBox, $args)
                $TargetControl.IsEnabled = $false
                & $clearTarget
            }.GetNewClosure())
        }
        'TextBox' {
            $sourceControl.Add_TextChanged({
                param($textBox, $args)
                $wasEnabled = $TargetControl.IsEnabled
                $isEnabled  = ![string]::IsNullOrWhiteSpace($textBox.Text)
                $TargetControl.IsEnabled = $isEnabled
                if ($wasEnabled -and !$isEnabled) { & $clearTarget }
            }.GetNewClosure())
        }
        'PasswordBox' {
            $sourceControl.Add_PasswordChanged({
                param($passwordBox, $args)
                $wasEnabled = $TargetControl.IsEnabled
                $isEnabled  = $passwordBox.SecurePassword.Length -gt 0
                $TargetControl.IsEnabled = $isEnabled
                if ($wasEnabled -and !$isEnabled) { & $clearTarget }
            }.GetNewClosure())
        }
        'ComboBox' {
            $sourceControl.Add_SelectionChanged({
                param($comboBox, $args)
                $wasEnabled = $TargetControl.IsEnabled
                $isEnabled  = $comboBox.SelectedIndex -ge 0
                $TargetControl.IsEnabled = $isEnabled
                if ($wasEnabled -and !$isEnabled) { & $clearTarget }
            }.GetNewClosure())
        }
        'Slider' {
            $sourceControl.Add_ValueChanged({
                param($slider, $args)
                $wasEnabled = $TargetControl.IsEnabled
                $isEnabled  = $slider.Value -gt 0
                $TargetControl.IsEnabled = $isEnabled
                if ($wasEnabled -and !$isEnabled) { & $clearTarget }
            }.GetNewClosure())
        }
        'DatePicker' {
            $sourceControl.Add_SelectedDateChanged({
                param($datePicker, $args)
                $wasEnabled = $TargetControl.IsEnabled
                $isEnabled  = $null -ne $datePicker.SelectedDate
                $TargetControl.IsEnabled = $isEnabled
                if ($wasEnabled -and !$isEnabled) { & $clearTarget }
            }.GetNewClosure())
        }
        'StackPanel' {
            # RadioGroup is a StackPanel containing RadioButtons - check for that pattern
            $radioButtons = $sourceControl.Children | Where-Object { $_.GetType().Name -eq 'RadioButton' }
            if ($radioButtons) {
                foreach ($radio in $radioButtons) {
                    $radio.Add_Checked({
                        param($radioButton, $args)
                        $TargetControl.IsEnabled = $true
                    }.GetNewClosure())
                }
            }
            else {
                Write-Warning "[Register-UiCondition] StackPanel has no RadioButtons - unsupported"
            }
        }
        default {
            Write-Warning "[Register-UiCondition] Unsupported control type: $($sourceControl.GetType().Name)"
        }
    }
}
