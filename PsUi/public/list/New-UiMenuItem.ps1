function New-UiMenuItem {
    <#
    .SYNOPSIS
        Defines one entry for a data grid's right-click menu.
    .DESCRIPTION
        Builder for the -RowContextMenu parameter on New-UiDataGrid. Each call becomes one menu
        item; pass the calls inside a scriptblock or an array and the menu keeps their order.
        Emits a definition object only - it does not add anything to the window.

        The action runs with $_ bound to the clicked row. When the click lands inside a
        multi-selection, the action runs once per selected row.

        Equivalent to one entry of the legacy label-keyed hashtable form, which -RowContextMenu
        still accepts.
    .PARAMETER Text
        Menu item label. Labels must be unique within one menu (case-insensitive).
    .PARAMETER Action
        Scriptblock to run when the item is clicked. $_ is the target row. On multi-select
        the action reruns once per selected row.
    .PARAMETER Enabled
        $true, $false, or a scriptblock probed per row every time the menu opens ($_ = row).
        The item grays out when no targeted row passes. Probing caps at 20 rows on big
        selections; past that the item stays enabled and the click still skips ineligible rows.
    .PARAMETER Icon
        Icon name shown ahead of the label. Tab completion lists the valid names.
    .PARAMETER Sync
        Run the action on the UI thread instead of a background runspace. For actions that open
        dialogs or child windows.
    .EXAMPLE
        New-UiDataGrid -Variable 'svc' -Items (Get-Service) -RowContextMenu {
            New-UiMenuItem 'Start' -Icon Play -Action { Start-Service $_.Name } -Enabled { $_.Status -eq 'Stopped' }
            New-UiMenuItem 'Details' -Sync -Action { Show-UiMessageDialog -Message ($_ | Out-String) }
        }
    .EXAMPLE
        # Legacy hashtable form, still supported
        New-UiDataGrid -Variable 'svc' -Items (Get-Service) -RowContextMenu ([ordered]@{
            'Start' = @{ Action = { Start-Service $_.Name }; Enabled = { $_.Status -eq 'Stopped' } }
            'Details' = @{ Action = { Show-UiMessageDialog -Message ($_ | Out-String) }; Sync = $true }
        })
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Text,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock]$Action,

        [object]$Enabled,

        [switch]$Sync
    )

    DynamicParam {
        Get-IconDynamicParameter -ParameterName 'Icon'
    }

    begin {
        $Icon = $PSBoundParameters['Icon']
    }

    process {
        # The menu builder casts a non-scriptblock Enabled straight to [bool], and 'false' casts truthy. Catch the type here where the error can name the right function.
        if ($null -ne $Enabled -and $Enabled -isnot [bool] -and $Enabled -isnot [scriptblock]) {
            throw "New-UiMenuItem: -Enabled takes `$true/`$false or a scriptblock. Got [$($Enabled.GetType().Name)]."
        }

        # Keys stay absent unless the parameter was bound. The consumer reads $null -ne Enabled, so absent and $false mean different things there. Sync stays conditional to match.
        $item = @{ Text = $Text; Action = $Action }
        if ($Icon) { $item['Icon'] = $Icon }
        if ($PSBoundParameters.ContainsKey('Enabled')) { $item['Enabled'] = $Enabled }
        if ($PSBoundParameters.ContainsKey('Sync')) { $item['Sync'] = [bool]$Sync }
        $item
    }
}
