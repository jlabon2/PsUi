function New-UiButtonCard {
    <#
    .SYNOPSIS
        Creates a button card with icon, header, description, and an action button.
    .DESCRIPTION
        Creates a styled card/groupbox containing an icon, header text, optional description,
        and an action button. The button executes asynchronously by default with full
        output streaming support. Use New-UiActionCard for the same card with -NoOutput
        baked in.
        
        Use -Action to provide an inline scriptblock, or -File to run an external
        script file. These parameters are mutually exclusive.
    .PARAMETER Header
        The card title/header text.
    .PARAMETER Description
        Optional description text shown below the header.
    .PARAMETER Icon
        Icon name from Segoe MDL2 Assets (e.g., 'Play', 'Save', 'Processing').
    .PARAMETER ButtonText
        Text shown on the action button. Defaults to 'Go'.
    .PARAMETER Action
        The scriptblock to execute when the button is clicked. Mutually exclusive with -File.
    .PARAMETER File
        Path to a script file to execute when clicked. Supports .ps1, .bat, .cmd,
        .vbs, and .exe files. Mutually exclusive with -Action.
    .PARAMETER ArgumentList
        Hashtable of arguments to pass to the script file.
    .PARAMETER Accent
        If specified, the button uses accent color styling.
    .PARAMETER FullWidth
        If specified, the card spans the full width of its container.
    .PARAMETER NoAsync
        Execute synchronously on the UI thread (blocks UI).
    .PARAMETER NoWait
        Execute async with output window, but don't block the parent window.
        Other buttons remain clickable while this action runs.
    .PARAMETER NoOutput
        Execute async but don't show output window.
    .PARAMETER HideEmptyOutput
        Show output window only when there's actual content.
    .PARAMETER ResultActions
        Hashtable array defining actions for DataGrid results.
    .PARAMETER SingleSelect
        If specified, ResultActions work with single selection.
    .PARAMETER LinkedVariables
        Variable names to capture from caller's scope.
    .PARAMETER LinkedFunctions
        Function names to capture from caller's scope.
    .PARAMETER LinkedModules
        Module paths to import in the async runspace.
    .PARAMETER Capture
        Variable names to capture from the runspace after execution completes.
        Captured variables are stored in the session and available to subsequent
        button actions via hydration, eliminating the need for Get-UiSession.
    .PARAMETER Parameters
        Hashtable of parameters to pass to the action.
    .PARAMETER Variables
        Hashtable of variables to inject into the action.
    .PARAMETER Variable
        Optional name to register the button for -SubmitButton lookups.
        When specified, inputs using -SubmitButton with this name will trigger
        the button's click event when Enter is pressed.
    .PARAMETER WPFProperties
        Hashtable of WPF properties to apply to the card container.
    .EXAMPLE
        New-UiButtonCard -Header "Get Processes" -Icon "Processing" -Action { Get-Process }
    .EXAMPLE
        New-UiButtonCard -Header "Save Data" -Description "Saves current state" -Icon "Save" -ButtonText "SAVE" -Accent -Action { Save-Data }
    .EXAMPLE
        New-UiButtonCard -Header "Run Deploy" -Icon "Deploy" -File "C:\Scripts\Deploy.ps1" -ArgumentList @{ Env = 'Prod' }
    #>
    [CmdletBinding(DefaultParameterSetName = 'ScriptBlock')]
    param(
        [Parameter(Mandatory)]
        [string]$Header,

        [string]$Description,

        [string]$ButtonText = 'Go',

        [Parameter(Mandatory, ParameterSetName = 'ScriptBlock')]
        [scriptblock]$Action,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$File,

        [Parameter(ParameterSetName = 'File')]
        [hashtable]$ArgumentList,

        [switch]$Accent,

        [switch]$FullWidth,

        # Action execution parameters (passed to New-UiButton)
        [switch]$NoAsync,
        [switch]$NoWait,
        [switch]$NoOutput,
        [switch]$HideEmptyOutput,
        [hashtable[]]$ResultActions,
        [switch]$SingleSelect,
        [string[]]$LinkedVariables,
        [string[]]$LinkedFunctions,
        [string[]]$LinkedModules,
        [string[]]$Capture,
        [hashtable]$Parameters,
        [hashtable]$Variables,

        [Parameter()]
        [string]$Variable,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    DynamicParam {
        Get-IconDynamicParameter -ParameterName 'Icon'
    }

    begin {
        $Icon = $PSBoundParameters['Icon']
    }

    process {

    # Can't use both - pick one
    if ($NoOutput -and $HideEmptyOutput) {
        throw "Parameters -NoOutput and -HideEmptyOutput are mutually exclusive. Use only one."
    }

    $session = Assert-UiSession -CallerName 'New-UiButtonCard'
    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent
    Write-Debug "Header='$Header', Icon='$Icon', Accent=$($Accent.IsPresent), Parent: $($parent.GetType().Name)"

    $groupBox = [PsUi.ControlFactory]::CreateGroupBox($null, 0)
    $groupBox.Height = [System.Double]::NaN

    # Apply responsive constraints (function checks if parent is WrapPanel)
    Set-ResponsiveConstraints -Control $groupBox -FullWidth:$FullWidth

    $grid = [System.Windows.Controls.Grid]::new()
    $grid.MinHeight = 40

    [void]$grid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
    [void]$grid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
    [void]$grid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
    $grid.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new(1, 'Star')
    $grid.ColumnDefinitions[2].Width = [System.Windows.GridLength]::new(128)

    # Column 0: Icon (if specified)
    $iconText = [PsUi.ModuleContext]::GetIcon($Icon)
    if ($Icon -and $iconText) {
        $grid.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(48)
        $iconBlock = [System.Windows.Controls.TextBlock]@{
            Text = $iconText
            FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            FontSize = 24
            HorizontalAlignment = 'Center'
            VerticalAlignment = 'Center'
            Tag = 'AccentBrush'
        }
        $iconBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush')
        if ([PsUi.ModuleContext]::IsInitialized) {
            [PsUi.ThemeEngine]::RegisterElement($iconBlock)
        }
        [void]$grid.Children.Add($iconBlock)
    }
    else {
        $grid.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(8)
    }

    # Column 1: Header and description text
    $textPanel = [System.Windows.Controls.StackPanel]@{
        VerticalAlignment = 'Center'
    }
    [System.Windows.Controls.Grid]::SetColumn($textPanel, 1)

    $headerBlock = [System.Windows.Controls.TextBlock]@{
        Text         = $Header
        FontFamily   = [System.Windows.Media.FontFamily]::new('Segoe UI Variable, Segoe UI')
        FontSize     = 14
        FontWeight   = 'Medium'
        Foreground   = ConvertTo-UiBrush $colors.ControlFg
        TextWrapping = 'Wrap'
        Tag          = 'ControlFgBrush'
    }
    [PsUi.ThemeEngine]::RegisterElement($headerBlock)
    [void]$textPanel.Children.Add($headerBlock)

    if ($Description) {
        $descriptionBlock = [System.Windows.Controls.TextBlock]@{
            Text         = $Description
            FontFamily   = [System.Windows.Media.FontFamily]::new('Segoe UI Variable, Segoe UI')
            FontSize     = 12
            Foreground   = ConvertTo-UiBrush $colors.SecondaryText
            TextWrapping = 'Wrap'
            ToolTip      = $Description
            Tag          = 'SecondaryTextBrush'
        }
        [PsUi.ThemeEngine]::RegisterElement($descriptionBlock)
        [void]$textPanel.Children.Add($descriptionBlock)
    }
    [void]$grid.Children.Add($textPanel)

    # Column 2: Action button
    # Temporarily set the grid as current parent so the button gets added there
    $originalParent = $session.CurrentParent
    $session.CurrentParent = $grid

    # Build splat for New-UiButton based on parameter set
    $buttonParams = @{
        Text       = $ButtonText
        Accent     = $Accent
        Width      = 120
        Height     = 32
        GridColumn = 2
    }

    # Use either Action or File based on parameter set
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $buttonParams['File'] = $File
        if ($ArgumentList) { $buttonParams['ArgumentList'] = $ArgumentList }
    }
    else {
        $buttonParams['Action'] = $Action
    }

    # Pass through action execution parameters
    if ($NoAsync) { $buttonParams['NoAsync'] = $true }
    if ($NoWait) { $buttonParams['NoWait'] = $true }
    if ($NoOutput) { $buttonParams['NoOutput'] = $true }
    if ($HideEmptyOutput) { $buttonParams['HideEmptyOutput'] = $true }
    if ($ResultActions) { $buttonParams['ResultActions'] = $ResultActions }
    if ($SingleSelect) { $buttonParams['SingleSelect'] = $true }
    if ($LinkedVariables) { $buttonParams['LinkedVariables'] = $LinkedVariables }
    if ($LinkedFunctions) { $buttonParams['LinkedFunctions'] = $LinkedFunctions }
    if ($LinkedModules) { $buttonParams['LinkedModules'] = $LinkedModules }
    if ($Capture) { $buttonParams['Capture'] = $Capture }
    if ($Parameters) { $buttonParams['Parameters'] = $Parameters }
    if ($Variables) { $buttonParams['Variables'] = $Variables }
    if ($Variable) { $buttonParams['Variable'] = $Variable }

    # Store Header in context for output window title
    $buttonParams['OutputTitle'] = $Header

    $button = New-UiButton @buttonParams

    # Restore original parent
    $session.CurrentParent = $originalParent

    # Attach grid to groupbox and add to parent
    $groupBox.Content = $grid

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $groupBox -Properties $WPFProperties
    }

    # Add to parent - don't return if added (to avoid pipeline output)
    Write-Debug "Adding button card '$Header' to parent"
    $addedToParent = $false
    if ($parent -is [System.Windows.Controls.Panel]) {
        [void]$parent.Children.Add($groupBox)
        $addedToParent = $true
    }
    elseif ($parent -is [System.Windows.Controls.ItemsControl]) {
        [void]$parent.Items.Add($groupBox)
        $addedToParent = $true
    }
    elseif ($parent -is [System.Windows.Controls.ContentControl]) {
        $parent.Content = $groupBox
        $addedToParent = $true
    }

    if (Get-Command New-UniqueControlName -ErrorAction SilentlyContinue) {
        Register-UiControl -Name (New-UniqueControlName -Prefix 'ButtonCard') -Control $groupBox
    }

    # Only return if not added to parent (for manual layout scenarios)
    if (!$addedToParent) {
        return $groupBox
    }
    }
}
