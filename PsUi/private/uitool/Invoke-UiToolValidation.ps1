<#
.SYNOPSIS
    Validates parameter values for New-UiTool before command execution.
#>
function Invoke-UiToolValidation {
    [CmdletBinding()]
    param(
        [string]$CommandName,
        [string]$ParameterSetName
    )

    $session = Get-UiSession
    $def = $session.PSBase.CurrentDefinition

    if (!$CommandName -and $def) {
        $CommandName = $def.CommandName
    }
    if (!$ParameterSetName -and $def) {
        $ParameterSetName = $def.ParameterSetName
    }

    # Get current parameter set from UI (if selector exists)
    $proxy = [PsUi.SessionManager]::Current.GetSafeVariable('selectedParameterSet')
    $currentSet = if ($proxy) { $proxy.Value } else { $null }
    if (!$currentSet) { $currentSet = $ParameterSetName }

    # Try to get command info - may fail for local functions
    $cmdInfo     = $null
    $cmdLookup   = $CommandName
    $storedParams = $null

    try {
        $cmdInfo = Get-Command $cmdLookup -ErrorAction Stop
    }
    catch {
        # Local function not available globally - use stored param info from session
        $session      = Get-UiSession
        $storedParams = $session.Variables['_uiTool_paramInfo']
    }

    $commonParams = @(
        'Verbose','Debug','ErrorAction','WarningAction','InformationAction',
        'ErrorVariable','WarningVariable','InformationVariable',
        'OutVariable','OutBuffer','PipelineVariable','WhatIf','Confirm','UseTransaction'
    )

    # Build current params list from cmdInfo or stored params
    $currentParams = $null
    if ($storedParams) {
        $currentParams = $storedParams
    }
    elseif ($cmdInfo) {
        $paramSetDef   = $cmdInfo.ParameterSets | Where-Object { $_.Name -eq $currentSet }
        $currentParams = [System.Collections.Generic.List[object]]::new()

        foreach ($paramName in $cmdInfo.Parameters.Keys) {
            if ($commonParams -contains $paramName) { continue }

            $param = $cmdInfo.Parameters[$paramName]
            if ($currentSet) {
                $inSet = $param.ParameterSets.ContainsKey($currentSet) -or
                         $param.ParameterSets.ContainsKey('__AllParameterSets')
                if (!$inSet) { continue }
            }

            # Check mandatory for THIS specific parameter set
            $isMandatoryInSet = $false
            if ($paramSetDef) {
                $paramInSet = $paramSetDef.Parameters | Where-Object { $_.Name -eq $paramName }
                if ($paramInSet) { $isMandatoryInSet = $paramInSet.IsMandatory }
            }

            $currentParams.Add([PSCustomObject]@{
                Name        = $paramName
                Type        = $param.ParameterType
                IsMandatory = $isMandatoryInSet
                IsSwitch    = $param.ParameterType -eq [switch]
            })
        }
    }

    # Can't validate without param info - proceed anyway
    if (!$currentParams) { return @() }

    $paramHash        = @{}
    $validationErrors = [System.Collections.Generic.List[string]]::new()
    $session          = Get-UiSession

    foreach ($paramDef in $currentParams) {
        $varName = "param_$($paramDef.Name)"
        $value   = $null

        # PSCredential uses a special wrapper stored in session.Variables
        if ($paramDef.Type -eq [System.Management.Automation.PSCredential]) {
            $credWrapper = $session.Variables[$varName]
            if ($credWrapper -and $credWrapper.PSObject.TypeNames -contains 'PsUi.CredentialControl') {
                # Assemble PSCredential from username + password boxes
                $username = $credWrapper.UsernameBox.Text
                $secPass  = $credWrapper.PasswordBox.SecurePassword
                if (![string]::IsNullOrWhiteSpace($username) -and $secPass.Length -gt 0) {
                    $value = [System.Management.Automation.PSCredential]::new($username, $secPass)
                }
            }
        }
        else {
            # Standard controls use SafeVariables proxy
            $proxy = [PsUi.SessionManager]::Current.GetSafeVariable($varName)
            $value = if ($proxy) { $proxy.Value } else { $null }
        }

        # For PSCredential, check null instead of IsNullOrWhiteSpace
        $isEmpty = if ($paramDef.Type -eq [System.Management.Automation.PSCredential]) {
            $null -eq $value
        }
        else {
            [string]::IsNullOrWhiteSpace($value)
        }

        # Skip empty non-mandatory values
        if ($isEmpty -and !$paramDef.IsMandatory) { continue }

        # Mandatory field left blank
        if ($paramDef.IsMandatory -and $isEmpty -and !$paramDef.IsSwitch) {
            $validationErrors.Add("$($paramDef.Name) is required")
            continue
        }

        try {
            if ($paramDef.IsSwitch) {
                if ($value -eq $true) { $paramHash[$paramDef.Name] = [switch]::Present }
            }
            elseif ($paramDef.Type -eq [string[]]) {
                if (![string]::IsNullOrWhiteSpace($value)) {
                    $paramHash[$paramDef.Name] = $value -split "`r?`n" | Where-Object { $_.Trim() }
                }
            }
            elseif ($paramDef.Type -eq [int] -or $paramDef.Type -eq [int32]) {
                if (![string]::IsNullOrWhiteSpace($value)) {
                    $paramHash[$paramDef.Name] = [int]$value
                }
            }
            elseif ($paramDef.Type -eq [int64]) {
                if (![string]::IsNullOrWhiteSpace($value)) {
                    $paramHash[$paramDef.Name] = [int64]$value
                }
            }
            elseif ($paramDef.Type -eq [double] -or $paramDef.Type -eq [float]) {
                if (![string]::IsNullOrWhiteSpace($value)) {
                    $paramHash[$paramDef.Name] = [double]$value
                }
            }
            elseif ($paramDef.Type -eq [bool]) {
                $paramHash[$paramDef.Name] = $value -eq $true
            }
            elseif ($paramDef.Type -eq [datetime]) {
                if ($value) { $paramHash[$paramDef.Name] = [datetime]$value }
            }
            elseif ($paramDef.Type -eq [System.Security.SecureString]) {
                if (![string]::IsNullOrWhiteSpace($value)) {
                    $paramHash[$paramDef.Name] = ConvertTo-SecureString $value -AsPlainText -Force
                }
            }
            elseif ($paramDef.Type -eq [System.Management.Automation.PSCredential]) {
                if ($value -and $value -is [System.Management.Automation.PSCredential]) {
                    $paramHash[$paramDef.Name] = $value
                }
                elseif ($paramDef.IsMandatory) {
                    $validationErrors.Add("$($paramDef.Name): Credential is required")
                }
            }
            elseif ($paramDef.Type -eq [scriptblock]) {
                if (![string]::IsNullOrWhiteSpace($value)) {
                    $paramHash[$paramDef.Name] = [scriptblock]::Create($value)
                }
            }
            else {
                if (![string]::IsNullOrWhiteSpace($value)) {
                    $paramHash[$paramDef.Name] = $value
                }
            }
        }
        catch {
            $validationErrors.Add("$($paramDef.Name): $($_.Exception.Message)")
        }
    }

    # Store validated params for the action to use
    if ($validationErrors.Count -eq 0) {
        $session = Get-UiSession
        $session.Variables['_uiTool_validatedParams'] = $paramHash
    }

    return $validationErrors
}
