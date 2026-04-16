function Register-UiCondition {
    <#
    .SYNOPSIS
        Wires up conditional enabling between controls or session variables.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$TargetControl,

        [Parameter(Mandatory)]
        [object]$Condition,

        [switch]$ClearIfDisabled
    )

    # Get session context for control lookups
    $session = [PsUi.SessionManager]::Current
    if (!$session) {
        Write-Warning "[Register-UiCondition] No active session - cannot wire condition"
        return
    }

    # Accept string variable name - first check for control, then fall back to session variable
    if ($Condition -is [string]) {
        $proxy = $session.GetSafeVariable($Condition)
        if ($proxy) {
            # Found a control - wire up control-based condition
            Register-SingleControlCondition -TargetControl $TargetControl -SourceProxy $proxy -ClearIfDisabled:$ClearIfDisabled
            return
        }
        
        # No control found - register as session variable binding (for -Capture variables)
        $session.RegisterVariableBinding($Condition, $TargetControl)
        Write-Debug "Registered variable binding for '$Condition'"
        return
    }

    # Accept control proxy directly
    if ($Condition -is [PsUi.ThreadSafeControlProxy]) {
        Register-SingleControlCondition -TargetControl $TargetControl -SourceProxy $Condition -ClearIfDisabled:$ClearIfDisabled
        return
    }

    # Scriptblock - parse for variables and wire up all referenced controls
    Register-ScriptBlockCondition -TargetControl $TargetControl -Condition $Condition -Session $session -ClearIfDisabled:$ClearIfDisabled
}

