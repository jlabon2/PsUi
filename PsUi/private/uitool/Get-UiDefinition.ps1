<#
.SYNOPSIS
    Introspects a PowerShell command and returns a UI definition schema.
#>
function Get-UiDefinition {
    [CmdletBinding()]
    param(
        # Command can be: cmdlet name, function name, script path, or CommandInfo object
        [Parameter(Mandatory, Position = 0)]
        [object]$Command,

        [string]$ParameterSet,

        [string[]]$ExcludeParameters = @(),

        [switch]$IncludeCommonParameters,

        # Input helper detection
        [string[]]$FilePickerParameters = @(),
        [string[]]$FolderPickerParameters = @(),
        [string[]]$ComputerPickerParameters = @(),
        [switch]$NoAutoHelpers,

        # Caller's SessionState for local function lookup
        [System.Management.Automation.SessionState]$CallerSessionState
    )

    # Collect all unique SessionStates from the call stack for function lookup
    # This handles nested scriptblocks (button actions, child windows, etc.)
    $callStackSessionStates = [System.Collections.Generic.List[System.Management.Automation.SessionState]]::new()
    if ($CallerSessionState) {
        $callStackSessionStates.Add($CallerSessionState)
    }
    
    # Walk up the call stack and collect all unique SessionStates
    try {
        $callStack = Get-PSCallStack
        $flags = [System.Reflection.BindingFlags]'Instance, NonPublic, Public'
        $sbProp = [System.Management.Automation.ScriptBlock].GetProperty('SessionState', $flags)
        
        foreach ($frame in $callStack) {
            if ($frame.InvocationInfo.MyCommand.ScriptBlock -and $sbProp) {
                $frameState = $sbProp.GetValue($frame.InvocationInfo.MyCommand.ScriptBlock)
                if ($frameState -and !$callStackSessionStates.Contains($frameState)) {
                    $callStackSessionStates.Add($frameState)
                }
            }
        }
        
        Write-Debug "Collected $($callStackSessionStates.Count) unique SessionStates from call stack"
    }
    catch {
        Write-Verbose "[Get-UiDefinition] Could not walk call stack: $_"
    }

    # Helper to look up function from any SessionState in the call stack
    $lookupLocalFunction = {
        param([string]$funcName)
        if ($callStackSessionStates.Count -eq 0) { return $null }

        # Search through all collected SessionStates
        foreach ($sessionState in $callStackSessionStates) {
            # Try InvokeCommand.GetCommand first
            try {
                $cmd = $sessionState.InvokeCommand.GetCommand(
                    $funcName,
                    [System.Management.Automation.CommandTypes]::Function
                )
                if ($cmd) {
                    Write-Debug "Found '$funcName' via SessionState lookup"
                    return $cmd
                }
            }
            catch { Write-Debug "GetCommand lookup failed: $_" }

            # Try reflection to access internal function table
            try {
                $internal = $null
                $field = $sessionState.GetType().GetField(
                    '_sessionState',
                    [System.Reflection.BindingFlags]'Instance, NonPublic'
                )
                if ($field) {
                    $internal = $field.GetValue($sessionState)
                }

                if (!$internal) {
                    $prop = $sessionState.GetType().GetProperty(
                        'Internal',
                        [System.Reflection.BindingFlags]'Instance, NonPublic'
                    )
                    if ($prop) {
                        $internal = $prop.GetValue($sessionState)
                    }
                }

                if ($internal) {
                    $methods = $internal.GetType().GetMethods(
                        [System.Reflection.BindingFlags]'Instance, Public, NonPublic'
                    ) | Where-Object { $_.Name -eq 'GetFunction' }

                    foreach ($method in $methods) {
                        try {
                            $params = $method.GetParameters()
                            if ($params.Count -eq 1 -and $params[0].ParameterType -eq [string]) {
                                $funcInfo = $method.Invoke($internal, @($funcName))
                                if ($funcInfo -and $funcInfo.ScriptBlock) {
                                    return [PSCustomObject]@{
                                        Name        = $funcName
                                        Definition  = $funcInfo.ScriptBlock.ToString()
                                        ScriptBlock = $funcInfo.ScriptBlock
                                        CommandType = 'Function'
                                    }
                                }
                            }
                        }
                        catch { Write-Debug "Reflection invoke failed: $_" }
                    }
                }
            }
            catch { Write-Debug "Reflection access failed: $_" }
        }

        return $null
    }

    # Result structure - gets filled in based on what we're parsing
    $cmdInfo            = $null
    $commandDefinition  = $null
    $commandInvocation  = $null
    $isExternalScript   = $false

    # Resolve the command based on input type
    if ($Command -is [System.Management.Automation.CommandInfo]) {
        $cmdInfo = $Command
        if ($cmdInfo -is [System.Management.Automation.FunctionInfo]) {
            $commandDefinition = $cmdInfo.Definition
            $commandInvocation = $cmdInfo.Name
        }
        elseif ($cmdInfo -is [System.Management.Automation.ExternalScriptInfo]) {
            $isExternalScript = $true
            $commandInvocation = $cmdInfo.Path
        }
        else {
            $commandInvocation = $cmdInfo.Name
        }
    }
    elseif ($Command -is [string]) {
        $commandStr = $Command.Trim()

        # Path separators or .ps1 extension = probably a script file
        $looksLikeScript = $commandStr -match '\\|/' -or $commandStr -match '\.ps1$'

        if ($looksLikeScript) {
            # Resolve to absolute path - try Resolve-Path first (works for relative paths from CWD)
            $scriptPath = $null
            try {
                $resolved = Resolve-Path $commandStr -ErrorAction Stop
                $scriptPath = $resolved.Path
            }
            catch {
                # Resolve-Path failed - try relative to caller script
                if ([System.IO.Path]::IsPathRooted($commandStr)) {
                    $scriptPath = $commandStr
                }
                else {
                    $callerPath = (Get-PSCallStack)[2].ScriptName  # [2] = caller of New-UiTool
                    if ($callerPath) {
                        $callerDir = Split-Path $callerPath -Parent
                        $scriptPath = Join-Path $callerDir $commandStr
                    }
                    else {
                        throw "Script not found: $commandStr"
                    }
                }
            }

            if (!(Test-Path $scriptPath)) {
                throw "Script not found: $scriptPath"
            }

            # Parse AST to check for embedded function definitions
            $scriptContent = Get-Content $scriptPath -Raw -ErrorAction Stop
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$tokens, [ref]$parseErrors)
            
            # Script-level param() block means we can build a UI for it
            $hasScriptParams = $ast.ParamBlock -and $ast.ParamBlock.Parameters.Count -gt 0
            
            # Find all function definitions in the script
            $functionDefs = $ast.FindAll({ 
                param($node) 
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] 
            }, $false)
            
            # If script has its own param block, treat it as a parameterized script
            # even if it contains internal helper functions
            if ($hasScriptParams) {
                # Parameterized script with internal helpers - use script params
                $cmdInfo = Get-Command $scriptPath -ErrorAction Stop
                $isExternalScript = $true
                $commandInvocation = $cmdInfo.Path
            }
            elseif ($functionDefs.Count -gt 0) {
                # Script contains function definitions but no script params - extract the target function
                $targetFunc = $null
                $scriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)
                
                if ($functionDefs.Count -eq 1) {
                    # Single function - use it
                    $targetFunc = $functionDefs[0]
                }
                else {
                    # Multiple functions - look for one matching the filename
                    $targetFunc = $functionDefs | Where-Object { $_.Name -eq $scriptBaseName } | Select-Object -First 1
                    
                    if (!$targetFunc) {
                        $funcNames = ($functionDefs | ForEach-Object { $_.Name }) -join ', '
                        throw "Script '$scriptPath' contains multiple functions ($funcNames). Specify which one by passing the function name after dot-sourcing the file, or rename the file to match the desired function."
                    }
                }
                
                # Create a temporary function using Invoke-Expression to preserve param block
                $tempFuncName = "_UiDef_Script_$([guid]::NewGuid().ToString('N').Substring(0,8))"
                $funcDefText = "function global:$tempFuncName $($targetFunc.Body.Extent.Text)"
                try {
                    Invoke-Expression $funcDefText
                    $cmdInfo = Get-Command $tempFuncName -ErrorAction Stop
                    $cmdInfo | Add-Member -NotePropertyName 'OriginalName' -NotePropertyValue $targetFunc.Name -Force
                    $cmdInfo | Add-Member -NotePropertyName 'SourceScriptPath' -NotePropertyValue $scriptPath -Force
                }
                finally {
                    Remove-Item -Path "function:global:$tempFuncName" -ErrorAction SilentlyContinue
                }
                
                $commandDefinition = $targetFunc.Extent.Text
                $commandInvocation = ". '$scriptPath'; $($targetFunc.Name)"
                $isExternalScript = $false  # Treat as function now
            }
            else {
                # No functions and no script params - still try as script
                $cmdInfo = Get-Command $scriptPath -ErrorAction Stop
                $isExternalScript = $true
                $commandInvocation = $cmdInfo.Path
            }
        }
        else {
            # Try local function lookup first
            $localFunc = & $lookupLocalFunction $commandStr
            if ($localFunc) {
                Write-Debug "Found local function '$commandStr', ParameterSets=$($localFunc.ParameterSets.Count)"
                
                # Use localFunc directly if it has parameter sets, otherwise create temp function
                # InvokeCommand.GetCommand sometimes returns FunctionInfo with empty ParameterSets
                if ($localFunc.ParameterSets.Count -gt 0) {
                    $cmdInfo = $localFunc
                }
                else {
                    # Parameter sets are empty - create temp global function via Invoke-Expression
                    # so PowerShell properly parses the CmdletBinding/param block
                    $sb = $localFunc.ScriptBlock
                    if (!$sb -and $localFunc.Definition) {
                        $sb = [scriptblock]::Create($localFunc.Definition)
                    }
                    
                    if ($sb) {
                        $tempFuncName = "_UiDef_Temp_$([guid]::NewGuid().ToString('N').Substring(0,8))"
                        $funcDefText = "function global:$tempFuncName { $($sb.ToString()) }"
                        
                        try {
                            Invoke-Expression $funcDefText
                            $cmdInfo = Get-Command $tempFuncName -ErrorAction Stop
                            Write-Debug "Created temp function, ParameterSets=$($cmdInfo.ParameterSets.Count)"
                            $cmdInfo | Add-Member -NotePropertyName 'OriginalName' -NotePropertyValue $commandStr -Force
                        }
                        catch {
                            Write-Debug "Temp function creation failed: $_"
                            $cmdInfo = $localFunc
                        }
                        finally {
                            # Clean up temp function to avoid polluting global namespace
                            Remove-Item -Path "function:global:$tempFuncName" -ErrorAction SilentlyContinue
                        }
                    }
                    else {
                        $cmdInfo = Get-Command $commandStr -ErrorAction SilentlyContinue
                    }
                }
                
                $commandDefinition = if ($localFunc.Definition) { $localFunc.Definition } else { $localFunc.ScriptBlock.ToString() }
                $commandInvocation = $commandStr
            }
            else {
                $cmdInfo = Get-Command $commandStr -ErrorAction Stop
                if ($cmdInfo -is [System.Management.Automation.FunctionInfo]) {
                    $commandDefinition = $cmdInfo.Definition
                }
                $commandInvocation = $cmdInfo.Name
            }
        }
    }
    else {
        throw "Invalid -Command type. Expected string, CommandInfo, or script path. Got: $($Command.GetType().Name)"
    }

    if (!$cmdInfo) {
        throw "Command '$Command' not found."
    }

    # Display name for scripts shows filename, functions show name
    $commandDisplayName = if ($cmdInfo.PSObject.Properties['OriginalName']) {
        $cmdInfo.OriginalName
    }
    elseif ($isExternalScript) {
        [System.IO.Path]::GetFileNameWithoutExtension($cmdInfo.Path)
    }
    else {
        $cmdInfo.Name
    }

    # Common parameters to exclude by default
    $commonParams = @(
        'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
        'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable',
        'OutBuffer', 'PipelineVariable', 'WhatIf', 'Confirm', 'UseTransaction'
    )

    $excludeList = [System.Collections.Generic.List[string]]::new()
    if ($ExcludeParameters) {
        foreach ($param in $ExcludeParameters) { $excludeList.Add($param) }
    }
    
    if (!$IncludeCommonParameters) {
        foreach ($param in $commonParams) { $excludeList.Add($param) }
    }

    # Detect available parameter sets
    $allParams = $cmdInfo.Parameters
    $parameterSets = $cmdInfo.ParameterSets | Where-Object { $_.Name -ne '__AllParameterSets' } | ForEach-Object { $_.Name }
    $hasMultipleSets = $parameterSets.Count -gt 1
    $parameterSetName = if ($ParameterSet) { $ParameterSet } else { $cmdInfo.DefaultParameterSet }

    $paramSetDef = $null
    if ($parameterSetName) {
        $paramSetDef = $cmdInfo.ParameterSets | Where-Object { $_.Name -eq $parameterSetName }
    }

    # Extract default values from AST
    $astDefaults = @{}
    try {
        $scriptBlock = $cmdInfo.ScriptBlock
        if ($scriptBlock -and $scriptBlock.Ast.ParamBlock) {
            foreach ($astParam in $scriptBlock.Ast.ParamBlock.Parameters) {
                $pName = $astParam.Name.VariablePath.UserPath
                if ($astParam.DefaultValue) {
                    $defaultText = $astParam.DefaultValue.Extent.Text

                    $evaluatedValue = $null
                    try {
                        if ($defaultText -match '^\s*[\$\@]?\(|^\s*\{') {
                            $evaluatedValue = $defaultText
                        }
                        elseif ($defaultText -match '^\s*[''"].*[''"]$|^\s*\d+$|^\s*\$true$|^\s*\$false$') {
                            $evaluatedValue = [scriptblock]::Create($defaultText).Invoke()[0]
                        }
                        else {
                            $evaluatedValue = $defaultText
                        }
                    }
                    catch {
                        $evaluatedValue = $defaultText
                    }

                    $astDefaults[$pName] = $evaluatedValue
                }
            }
        }
    }
    catch {
        Write-Verbose "[Get-UiDefinition] Could not extract AST defaults: $_"
    }

    # Build parameter definitions
    $parameters = [System.Collections.Generic.List[object]]::new()
    foreach ($paramName in $allParams.Keys) {
        if ($excludeList -contains $paramName) { continue }

        $param = $allParams[$paramName]

        # Filter by parameter set
        if ($parameterSetName) {
            $inSet = $param.ParameterSets.ContainsKey($parameterSetName) -or
                     $param.ParameterSets.ContainsKey('__AllParameterSets')
            if (!$inSet) { continue }
        }

        # Check mandatory for this specific parameter set
        $isMandatoryInSet = $false
        if ($paramSetDef) {
            $paramInSet = $paramSetDef.Parameters | Where-Object { $_.Name -eq $paramName }
            if ($paramInSet) {
                $isMandatoryInSet = $paramInSet.IsMandatory
            }
        }
        else {
            # Fallback: check [Parameter(Mandatory)] attribute directly
            $mandatoryAttr = $param.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
            }
            if ($mandatoryAttr) {
                $isMandatoryInSet = $true
            }
        }

        # A switch is "set-defining" if its name matches the parameter set name
        $isSetDefiningSwitch = $false
        if ($param.ParameterType -eq [switch] -and $parameterSetName) {
            if ($paramName -eq $parameterSetName) {
                $hasMandatoryParams = $paramSetDef.Parameters | Where-Object { $_.IsMandatory } | Select-Object -First 1
                if (!$hasMandatoryParams) {
                    $isSetDefiningSwitch = $true
                }
            }
        }

        $defaultValue = $null
        if ($astDefaults -and $astDefaults.ContainsKey($paramName)) {
            $defaultValue = $astDefaults[$paramName]
        }

        # Determine control type based on parameter metadata
        $controlType = 'TextBox'  # Default
        $controlOptions = @{}

        $validateSet = ($param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues
        $validateRange = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] } | Select-Object -First 1

        if ($validateSet -and $validateSet.Count -gt 0) {
            $controlType = 'Dropdown'
            $controlOptions.Items = $validateSet
        }
        elseif ($param.ParameterType -eq [switch]) {
            $controlType = 'Toggle'
        }
        elseif ($param.ParameterType -eq [bool]) {
            $controlType = 'Toggle'
        }
        elseif ($param.ParameterType -eq [datetime]) {
            $controlType = 'DatePicker'
        }
        elseif ($param.ParameterType -eq [System.Security.SecureString]) {
            $controlType = 'Password'
        }
        elseif ($param.ParameterType -eq [System.Management.Automation.PSCredential]) {
            $controlType = 'Credential'
        }
        elseif ($param.ParameterType -eq [string[]] -or $param.ParameterType -eq [object[]]) {
            $controlType = 'TextArea'
        }
        elseif (($param.ParameterType -eq [int] -or $param.ParameterType -eq [double]) -and $validateRange) {
            $controlType = 'Slider'
            $controlOptions.Minimum = $validateRange.MinRange
            $controlOptions.Maximum = $validateRange.MaxRange
        }
        elseif ($param.ParameterType -eq [int] -or $param.ParameterType -eq [long]) {
            $controlType = 'NumberInput'
            $controlOptions.IsInteger = $true
        }
        elseif ($param.ParameterType -eq [double] -or $param.ParameterType -eq [float] -or $param.ParameterType -eq [decimal]) {
            $controlType = 'NumberInput'
            $controlOptions.IsInteger = $false
        }

        $parameters.Add([PSCustomObject]@{
            Name           = $paramName
            Type           = $param.ParameterType
            TypeName       = $param.ParameterType.Name
            ControlType    = $controlType
            ControlOptions = $controlOptions
            IsMandatory    = $isMandatoryInSet -or $isSetDefiningSwitch
            HelpMessage    = ($param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).HelpMessage | Select-Object -First 1
            ValidateSet    = $validateSet
            ValidateRange  = $validateRange
            DefaultValue   = $defaultValue
            Aliases        = $param.Aliases
            IsSwitch       = $param.ParameterType -eq [switch]
            Position       = ($param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Position | Where-Object { $_ -ge 0 } | Select-Object -First 1
        })
    }

    # Sort by mandatory first, then position, then alphabetical
    $parameters = $parameters | Sort-Object @{Expression={!$_.IsMandatory}},
                                            @{Expression={if ($null -eq $_.Position) { 999 } else { $_.Position }}},
                                            Name

    # Check for empty parameters - the command has nothing to configure
    if (!$parameters -or $parameters.Count -eq 0) {
        $cmdDesc = if ($isExternalScript) { "Script '$commandInvocation'" } else { "Command '$commandDisplayName'" }
        throw "$cmdDesc has no parameters. New-UiTool requires a command with configurable parameters to generate a UI."
    }

    # Get help information
    $helpTarget = if ($isExternalScript) { $commandInvocation } else { $commandDisplayName }
    $helpInfo = Get-Help $helpTarget -Full -ErrorAction SilentlyContinue
    $description = if ($helpInfo.Description) {
        $rawDesc = ($helpInfo.Description | ForEach-Object { $_.Text }) -join ' '
        
        # Collapse extra whitespace but preserve markdown for UI rendering
        $rawDesc = $rawDesc -replace '\s+', ' '
        $rawDesc.Trim()
    }
    else { $null }

    # Build parameter descriptions from help
    $paramDescriptions = @{}
    if ($helpInfo.parameters.parameter) {
        foreach ($hp in $helpInfo.parameters.parameter) {
            if ($hp.Description) {
                $descLines = $hp.Description | ForEach-Object { $_.Text } | Where-Object { $_ -notmatch '^\s*>' }
                $descText = ($descLines -join ' ').Trim()
                $descText = $descText -replace '\*\*([^*]+)\*\*', '$1'
                $descText = $descText -replace '\*([^*]+)\*', '$1'
                $descText = $descText -replace '`([^`]+)`', '$1'
                $descText = $descText -replace '\s+', ' '

                if (![string]::IsNullOrWhiteSpace($descText)) {
                    $paramDescriptions[$hp.Name] = $descText
                }
            }
        }
    }

    # Build input helpers configuration
    $inputHelpers = @{
        FilePicker     = [System.Collections.Generic.List[string]]::new()
        FolderPicker   = [System.Collections.Generic.List[string]]::new()
        ComputerPicker = [System.Collections.Generic.List[string]]::new()
        FilterBuilder  = @{}
    }
    if ($FilePickerParameters) { $inputHelpers.FilePicker.AddRange($FilePickerParameters) }
    if ($FolderPickerParameters) { $inputHelpers.FolderPicker.AddRange($FolderPickerParameters) }
    if ($ComputerPickerParameters) { $inputHelpers.ComputerPicker.AddRange($ComputerPickerParameters) }

    # Detect command type to determine filter mode
    $cmdName = $cmdInfo.Name
    $filterMode = 'Generic'
    if ($cmdName -match '^Get-AD|^Set-AD|^New-AD|^Remove-AD') {
        $filterMode = 'AD'
    }
    elseif ($cmdName -match '^Get-Wmi|^Get-Cim|^Invoke-Wmi|^Invoke-Cim') {
        $filterMode = 'WMI'
    }
    elseif ($cmdName -match '^Get-ChildItem$|^Get-Item$|^Copy-Item$|^Move-Item$|^Remove-Item$|^Rename-Item$') {
        $filterMode = 'File'
    }
    else {
        # For scripts/functions, detect file mode if both Path-like and Filter params exist
        $paramNames = $parameters | ForEach-Object { $_.Name }
        $hasPathParam   = $paramNames | Where-Object { $_ -match '^Path$|Directory|Folder' }
        $hasFilterParam = $paramNames | Where-Object { $_ -match '^Filter$' }
        if ($hasPathParam -and $hasFilterParam) {
            $filterMode = 'File'
        }
    }

    if (!$NoAutoHelpers) {
        foreach ($param in $parameters) {
            $pName = $param.Name

            if ($inputHelpers.FilePicker -contains $pName -or $inputHelpers.FolderPicker -contains $pName -or $inputHelpers.ComputerPicker -contains $pName) {
                continue
            }

            if ($param.Type -and $param.Type -ne [string] -and $param.Type -ne [string[]]) {
                continue
            }

            if ($pName -match 'Directory|Folder|FolderPath|DirectoryPath|^Path$|^LiteralPath$') {
                $inputHelpers.FolderPicker.Add($pName)
            }
            elseif ($pName -match 'File|FileName|FilePath') {
                $inputHelpers.FilePicker.Add($pName)
            }
            elseif ($pName -match '^Filter$|^Include$|^Exclude$') {
                $inputHelpers.FilterBuilder[$pName] = $filterMode
            }
            elseif ($pName -match 'ComputerName|Computer|Server|ServerName|HostName|Host|^CN$|MachineName|Machine') {
                $inputHelpers.ComputerPicker.Add($pName)
            }
        }
    }

    # Return the complete definition schema (no WPF objects!)
    [PSCustomObject]@{
        # Command metadata
        CommandInfo       = $cmdInfo
        CommandName       = $commandInvocation
        CommandDefinition = $commandDefinition
        DisplayName       = $commandDisplayName
        Description       = $description
        IsExternalScript  = $isExternalScript

        # Parameter set info
        ParameterSetName  = $parameterSetName
        ParameterSets     = $parameterSets
        HasMultipleSets   = $hasMultipleSets

        # Parameter definitions (the schema)
        Parameters        = $parameters
        ParamDescriptions = $paramDescriptions

        # Input helper configuration
        InputHelpers      = $inputHelpers
    }
}
