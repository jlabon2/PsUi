
function Register-VariableHydration {
    <#
    .SYNOPSIS
        Prepares linked variables, functions, and modules for async execution.
    #>
    [CmdletBinding()]
    param(
        [System.Collections.IDictionary]$LinkedVariableValues,
        [System.Collections.IDictionary]$LinkedFunctionDefinitions,
        [string[]]$LinkedVariables,
        [string[]]$LinkedFunctions,
        [string[]]$LinkedModules,
        [switch]$DebugEnabled
    )

    $isDebug = $DebugEnabled

    # Start with any explicitly provided dictionaries
    $funcDefs  = if ($LinkedFunctionDefinitions) { $LinkedFunctionDefinitions.Clone() } else { @{} }
    $varValues = if ($LinkedVariableValues) { $LinkedVariableValues.Clone() } else { @{} }
    
    if ($isDebug) { [Console]::WriteLine("[DEBUG] Register-VariableHydration starting...") }
    if ($isDebug -and $LinkedVariableValues) { [Console]::WriteLine("[DEBUG]   LinkedVariableValues provided: $($LinkedVariableValues.Count) items") }
    if ($isDebug -and $LinkedFunctionDefinitions) { [Console]::WriteLine("[DEBUG]   LinkedFunctionDefinitions provided: $($LinkedFunctionDefinitions.Count) items") }

    # Control variables ($controlName) are hydrated by StateHydrationEngine.HydrateViaScript
    # which reads live values from the actual WPF controls.
    # $WPF hashtable is NOT injected - it contained stale initial values.

    # Add standard preference variables
    $stdVars = 'PSScriptRoot', 'PSCommandPath', 'ErrorActionPreference', 'WarningPreference', 'VerbosePreference', 'DebugPreference', 'InformationPreference', 'ProgressPreference'
    $prefVarsAdded = 0
    foreach ($stdVarName in $stdVars) {
        if (!$varValues.ContainsKey($stdVarName)) {
            $var = Get-Variable -Name $stdVarName -Scope 1 -ErrorAction SilentlyContinue
            if ($var) { 
                $varValues[$stdVarName] = $var.Value
                $prefVarsAdded++
            }
        }
    }
    if ($isDebug) { [Console]::WriteLine("[DEBUG]   Added $prefVarsAdded PowerShell preference variables") }

    # Add dynamic lookups (Legacy behavior for LinkedVariables array)
    if ($LinkedVariables) {
        $foundVars = 0
        $missingVars = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $LinkedVariables) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if (!$varValues.ContainsKey($name)) {
                $var = Get-Variable -Name $name -Scope 1 -ErrorAction SilentlyContinue
                if ($var) { 
                    $varValues[$name] = $var.Value
                    $foundVars++
                }
                else {
                    $missingVars.Add($name)
                }
            }
        }
        if ($isDebug) { [Console]::WriteLine("[DEBUG]   LinkedVariables: found $foundVars of $($LinkedVariables.Count) requested") }
        if ($isDebug -and $missingVars.Count -gt 0) { [Console]::WriteLine("[DEBUG]   WARNING: LinkedVariables not found: $($missingVars -join ', ')") }
    }
    if ($LinkedFunctions) {
        $foundFuncs = 0
        $missingFuncs = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $LinkedFunctions) {
            if (!$funcDefs.ContainsKey($name)) {
                if (Test-Path "Function:\$name") {
                    $funcDefs[$name] = (Get-Item "Function:\$name").Definition
                    $foundFuncs++
                }
                else {
                    $missingFuncs.Add($name)
                }
            }
        }
        if ($isDebug) { [Console]::WriteLine("[DEBUG]   LinkedFunctions: found $foundFuncs of $($LinkedFunctions.Count) requested") }
        if ($isDebug -and $missingFuncs.Count -gt 0) { [Console]::WriteLine("[DEBUG]   WARNING: LinkedFunctions not found: $($missingFuncs -join ', ')") }
    }

    # Capture modules to import into async runspace
    $WPFToolsPath = (Get-Module PsUi).Path
    if (!$WPFToolsPath) {
        $WPFToolsPath = 'PsUi'
    }

    # Always include PsUi
    [System.Collections.Generic.List[string]]$capturedModules = [System.Collections.Generic.List[string]]::new()
    $capturedModules.Add($WPFToolsPath)
    if ($LinkedModules) {
        $capturedModules.AddRange($LinkedModules)
        if ($isDebug) { [Console]::WriteLine("[DEBUG]   LinkedModules: $($LinkedModules -join ', ')") }
    }
    
    if ($isDebug) { [Console]::WriteLine("[DEBUG] Hydration complete: $($varValues.Count) vars, $($funcDefs.Count) funcs, $($capturedModules.Count) modules") }

    return @{
        Variables = $varValues
        Functions = $funcDefs
        Modules   = $capturedModules
    }
}
