function New-DataGridContextMenu {
    <#
    .SYNOPSIS
        Creates a standard context menu for DataGrid controls with copy, export, and select actions.
        Datagrids are used pretty heavily throughout, so having a common context mennu improves consistency 
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid
    )
    
    $contextMenu = [System.Windows.Controls.ContextMenu]::new()

    # Copy Selected Rows menu item
    $copyMenuItem        = [System.Windows.Controls.MenuItem]::new()
    $copyMenuItem.Header = 'Copy Selected Rows'
    [void]$contextMenu.Items.Add($copyMenuItem)

    $copyMenuItem.Add_Click({
        if ($DataGrid.SelectedItems.Count -gt 0) {
            $text = $DataGrid.SelectedItems | ConvertTo-Csv -NoTypeInformation | Out-String
            [System.Windows.Clipboard]::SetText($text)
        }
    }.GetNewClosure())

    # Handle Ctrl+C to use our custom copy logic instead of WPF's default (which can output "System.Object[]")
    $DataGrid.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq 'C' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
            if ($sender.SelectedItems.Count -gt 0) {
                $text = $sender.SelectedItems | ConvertTo-Csv -NoTypeInformation | Out-String
                [System.Windows.Clipboard]::SetText($text)
                $eventArgs.Handled = $true
            }
        }
    })

    # Export to CSV menu item
    $exportMenuItem        = [System.Windows.Controls.MenuItem]::new()
    $exportMenuItem.Header = 'Export to CSV...'
    [void]$contextMenu.Items.Add($exportMenuItem)

    $exportMenuItem.Add_Click({
        $saveDialog            = [Microsoft.Win32.SaveFileDialog]::new()
        $saveDialog.Filter     = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
        $saveDialog.DefaultExt = '.csv'
        if ($saveDialog.ShowDialog()) { $DataGrid.ItemsSource | Export-Csv -Path $saveDialog.FileName -NoTypeInformation }
    }.GetNewClosure())

    # Select All menu item
    $selectAllMenuItem        = [System.Windows.Controls.MenuItem]::new()
    $selectAllMenuItem.Header = 'Select All'
    [void]$contextMenu.Items.Add($selectAllMenuItem)
    $selectAllMenuItem.Add_Click({ $DataGrid.SelectAll() }.GetNewClosure())

    # Attach to DataGrid and apply styling
    $DataGrid.ContextMenu = $contextMenu
    Set-ContextMenuStyle -ContextMenu $contextMenu
}
