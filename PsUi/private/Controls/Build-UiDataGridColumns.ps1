function Build-UiDataGridColumns {
    <#
    .SYNOPSIS
        Builds DataGrid columns. -Columns: omit for auto, string[] to filter, hashtable[] for explicit definitions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [object[]]$Items,

        $Columns,

        [switch]$Editable,

        [switch]$DefaultPropertiesOnly,

        [switch]$HideEmptyColumns,

        [switch]$NoStretchLastColumn,

        [switch]$VisualValues,

        [switch]$MarkEmptyCells
    )

    # No data. Skip column build entirely. This will be rerun on item arrival. $null check, not truthiness: a lone falsy scalar (@(0)/@('')/@($false)) unwraps to a falsy value under !$Items.
    if ($null -eq $Items -or $Items.Count -eq 0) {
        return @{ AllProperties = @(); DefaultProperties = @(); PopulatedProperties = @() }
    }

    # Column kind first. Explicit hashtable columns are user defined and don't depend on the row's properties, so the property less early return below must not gate them.
    $specKind = 'Auto'
    if ($null -ne $Columns) {
        $arr = @($Columns)
        if ($arr.Count -gt 0) {
            $allStrings = $true
            foreach ($entry in $arr) {
                if ($entry -isnot [string]) { $allStrings = $false; break }
            }
            $specKind = if ($allStrings) { 'Filter' } else { 'Explicit' }
        }
    }

    # Column generation keys off the first row's properties. A first row with nothing to show (an empty PSCustomObject) built zero columns and on the seed path rearmed forever, so a later row with real data never got to seed. Skip to the first row that's actually buildable: a scalar (its own Value column) or an object with a non underscore property.
    $firstItem = $Items[0]
    $foundBuildable = $false
    foreach ($candidate in $Items) {
        if ($null -eq $candidate) { continue }
        if ($candidate -is [string] -or $candidate -is [System.ValueType]) { $firstItem = $candidate; $foundBuildable = $true; break }
        foreach ($prop in $candidate.PSObject.Properties) {
            if (!$prop.Name.StartsWith('_')) { $firstItem = $candidate; $foundBuildable = $true; break }
        }
        if ($foundBuildable) { break }
    }

    # Nothing renderable yet (every row a property less object) on a property derived path (Auto/Filter). Bail BEFORE any BeginInit so the grid's init state stays clean - a build that opens BeginInit and errors off pipeline (the seed runs on a Background dispatch) skips its finally EndInit, and the next build then throws "nested BeginInit". Returning empty rearms the seed for a later row. Explicit columns come from the hashtable, so they build regardless.
    if (!$foundBuildable -and $specKind -in 'Auto', 'Filter') {
        return @{ AllProperties = @(); DefaultProperties = @(); PopulatedProperties = @() }
    }

    # Explicit columns can reach here with no buildable row (an -ItemsSource collection whose first element is $null - the ItemsSource path doesn't null filter). $firstItem is then still $Items[0] = $null, and New-UiDataGridTextColumn's -FirstItem is Mandatory and rejects $null, throwing out of the build. Fall back to an empty object - the type probe finds nothing and the explicit column definition supplies Name/Type/etc.
    if ($null -eq $firstItem) { $firstItem = [PSCustomObject]@{} }

    Write-Debug "Build-UiDataGridColumns kind=$specKind, items=$($Items.Count), editable=$Editable"

    # Auto and Filter share the Add-DataGridColumns build path (array popups, alias resolution, DefaultDisplayPropertySet fallback). Visibility tweaks happen after.
    if ($specKind -in 'Auto', 'Filter') {
        $colResult    = Add-DataGridColumns -DataGrid $DataGrid -FirstItem $firstItem
        $allProps     = @($colResult.AllProperties)
        $defaultProps = @($colResult.DefaultProperties)

        if ($specKind -eq 'Filter') {
            # Two passes, one to set visibility on all columns first, then reorder the visible ones.
            # One pass screws up positions. Hiding items and reordering items seem to fight each other.
            $requested = @($Columns)
            $headerToCol = @{}

            foreach ($col in $DataGrid.Columns) {
                $hdr = if ($null -ne $col.Header) { [string]$col.Header } else { '' }
                if ($hdr) { $headerToCol[$hdr] = $col }
                $col.Visibility = if ($hdr -and ($requested -contains $hdr)) { [System.Windows.Visibility]::Visible }
                else { [System.Windows.Visibility]::Collapsed }
            }

            $displayIndex = 0
            foreach ($wanted in $requested) {
                $col = $headerToCol[[string]$wanted]
                if ($col) {
                    $col.DisplayIndex = $displayIndex
                    $displayIndex++
                }
            }
        }
        elseif (!$DefaultPropertiesOnly) {
            # Add-DataGridColumns auto hides non default props. Reveal them all.
            foreach ($col in $DataGrid.Columns) { $col.Visibility = [System.Windows.Visibility]::Visible }
        }

        # HideEmptyColumns runs last so it wins over the above.
        $populated = $allProps
        if ($HideEmptyColumns) {
            $populated = Get-PopulatedProperties -Items $Items -PropertyNames $allProps
            foreach ($col in $DataGrid.Columns) {
                # Scalar grids bind their one Value column to '.'; Raw strings/ints have no such property to probe and hiding it blanked the whole grid.
                $colPath = if ($col -is [System.Windows.Controls.DataGridBoundColumn] -and $col.Binding -and $col.Binding.Path) { [string]$col.Binding.Path.Path } else { $null }
                if ($colPath -eq '.') { continue }
                if ($col.Header -and !$populated.Contains([string]$col.Header)) {
                    $col.Visibility = [System.Windows.Visibility]::Collapsed
                }
            }
        }

        # Per column ReadOnly is an Explicit columns concept. A hashtable in -Columns always classifies as Explicit above, so the Auto/Filter branch only ever sees strings or nothing. There's nothing to honor here. The Explicit path tracks OriginalReadOnlyMap itself.
        # Array template columns stay readonly.
        if ($Editable) {
            $editorStyle = Get-UiDataGridTextEditorStyle
            $probeMax    = [Math]::Min(10, $Items.Count)
            # Snapshot the collection, the typed branch below swaps columns in place.
            foreach ($col in @($DataGrid.Columns)) {
                if ($col -isnot [System.Windows.Controls.DataGridTextColumn]) { continue }

                # Real property name for the value type probe and write back binding below. SortMemberPath, Header as fallback.
                $propName = if ($col.SortMemberPath) { [string]$col.SortMemberPath } else { [string]$col.Header }

                # Scalar rows bind '.', theres no property to write back to, so editing stays off.
                # Rebinding to the 'Value' header path blanked the whole grid.
                $scalarPath = if ($col.Binding -and $col.Binding.Path) { [string]$col.Binding.Path.Path } else { $null }
                if ($scalarPath -eq '.') { continue }

                # Dotted property names pass the literal member probe below, but WPF's path grammar reads 'Is.Active' as a nested path (Is, then Active) and never resolves.
                # Readonly beats fake editable.
                if ($propName -match '\.') {
                    Write-Debug "Editable sweep: '$propName' contains a dot; WPF can't path-bind it - staying read-only."
                    continue
                }

                $sample = $null
                for ($i = 0; $i -lt $probeMax; $i++) {
                    try {
                        $candidate = $Items[$i].$propName
                        if ($null -ne $candidate) { $sample = $candidate; break }
                    }
                    catch { Write-Debug "Editable sweep probe failed for '$propName' at $i`: $_" }
                }

                # Bool / enum / datetime route through the explicit path builder, which picks the checkbox, the enum dropdown, or the DatePicker template. The glyph converter below then upgrades editable checkboxes exactly like explicit columns. Flipping these to editable TEXT wrote raw strings over typed values on commit (PSCustomObject notes are untyped, so the binding never coerces).
                if ($sample -is [bool] -or $sample -is [datetime] -or ($null -ne $sample -and $sample.GetType().IsEnum)) {
                    $colDef = @{ Header = [string]$col.Header }
                    if ($col.Binding -and $col.Binding.StringFormat) { $colDef['Format'] = [string]$col.Binding.StringFormat }
                    $typedCol = New-UiDataGridTextColumn -Name $propName -FirstItem $firstItem -SampleItems $Items -Column $colDef -Editable
                    $typedCol.Width       = $col.Width
                    $typedCol.MinWidth    = $col.MinWidth
                    $typedCol.Visibility  = $col.Visibility
                    $typedCol.CanUserSort = $col.CanUserSort

                    # Remove/Insert resets DisplayIndex to the collection position - restore it.
                    $di  = $col.DisplayIndex
                    $idx = $DataGrid.Columns.IndexOf($col)
                    $DataGrid.Columns.RemoveAt($idx)
                    $DataGrid.Columns.Insert($idx, $typedCol)
                    if ($di -ge 0) {
                        try { $typedCol.DisplayIndex = $di } catch { Write-Debug "DisplayIndex restore failed: $_" }
                    }
                    continue
                }

                # Complex objects and all null probes stay readonly, matching the explicit path's downgrade - a raw text editor over these writes strings into the object.
                # decimal isn't a .NET primitive (it's a struct), so financial columns fell through to readonly while int/double edited fine - call it out explicitly.
                if ($null -eq $sample -or !($sample -is [string] -or $sample -is [decimal] -or $sample.GetType().IsPrimitive)) {
                    Write-Debug "Editable sweep: '$propName' ($(if ($null -ne $sample) { $sample.GetType().Name } else { 'null probe' })) unsupported for text editing; staying read-only."
                    continue
                }

                $col.IsReadOnly = $false
                # Bind to SortMemberPath (the real property name) so two way edits hit the right property even when Header is a display alias.
                $newBinding    = [System.Windows.Data.Binding]::new($propName)
                $newBinding.Mode = [System.Windows.Data.BindingMode]::TwoWay
                $newBinding.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::LostFocus
                $col.Binding = $newBinding
                $col.EditingElementStyle = $editorStyle
            }
        }

        if ($VisualValues) {
            Convert-UiDataGridBoolColumnsToGlyph -DataGrid $DataGrid -Items $Items
        }

        # MarkEmptyCells runs AFTER bool to glyph conversion. Glyph templates handle null via the em dash already. Only surviving text columns need the hatch.
        if ($MarkEmptyCells) { Add-UiDataGridEmptyCellDecorator -DataGrid $DataGrid -Items $Items }

        Set-LastDataColumnStar -DataGrid $DataGrid -Skip:$NoStretchLastColumn

        return @{
            AllProperties       = $allProps
            DefaultProperties   = $defaultProps
            PopulatedProperties = $populated
        }
    }

    # Explicit hashtable[]... every column ends up built by hand below.
    $allProps     = [System.Collections.Generic.List[string]]::new()
    $defaultProps = [System.Collections.Generic.List[string]]::new()
    $roNames      = [System.Collections.Generic.List[string]]::new()
    # Column lookup by Name. HideEmptyColumns matches populated property names, but a user supplied Header (Header='User ID', Name='UserId') can diverge from Name and a Header keyed lookup silently hides populated columns.
    $nameToCol    = @{}

    # Batch column adds into one layout pass. N adds otherwise fire MeasureOverride N times.
    # No try/finally: off pipeline (a -NoAsync Action is a WPF event delegate, no pipeline) PS's CheckActionPreference NREs on try block exit. trap rebalances BeginInit on error. Tail EndInit covers success. Same BeginInit/trap pattern as the auto path in Add-DataGridColumns.
    $DataGrid.BeginInit()
    trap {
        $DataGrid.EndInit()
        Write-Debug "Build-UiDataGridColumns build failed: $($_.Exception.Message)"
        break
    }

    foreach ($entry in @($Columns)) {

        # Reset per iteration - `continue` inside the switch default below exits the switch, not this foreach, so a stale $col from the prior round would otherwise survive into the Add() and WPF throws "already in another collection"
        $col = $null

        # Bare strings in a mixed array become plain text columns.
        if ($entry -is [string]) {
            $textCol = New-UiDataGridTextColumn -Name $entry -FirstItem $firstItem -SampleItems $Items -Editable:$Editable
            [void]$DataGrid.Columns.Add($textCol)
            [void]$allProps.Add($entry)
            [void]$defaultProps.Add($entry)
            $nameToCol[$entry] = $textCol
            continue
        }

        $column = $entry
        if ($column -isnot [hashtable] -and $column -isnot [System.Collections.IDictionary]) {
            Write-Warning "Build-UiDataGridColumns: skipping unrecognized column entry of type $($column.GetType().FullName)"
            continue
        }

        $type = if ($column.Type) { [string]$column.Type } else { 'Text' }
        $name = if ($column.Name) { [string]$column.Name } else { $null }

        switch ($type) {
            'Button' { $col = New-UiDataGridCellControlColumn -Column $column -CellType 'Button' }
            'Toggle' { $col = New-UiDataGridCellControlColumn -Column $column -CellType 'Toggle' }
            'Link'   { $col = New-UiDataGridCellControlColumn -Column $column -CellType 'Link'   }
            default  {
                if (!$name) {
                    Write-Warning "Build-UiDataGridColumns: text-column hashtable missing -Name; skipping."
                    continue
                }
                $col = New-UiDataGridTextColumn -Name $name -FirstItem $firstItem -SampleItems $Items -Column $column -Editable:$Editable
            }
        }

        if (!$col) { continue }
        [void]$DataGrid.Columns.Add($col)

        # User specified widths must survive Set-LastDataColumnStar's stale star reset without this set, an explicit Width='*' on any column other than the rightmost got wiped to Auto.
        if ($column.Contains('Width') -and $null -ne $column['Width']) {
            if (!$DataGrid.Resources.Contains('__ExplicitWidthColumns')) {
                $DataGrid.Resources['__ExplicitWidthColumns'] = [System.Collections.Generic.HashSet[object]]::new()
            }
            [void]$DataGrid.Resources['__ExplicitWidthColumns'].Add($col)
        }

        if ($name) {
            [void]$allProps.Add($name)
            [void]$defaultProps.Add($name)
            $nameToCol[$name] = $col
        }

        # Track per column ReadOnly=$true text columns so the decorator can tell user RO from empty cell RO.
        if ($type -eq 'Text' -or !$column.Type) {
            if ($column.Contains('ReadOnly') -and $column['ReadOnly']) {
                $roKey = if ($name) { $name } elseif ($column.Header) { [string]$column.Header } else { $null }
                if ($roKey) { [void]$roNames.Add($roKey) }
            }
        }
    }

    $DataGrid.EndInit()

    # Same -Editable gate as the auto path. The map only means something when the sweep has flipped IsReadOnly out from under the decorator.
    if ($Editable -and $roNames.Count -gt 0) {
        if ($DataGrid.Tag -isnot [hashtable]) { $DataGrid.Tag = @{} }
        if (!$DataGrid.Tag.Contains('OriginalReadOnlyMap')) { $DataGrid.Tag['OriginalReadOnlyMap'] = @{} }
        foreach ($roKey in $roNames) { $DataGrid.Tag['OriginalReadOnlyMap'][$roKey] = $true }
    }

    # HideEmptyColumns for the explicit hashtable path too (only matters for text columns).
    # Match by Name via $nameToCol. Header can be a friendly label string that won't appear in Get-PopulatedProperties (which... yeah, keys on property names).
    $populated = @($allProps)
    if ($HideEmptyColumns -and $allProps.Count -gt 0) {
        $populated = Get-PopulatedProperties -Items $Items -PropertyNames $allProps
        foreach ($mappedName in $nameToCol.Keys) {
            if (!$populated.Contains($mappedName)) {
                $nameToCol[$mappedName].Visibility = [System.Windows.Visibility]::Collapsed
            }
        }
    }

    if ($VisualValues) { Convert-UiDataGridBoolColumnsToGlyph -DataGrid $DataGrid -Items $Items }

    # Pass $Items so the decorator probes for nulls instead of templating every text column.
    if ($MarkEmptyCells) { Add-UiDataGridEmptyCellDecorator -DataGrid $DataGrid -Items $Items }

    Set-LastDataColumnStar -DataGrid $DataGrid -Skip:$NoStretchLastColumn

    return @{
        AllProperties       = @($allProps)
        DefaultProperties   = @($defaultProps)
        PopulatedProperties = $populated
    }
}
