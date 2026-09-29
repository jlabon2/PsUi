function New-UiResultAction {
    <#
    .SYNOPSIS
        Defines one entry for a button's Actions dropdown in the output window.
    .DESCRIPTION
        Builder for the -ResultActions parameter on New-UiButton, New-UiButtonCard, and New-UiTool.
        Each call becomes one item in the results grid's Actions dropdown, run against the selected
        rows. Pass the calls inside a scriptblock or an array; the dropdown keeps their order.
        Emits a definition object only - it does not add anything to the window.

        Equivalent to a @{ Text; Action; Icon; Confirm; ObjectType } hashtable, which
        -ResultActions still accepts.
    .PARAMETER Text
        Dropdown item label.
    .PARAMETER Action
        Scriptblock run against the selection. $_ is the selected row, or the whole array when
        more than one row is selected. $Selected is always the full array.
    .PARAMETER Icon
        Icon name shown ahead of the label. Tab completion lists the valid names.
    .PARAMETER Confirm
        Ask before running. Format string where {0} is the selection count, so
        'Stop {0} processes?' reads right at any selection size.
    .PARAMETER ObjectType
        Show this action only on result tabs whose type matches one of these names.
        Tabs are labeled with the short type name (Process, not System.Diagnostics.Process),
        and the match is exact or substring against that label.
    .EXAMPLE
        New-UiButton -Text 'Get Processes' -Action { Get-Process } -ResultActions {
            New-UiResultAction 'Stop' -Icon Stop -Confirm 'Stop {0} processes?' -Action { $_ | Stop-Process -Force }
            New-UiResultAction 'Details' -Action { $Selected | Format-List * | Out-String | Write-Host }
        }
    .EXAMPLE
        # Legacy hashtable form, still supported
        New-UiButton -Text 'Get Processes' -Action { Get-Process } -ResultActions @(
            @{ Text = 'Stop'; Icon = 'Stop'; Confirm = 'Stop {0} processes?'; Action = { $_ | Stop-Process -Force } }
        )
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Text,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock]$Action,

        [string]$Confirm,

        [string[]]$ObjectType
    )

    DynamicParam {
        Get-IconDynamicParameter -ParameterName 'Icon'
    }

    begin {
        $Icon = $PSBoundParameters['Icon']
    }

    process {
        $entry = @{ Text = $Text; Action = $Action }
        if ($Icon) { $entry['Icon'] = $Icon }
        if ($PSBoundParameters.ContainsKey('Confirm')) { $entry['Confirm'] = $Confirm }
        if ($PSBoundParameters.ContainsKey('ObjectType')) { $entry['ObjectType'] = $ObjectType }
        $entry
    }
}
