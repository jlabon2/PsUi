function Invoke-UiDataGridExportToCsv {
    <#
    .SYNOPSIS
        Prompts for a CSV path and exports DataGrid items, restricted to visible columns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid
    )

    $dlg            = [Microsoft.Win32.SaveFileDialog]::new()
    $dlg.Filter     = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
    $dlg.DefaultExt = '.csv'
    $dlg.FileName   = 'export.csv'

    # Owner pin keeps the dialog from landing behind the grid's window.
    $owner = [System.Windows.Window]::GetWindow($DataGrid)
    $dialogResult = if ($owner) { $dlg.ShowDialog($owner) } else { $dlg.ShowDialog() }
    if (!$dialogResult) { return }

    try {
        $source = $DataGrid.ItemsSource
        if (!$source) { return }

        # Same visibility filter as the copy path. Hidden columns stay out of the file.
        $visibleProps = Get-UiDataGridVisibleColumnPaths -DataGrid $DataGrid

        $sanitize = ($DataGrid.Tag -is [hashtable]) -and ($DataGrid.Tag['SanitizeFormulas'] -eq $true)

        # Format-UiDataGridExportRows takes IEnumerable. No need to access via @().
        $projectionArgs = @{ Items = $source; Sanitize = $sanitize }
        if ($visibleProps -and $visibleProps.Count -gt 0) { $projectionArgs.Properties = $visibleProps }

        # PS 5.1 Export-Csv defaults to ANSI - force UTF-8 for non ASCII rows.
        Format-UiDataGridExportRows @projectionArgs | Export-Csv -Path $dlg.FileName -NoTypeInformation -Force -Encoding UTF8
    }
    catch {
        # Silent catch made this look like a broken Export button. Usually the file'll be open in Excel.
        Write-Debug "Export failed: $_"
        $msg  = "Failed to export to $($dlg.FileName):`n`n$($_.Exception.Message)"
        $btn  = [System.Windows.MessageBoxButton]::OK
        $icon = [System.Windows.MessageBoxImage]::Warning

        if ($owner) { [void][System.Windows.MessageBox]::Show($owner, $msg, 'Export Failed', $btn, $icon) }
        else        { [void][System.Windows.MessageBox]::Show($msg, 'Export Failed', $btn, $icon) }
    }
}
