function New-UiActionCard {
    <#
    .SYNOPSIS
        Creates a silent action card that runs without an output window.
    .DESCRIPTION
        Thin wrapper around New-UiButtonCard with -NoOutput baked in. Use this for
        cards that update UI state, open dialogs, or perform quick operations without
        needing output display. For cards that produce pipeline output or need an
        output window, use New-UiButtonCard instead.
    .PARAMETER Header
        The card title/header text.
    .PARAMETER Description
        Optional description text shown below the header.
    .PARAMETER ButtonText
        Text shown on the action button. Defaults to 'Go'.
    .PARAMETER Action
        The scriptblock to execute when the button is clicked. Mutually exclusive with -File.
    .PARAMETER File
        Path to a script file to execute when clicked. Mutually exclusive with -Action.
    .PARAMETER ArgumentList
        Hashtable of arguments to pass to the script file.
    .PARAMETER Accent
        If specified, the button uses accent color styling.
    .PARAMETER FullWidth
        If specified, the card spans the full width of its container.
    .PARAMETER NoAsync
        Execute synchronously on the UI thread (blocks UI).
    .PARAMETER NoWait
        Execute async but don't block the parent window.
    .PARAMETER LinkedVariables
        Variable names to capture from caller's scope.
    .PARAMETER LinkedFunctions
        Function names to capture from caller's scope.
    .PARAMETER LinkedModules
        Module paths to import in the async runspace.
    .PARAMETER Capture
        Variable names to capture from the runspace after execution completes.
    .PARAMETER Parameters
        Hashtable of parameters to pass to the action.
    .PARAMETER Variables
        Hashtable of variables to inject into the action.
    .PARAMETER Variable
        Optional name to register the button for -SubmitButton lookups.
    .PARAMETER WPFProperties
        Hashtable of WPF properties to apply to the card container.
    .EXAMPLE
        New-UiActionCard -Header 'File Picker' -Icon 'OpenFile' -ButtonText 'Pick' -Action { Show-UiFilePicker }
    .EXAMPLE
        New-UiActionCard -Header 'Register Theme' -Icon 'ColorBackground' -Accent -ButtonText 'Register' -Action { Register-UiTheme @theme }
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

        [switch]$NoAsync,
        [switch]$NoWait,
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
        # Wrapper (not alias) so -NoOutput and -HideEmptyOutput stay out of IntelliSense
        $cardParams = @{}
        foreach ($key in $PSBoundParameters.Keys) {
            if ($key -eq 'Icon') { continue }
            $cardParams[$key] = $PSBoundParameters[$key]
        }
        if ($Icon) { $cardParams['Icon'] = $Icon }
        $cardParams['NoOutput'] = $true

        New-UiButtonCard @cardParams
    }
}
