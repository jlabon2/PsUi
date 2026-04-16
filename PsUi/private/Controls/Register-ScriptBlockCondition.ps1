function Register-ScriptBlockCondition {
    <#
    .SYNOPSIS
        Wires a scriptblock condition that may reference multiple controls.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$TargetControl,

        [Parameter(Mandatory)]
        [scriptblock]$Condition,

        [Parameter(Mandatory)]
        [PsUi.SessionContext]$Session,

        [switch]$ClearIfDisabled
    )

    # Parse the scriptblock text to find variable references
    $scriptText   = $Condition.ToString()
    $varMatches   = [regex]::Matches($scriptText, '\$([A-Za-z_][A-Za-z0-9_]*)')
    $controlNames = @{}

    foreach ($match in $varMatches) {
        $varName = $match.Groups[1].Value

        # Skip built-in PowerShell variables
        if ($varName -in @('null', 'true', 'false', '_', 'PSItem', 'args', 'input', 'this')) { continue }

        # Variable name -> registered control proxy (if it exists)
        $proxy = $Session.GetSafeVariable($varName)
        if ($proxy) { $controlNames[$varName] = $proxy }
    }

    if ($controlNames.Count -eq 0) {
        Write-Warning "[Register-UiCondition] No control variables found in scriptblock"
        return
    }

    # Create closure to clear target control when disabled
    $clearTarget = New-ClearTargetAction -TargetControl $TargetControl -ClearIfDisabled:$ClearIfDisabled

    # Capture the condition text for evaluation (no escaping needed, values are escaped separately)
    $conditionText = $Condition.ToString()

    # Create evaluation function that hydrates values and runs the scriptblock
    $evaluator = {
        # Build a hashtable of current control values
        $values = @{}
        foreach ($name in $controlNames.Keys) {
            $proxy   = $controlNames[$name]
            $control = $proxy.Control
            $values[$name] = Get-ControlConditionValue -Control $control -ReturnValue
        }

        # Evaluate condition using safe variable injection (no string interpolation of values)
        $conditionResult = $false
        try {
            $conditionScript = [scriptblock]::Create($conditionText)
            $conditionResult = $conditionScript.InvokeWithContext($null, [psvariable[]]($values.GetEnumerator() | ForEach-Object { [psvariable]::new($_.Key, $_.Value) })) -eq $true
        }
        catch {
            Write-Debug "Error evaluating condition: $_"
            $conditionResult = $false
        }

        $wasEnabled = $TargetControl.IsEnabled
        $TargetControl.IsEnabled = $conditionResult
        if ($wasEnabled -and !$conditionResult) { & $clearTarget }
    }.GetNewClosure()

    # Set initial state
    & $evaluator

    # Debounce text inputs to reduce scriptblock compilations during fast typing
    $debouncer = [PsUi.UiDebouncer]::new()

    # Dispose debouncer when target control is unloaded to prevent resource leak
    $TargetControl.Add_Unloaded({
        $debouncer.Dispose()
    }.GetNewClosure())

    # Wire up change events on all referenced controls
    foreach ($name in $controlNames.Keys) {
        $proxy         = $controlNames[$name]
        $sourceControl = $proxy.Control

        switch ($sourceControl.GetType().Name) {
            'CheckBox' {
                $sourceControl.Add_Checked({ & $evaluator }.GetNewClosure())
                $sourceControl.Add_Unchecked({ & $evaluator }.GetNewClosure())
            }
            'TextBox' {
                # Debounce text input to avoid compiling scriptblock on every keystroke
                # Store evaluator reference in array to ensure proper closure capture
                $evalRef = @{ Eval = $evaluator }
                $sourceControl.Add_TextChanged({
                    $debouncer.Debounce(150, { & $evalRef.Eval }.GetNewClosure())
                }.GetNewClosure())
            }
            'PasswordBox' {
                # Debounce password input too
                $evalRef = @{ Eval = $evaluator }
                $sourceControl.Add_PasswordChanged({
                    $debouncer.Debounce(150, { & $evalRef.Eval }.GetNewClosure())
                }.GetNewClosure())
            }
            'ComboBox' {
                $sourceControl.Add_SelectionChanged({ & $evaluator }.GetNewClosure())
            }
            'Slider' {
                $sourceControl.Add_ValueChanged({ & $evaluator }.GetNewClosure())
            }
            'DatePicker' {
                $sourceControl.Add_SelectedDateChanged({ & $evaluator }.GetNewClosure())
            }
            'StackPanel' {
                # RadioGroup pattern - wire all RadioButtons
                $radioButtons = $sourceControl.Children | Where-Object { $_.GetType().Name -eq 'RadioButton' }
                foreach ($radio in $radioButtons) {
                    $radio.Add_Checked({ & $evaluator }.GetNewClosure())
                }
            }
        }
    }
}
