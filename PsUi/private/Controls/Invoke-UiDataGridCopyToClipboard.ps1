function Invoke-UiDataGridCopyToClipboard {
    <#
    .SYNOPSIS
        Selected rows, or the focused cell, onto the clipboard with only the visible columns. False where it fell through.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [switch]$Cell
    )

    # DataGrid property reads (SelectedItems, CurrentCell, Tag, Columns) have UI thread affinity, and Clipboard.SetText is STA only.
    # From a background runspace SelectedItems reads as an empty enumeration, so the function returns early and copies no rows.
    # The whole body goes over in one Dispatcher.Invoke, so a single hop covers every read and the write.
    $cellMode = [bool]$Cell
    $gridRef  = $DataGrid

    # The only thing this hands back, since every failure below goes to Write-Debug and stops there.
    # Hashtable and not a plain variable, since & $work runs in a child scope where $copied = $true would never reach this one.
    $copied = @{ Value = $false }

    # GetNewClosure drops module private function resolution, so a name looked up inside $work throws CommandNotFound into its own catch.
    # Carry the functions as references instead.
    $getPaths   = ${function:Get-UiDataGridVisibleColumnPaths}
    $formatRows = ${function:Format-UiDataGridExportRows}
    $cellValue  = ${function:Get-UiDataGridCellValue}
    $exportText = ${function:ConvertTo-UiExportText}

    $work = {
        if ($cellMode) {
            # Row selection mode has no selected cell, so the focused one comes from CurrentCell.
            $cellInfo = $gridRef.CurrentCell
            if (!$cellInfo.IsValid) { return }

            $item = $cellInfo.Item
            $col  = $cellInfo.Column

            if ($null -eq $item -or $null -eq $col) { return }

            $bindPath = if ($col.SortMemberPath) { [string]$col.SortMemberPath }
                        elseif ($col -is [System.Windows.Controls.DataGridBoundColumn] -and $col.Binding -and $col.Binding.Path) { [string]$col.Binding.Path.Path }
                        elseif ($col.ClipboardContentBinding -and $col.ClipboardContentBinding.Path) { [string]$col.ClipboardContentBinding.Path.Path }
                        else { $null }

            # The text a row copy writes, so a list cell copies as a, b and a hashtable as its pairs.
            $text = ''
            if ($bindPath) {
                try { $text = [string](& $exportText -Value (& $cellValue -Row $item -Path $bindPath)) }
                catch { Write-Debug "Cell read failed for '$bindPath': $_" }
            }

            try {
                [System.Windows.Clipboard]::SetText($text)
                $copied.Value = $true
            }
            catch { Write-Debug "Cell copy failed: $_" }
            return
        }

        # Selected rows as CSV, scoped to visible columns so the clipboard matches what's on screen.
        if ($gridRef.SelectedItems.Count -eq 0) { return }
        try {
            $visibleProps = & $getPaths -DataGrid $gridRef
            $sanitize     = ($gridRef.Tag -is [hashtable]) -and ($gridRef.Tag['SanitizeFormulas'] -eq $true)

            $projectionArgs = @{ Items = $gridRef.SelectedItems; Sanitize = $sanitize }
            if ($visibleProps -and $visibleProps.Count -gt 0) { $projectionArgs.Properties = $visibleProps }

            # Out-String tacks on a trailing newline, so this joins the rows instead.
            $text = [string]::Join([Environment]::NewLine, (& $formatRows @projectionArgs | ConvertTo-Csv -NoTypeInformation))
            [System.Windows.Clipboard]::SetText($text)
            $copied.Value = $true
        }
        catch { Write-Debug "Row copy failed: $_" }
    }.GetNewClosure()

    if ($DataGrid.Dispatcher.CheckAccess()) { & $work }
    else { $DataGrid.Dispatcher.Invoke([Action]$work) }

    return $copied.Value
}
