function Add-UiDataGridEmptyCellDecorator {
    <#
    .SYNOPSIS
        Marks null/empty text cells with a diagonal pattern so empty data is easy to see in a longer list of data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        # Sample rows to check which columns have empty values. Columns with no empties skip the decoration (the decorated template is heavier to scroll).
        [object[]]$Items
    )

    # Two brushes: one for the normal row, a brighter one for selected rows so the hatch doesn't dissapear into the selection color.
    if (!$DataGrid.Resources.Contains('__EmptyCellHatch')) {
        $DataGrid.Resources.Add('__EmptyCellHatch',         (Get-UiDataGridEmptyCellHatchBrush))
        $DataGrid.Resources.Add('__EmptyCellHatchSelected', (Get-UiDataGridEmptyCellHatchBrush -SelectedVariant))
    }

    # Set-LastDataColumnStar reads this HashSet to treat decorated columns as data bound.
    # Without it, decorated grids leave a gap right of the last visible column.
    if (!$DataGrid.Resources.Contains('__EmptyCellDecoratedColumns')) {
        $DataGrid.Resources.Add('__EmptyCellDecoratedColumns', [System.Collections.Generic.HashSet[object]]::new())
    }
    $decoratedSet = $DataGrid.Resources['__EmptyCellDecoratedColumns']

    # Editable grid path: Build-UiDataGridColumns flips IsReadOnly to $false on every DataGridTextColumn BEFORE the decorator runs, so the live IsReadOnly check excludes everything.
    # Prefer $DataGrid.Tag.OriginalReadOnlyMap (columnName to bool, populated by Build-UiDataGridColumns from per column ReadOnly=$true entries).
    # Fall back to "every DataGridTextColumn with a binding path is a candidate."
    $originalMap = $null
    if ($DataGrid.Tag -is [hashtable] -and $DataGrid.Tag.Contains('OriginalReadOnlyMap')) {
        $originalMap = $DataGrid.Tag.OriginalReadOnlyMap
    }

    $isOriginallyReadOnly = {
        param($col)
        if ($originalMap) {
            $key = if ($col.SortMemberPath) { [string]$col.SortMemberPath }
                   elseif ($null -ne $col.Header) { [string]$col.Header }
                   else { $null }
            if ($key -and $originalMap.Contains($key)) { return [bool]$originalMap[$key] }
            return $false
        }
        # No upstream map... trust the live column state. An -Editable grid with zero per column ReadOnly entries never writes the map, so defaulting to $true here would apply the hatch template to its editable text columns and kill editing.
        # In testing this hasn't been a problem.
        return [bool]$col.IsReadOnly
    }.GetNewClosure()

    # Collect candidates first - altering Columns while enumerating screws up the collection.
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($col in $DataGrid.Columns) {
        if ($col -isnot [System.Windows.Controls.DataGridTextColumn]) { continue }
        if (!(& $isOriginallyReadOnly $col)) { continue }
        if (!$col.Binding) { continue }
        $bindPath = if ($col.SortMemberPath) { [string]$col.SortMemberPath }
                    elseif ($col.Binding.Path) { [string]$col.Binding.Path.Path }
                    else { $null }
        if (!$bindPath -or $bindPath -eq '.') { continue }
        [void]$candidates.Add(@{ Column = $col; Path = $bindPath })
    }

    # Scan up to 100 rows per column. Columns with no nulls/empties in that window stay plain text and skip the per scroll template overhead.
    # With no -Items, no scan. Swap everything (matches what New-ErrorsTab depends on).
    $toSwap = [System.Collections.Generic.List[object]]::new()
    if ($Items -and $Items.Count -gt 0) {
        $probeBudget = [Math]::Min(100, $Items.Count)
        foreach ($cand in $candidates) {
            $hasEmpty = $false
            for ($i = 0; $i -lt $probeBudget; $i++) {
                try {
                    $val = $Items[$i].($cand.Path)
                    if ($null -eq $val -or ($val -is [string] -and $val -eq '')) {
                        $hasEmpty = $true
                        break
                    }
                }
                catch { Write-Debug "MarkEmptyCells probe '$($cand.Path)' at $i failed: $_" }
            }
            if ($hasEmpty) { [void]$toSwap.Add($cand) }
        }
    }
    else { foreach ($cand in $candidates) { [void]$toSwap.Add($cand) }  }

    if ($toSwap.Count -eq 0) {
        if ($candidates.Count -gt 0) {
            Write-Debug "MarkEmptyCells: probed $($candidates.Count) read-only column(s), none had null/empty values - skipping decoration."
            return
        }
        # Debug, not Warning: a fully editable grid with the default MarkEmptyCells is a normal configuration now that the decorator trusts live IsReadOnly - nothing to hatch is the expected outcome, not a config mistake.
        $editableTexts = @($DataGrid.Columns | Where-Object {
            $_ -is [System.Windows.Controls.DataGridTextColumn] -and !$_.IsReadOnly
        })
        if ($editableTexts.Count -gt 0) {
            Write-Debug "MarkEmptyCells: every text column is editable, nothing to hatch (set ReadOnly = `$true on a column to opt it in)."
        }
        return
    }

    foreach ($entry in $toSwap) {
        $original = $entry.Column
        $bindPath = $entry.Path
        $idx = $DataGrid.Columns.IndexOf($original)
        if ($idx -lt 0) { continue }

        $gridFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.Grid])

        # Hatch defaults to Collapsed. Null and empty string triggers flip it Visible.
        $hatchFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.Border])
        $hatchFactory.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, '__EmptyCellHatch')
        $hatchFactory.SetValue([System.Windows.Controls.Border]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)
        $hatchFactory.SetValue([System.Windows.Controls.Border]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Stretch)
        # No ToolTip here: IsHitTestVisible=$false means the border never gets MouseEnter, so a tooltip on it can never open. The hatch itself is the empty value signal.
        $hatchFactory.SetValue([System.Windows.Controls.Border]::IsHitTestVisibleProperty, $false)

        $hatchStyle = [System.Windows.Style]::new([System.Windows.Controls.Border])
        [void]$hatchStyle.Setters.Add([System.Windows.Setter]::new( [System.Windows.UIElement]::VisibilityProperty, [System.Windows.Visibility]::Collapsed))
        $nullTrigger = [System.Windows.DataTrigger]::new()
        $nullTrigger.Binding = [System.Windows.Data.Binding]::new($bindPath)
        $nullTrigger.Value   = $null

        [void]$nullTrigger.Setters.Add([System.Windows.Setter]::new( [System.Windows.UIElement]::VisibilityProperty, [System.Windows.Visibility]::Visible))
        [void]$hatchStyle.Triggers.Add($nullTrigger)

        $emptyTrigger = [System.Windows.DataTrigger]::new()
        $emptyTrigger.Binding = [System.Windows.Data.Binding]::new($bindPath)
        $emptyTrigger.Value   = ''

        [void]$emptyTrigger.Setters.Add([System.Windows.Setter]::new(
            [System.Windows.UIElement]::VisibilityProperty, [System.Windows.Visibility]::Visible))
        [void]$hatchStyle.Triggers.Add($emptyTrigger)

        # Brighter hatch when the cell is selected. Bind to the immediate DataGridCell ancestor (one step up) instead of walking to DataGridRow - same visual result, much shorter visual tree walk per cell.
        $selBinding = [System.Windows.Data.Binding]::new('IsSelected')
        $selBinding.RelativeSource = [System.Windows.Data.RelativeSource]::new(  [System.Windows.Data.RelativeSourceMode]::FindAncestor,  [System.Windows.Controls.DataGridCell], 1)
        $selBinding.FallbackValue = $false
        $selTrigger = [System.Windows.DataTrigger]::new()
        $selTrigger.Binding = $selBinding
        $selTrigger.Value   = $true

        [void]$selTrigger.Setters.Add([System.Windows.Setter]::new(  [System.Windows.Controls.Border]::BackgroundProperty,  [System.Windows.DynamicResourceExtension]::new('__EmptyCellHatchSelected')))
        [void]$hatchStyle.Triggers.Add($selTrigger)

        $hatchFactory.SetValue([System.Windows.Controls.Border]::StyleProperty, $hatchStyle)
        $gridFactory.AppendChild($hatchFactory)

        # Foreground inherits so the selected row text colour still works.
        $tbFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.TextBlock])
        $tbBinding = [System.Windows.Data.Binding]::new($bindPath)
        
        # Carry the full converter/format chain over. StringFormat alone drops Converter, ConverterParameter, ConverterCulture, FallbackValue, TargetNullValue. Decorating an IValueConverter column without these would silently change displayed cell text.
        if ($original.Binding.StringFormat)       { $tbBinding.StringFormat       = $original.Binding.StringFormat }
        if ($original.Binding.Converter)          { $tbBinding.Converter          = $original.Binding.Converter }
        if ($null -ne $original.Binding.ConverterParameter) { $tbBinding.ConverterParameter = $original.Binding.ConverterParameter }
        if ($original.Binding.ConverterCulture)   { $tbBinding.ConverterCulture   = $original.Binding.ConverterCulture }
        if ($null -ne $original.Binding.FallbackValue)      { $tbBinding.FallbackValue      = $original.Binding.FallbackValue }
        if ($null -ne $original.Binding.TargetNullValue)    { $tbBinding.TargetNullValue    = $original.Binding.TargetNullValue }
        
        $tbFactory.SetBinding([System.Windows.Controls.TextBlock]::TextProperty, $tbBinding)
        $tbFactory.SetValue([System.Windows.Controls.TextBlock]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
        $tbFactory.SetValue([System.Windows.Controls.TextBlock]::TextTrimmingProperty, [System.Windows.TextTrimming]::CharacterEllipsis)
        $gridFactory.AppendChild($tbFactory)

        $tpl = [System.Windows.DataTemplate]::new()
        $tpl.VisualTree = $gridFactory

        # Capture DisplayIndex first - the Remove/Insert below would wipe it back to collection position.
        $originalDi = $original.DisplayIndex

        $newCol = [System.Windows.Controls.DataGridTemplateColumn]::new()
        $newCol.Header         = $original.Header
        $newCol.Width          = $original.Width
        $newCol.MinWidth       = $original.MinWidth
        $newCol.SortMemberPath = $bindPath
        $newCol.IsReadOnly     = $true
        $newCol.CanUserSort    = $original.CanUserSort
        $newCol.Visibility     = $original.Visibility
        $newCol.CellTemplate   = $tpl

        $DataGrid.Columns.RemoveAt($idx)
        $DataGrid.Columns.Insert($idx, $newCol)
        if ($originalDi -ge 0) {
            try { $newCol.DisplayIndex = $originalDi } catch { Write-Debug "Couldn't restore DisplayIndex: $_" }
        }

        # Explicit width registration must follow the swap or Set-LastDataColumnStar treats the replacement's star as stale and wipes it to Auto.
        if ($DataGrid.Resources.Contains('__ExplicitWidthColumns')) {
            $explicitSet = $DataGrid.Resources['__ExplicitWidthColumns']
            if ($explicitSet.Contains($original)) {
                [void]$explicitSet.Remove($original)
                [void]$explicitSet.Add($newCol)
            }
        }

        [void]$decoratedSet.Add($newCol)
    }
}
