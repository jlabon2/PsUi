function Set-UiValue {
    <#
    .SYNOPSIS
        Sets the value of a UI control by its variable name.
    .DESCRIPTION
        Updates the value of a registered UI control from code. This works both from
        -NoAsync button actions (UI thread) and from async contexts. The function
        automatically handles dispatcher marshaling for thread safety.
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
    
    $session = [PsUi.SessionManager]::Current
    if (!$session) { Write-Warning "Set-UiValue: No active UI session found."; return }
    
    $control = $session.GetControl($Variable)
    if (!$control) { Write-Warning "Set-UiValue: Control '$Variable' not found in session."; return }
    
    $dispatcher     = $control.Dispatcher
    $needsDispatch  = !$dispatcher.CheckAccess()
    
    # Build the setter action - try hydration engine first, fall back to common properties
    $setAction = {
        param($ctrl, $val)
        
        $applied = [PsUi.UiHydration]::TryApplyValue($ctrl, $val)
        if ($applied) { return }
        
        # Hydration engine didn't handle it - try common property patterns
        $type = $ctrl.GetType()
        
        if ($type.GetProperty('Text'))              { $ctrl.Text = [string]$val }
        elseif ($type.GetProperty('Content'))       { $ctrl.Content = $val }
        elseif ($type.GetProperty('IsChecked'))     { $ctrl.IsChecked = [bool]$val }
        elseif ($type.GetProperty('SelectedItem'))  { $ctrl.SelectedItem = $val }
        elseif ($type.GetProperty('Value'))         { $ctrl.Value = $val }
        else { Write-Warning "Set-UiValue: Could not determine how to set value on control type '$($type.Name)'." }
    }
    
    if ($needsDispatch) {
        $dispatcher.Invoke([Action[object, object]]$setAction, @($control, $Value))
    }
    else {
        & $setAction $control $Value
    }
}
