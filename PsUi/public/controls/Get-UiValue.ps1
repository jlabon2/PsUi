function Get-UiValue {
    <#
    .SYNOPSIS
        Gets the value of a UI control by its variable name.
    .DESCRIPTION
        Retrieves the current value of a registered UI control. This works from
        -NoAsync button actions where hydration doesn't apply. The function
        automatically handles dispatcher marshaling for thread safety.
    .PARAMETER Variable
        The variable name of the control. This matches the -Variable parameter
        used when creating the control.
    .EXAMPLE
        $url = Get-UiValue -Variable 'urlInput'
        
        Gets the current value from the control registered as 'urlInput'.
    .EXAMPLE
        New-UiButton -Text 'Submit' -NoAsync -Action {
            $name = Get-UiValue -Variable 'userName'
            Write-Host "Hello, $name!"
        }
        
        Button action that reads a control value on the UI thread.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Variable
    )
    
    $session = [PsUi.SessionManager]::Current
    if (!$session) { Write-Warning "Get-UiValue: No active UI session found."; return $null }
    
    $control = $session.GetControl($Variable)
    if (!$control) { Write-Warning "Get-UiValue: Control '$Variable' not found in session."; return $null }
    
    $dispatcher    = $control.Dispatcher
    $needsDispatch = !$dispatcher.CheckAccess()
    
    $getAction = {
        param($ctrl)
        return [PsUi.ControlValueExtractor]::ExtractValue($ctrl)
    }
    
    if ($needsDispatch) {
        return $dispatcher.Invoke([Func[object, object]]$getAction, $control)
    }
    else {
        return (& $getAction $control)
    }
}
