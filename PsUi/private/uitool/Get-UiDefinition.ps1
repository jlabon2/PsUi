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
        [string[]]$UserPickerParameters = @(),
        [string[]]$GroupPickerParameters = @(),
        [string[]]$MemberPickerParameters = @(),
        [string[]]$OUPickerParameters = @(),
        [switch]$NoAutoHelpers,

        # The calling script's SessionState, for looking up its local functions.
        [System.Management.Automation.SessionState]$CallerSessionState
    )

    # Collect all unique SessionStates from the call stack for function lookup
    # This handles nested scriptblocks (button actions, child windows, etc.)
    $callStackSessionStates = [System.Collections.Generic.List[System.Management.Automation.SessionState]]::new()
    if ($CallerSessionState) { $callStackSessionStates.Add($CallerSessionState) }

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
                if ($field) { $internal = $field.GetValue($sessionState) }

                if (!$internal) {
                    $prop = $sessionState.GetType().GetProperty(
                        'Internal',
                        [System.Reflection.BindingFlags]'Instance, NonPublic'
                    )
                    if ($prop) { $internal = $prop.GetValue($sessionState) }
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

    # Result structure, filled in from whatever is being parsed.
    $cmdInfo            = $null
    $commandDefinition  = $null
    $commandInvocation  = $null
    $isExternalScript   = $false
    $functionFile       = $null
    $fileHelp           = $null

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
        else { $commandInvocation = $cmdInfo.Name }
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
                # Resolve-Path failed, so try relative to the calling script.
                if ([System.IO.Path]::IsPathRooted($commandStr)) { $scriptPath = $commandStr }
                else {
                    $callerPath = (Get-PSCallStack)[2].ScriptName  # [2] = caller of New-UiTool
                    if ($callerPath) {
                        $callerDir = Split-Path $callerPath -Parent
                        $scriptPath = Join-Path $callerDir $commandStr
                    }
                    else { throw "Script not found: $commandStr" }
                }
            }

            if (!(Test-Path $scriptPath)) { throw "Script not found: $scriptPath" }

            # Parse AST to check for embedded function definitions
            $scriptContent = Get-Content $scriptPath -Raw -ErrorAction Stop
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$tokens, [ref]$parseErrors)

            # A script level param() block means a UI can be built for it.
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

                # function global:Get-Report keeps the scope in its Name, which Get-Command and the file name both lack
                $scopePrefix = '^(global|local|script|private):'

                if ($functionDefs.Count -eq 1) {
                    # Single function - use it
                    $targetFunc = $functionDefs[0]
                }
                else {
                    # Multiple functions - look for one matching the filename
                    $targetFunc = $functionDefs | Where-Object { ($_.Name -replace $scopePrefix) -eq $scriptBaseName } | Select-Object -First 1

                    if (!$targetFunc) {
                        $funcNames = ($functionDefs | ForEach-Object { $_.Name }) -join ', '
                        throw "Script '$scriptPath' contains multiple functions ($funcNames), and none is named after the file. Rename the file after the one to wrap, and the rest come along as its helpers."
                    }
                }
                $targetName = $targetFunc.Name -replace $scopePrefix

                # Run dot sources the whole file before each call so anything at the top level besides definitions would rerun on every click
                $looseCode = foreach ($block in @($ast.BeginBlock, $ast.ProcessBlock, $ast.EndBlock)) {
                    if (!$block) { continue }
                    foreach ($statement in $block.Statements) {
                        if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) { continue }
                        if ($statement -is [System.Management.Automation.Language.TypeDefinitionAst]) { continue }
                        $statement
                    }
                }
                if ($looseCode) {
                    $looseLine = @($looseCode)[0].Extent.StartLineNumber
                    throw "Script '$scriptPath' runs code outside its functions (line $looseLine), and New-UiTool dot sources the whole file on every Run to bring $targetName and its helpers along. Move that code out of the file, or give the script a param block so it runs as a script."
                }

                # Run and Help load the file elsewhere without this session's PSDrives
                $functionFile = Convert-Path -LiteralPath $scriptPath

                # Child scope, so the file's functions go once this returns
                $loaded = & {
                    param($path, $name)
                    . $path
                    @{
                        Command = Get-Command -Name $name -CommandType Function -ErrorAction Stop
                        Help    = Get-Help -Name $name -Full -ErrorAction SilentlyContinue
                    }
                } $functionFile $targetName

                $cmdInfo           = $loaded.Command
                $fileHelp          = $loaded.Help
                $commandDefinition = $cmdInfo.Definition
                $commandInvocation = $cmdInfo.Name
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
                if ($localFunc.ParameterSets.Count -gt 0) { $cmdInfo = $localFunc }
                else {
                    # Parameter sets are empty - create temp global function via Invoke-Expression so PS properly parses the CmdletBinding/param block
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

                        # 5.1 throws past a finally when a click opens the tool.
                        # Remove-Item quietly skips a function:global: path.
                        Remove-Item -Path "function:\$tempFuncName" -ErrorAction SilentlyContinue
                    }
                    else { $cmdInfo = Get-Command $commandStr -ErrorAction SilentlyContinue }
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

    if (!$cmdInfo) { throw "Command '$Command' not found." }

    # Display name for scripts shows filename, functions show name
    $commandDisplayName = if ($cmdInfo.PSObject.Properties['OriginalName']) {
        $cmdInfo.OriginalName
    }
    elseif ($isExternalScript) { [System.IO.Path]::GetFileNameWithoutExtension($cmdInfo.Path) }
    else { $cmdInfo.Name }

    # Cmdlet's own lists so ProgressAction comes along on 7.4 and up
    $commonParams = @([System.Management.Automation.Cmdlet]::CommonParameters) + @([System.Management.Automation.Cmdlet]::OptionalCommonParameters)

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
    # Use explicit set, then default, then first available (some cmdlets have no default)
    $parameterSetName = if ($ParameterSet) { $ParameterSet }
                        elseif ($cmdInfo.DefaultParameterSet) { $cmdInfo.DefaultParameterSet }
                        elseif ($parameterSets.Count -gt 0) { $parameterSets[0] }
                        else { $null }

    $paramSetDef = $null
    if ($parameterSetName) {
        $paramSetDef = $cmdInfo.ParameterSets | Where-Object { $_.Name -eq $parameterSetName }
    }

    $astDefaults = @{}
    try {
        $defAst = if ($cmdInfo.ScriptBlock) { $cmdInfo.ScriptBlock.Ast } else { $null }

        # A function's param block sits down in Body
        $astParams = if ($defAst -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            if ($defAst.Body.ParamBlock) { $defAst.Body.ParamBlock.Parameters } else { $defAst.Parameters }
        }
        elseif ($defAst -and $defAst.ParamBlock) { $defAst.ParamBlock.Parameters }

        foreach ($astParam in $astParams) {
            if (!$astParam.DefaultValue) { continue }

            $pName = $astParam.Name.VariablePath.UserPath
            try { $astDefaults[$pName] = Get-UiParameterDefault -Ast $astParam.DefaultValue }
            catch {
                Write-Debug "Leaving -$pName empty, its default needs code to run: $($astParam.DefaultValue.Extent.Text)"

                # Keeping the key lets HasDefault leave a date picker blank instead of setting it to today
                $astDefaults[$pName] = $null
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
            if ($paramInSet) { $isMandatoryInSet = $paramInSet.IsMandatory }
        }
        else {
            # Fall back to reading the [Parameter(Mandatory)] attribute directly
            $mandatoryAttr = $param.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
            }
            if ($mandatoryAttr) { $isMandatoryInSet = $true }
        }

        # A switch is "set-defining" if its name matches the parameter set name
        $isSetDefiningSwitch = $false
        if ($param.ParameterType -eq [switch] -and $parameterSetName) {
            if ($paramName -eq $parameterSetName) {
                $hasMandatoryParams = $paramSetDef.Parameters | Where-Object { $_.IsMandatory } | Select-Object -First 1
                if (!$hasMandatoryParams) { $isSetDefiningSwitch = $true }
            }
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
        # Ahead of the number arms in the switch, since a ranged int or double wants a slider rather than a box.
        elseif (($param.ParameterType -eq [int] -or $param.ParameterType -eq [double]) -and $validateRange) {
            $controlType = 'Slider'
            $controlOptions.Minimum = $validateRange.MinRange
            $controlOptions.Maximum = $validateRange.MaxRange
        }
        else {
            # Every label is a distinct type, so no value reaches two clauses and none of them needs a break.
            switch ($param.ParameterType) {
                ([switch])   { $controlType = 'Toggle' }
                ([bool])     { $controlType = 'Toggle' }
                ([datetime]) { $controlType = 'DatePicker' }
                ([System.Security.SecureString])              { $controlType = 'Password' }
                ([System.Management.Automation.PSCredential]) { $controlType = 'Credential' }
                ([string[]]) { $controlType = 'TextArea' }
                ([object[]]) { $controlType = 'TextArea' }
                ([int])      { $controlType = 'NumberInput'; $controlOptions.IsInteger = $true }
                ([long])     { $controlType = 'NumberInput'; $controlOptions.IsInteger = $true }
                ([double])   { $controlType = 'NumberInput'; $controlOptions.IsInteger = $false }
                ([float])    { $controlType = 'NumberInput'; $controlOptions.IsInteger = $false }
                ([decimal])  { $controlType = 'NumberInput'; $controlOptions.IsInteger = $false }
            }
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
            DefaultValue   = $astDefaults[$paramName]
            HasDefault     = $astDefaults.ContainsKey($paramName)
            Aliases        = $param.Aliases
            IsSwitch       = $param.ParameterType -eq [switch]
            Position       = ($param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Position | Where-Object { $_ -ge 0 } | Select-Object -First 1
        })
    }

    # Sort by mandatory first, then position, then alphabetical
    $parameters = $parameters | Sort-Object @{Expression={!$_.IsMandatory}},
                                            @{Expression={if ($null -eq $_.Position) { 999 } else { $_.Position }}},
                                            Name

    # Check for empty parameters, where the command has no knobs to configure.
    if (!$parameters -or $parameters.Count -eq 0) {
        $cmdDesc = if ($isExternalScript) { "Script '$commandInvocation'" } else { "Command '$commandDisplayName'" }
        throw "$cmdDesc has no parameters. New-UiTool requires a command with configurable parameters to generate a UI."
    }

    # Get help information
    $helpTarget = if ($isExternalScript) { $commandInvocation } else { $commandDisplayName }
    $helpInfo   = if ($fileHelp) { $fileHelp } else { Get-Help $helpTarget -Full -ErrorAction SilentlyContinue }

    # ConvertTo-FormattedTextBlock renders the emphasis and code ticks on the About card
    $description = if ($helpInfo.Description) {
        ConvertFrom-UiHelpMarkdown -Text @($helpInfo.Description | ForEach-Object { $_.Text })
    }
    else {
        # Fall back to the synopsis, or a command carrying only a .SYNOPSIS opens with an empty About card.
        # Get-Help makes one up for a command without help, and what it makes up is the syntax line, so that structure gets ignored
        $synopsis = ("$($helpInfo.Synopsis)" -replace '\s+', ' ').Trim()
        $ownName  = [regex]::Escape("$($helpInfo.Name)")
        if ($synopsis -and $synopsis -notmatch "^$ownName(\s+[\[-]|$)") { $synopsis } else { $null }
    }

    # Build parameter descriptions from help
    $paramDescriptions = @{}
    if ($helpInfo.parameters.parameter) {
        foreach ($hp in $helpInfo.parameters.parameter) {
            if ($hp.Description) {
                $descText = ConvertFrom-UiHelpMarkdown -Text @($hp.Description | ForEach-Object { $_.Text }) -Inline
                if (![string]::IsNullOrWhiteSpace($descText)) {
                    $paramDescriptions[$hp.Name] = $descText
                }
            }
        }
    }

    # Grab online help URI from the command (available even without Update-Help)
    $helpUri = if ($cmdInfo.HelpUri) { $cmdInfo.HelpUri } else { $null }

    # Build input helpers configuration
    $inputHelpers = @{
        FilePicker     = [System.Collections.Generic.List[string]]::new()
        FolderPicker   = [System.Collections.Generic.List[string]]::new()
        ComputerPicker = [System.Collections.Generic.List[string]]::new()
        UserPicker     = [System.Collections.Generic.List[string]]::new()
        GroupPicker    = [System.Collections.Generic.List[string]]::new()
        MemberPicker   = [System.Collections.Generic.List[string]]::new()
        OUPicker       = [System.Collections.Generic.List[string]]::new()
        FilterBuilder  = @{}
    }
    if ($FilePickerParameters) { $inputHelpers.FilePicker.AddRange($FilePickerParameters) }
    if ($FolderPickerParameters) { $inputHelpers.FolderPicker.AddRange($FolderPickerParameters) }
    if ($ComputerPickerParameters) { $inputHelpers.ComputerPicker.AddRange($ComputerPickerParameters) }
    if ($UserPickerParameters) { $inputHelpers.UserPicker.AddRange($UserPickerParameters) }
    if ($GroupPickerParameters) { $inputHelpers.GroupPicker.AddRange($GroupPickerParameters) }
    if ($MemberPickerParameters) { $inputHelpers.MemberPicker.AddRange($MemberPickerParameters) }
    if ($OUPickerParameters) { $inputHelpers.OUPicker.AddRange($OUPickerParameters) }

    # Detect command type to determine filter mode
    $cmdName = $cmdInfo.Name
    $filterMode = 'Generic'
    # switch runs every clause that matches, so each one breaks to keep the first match winning.
    switch -Regex ($cmdName) {
        '^Get-AD|^Set-AD|^New-AD|^Remove-AD'        { $filterMode = 'AD'; break }
        '^Get-Wmi|^Get-Cim|^Invoke-Wmi|^Invoke-Cim' { $filterMode = 'WMI'; break }
        '^Get-ChildItem$|^Get-Item$|^Copy-Item$|^Move-Item$|^Remove-Item$|^Rename-Item$' { $filterMode = 'File'; break }
        default {
            # Scripts and functions count as file mode when they take a path and a filter both.
            $paramNames = $parameters | ForEach-Object { $_.Name }
            $hasPathParam   = $paramNames | Where-Object { $_ -match '^Path$|Directory|Folder' }
            $hasFilterParam = $paramNames | Where-Object { $_ -match '^Filter$' }
            if ($hasPathParam -and $hasFilterParam) { $filterMode = 'File' }
        }
    }

    if (!$NoAutoHelpers) {
        foreach ($param in $parameters) {
            $pName = $param.Name

            if ($inputHelpers.FilePicker -contains $pName -or $inputHelpers.FolderPicker -contains $pName -or $inputHelpers.ComputerPicker -contains $pName -or $inputHelpers.UserPicker -contains $pName -or $inputHelpers.GroupPicker -contains $pName -or $inputHelpers.MemberPicker -contains $pName -or $inputHelpers.OUPicker -contains $pName) {
                continue
            }

            # FileServer hits the File pattern and the Server pattern both, so the breaks matter more here.
            switch -Regex ($pName) {
                'Directory|Folder|FolderPath|DirectoryPath|^Path$|^LiteralPath$'                  { $inputHelpers.FolderPicker.Add($pName); break }
                'File|FileName|FilePath'                                                          { $inputHelpers.FilePicker.Add($pName); break }
                '^Filter$|^Include$|^Exclude$'                                                    { $inputHelpers.FilterBuilder[$pName] = $filterMode; break }
                '^OU$|^SearchBase$|^BaseDN$|^SearchRoot$|^TargetOU$|OrganizationalUnit'           { $inputHelpers.OUPicker.Add($pName); break }
                '^Owner$|^Manager$|^User$|^UserName$|^SamAccountName$|^UserPrincipalName$|^UPN$'  { $inputHelpers.UserPicker.Add($pName); break }
                '^Group$|^GroupName$|^MemberOf$|^GroupDN$'                                        { $inputHelpers.GroupPicker.Add($pName); break }
                '^Member$|^Members$'                                                              { $inputHelpers.MemberPicker.Add($pName); break }
                'ComputerName|Computer|Server|ServerName|HostName|Host|^CN$|MachineName|Machine'  { $inputHelpers.ComputerPicker.Add($pName); break }
            }
        }
    }

    # Return the complete definition schema (no WPF objects!)
    [PSCustomObject]@{
        # Command metadata
        CommandInfo       = $cmdInfo
        CommandName       = $commandInvocation
        CommandDefinition = $commandDefinition
        FunctionFile      = $functionFile
        DisplayName       = $commandDisplayName
        Description       = $description
        HelpUri           = $helpUri
        IsExternalScript  = $isExternalScript

        # Parameter set info
        ParameterSetName  = $parameterSetName
        ParameterSets     = $parameterSets
        HasMultipleSets   = $hasMultipleSets

        # Parameter definitions (the schema)
        Parameters        = $parameters
        ParamDescriptions = $paramDescriptions
        ParameterDefaults = $astDefaults
        IncludeCommon     = [bool]$IncludeCommonParameters

        # Input helper configuration
        InputHelpers      = $inputHelpers
    }
}
