function New-UiTool {
    <#
    .SYNOPSIS
        Builds a form from a command's parameter metadata.
    .DESCRIPTION
        New-UiTool reads a command's parameter metadata and builds a form with a matching
        control per parameter:

        - [ValidateSet] becomes a dropdown
        - [switch] and [bool] become toggles
        - [int]/[double] become number inputs, or a slider when ValidateRange spans 10 steps or fewer
        - [string] becomes a text input, [string[]] a multi-line text area
        - [datetime] becomes a date picker
        - [SecureString] becomes a password input, [PSCredential] a username and password pair
        - Mandatory parameters gate the run button
        - .PARAMETER help text becomes the caption under each control

        Execution runs on a background thread, so the window stays alive during long commands.
        Results land in a sortable output grid.

        All of this reads static parameter metadata. Dynamic parameters and validation that
        depends on live state don't survive inspection; build those forms by hand with the
        regular controls. For everything else, "time to GUI" for a script is one line.
    .PARAMETER Command
        The command to wrap: a cmdlet, function, alias, script path, or a CommandInfo object.
    .PARAMETER Title
        Window title. Defaults to the command name.
    .PARAMETER Width
        Window width in pixels. Standalone windows default to 600. Inside a host window
        the child opens at 800 unless you pass one.
    .PARAMETER Height
        Window height in pixels. Only applied when you pass it. Inside a host window the
        child otherwise opens at 600, standalone the window sizes itself.
    .PARAMETER ParameterSet
        If the command has multiple parameter sets, specify which one to use.
        If not specified, uses the default parameter set or shows a selector.
    .PARAMETER Theme
        UI theme (Light, Dark, etc.)
    .PARAMETER ExcludeParameters
        Array of parameter names to exclude from the UI.
    .PARAMETER IncludeCommonParameters
        Include common parameters like -Verbose, -Debug, etc. Default is false.
    .PARAMETER ResultActions
        Actions offered against selected rows in the results grid. Pass a
        { New-UiResultAction ... } definition block, an array of New-UiResultAction output,
        or the legacy hashtable array (Text + Action required; optional: Icon, Confirm, ObjectType
        optional). The scriptblock receives $_ as the selected row(s).
    .PARAMETER SingleSelect
        When used with ResultActions, limits selection to a single row.
    .PARAMETER HideThemeButton
        Removes the theme switcher from the titlebar.
    .PARAMETER ShowParamType
        Displays the parameter type next to each input label.
    .PARAMETER FilePickerParameters
        Parameter names that should get a file browse button.
    .PARAMETER FolderPickerParameters
        Parameter names that should get a folder browse button.
    .PARAMETER ComputerPickerParameters
        Parameter names that should get an AD computer picker button.
    .PARAMETER UserPickerParameters
        Parameter names that should get an AD user picker button.
    .PARAMETER GroupPickerParameters
        Parameter names that should get an AD group picker button.
    .PARAMETER MemberPickerParameters
        Parameter names that should get an AD user/group picker button.
    .PARAMETER OUPickerParameters
        Parameter names that should get an AD OU picker button.
    .PARAMETER NoAutoHelpers
        Disables automatic helper button detection for common parameter names
        like Path or ComputerName.
    .PARAMETER LayoutStyle
        Control arrangement: Stack (vertical) or Wrap (multi-column).
    .PARAMETER MaxColumns
        Maximum columns when using Wrap layout. 0 means auto-detect based on window width.
    .EXAMPLE
        New-UiTool -Command 'Get-Process'

        Creates a GUI for Get-Process with inputs for Name, Id, etc.
    .EXAMPLE
        New-UiTool -Command 'Get-ChildItem' -Title "File Browser" -ExcludeParameters 'LiteralPath'

        Creates a file browser tool, excluding the LiteralPath parameter.
    .EXAMPLE
        New-UiTool -Command 'Stop-Service' -ParameterSet 'InputObject'

        Creates a service stopper using a specific parameter set.
    .EXAMPLE
        New-UiTool -Command 'Get-Process' -ResultActions {
            New-UiResultAction 'Stop' -Icon Stop -Confirm 'Stop {0} processes?' -Action { $_ | Stop-Process -Force }
        }

        Creates a process viewer with a Stop action that kills selected processes after a
        confirm. The legacy hashtable form still works:
        -ResultActions @( @{ Text = 'Stop'; Icon = 'Stop'; Action = { $_ | Stop-Process -Force } } )
    .EXAMPLE
        # Local function - no need to register globally
        function My-CustomTool { param([string]$Name) Write-Host "Hello $Name" }
        New-UiTool -Command 'My-CustomTool'

        Creates a GUI for a function defined in your script (detected from the calling scope).
    .EXAMPLE
        New-UiTool -Command '.\MyScript.ps1'

        Creates a GUI for a parameterized script file.
    #>
    [CmdletBinding()]
    param(
        # Command can be: cmdlet name, function name, script path, or CommandInfo object
        [Parameter(Mandatory, Position = 0)]
        [object]$Command,

        [string]$Title,

        [int]$Width = 600,

        [int]$Height = 500,

        [string]$ParameterSet,

        [ArgumentCompleter({ [PsUi.ThemeEngine]::GetAvailableThemes() })]
        [string]$Theme,

        [string[]]$ExcludeParameters = @(),

        [switch]$IncludeCommonParameters,

        [switch]$HideThemeButton,

        [switch]$ShowParamType,

        # Untyped: takes a New-UiResultAction definition block, an array of definitions, or the legacy hashtable array
        [object]$ResultActions,

        [switch]$SingleSelect,

        # Input helper parameters - add browse buttons next to TextBox inputs
        [string[]]$FilePickerParameters = @(),

        [string[]]$FolderPickerParameters = @(),

        [string[]]$ComputerPickerParameters = @(),

        [string[]]$UserPickerParameters = @(),

        [string[]]$GroupPickerParameters = @(),

        [string[]]$MemberPickerParameters = @(),

        [string[]]$OUPickerParameters = @(),

        [switch]$NoAutoHelpers,

        # Layout options for parameter panel
        [ValidateSet('Stack', 'Wrap')]
        [string]$LayoutStyle = 'Stack',

        [ValidateScript({ $_ -eq 0 -or ($_ -ge 1 -and $_ -le 4) })]
        [int]$MaxColumns = 0
    )

    Write-Debug "Starting for command '$Command', Width=$Width, Height=$Height"

    # Normalized now, not when the deferred content block runs mid window build. The user's definition block should execute at call time and errors should name this function.
    if ($null -ne $ResultActions) {
        $ResultActions = [hashtable[]](ConvertTo-UiDefinitionArray -InputObject $ResultActions -ParameterName '-ResultActions' -CallerName 'New-UiTool')
    }

    # Get caller's SessionState for local function lookup
    $callerSessionState = $null
    try {
        $callerScope = (Get-PSCallStack)[1]
        if ($callerScope -and $callerScope.InvocationInfo.MyCommand.ScriptBlock) {
            $flags = [System.Reflection.BindingFlags]'Instance, NonPublic, Public'
            $prop = [System.Management.Automation.ScriptBlock].GetProperty('SessionState', $flags)
            if ($prop) {
                $callerSessionState = $prop.GetValue($callerScope.InvocationInfo.MyCommand.ScriptBlock)
            }
        }
    }
    catch {
        Write-Verbose "[New-UiTool] Could not extract caller SessionState: $_"
    }

    Write-Debug "Introspecting command metadata"
    $defParams = @{
        Command                  = $Command
        ParameterSet             = $ParameterSet
        ExcludeParameters        = $ExcludeParameters
        IncludeCommonParameters  = $IncludeCommonParameters
        FilePickerParameters     = $FilePickerParameters
        FolderPickerParameters   = $FolderPickerParameters
        ComputerPickerParameters = $ComputerPickerParameters
        UserPickerParameters     = $UserPickerParameters
        GroupPickerParameters    = $GroupPickerParameters
        MemberPickerParameters   = $MemberPickerParameters
        OUPickerParameters       = $OUPickerParameters
        NoAutoHelpers            = $NoAutoHelpers
        CallerSessionState       = $callerSessionState
    }
    $uiDef = Get-UiDefinition @defParams
    Write-Debug "Got definition: $($uiDef.Parameters.Count) parameters, sets: $($uiDef.ParameterSets -join ', ')"

    # Store the definition in session context for stateless button access
    # This lets button handlers read command info without closures
    try {
        $existingSession = [PsUi.SessionManager]::Current
        if ($existingSession) {
            $existingSession.CurrentDefinition = $uiDef
        }
    }
    catch {
        Write-Verbose "[New-UiTool] Could not store definition in SessionContext: $_"
    }

    Write-Debug "Introspection complete: $($uiDef.Parameters.Count) parameter(s) detected"

    $cmdInfo               = $uiDef.CommandInfo
    $commandInvocation     = $uiDef.CommandName
    $commandDefinition     = $uiDef.CommandDefinition
    $commandDisplayName    = $uiDef.DisplayName
    $description           = $uiDef.Description
    $isExternalScript      = $uiDef.IsExternalScript
    $parameterSetName      = $uiDef.ParameterSetName
    $parameterSets         = $uiDef.ParameterSets
    $hasMultipleSets       = $uiDef.HasMultipleSets
    $targetParams          = $uiDef.Parameters
    $paramDescriptions     = $uiDef.ParamDescriptions
    $inputHelpers          = $uiDef.InputHelpers

    if (!$Title) {
        $Title = $commandDisplayName
    }

    Write-Debug "Rendering UI for '$commandDisplayName'"

    # Three display modes - embed inline while the host is still being built, spawn a child
    # window from a click handler, or stand up a top-level window if no host exists.
    # Window.IsLoaded gates the first two: false during build, true after Show().
    # Get-UiSession not [SessionManager]::Current - the pool can switch threads and
    # Current is ThreadStatic; Get-UiSession falls back to a per-runspace global.
    $existingSession = try { Get-UiSession } catch { $null }
    $hasWindow       = $existingSession -and $existingSession.Window
    $hostIsLoaded    = $false
    if ($hasWindow) {
        try { $hostIsLoaded = [bool]$existingSession.Window.IsLoaded } catch { $hostIsLoaded = $false }
    }
    $isEmbedded    = $hasWindow -and !$hostIsLoaded
    $isChildWindow = $hasWindow -and $hostIsLoaded
    Write-Debug "Tool dispatch: embedded=$isEmbedded, childWindow=$isChildWindow, hostIsLoaded=$hostIsLoaded"

    # Copy variables to avoid GetNewClosure issues with ValidateSet attributes
    $capturedTheme           = if ($Theme) { $Theme } else { 'Light' }
    $capturedTitle           = $Title
    $capturedWidth           = $Width
    $capturedHeight          = $Height
    $capturedWidthExplicit   = $PSBoundParameters.ContainsKey('Width')
    $capturedHeightExplicit  = $PSBoundParameters.ContainsKey('Height')
    $capturedHideThemeButton = $HideThemeButton

    $capturedCommandInvocation  = $commandInvocation
    $capturedCommandDefinition  = $commandDefinition
    $capturedIsExternalScript   = $isExternalScript
    $capturedCommandDisplayName = $commandDisplayName
    $capturedShowParamType      = $ShowParamType

    $inputHelpers = @{
        FilePicker      = [System.Collections.Generic.List[string]]::new()
        FolderPicker    = [System.Collections.Generic.List[string]]::new()
        ComputerPicker  = [System.Collections.Generic.List[string]]::new()
        UserPicker      = [System.Collections.Generic.List[string]]::new()
        GroupPicker     = [System.Collections.Generic.List[string]]::new()
        MemberPicker    = [System.Collections.Generic.List[string]]::new()
        OUPicker        = [System.Collections.Generic.List[string]]::new()
        FilterBuilder   = @{}  # Hashtable: ParamName -> FilterMode
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
        $paramNames = $targetParams | ForEach-Object { $_.Name }
        $hasPathParam   = $paramNames | Where-Object { $_ -match '^Path$|Directory|Folder' }
        $hasFilterParam = $paramNames | Where-Object { $_ -match '^Filter$' }
        if ($hasPathParam -and $hasFilterParam) {
            $filterMode = 'File'
        }
    }

    if (!$NoAutoHelpers) {
        foreach ($param in $targetParams) {
            $pName = $param.Name

            # Skip if already manually specified
            if ($inputHelpers.FilePicker -contains $pName -or $inputHelpers.FolderPicker -contains $pName -or $inputHelpers.ComputerPicker -contains $pName -or $inputHelpers.UserPicker -contains $pName -or $inputHelpers.GroupPicker -contains $pName -or $inputHelpers.MemberPicker -contains $pName -or $inputHelpers.OUPicker -contains $pName) {
                continue
            }

            # Auto-detect folder parameters (explicit folder names OR generic path params)
            if ($pName -match 'Directory|Folder|FolderPath|DirectoryPath|^Path$|^LiteralPath$') {
                $inputHelpers.FolderPicker.Add($pName)
            }
            # Auto-detect file parameters (only when 'File' is explicitly in the name)
            elseif ($pName -match 'File|FileName|FilePath') {
                $inputHelpers.FilePicker.Add($pName)
            }
            # Auto-detect filter parameters, apply detected mode
            elseif ($pName -match '^Filter$|^Include$|^Exclude$') {
                $inputHelpers.FilterBuilder[$pName] = $filterMode
            }
            # Auto-detect OU parameters
            elseif ($pName -match '^OU$|^SearchBase$|^BaseDN$|^SearchRoot$|^TargetOU$|OrganizationalUnit') {
                $inputHelpers.OUPicker.Add($pName)
            }
            # Auto-detect user parameters
            elseif ($pName -match '^Owner$|^Manager$|^User$|^UserName$|^SamAccountName$|^UserPrincipalName$|^UPN$') {
                $inputHelpers.UserPicker.Add($pName)
            }
            # Auto-detect group parameters
            elseif ($pName -match '^Group$|^GroupName$|^MemberOf$|^GroupDN$') {
                $inputHelpers.GroupPicker.Add($pName)
            }
            # Auto-detect member parameters (users or groups)
            elseif ($pName -match '^Member$|^Members$') {
                $inputHelpers.MemberPicker.Add($pName)
            }
            # Auto-detect computer name parameters
            elseif ($pName -match 'ComputerName|Computer|Server|ServerName|HostName|Host|^CN$|MachineName|Machine') {
                $inputHelpers.ComputerPicker.Add($pName)
            }
        }
    }
    $capturedInputHelpers = $inputHelpers
    $capturedLayoutStyle  = $LayoutStyle
    $capturedMaxColumns   = $MaxColumns
    $capturedCommand      = $Command
    $capturedExcludes     = $ExcludeParameters

    # Nullify the validated parameter to prevent GetNewClosure from failing
    Remove-Variable -Name Theme -Scope Local -ErrorAction SilentlyContinue

    $toolContent = {

        # Header with command description in a full-width card
        if ($description -and $description -ne $commandDisplayName) {
            # Capture description locally for the nested scriptblock (PS 5.1 closure workaround)
            $aboutText = $description
            New-UiCard -Header "About" -FullWidth -Content {
                $colors = Get-ThemeColors
                $formattedText = ConvertTo-FormattedTextBlock -Text $aboutText -FontSize 12 -Foreground $colors.SecondaryText
                
                # Add to current parent
                $session = Get-UiSession
                $parent = $session.CurrentParent
                if ($parent -is [System.Windows.Controls.Panel]) {
                    [void]$parent.Children.Add($formattedText)
                }
                elseif ($parent -is [System.Windows.Controls.ContentControl]) {
                    $parent.Content = $formattedText
                }
            }
        }

        $session = Get-UiSession
        $colors = Get-ThemeColors

        $paramsGroupBox = [System.Windows.Controls.GroupBox]::new()
        $paramsGroupBox.Margin = [System.Windows.Thickness]::new(0,0,0,8)

        if ($hasMultipleSets) {
            $setItems = @($parameterSets)
            $defaultSet = if ($parameterSetName) { $parameterSetName } else { $setItems[0] }

            # Re-capture values for the nested OnChange closure (PS 5.1 closure workaround)
            $capturedHelpers       = $capturedInputHelpers
            $capturedCmdInfoForOnChange = $cmdInfo
            $capturedCmdForOnChange = $capturedCommand
            $capturedExcludesForOnChange = $capturedExcludes
            $capturedShowParamTypeForOnChange = $capturedShowParamType
            $capturedDescriptionsForOnChange = $paramDescriptions

            $headerGrid = [System.Windows.Controls.Grid]::new()
            $col1 = [System.Windows.Controls.ColumnDefinition]::new()
            $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $col2 = [System.Windows.Controls.ColumnDefinition]::new()
            $col2.Width = [System.Windows.GridLength]::Auto
            [void]$headerGrid.ColumnDefinitions.Add($col1)
            [void]$headerGrid.ColumnDefinitions.Add($col2)

            $headerText = [System.Windows.Controls.TextBlock]::new()
            $headerText.Text = "Parameters"
            $headerText.VerticalAlignment = 'Center'
            $headerText.FontWeight = 'SemiBold'
            [System.Windows.Controls.Grid]::SetColumn($headerText, 0)
            [void]$headerGrid.Children.Add($headerText)

            $comboResult = New-UiDropdownButton -Items $setItems -Default $defaultSet -Variable 'selectedParameterSet' -Icon 'Filter' -Tooltip "Parameter Set: $defaultSet" -ShowText -NoAutoAdd -OnChange {
                param($newSet)

                $sess = Get-UiSession

                # Skip if selecting the same set that's already active
                $lastSet = $sess.GetControl('_uiTool_lastParamSet')
                if ($lastSet -and $lastSet.Tag -eq $newSet) {
                    return
                }

                $paramsPanel = $sess.GetControl('_uiTool_paramsContent')
                if (!$paramsPanel) { return }

                # Guard against null command info (PS 5.1 closure issue)
                if (!$capturedCmdInfoForOnChange) {
                    Write-Warning "Parameter set switch failed: command info not captured"
                    return
                }

                # Use captured CommandInfo directly (don't re-fetch - extracted functions may be gone)
                $cmdInfo = $capturedCmdInfoForOnChange
                $commonParams = @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable','WhatIf','Confirm','UseTransaction')
                $excludeList = @($capturedExcludesForOnChange) + $commonParams

                # Get the parameter set definition to check mandatory correctly
                $paramSetDef = $cmdInfo.ParameterSets | Where-Object { $_.Name -eq $newSet }

                # Suppress DynamicParam errors when iterating parameters (extracted functions lack module context)
                $oldErrorAction = $ErrorActionPreference
                $ErrorActionPreference = 'SilentlyContinue'

                $newParams = [System.Collections.Generic.List[object]]::new()
                foreach ($paramName in $cmdInfo.Parameters.Keys) {
                    if ($excludeList -contains $paramName) { continue }
                    $param = $cmdInfo.Parameters[$paramName]
                    $inSet = $param.ParameterSets.ContainsKey($newSet) -or $param.ParameterSets.ContainsKey('__AllParameterSets')
                    if (!$inSet) { continue }

                    # Check mandatory for THIS specific parameter set
                    $isMandatoryInSet = $false
                    if ($paramSetDef) {
                        $paramInSet = $paramSetDef.Parameters | Where-Object { $_.Name -eq $paramName }
                        if ($paramInSet) {
                            $isMandatoryInSet = $paramInSet.IsMandatory
                        }
                    }

                    # A switch is "set-defining" if its name matches the parameter set name
                    # AND the set has no other mandatory parameters
                    $isSetDefiningSwitch = $false
                    if ($param.ParameterType -eq [switch]) {
                        if ($paramName -eq $newSet) {
                            $hasMandatoryParams = $paramSetDef.Parameters | Where-Object { $_.IsMandatory } | Select-Object -First 1
                            if (!$hasMandatoryParams) {
                                $isSetDefiningSwitch = $true
                            }
                        }
                    }

                    $newParams.Add([PSCustomObject]@{
                        Name        = $paramName
                        Type        = $param.ParameterType
                        IsMandatory = $isMandatoryInSet -or $isSetDefiningSwitch
                        ValidateSet = ($param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues
                        ValidateRange = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] } | Select-Object -First 1
                        DefaultValue = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.PSDefaultValueAttribute] } | Select-Object -First 1
                        IsSwitch    = $param.ParameterType -eq [switch]
                        Position    = ($param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Position | Where-Object { $_ -ge 0 } | Select-Object -First 1
                    })
                }

                # Restore error action
                $ErrorActionPreference = $oldErrorAction

                # Sort by mandatory first, then position, then alphabetical (matches initial load)
                $newParams = $newParams | Sort-Object @{Expression={!$_.IsMandatory}},
                                                      @{Expression={if ($null -eq $_.Position) { 999 } else { $_.Position }}},
                                                      Name

                # Track the current set
                $tracker = $sess.GetControl('_uiTool_lastParamSet')
                if ($tracker) { $tracker.Tag = $newSet }

                # Use cached descriptions (already loaded at startup - no need to re-parse help)
                $descriptions = $capturedDescriptionsForOnChange

                # Determine if we're in wrap mode by checking panel type
                $isWrapMode = $paramsPanel -is [System.Windows.Controls.WrapPanel]

                # Clear and rebuild with correct layout mode
                $paramsPanel.Children.Clear()
                Initialize-UiToolParameters -TargetPanel $paramsPanel -Parameters $newParams -Descriptions $descriptions -ShowParamType:$capturedShowParamTypeForOnChange -InputHelpers $capturedHelpers -UseWrapLayout:$isWrapMode

                # Manually apply column widths since SizeChanged won't fire (panel size didn't change)
                if ($isWrapMode -and $paramsPanel.Tag -is [hashtable] -and $paramsPanel.Tag.MaxColumns -gt 0) {
                    $maxCols = $paramsPanel.Tag.MaxColumns

                    $paddingBuffer = 16
                    $availableWidth = $paramsPanel.ActualWidth - $paddingBuffer
                    if ($availableWidth -gt 0) {
                        $minColumnWidth = 150
                        $possibleCols = [Math]::Max(1, [Math]::Floor($availableWidth / $minColumnWidth))
                        $actualCols = [Math]::Min($possibleCols, $maxCols)
                        $actualCols = [Math]::Max($actualCols, 1)
                        $childWidth = [Math]::Floor(($availableWidth / $actualCols) - 8)

                        foreach ($child in $paramsPanel.Children) {
                            if ($child -is [System.Windows.FrameworkElement]) {
                                if ($child.Tag -eq 'FullWidth') { continue }
                                $child.Width = $childWidth
                            }
                        }
                    }
                }

                # Update stored param info and validate Run button state
                $sess.Variables['_uiTool_paramInfo'] = $newParams
                Update-UiToolRunButtonState

                Write-Debug "Switched to parameter set: $newSet"
            }.GetNewClosure()

            $comboContainer = $comboResult.Container
            $comboContainer.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
            [System.Windows.Controls.Grid]::SetColumn($comboContainer, 1)
            [void]$headerGrid.Children.Add($comboContainer)

            $paramsGroupBox.Header = $headerGrid
        }
        else {
            $paramsGroupBox.Header = "Parameters"
        }

        Set-GroupBoxStyle -GroupBox $paramsGroupBox

        # Create inner panel for parameters (StackPanel or WrapPanel based on LayoutStyle)
        if ($capturedLayoutStyle -eq 'Wrap') {
            $paramsContent = [System.Windows.Controls.WrapPanel]@{
                Orientation         = 'Horizontal'
                HorizontalAlignment = 'Stretch'
            }

            # Store MaxColumns on Tag so it's accessible during param set switching
            $paramsContent.Tag = @{ MaxColumns = $capturedMaxColumns }

            # Add responsive sizing when MaxColumns is specified
            if ($capturedMaxColumns -gt 0) {
                $paramsContent.Add_SizeChanged({
                    param($sender, $eventArgs)

                    # Read MaxColumns from Tag
                    $maxCols = 2
                    if ($sender.Tag -is [hashtable] -and $sender.Tag.MaxColumns) {
                        $maxCols = $sender.Tag.MaxColumns
                    }

                    $paddingBuffer = 16
                    $availableWidth = $sender.ActualWidth - $paddingBuffer
                    if ($availableWidth -le 0) { return }

                    # Calculate column width based on MaxColumns
                    $minColumnWidth = 150
                    $possibleCols = [Math]::Max(1, [Math]::Floor($availableWidth / $minColumnWidth))
                    $actualCols = [Math]::Min($possibleCols, $maxCols)
                    $actualCols = [Math]::Max($actualCols, 1)

                    $childWidth = [Math]::Floor(($availableWidth / $actualCols) - 8)

                    # Apply width to all children that support it
                    foreach ($child in $sender.Children) {
                        if ($child -is [System.Windows.FrameworkElement]) {
                            if ($child.Tag -eq 'FullWidth') { continue }
                            $child.Width = $childWidth
                        }
                    }
                })
            }
        }
        else {
            $paramsContent = [System.Windows.Controls.StackPanel]::new()
            $paramsContent.Orientation = 'Vertical'
        }
        $paramsGroupBox.Content = $paramsContent

        # Register the inner panel so we can reference it later
        $session.AddControlSafe('_uiTool_paramsContent', $paramsContent)

        # Create a hidden tracker for the last selected parameter set (to avoid redundant refreshes)
        $paramSetTracker = [System.Windows.Controls.TextBlock]::new()
        $paramSetTracker.Visibility = 'Collapsed'
        $paramSetTracker.Tag = $parameterSetName
        $session.AddControlSafe('_uiTool_lastParamSet', $paramSetTracker)

        # Add to current parent with full-width constraint
        $parent = $session.CurrentParent
        if ($parent -is [System.Windows.Controls.Panel]) {
            $parent.Children.Add($paramsGroupBox) | Out-Null
        }
        elseif ($parent -is [System.Windows.Controls.ContentControl]) {
            $parent.Content = $paramsGroupBox
        }
        Set-FullWidthConstraint -Control $paramsGroupBox -Parent $parent -FullWidth

        # Build initial parameters using the helper
        Initialize-UiToolParameters -TargetPanel $paramsContent -Parameters $targetParams -Descriptions $paramDescriptions -ThemeColors $colors -ShowParamType:$capturedShowParamType -InputHelpers $capturedInputHelpers -UseWrapLayout:($capturedLayoutStyle -eq 'Wrap')

        # Store parameter info in session for validation/clear scripts (works for local functions)
        $session.Variables['_uiTool_paramInfo'] = $targetParams

        # Store the definition in session now that session is initialized
        # This enables stateless button access to command info
        $session.PSBase.CurrentDefinition = $uiDef

        New-UiSeparator

        # Display name for button label
        $cmdDisplayName = $capturedCommandDisplayName

        # Action buttons panel - buttons are stateless, reading from SessionContext.CurrentDefinition
        New-UiPanel -Orientation Horizontal {

            # Stateless validation script - reads command info from session
            $validateScript = { Invoke-UiToolValidation }

            # Stateless run script - reads command info from session
            $runScript = { Invoke-UiToolAction }

            $runBtnParams = @{
                Text           = "Run $cmdDisplayName"
                Icon           = 'Play'
                Accent         = $true
                ValidateScript = $validateScript
                Action         = $runScript
                ResultActions  = $ResultActions
                SingleSelect   = $SingleSelect
            }
            New-UiButton @runBtnParams

            # Store Run button reference for enable/disable based on mandatory params
            $session = Get-UiSession
            $parent  = $session.CurrentParent
            if ($parent -is [System.Windows.Controls.Panel] -and $parent.Children.Count -gt 0) {
                $runBtn = $parent.Children[$parent.Children.Count - 1]
                $session.Variables['_uiTool_runButton'] = $runBtn
            }

            # Stateless clear script - reads parameter names from session
            $clearScript = { Clear-UiToolParameters }

            New-UiButton -Text "Clear" -Icon "Delete" -NoAsync -Action $clearScript

            # Stateless help script - reads command info from session
            $helpScript = { Show-UiToolHelp }

            New-UiButton -Text "Help" -Icon "Help" -ScrollToTop -Action $helpScript
        }

        # Initial validation to set Run button state based on mandatory params
        Update-UiToolRunButtonState
    }.GetNewClosure()

    if ($isEmbedded) {
        # Host build context - drop the controls straight in.
        & $toolContent
    }
    elseif ($isChildWindow) {
        # Click handler context - we're on the host UI thread (New-UiButton's AST
        # flipped us). Default 600x500 is too cramped inside the child window's chrome.
        $childParams = @{
            Title  = $capturedTitle
            Width  = if ($capturedWidthExplicit)  { $capturedWidth }  else { 800 }
            Height = if ($capturedHeightExplicit) { $capturedHeight } else { 600 }
        }
        New-UiChildWindow @childParams -Content $toolContent
    }
    else {
        # No host - top-level standalone window.
        $windowParams = @{
            Title           = $capturedTitle
            Width           = $capturedWidth
            HideThemeButton = $capturedHideThemeButton
        }
        if ($capturedHeightExplicit) { $windowParams.Height = $capturedHeight }
        if ($capturedTheme)          { $windowParams.Theme  = $capturedTheme }

        New-UiWindow @windowParams -Content $toolContent
    }
}
