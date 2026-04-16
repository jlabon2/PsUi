function New-ClearTargetAction {
    <#
    .SYNOPSIS
        Creates a closure that clears the target control's value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$TargetControl,

        [switch]$ClearIfDisabled
    )

    $shouldClear = $ClearIfDisabled

    return {
        if ($shouldClear) {
            switch ($TargetControl.GetType().Name) {
                'TextBox'     { $TargetControl.Text = '' }
                'PasswordBox' { $TargetControl.Clear() }
                'ComboBox'    { $TargetControl.SelectedIndex = 0 }
                'CheckBox'    { $TargetControl.IsChecked = $false }
                'Slider'      { $TargetControl.Value = $TargetControl.Minimum }
                'DatePicker'  { $TargetControl.SelectedDate = $null }
                'RadioGroup'  { }  # RadioGroups typically don't clear - leave as-is
            }
        }
    }.GetNewClosure()
}
