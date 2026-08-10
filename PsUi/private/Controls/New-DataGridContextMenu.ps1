function New-DataGridContextMenu {
    <#
    .SYNOPSIS
        Standard DataGrid context menu (copy cell, copy rows, export, select all). One per grid.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid
    )

    $contextMenu = [System.Windows.Controls.ContextMenu]::new()

    # WPF click handlers resolve command NAMES against the runspace global scope, so a standalone grid whose runspace never injected these module private helpers (Out-CSVDataGrid calls ShowDialog and injects nothing) threw CommandNotFound on copy/export.
    # Capture them as refs here in module scope and invoke through the variable (the same ref trick Invoke-UiDataGridCopyToClipboard already uses for its own private deps!)
    $copyToClipboard = ${function:Invoke-UiDataGridCopyToClipboard}
    $exportToCsv     = ${function:Invoke-UiDataGridExportToCsv}

    # Single value, no CSV envelope.
    $copyCellMenuItem        = [System.Windows.Controls.MenuItem]::new()
    $copyCellMenuItem.Header = 'Copy Cell'
    [void]$contextMenu.Items.Add($copyCellMenuItem)

    $copyCellMenuItem.Add_Click({
        & $copyToClipboard -DataGrid $DataGrid -Cell
    }.GetNewClosure())

    # This and the Ctrl+C handler both route through Invoke-UiDataGridCopyToClipboard so the _* exclusion stays consistent with the toolbar.
    $copyMenuItem        = [System.Windows.Controls.MenuItem]::new()
    $copyMenuItem.Header = 'Copy Selected Rows'
    [void]$contextMenu.Items.Add($copyMenuItem)

    $copyMenuItem.Add_Click({ & $copyToClipboard -DataGrid $DataGrid }.GetNewClosure())

    # WPF's default Ctrl+C copies "System.Object[]" for non string rows and bypasses the _* strip. Always intercept this.
    # Skip when the original source is a cell editor. Ctrl+C on that should copy the selected text inside the editor.
    $DataGrid.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -ne 'C' -or [System.Windows.Input.Keyboard]::Modifiers -ne 'Control') { return }
        if ($eventArgs.OriginalSource -is [System.Windows.Controls.Primitives.TextBoxBase]) { return }
        if ($sender.SelectedItems.Count -gt 0) {
            & $copyToClipboard -DataGrid $sender
            $eventArgs.Handled = $true
        }
    }.GetNewClosure())

    $exportMenuItem        = [System.Windows.Controls.MenuItem]::new()
    $exportMenuItem.Header = 'Export to CSV...'
    [void]$contextMenu.Items.Add($exportMenuItem)

    $exportMenuItem.Add_Click({
        & $exportToCsv -DataGrid $DataGrid
    }.GetNewClosure())

    $selectAllMenuItem        = [System.Windows.Controls.MenuItem]::new()
    $selectAllMenuItem.Header = 'Select All'
    [void]$contextMenu.Items.Add($selectAllMenuItem)
    $selectAllMenuItem.Add_Click({ $DataGrid.SelectAll() }.GetNewClosure())

    $DataGrid.ContextMenu = $contextMenu
    Set-ContextMenuStyle -ContextMenu $contextMenu
}
