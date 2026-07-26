function Show-UiOutput {
    <#
    .SYNOPSIS
        Displays streaming async output in a themed WPF window.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PsUi.AsyncExecutor]$Executor,

        [string]$Title = 'Output',

        [ValidateRange(400, 2000)]
        [int]$Width = 900,

        [ValidateRange(300, 1500)]
        [int]$Height = 600,

        [System.Windows.Window]$ParentWindow,

        [scriptblock]$Action,
        [hashtable]$Parameters,
        [hashtable[]]$ResultActions,
        [switch]$SingleSelect,
        [string[]]$LinkedVariables,
        [string[]]$LinkedFunctions,
        [string[]]$LinkedModules,
        [System.Collections.IDictionary]$LinkedVariableValues,
        [System.Collections.IDictionary]$LinkedFunctionDefinitions,

        # Variable names to capture from runspace after execution
        [string[]]$Capture,

        [switch]$HideUntilContent,

        # Non-blocking mode - output window doesn't block parent
        [switch]$NoWait,

        # Scroll console to top on completion instead of staying at bottom
        [switch]$ScrollToTop,

        # Legacy parameter - ignored but kept for backward compatibility
        [switch]$Streaming
    )

    # Delegate to streaming output implementation
    $streamingParams = @{
        Executor                  = $Executor
        Title                     = $Title
        Width                     = $Width
        Height                    = $Height
        ParentWindow              = $ParentWindow
        Action                    = $Action
        Parameters                = $Parameters
        ResultActions             = $ResultActions
        SingleSelect              = $SingleSelect
        LinkedVariables           = $LinkedVariables
        LinkedFunctions           = $LinkedFunctions
        LinkedModules             = $LinkedModules
        LinkedVariableValues      = $LinkedVariableValues
        LinkedFunctionDefinitions = $LinkedFunctionDefinitions
        Capture                   = $Capture
        HideUntilContent          = $HideUntilContent
        NoWait                    = $NoWait
        ScrollToTop               = $ScrollToTop
    }

    Show-StreamingOutput @streamingParams
}
