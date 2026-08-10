function Invoke-UiDataGridCopyToClipboard {
    <#
    .SYNOPSIS
        Copies selected rows (or focused cell) from a DataGrid to the clipboard, honoring column visibility.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [switch]$Cell
    )

    # DataGrid property reads (SelectedItems, CurrentCell, Tag, Columns) have UI thread affinity, and Clipboard.SetText is STA only.
    # A background runspace would otherwise see SelectedItems as an empty enumeration and the function would return early without copying anything.
    # Dispatch the whole body once instead of piecemeal so one marshal covers all reads + the write.
    $cellMode = [bool]$Cell
    $gridRef  = $DataGrid

    # GetNewClosure drops module private function resolution (same trap as New-ProgressPanel), the row branch silently died in its catch with CommandNotFound.
    # Carry the functions as references.
    $getPaths   = ${function:Get-UiDataGridVisibleColumnPaths}
    $formatRows = ${function:Format-UiDataGridExportRows}

    $work = {
        if ($cellMode) {
            # No "selected cell" in row selection mode - CurrentCell tracks the focused one.
            $cellInfo = $gridRef.CurrentCell
            if (!$cellInfo.IsValid) { return }

            $item = $cellInfo.Item
            $col  = $cellInfo.Column

            if ($null -eq $item -or $null -eq $col) { return }

            $bindPath = if ($col.SortMemberPath) { [string]$col.SortMemberPath }
                        elseif ($col -is [System.Windows.Controls.DataGridBoundColumn] -and $col.Binding -and $col.Binding.Path) { [string]$col.Binding.Path.Path }
                        elseif ($col.ClipboardContentBinding -and $col.ClipboardContentBinding.Path) { [string]$col.ClipboardContentBinding.Path.Path }
                        else { $null }

            $text = ''
            if ($bindPath -eq '.') {
                # Scalar Value column - the item IS the cell. Skipping it copied '' over the user's clipboard.
                $text = [string]$item
            }
            elseif ($bindPath) {
                try {
                    $val = $item.$bindPath
                    if ($null -ne $val) { $text = [string]$val }
                }
                catch { Write-Debug "Cell read failed for '$bindPath': $_" }
            }

            try { [System.Windows.Clipboard]::SetText($text) }
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

            # Out-String tacks on a trailing newline. Join drops it.
            $text = [string]::Join([Environment]::NewLine, (& $formatRows @projectionArgs | ConvertTo-Csv -NoTypeInformation))
            [System.Windows.Clipboard]::SetText($text)
        }
        catch { Write-Debug "Row copy failed: $_" }
    }.GetNewClosure()

    if ($DataGrid.Dispatcher.CheckAccess()) { & $work }
    else { $DataGrid.Dispatcher.Invoke([Action]$work) }
}
