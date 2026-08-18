function New-UiColumn {
    <#
    .SYNOPSIS
        Defines one column for New-UiDataGrid -Columns.
    .DESCRIPTION
        Builder for the -Columns parameter on New-UiDataGrid. Covers all four column kinds: Text
        (the default, reads a row property), Button, Toggle, and Link. Pass the calls inside a
        scriptblock or an array; column order follows call order, and plain property-name strings
        still work alongside builder calls. Emits a definition object only - it does not add
        anything to the window.

        Equivalent to the column hashtable form (@{ Name; Header; Type; ... }), which -Columns
        still accepts.
    .PARAMETER Name
        Row property this column binds to. Text columns need it; Button, Toggle, and Link columns
        can run on -Header alone.
    .PARAMETER Type
        Column kind: Text (default), Button, Toggle, or Link.
    .PARAMETER Header
        Column header text. Defaults to -Name.
    .PARAMETER Width
        Column width: a number, 'Auto', 'Star', '*', or star notation like '2*'.
    .PARAMETER MinWidth
        Minimum width in pixels. Overrides the computed floor.
    .PARAMETER Format
        StringFormat for the cell text, e.g. '{0:N2}' or '{0:yyyy-MM-dd}'.
    .PARAMETER ReadOnly
        Lock the column even when the grid is -Editable.
    .PARAMETER Editable
        Per-column edit rule: $true/$false, a row property name, or a scriptblock probed per cell
        with $_ bound to the row.
    .PARAMETER EditorType
        Editor used when the cell enters edit mode: Auto (default), Text, CheckBox, ComboBox, or
        DatePicker.
    .PARAMETER Choices
        ComboBox editor items, plain values. Omitted on an enum property, the enum's own
        values fill the list.
    .PARAMETER Validator
        Scriptblock run before an edit commits: param($newValue, $row), return $false to reject
        and roll the cell back.
    .PARAMETER Action
        Click scriptblock for Button and Link columns. $_ is the row.
    .PARAMETER OnChange
        Scriptblock for Toggle columns, run after the checkbox flips: param($row, $checked).
    .PARAMETER Binding
        Row property backing the cell control. Required for Toggle (the bool the checkbox reads
        and writes); optional label binding for Button and Link.
    .PARAMETER Text
        Static label for Button and Link cells. -Binding wins over it when both are set.
    .PARAMETER Icon
        Icon name for Button cells. Tab completion lists the valid names.
    .PARAMETER Url
        Link target with {PropertyName} row substitution, e.g. 'https://{Host}/status'.
    .PARAMETER AllowFileScheme
        Let Link columns open file: URLs. Without it only http, https, mailto, and tel pass.
    .PARAMETER Sync
        Run -Action on the UI thread instead of a background runspace.
    .EXAMPLE
        New-UiDataGrid -Variable 'svc' -Items (Get-Service) -Editable -Columns {
            New-UiColumn Name -ReadOnly
            New-UiColumn Status -Editable $true
            New-UiColumn StartType -Editable $true -EditorType ComboBox -Choices 'Automatic', 'Manual', 'Disabled'
            New-UiColumn -Header 'Restart' -Type Button -Text 'Restart' -Action { Restart-Service $_.Name }
        }
    .EXAMPLE
        # Legacy hashtable form, still supported
        New-UiDataGrid -Variable 'svc' -Items (Get-Service) -Editable -Columns @(
            @{ Name = 'Name'; ReadOnly = $true }
            @{ Name = 'Status'; Editable = $true }
            @{ Header = 'Restart'; Type = 'Button'; Text = 'Restart'; Action = { Restart-Service $_.Name } }
        )
    .EXAMPLE
        # Builder calls and plain property-name strings mix freely
        New-UiDataGrid -Variable 'proc' -Items (Get-Process) -Columns @(
            'Name'
            'Id'
            (New-UiColumn WorkingSet -Header 'Memory' -Format '{0:N0}')
        )
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name,

        [ValidateSet('Text', 'Button', 'Toggle', 'Link')]
        [string]$Type,

        [string]$Header,

        [object]$Width,

        [int]$MinWidth,

        [string]$Format,

        [switch]$ReadOnly,

        [object]$Editable,

        [ValidateSet('Auto', 'Text', 'CheckBox', 'ComboBox', 'DatePicker')]
        [string]$EditorType,

        [object[]]$Choices,

        [scriptblock]$Validator,

        [scriptblock]$Action,

        [scriptblock]$OnChange,

        [string]$Binding,

        [string]$Text,

        [string]$Url,

        [switch]$AllowFileScheme,

        [switch]$Sync
    )

    DynamicParam {
        Get-IconDynamicParameter -ParameterName 'Icon'
    }

    process {
        # Throws at definition time for the combos the grid would otherwise reject (or silently break) hundreds of lines deeper.
        if (!$Name -and !$Header) { throw "New-UiColumn: give the column -Name (a row property) or -Header." }
        if ($Type -eq 'Toggle' -and !$PSBoundParameters.ContainsKey('Binding')) {
            throw "New-UiColumn: a Toggle column needs -Binding (the bool row property the checkbox reads and writes)."
        }
        if ($Type -eq 'Link' -and !$Url -and !$Action) { throw "New-UiColumn: a Link column needs -Url or -Action." }

        # One key per bound parameter, same names both sides. Switches flatten to plain bools; unbound keys stay absent becuase the grid reads .Contains() on some of them.
        $switchNames = @('ReadOnly', 'AllowFileScheme', 'Sync')
        $column      = @{}
        foreach ($boundName in $PSBoundParameters.Keys) {
            if ($boundName -in [System.Management.Automation.PSCmdlet]::CommonParameters) { continue }
            if ($boundName -in $switchNames) { $column[$boundName] = [bool]$PSBoundParameters[$boundName] }
            else { $column[$boundName] = $PSBoundParameters[$boundName] }
        }
        $column
    }
}
