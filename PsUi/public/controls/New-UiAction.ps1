function New-UiAction {
    <#
    .SYNOPSIS
        Creates a silent button that runs actions without an output window.
    .DESCRIPTION
        Thin wrapper around New-UiButton with -NoOutput baked in. Use this for buttons
        that update UI state (charts, forms, toggles) rather than producing pipeline
        output. For buttons that need an output window, use New-UiButton instead.
    .PARAMETER Text
        The button label text.
    .PARAMETER Action
        The scriptblock to execute when clicked. Mutually exclusive with -File.
    .PARAMETER File
        Path to a script file to execute when clicked. Supports .ps1, .bat, .cmd,
        .vbs, and .exe files. Mutually exclusive with -Action.
    .PARAMETER ArgumentList
        Hashtable of arguments to pass to the script file.
    .PARAMETER Accent
        Use accent color styling for the button.
    .PARAMETER Width
        Button width in pixels. Defaults to auto-sizing.
    .PARAMETER Height
        Button height in pixels. Defaults to 28.
    .PARAMETER NoAsync
        Execute synchronously on the UI thread (blocks UI).
    .PARAMETER NoWait
        Execute async but don't block the parent window.
    .PARAMETER NoInteractive
        Use fast pooled execution without interactive input support.
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
    .PARAMETER ValidateScript
        Pre-action validation script. Runs synchronously before Action.
    .PARAMETER GridColumn
        If specified, sets Grid.Column attached property.
    .PARAMETER GridRow
        If specified, sets Grid.Row attached property.
    .PARAMETER EnabledWhen
        Conditional enabling based on another control's state.
    .PARAMETER Variable
        Optional name to register the button for -SubmitButton lookups.
    .PARAMETER WPFProperties
        Hashtable of WPF properties to apply to the button.
    .EXAMPLE
        New-UiAction -Text 'Save' -Icon 'Save' -Accent -Action { Set-UiValue -Variable 'status' -Value 'Saved' }
    .EXAMPLE
        New-UiAction -Text 'Add Point' -Icon 'Add' -Action { Update-UiChart -Variable 'chart' -Data $newData }
    #>
    [CmdletBinding(DefaultParameterSetName = 'ScriptBlock')]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory, ParameterSetName = 'ScriptBlock')]
        [scriptblock]$Action,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$File,

        [Parameter(ParameterSetName = 'File')]
        [hashtable]$ArgumentList,

        [switch]$Accent,
        [int]$Width,
        [int]$Height = 28,

        [switch]$NoAsync,
        [switch]$NoWait,
        [switch]$NoInteractive,
        [string[]]$LinkedVariables,
        [string[]]$LinkedFunctions,
        [string[]]$LinkedModules,
        [string[]]$Capture,
        [hashtable]$Parameters,
        [hashtable]$Variables,
        [scriptblock]$ValidateScript,

        [int]$GridColumn = -1,
        [int]$GridRow = -1,

        [Parameter()]
        [object]$EnabledWhen,

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
        $buttonParams = @{}
        foreach ($key in $PSBoundParameters.Keys) {
            if ($key -eq 'Icon') { continue }
            $buttonParams[$key] = $PSBoundParameters[$key]
        }
        if ($Icon) { $buttonParams['Icon'] = $Icon }
        $buttonParams['NoOutput'] = $true

        New-UiButton @buttonParams
    }
}
