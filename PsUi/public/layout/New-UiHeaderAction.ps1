function New-UiHeaderAction {
    <#
    .SYNOPSIS
        Defines the header button for New-UiPanel -HeaderAction.
    .DESCRIPTION
        Builder for the -HeaderAction parameter: a small icon button on the right edge of a panel
        header. Emits a definition object only - it does not add anything to the window.

        Equivalent to the @{ Icon; Tooltip; Action } hashtable, which -HeaderAction still accepts.
    .PARAMETER Action
        Scriptblock run when the header button is clicked.
    .PARAMETER Tooltip
        Hover text on the button.
    .PARAMETER Icon
        Icon name for the button glyph. Defaults to Info when omitted. Tab completion lists the
        valid names.
    .EXAMPLE
        New-UiPanel -Header 'Report' -HeaderAction (
            New-UiHeaderAction -Icon Refresh -Tooltip 'Reload the report' -Action { Write-Status 'Reloading...' }
        ) -Content {
            New-UiLabel -Text 'Report body'
        }
    .EXAMPLE
        # Legacy hashtable form, still supported
        New-UiPanel -Header 'Report' -HeaderAction @{
            Icon    = 'Refresh'
            Tooltip = 'Reload the report'
            Action  = { Write-Status 'Reloading...' }
        } -Content {
            New-UiLabel -Text 'Report body'
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$Action,

        [string]$Tooltip
    )

    DynamicParam {
        Get-IconDynamicParameter -ParameterName 'Icon'
    }

    begin {
        $Icon = $PSBoundParameters['Icon']
    }

    process {
        $headerAction = @{ Action = $Action }
        if ($Icon) { $headerAction['Icon'] = $Icon }
        if ($PSBoundParameters.ContainsKey('Tooltip')) { $headerAction['Tooltip'] = $Tooltip }
        $headerAction
    }
}
