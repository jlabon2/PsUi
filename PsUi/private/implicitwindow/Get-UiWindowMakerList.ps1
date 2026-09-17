function Get-UiWindowMakerList {
    <#
    .SYNOPSIS
        The PsUi commands that open a window of their own. The read stops in front of one of
        these rather than pulling a second window into the content.
    #>
    [CmdletBinding()]
    param()

    if ($script:uiWindowMakers) { return ,$script:uiWindowMakers }

    $makers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($name in 'New-UiWindow', 'New-UiChildWindow', 'New-UiTool', 'Out-Datagrid', 'Out-CSVDataGrid',
                      'Out-TextEditor', 'Show-WindowsObjectPicker') {
        [void]$makers.Add($name)
    }

    $module = $ExecutionContext.SessionState.Module
    if ($module) {
        foreach ($name in $module.ExportedCommands.Keys) {
            # Every Show-Ui command puts something on screen and blocks, apart from Show-UiStatusBar, which only reveals a bar in the window already being built.
            if ($name -like 'Show-Ui*' -and $name -ne 'Show-UiStatusBar') { [void]$makers.Add($name) }
        }
    }

    # A set built with no module behind it would persist for the session.
    if ($module) { $script:uiWindowMakers = $makers }
    return ,$makers
}
