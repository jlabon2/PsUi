function Set-UiValue {
    <#
    .SYNOPSIS
        Sets the value of a UI control by its variable name.
    .DESCRIPTION
        Sets a registered control's value from any action, async or -NoAsync. A value the control
        can't take (such as a string for a slider) skips it and writes an error indicating
        the control. The action continues unless it runs under -ErrorAction Stop.
    .PARAMETER Variable
        The variable name of the control to update. This matches the -Variable parameter
        used when creating the control.
    .PARAMETER Value
        The value to set on the control. Type conversion is attempted automatically.
    .EXAMPLE
        Set-UiValue -Variable 'status' -Value 'Processing...'
        
        Updates the control registered as 'status' to display 'Processing...'.
    .EXAMPLE
        New-UiButton -Text 'Submit' -NoAsync -Action {
            Set-UiValue -Variable 'output' -Value "Submitted at $(Get-Date)"
        }
        
        Button action that updates a control synchronously on the UI thread.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Variable,
        
        [Parameter(Mandatory, Position = 1)]
        [object]$Value
    )
    
    # SessionManager::Current is ThreadStatic, and on the dedicated runspace path the pipeline thread never gets it set. Get-UiSession checks the runspace's injected session id first.
    $session = Get-UiSession
    if (!$session) { Write-Warning "Set-UiValue: No active UI session found."; return }
    
    $control = $session.GetControl($Variable)
    if (!$control) { Write-Warning "Set-UiValue: Control '$Variable' not found in session."; return }
    
    # Build the setter action - try hydration engine first, fall back to common properties
    $setAction = {
        param($ctrl, $val)

        # The setter's own error just says 'Exception setting "Value"', so the refusal comes back here for the error below to say which control turned it down
        $report = @{ Refused = $false; Cause = $null }
        trap { $report.Refused = $true; $report.Cause = $_.Exception; continue }

        $applied = [PsUi.UiHydration]::TryApplyValue($ctrl, $val)
        if ($applied) { return }

        # Hydration engine didn't handle it - try common property patterns
        $type          = $ctrl.GetType()
        $valueProperty = $type.GetProperty('Value')

        # IsChecked ahead of Content, otherwise a toggle takes the value as its label
        if ($type.GetProperty('Text'))              { $ctrl.Text = [string]$val }
        elseif ($type.GetProperty('IsChecked'))     { $ctrl.IsChecked = [bool]$val }
        elseif ($type.GetProperty('Content'))       { $ctrl.Content = $val }
        elseif ($type.GetProperty('SelectedItem'))  { $ctrl.SelectedItem = $val }
        elseif ($valueProperty) {
            # Checking first keeps the setter's error out of $Error and -ErrorVariable, where a trapped set leaves up to three copies
            $converted  = $null
            $fits       = [System.Management.Automation.LanguagePrimitives]::TryConvertTo($val, $valueProperty.PropertyType, [ref]$converted)
            $descriptor = [System.ComponentModel.DependencyPropertyDescriptor]::FromName('Value', $type, $type)

            # NaN converts fine, then the slider's own check turns it down
            if ($fits -and $descriptor) { $fits = $descriptor.DependencyProperty.IsValidValue($converted) }
            if ($fits) { $ctrl.Value = $converted }
            else { $report.Refused = $true }
        }
        else { $type.Name }

        if ($report.Refused) { $report }
    }

    $outcome = Invoke-OnUIThread -Dispatcher $control.Dispatcher -ArgumentList $control, $Value -ScriptBlock $setAction
    if ($outcome -is [hashtable]) {
        # Slider reads as 'slider', DatePicker as 'date picker'
        $kind    = ($control.GetType().Name -creplace '(?<=[a-z])(?=[A-Z])', ' ').ToLower()
        $refusal = [System.ArgumentException]::new("'$Value' isn't a value the $kind '$Variable' takes.", $outcome.Cause)

        # An $ErrorActionPreference set in the action stops at the module's edge,so the calling script's gets copied in unless -ErrorAction already had its say
        if (!$PSBoundParameters.ContainsKey('ErrorAction')) {
            $ErrorActionPreference = $PSCmdlet.SessionState.PSVariable.GetValue('ErrorActionPreference')
        }
        $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new($refusal, 'SetUiValueRefused', 'InvalidArgument', $Value))
        return
    }
    if ($outcome) { Write-Warning "Set-UiValue: Could not determine how to set value on control type '$outcome'." }
}
