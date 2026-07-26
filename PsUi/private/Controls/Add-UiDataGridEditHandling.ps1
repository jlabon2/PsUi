function Add-UiDataGridEditHandling {
    <#
    .SYNOPSIS
        Per cell editable checks, per column validation, OnCellEdit/OnRowEdit dispatch.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid,

        $Columns,

        [scriptblock]$OnCellEdit,

        [scriptblock]$OnRowEdit
    )

    # Name keyed (preferred) with Header fallback so each edit event isn't rewalking the array.
    # Header keyed alone collided when two columns shared a display header.
    $columnMap = @{}
    if ($Columns) {
        foreach ($entry in @($Columns)) {
            if ($entry -is [hashtable] -or $entry -is [System.Collections.IDictionary]) {
                $key = if ($entry.Name) { [string]$entry.Name }
                       elseif ($entry.Header) { [string]$entry.Header }
                       else { $null }
                if ($key) {
                    # Duplicate key: second definition wins. Almost always a misconfigured column list.
                    if ($columnMap.ContainsKey($key)) { Write-Debug "Add-UiDataGridEditHandling: duplicate column key '$key' overwriting earlier entry" }
                    $columnMap[$key] = $entry
                }
            }
        }
    }

    $rowChanges = [System.Collections.Generic.Dictionary[object, System.Collections.Generic.List[string]]]::new()

    # Preedit snapshots keyed by property name (one cell edits at a time). ComboBox and glyph checkbox editors write the row the moment the user picks (PropertyChanged), so a row read at CellEditEnding compared new against new and the edit vanished... OnCellEdit and the writethrough both saw no change, and a failing Validator couldn't block what had already landed....
    $preEdit = @{}

    # Plain $true/$false Editable is handled at column build. This runs only when Editable is a scriptblock or a property name on the row.
    $Grid.Add_BeginningEdit({
        param($sender, $eventArgs)
        $colHeader = [string]$eventArgs.Column.Header
        $sortPath  = if (![string]::IsNullOrEmpty($eventArgs.Column.SortMemberPath)) { [string]$eventArgs.Column.SortMemberPath } else { '' }
        $row       = $eventArgs.Row.Item

        # Snapshot before the Editable gate...every column needs one, gated or not.
        $snapName = if ($sortPath) { $sortPath } else { $colHeader }
        if ($snapName) {
            try { $preEdit[$snapName] = $row.$snapName } catch { $preEdit[$snapName] = $null }
        }

        $column    = if ($sortPath -and $columnMap.ContainsKey($sortPath)) { $columnMap[$sortPath] } else { $columnMap[$colHeader] }
        if (!$column) { return }
        # Contains, not ContainsKey, column definitions can be any IDictionary and OrderedDictionary has no ContainsKey method.
        if (!$column.Contains('Editable')) { return }
        $editVal = $column.Editable
        if ($editVal -is [bool]) { return }

        $can = $false
        try {
            # ForEach-Object binds $_ to the row. & $editVal $row leaves $_ unset and the natural `{ $_.IsAdmin }` form silently returns falsy.
            if ($editVal -is [scriptblock]) { $can = [bool]($row | ForEach-Object $editVal) }
            elseif ($editVal -is [string]) { $can = [bool]($row.$editVal) }
        }
        catch {
            Write-Debug "Editable check for '$colHeader' threw: $_"
            $can = $false
        }
        if (!$can) { $eventArgs.Cancel = $true }
    }.GetNewClosure())

    $Grid.Add_CellEditEnding({
        param($sender, $eventArgs)
        $colHeader = [string]$eventArgs.Column.Header

        # Auto generated columns leave SortMemberPath as '' (not $null), so the truthy check needs IsNullOrEmpty. Name keyed lookup hits the column hashtable. Falls back to Header when a column was registered by Header only.
        $propName  = if (![string]::IsNullOrEmpty($eventArgs.Column.SortMemberPath)) { [string]$eventArgs.Column.SortMemberPath } else { $colHeader }
        $row       = $eventArgs.Row.Item

        if ($eventArgs.EditAction -eq [System.Windows.Controls.DataGridEditAction]::Cancel) {
            # Esc after a PropertyChanged editor already wrote the row: put the snapshot back so cancel actually cancels. The edit exit template swap reevaluates bindings, so the restored value redraws without a refresh.
            if ($propName -and $preEdit.ContainsKey($propName)) {
                try { $row.$propName = $preEdit[$propName] } catch { Write-Debug "Cancel restore for '$propName' failed: $_" }
                [void]$preEdit.Remove($propName)
            }
            return
        }

        $column    = if ($propName -and $columnMap.ContainsKey($propName)) { $columnMap[$propName] } else { $columnMap[$colHeader] }

        # The edit hasn't written back to the object yet, so read from the editor control directly.
        # Template columns (DatePicker editors, glyph swapped bool checkboxes) hand back a ContentPresenter wrapping the CellEditingTemplate, not the editor - dig the real control out first or those edits commit through the binding without ever reporting.
        $editEl = $eventArgs.EditingElement
        if ($editEl -is [System.Windows.Controls.ContentPresenter]) {
            $walk = [System.Collections.Generic.Stack[object]]::new()
            $walk.Push($editEl)
            while ($walk.Count -gt 0) {
                $node  = $walk.Pop()
                $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($node)
                $hit   = $null
                for ($i = 0; $i -lt $count; $i++) {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($node, $i)
                    if ($child -is [System.Windows.Controls.TextBox] -or
                        $child -is [System.Windows.Controls.CheckBox] -or
                        $child -is [System.Windows.Controls.ComboBox] -or
                        $child -is [System.Windows.Controls.DatePicker]) { $hit = $child; break }
                    $walk.Push($child)
                }
                if ($hit) { $editEl = $hit; break }
            }
        }

        $newValue    = $null
        $editorKnown = $true
        if ($editEl -is [System.Windows.Controls.TextBox])         { $newValue = $editEl.Text }
        elseif ($editEl -is [System.Windows.Controls.CheckBox])    { $newValue = $editEl.IsChecked }
        elseif ($editEl -is [System.Windows.Controls.ComboBox])    { $newValue = $editEl.SelectedItem }
        elseif ($editEl -is [System.Windows.Controls.DatePicker])  { $newValue = $editEl.SelectedDate }
        else { $editorKnown = $false }

        # Still unrecognized after the dig (custom editors): no value to read, so nothing to validate or diff. Treating the $null as an edit fired phantom OnCellEdit against the typed old value on every tab through.
        if (!$editorKnown) { return }

        # Snapshot from BeginningEdit, not a row read - PropertyChanged editors (ComboBox, glyph checkbox) have already written the row by now and a row read says old == new.
        # Peek, don't consume: a validator Cancel keeps the cell in edit mode and the retry commit refires this handler with NO BeginningEdit to rearm the snapshot. Consuming it early meant the retry compared new against new (edit swallowed) and a second invalid pick "rolled back" to the first invalid value.
        $oldValue = $null
        $hadSnapshot = $propName -and $preEdit.ContainsKey($propName)
        if ($hadSnapshot) { $oldValue = $preEdit[$propName] }
        else {
            try { $oldValue = $row.$propName } catch { }
        }

        if ($column -and $column.Validator) {
            # Validator gets the raw editor value (string from TextBox, bool from CheckBox, etc).
            # Coercion happens during binding writeback, which hasn't fired yet. If the validator needs the typed value, coerce inside it.
            $ok = $false
            try { $ok = [bool](& $column.Validator $newValue $row) }
            catch {
                # Write-Error inside a UI callback has nowhere to go and just crashes. Use Write-Debug.
                Write-Debug "Validator for '$colHeader' threw: $($_.Exception.Message)"
                $ok = $false
            }
            if (!$ok) {
                # PropertyChanged editors already wrote the row - restore the snapshot so a failing Validator actually blocks the edit instead of blessing it after the fact.
                try { $row.$propName = $oldValue } catch { Write-Debug "Validator rollback for '$propName' failed: $_" }
                $eventArgs.Cancel = $true
                return
            }
        }

        # Commit is going through and the edit session ends here, so the snapshot is spent.
        if ($hadSnapshot) { [void]$preEdit.Remove($propName) }

        # No change, user tabbed through without editing. Skip accumulation and dispatch.
        # String normalized compare: $newValue is the editor's raw string but $oldValue keeps the row's type, and '5'.Equals(5) is $false - every untouched int cell counted as an edit.
        # -ceq, not -eq: case insensitive compare swallowed 'abc' to 'ABC' edits entirely.
        $valuesEqual = ($null -eq $newValue -and $null -eq $oldValue) -or
                       ($null -ne $newValue -and ([string]$newValue -ceq [string]$oldValue))
        if ($valuesEqual) { return }

        if (!$rowChanges.ContainsKey($row)) { $rowChanges[$row] = [System.Collections.Generic.List[string]]::new() }
        if ($rowChanges[$row] -notcontains $propName) { [void]$rowChanges[$row].Add($propName) }

        # Defer so the binding writeback lands before the handler reads the row. Items.Refresh moved to RowEditEnding - refreshing per cell reruns the filter over every row.
        if ($OnCellEdit) {
            $deferredRow     = $row
            $deferredCol     = $propName
            $deferredNew     = $newValue
            $deferredOld     = $oldValue
            $deferredHandler = $OnCellEdit

            $deferred = {
                try { & $deferredHandler $deferredRow $deferredCol $deferredNew $deferredOld }
                catch { Write-Debug "OnCellEdit failed: $($_.Exception.Message)" }
            }.GetNewClosure()

            [void]$sender.Dispatcher.BeginInvoke([Action]$deferred, [System.Windows.Threading.DispatcherPriority]::Background)
        }
    }.GetNewClosure())

    # PSCustomObject has no rollback? Even on cancel, committed cells already wrote. Clear the changed columns either way so entries don't leak into the next row.
    $Grid.Add_RowEditEnding({
        param($sender, $eventArgs)
        $row = $eventArgs.Row.Item
        $isCancel = $eventArgs.EditAction -eq [System.Windows.Controls.DataGridEditAction]::Cancel

        $changedCols = @()
        if ($rowChanges.ContainsKey($row)) {
            $changedCols = @($rowChanges[$row])
            [void]$rowChanges.Remove($row)
        }

        # Refresh fires on both commit and cancel. PSCustomObject has no rollback so committed cells already wrote. Mirrors across cells need the refresh to catch up. Items.Refresh drops SelectedItem/SelectedItems - snapshot and restore around it. Filter cache is also stale.
        if ($changedCols.Count -gt 0) {
            # Owned grids bake _SearchText on the row as a PSNoteProperty at snapshot time.
            # The new cell value just landed on the row, but the index is the concatenation from before the edit. New-UiDataGridFilterController's predicate reads _SearchText FIRST before the searchCache - so clearing the cache below isn't enough. The edited row would still match the OLD text on the next Refresh. Rebuild in place (guarded: rows without the property are user owned ItemsSource objects and stay unmutated).
            try {
                if ($row.PSObject.Properties['_SearchText']) { Add-UiDataGridSearchText -PsObject $row -Force }
            }
            catch { Write-Debug "Row _SearchText rebuild after edit failed: $_" }

            # Display rows are snapshot copies. The original object rides along as _BaseObject.
            # Push committed values through so -PassThru (which unwraps _BaseObject) reflects the edit. Runs on cancel too - PSCustomObject has no rollback, committed cells already wrote to the display row.
            try {
                $baseProp = $row.PSObject.Properties['_BaseObject']
                $base = if ($baseProp) { $baseProp.Value } else { $null }
                if ($null -ne $base -and ![object]::ReferenceEquals($base, $row)) {
                    if ($base -is [System.Collections.IDictionary]) {
                        foreach ($colName in $changedCols) {
                            if ($base.Contains($colName)) { $base[$colName] = $row.$colName }
                        }
                    }
                    else {
                        foreach ($colName in $changedCols) {
                            $srcProp = $row.PSObject.Properties[$colName]
                            $dstProp = $base.PSObject.Properties[$colName]
                            if ($srcProp -and $dstProp -and $dstProp.IsSettable) { $dstProp.Value = $srcProp.Value }
                        }
                    }
                }
            }
            catch { Write-Debug "Edit write-through to _BaseObject failed: $_" }

            $refreshGrid    = $sender
            $savedSelection = @($refreshGrid.SelectedItems)
            $savedCurrent   = $refreshGrid.CurrentItem
            $refreshAction = {
                try {
                    $refreshGrid.Items.Refresh()
                    # SelectedItems.Add throws on Single mode grids. SelectedItem assignment is the legal form there.
                    if ($refreshGrid.SelectionMode -eq [System.Windows.Controls.DataGridSelectionMode]::Single) {
                        if ($savedSelection.Count -gt 0 -and $null -ne $savedSelection[0]) { $refreshGrid.SelectedItem = $savedSelection[0] }
                    }
                    else {
                        foreach ($sel in $savedSelection) {
                            if ($null -ne $sel -and !$refreshGrid.SelectedItems.Contains($sel)) {
                                [void]$refreshGrid.SelectedItems.Add($sel)
                            }
                        }
                    }
                    if ($null -ne $savedCurrent) { $refreshGrid.CurrentItem = $savedCurrent }
                }
                catch { Write-Debug "RowEditEnding refresh failed: $_" }
            }.GetNewClosure()
            [void]$sender.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]$refreshAction)

            # Filter box is suppressed under -NoFilter, so the tag has no FilterBox and the lookup finds nothing.
            try {
                $gridTag = $refreshGrid.Tag
                $filterBox = if ($gridTag -is [hashtable] -and $gridTag.FilterBox) { $gridTag.FilterBox } else { $null }
                if ($filterBox) {
                    $filterState = $filterBox.Tag
                    if ($filterState -and $filterState.ClearSearchCache) { & $filterState.ClearSearchCache }
                }
            }
            catch { Write-Debug "Filter cache invalidation skipped: $_" }
        }

        if ($isCancel) { return }

        if ($OnRowEdit -and $changedCols.Count -gt 0) {
            # Defer so a slow user callback doesn't block the row commit. Same as OnCellEdit.
            $deferredRow      = $row
            $deferredCols     = $changedCols
            $deferredRowHand  = $OnRowEdit
            $deferredRowSb    = {
                try { & $deferredRowHand $deferredRow $deferredCols }
                catch { Write-Debug "OnRowEdit failed: $($_.Exception.Message)" }
            }.GetNewClosure()
            [void]$sender.Dispatcher.BeginInvoke([Action]$deferredRowSb, [System.Windows.Threading.DispatcherPriority]::Background)
        }
    }.GetNewClosure())
}
