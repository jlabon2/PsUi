function Convert-UiDataGridBoolColumnsToGlyph {
    <#
    .SYNOPSIS
        Swaps boolean columns for glyph columns. Checkmark for true, X for false, dash for null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Items
    )

    # Bools only for now. Probe is cheap so extending to other types later is fine. This'll be fleshed out at some point, this is more to nail the concept first.
    if ($null -eq $Items -or $Items.Count -eq 0) { return }

    $iconFont   = [PsUi.ModuleContext]::ActiveIconFontFamily
    $glyphTrue  = [PsUi.ModuleContext]::GetIcon('CheckMark')

    if (!$glyphTrue) { $glyphTrue = [PsUi.ModuleContext]::GetIcon('Accept') }
    if (!$glyphTrue) { $glyphTrue = [string][char]0x2713 }

    $glyphFalse = [PsUi.ModuleContext]::GetIcon('Cancel')
    if (!$glyphFalse) { $glyphFalse = [PsUi.ModuleContext]::GetIcon('ChromeClose') }
    if (!$glyphFalse) { $glyphFalse = [string][char]0x2715 }

    # Dash (technically an emdash) renders identically in MDL2 and Fluent, so no fallback needed.
    $glyphNull  = [string][char]0x2014

    # Null state font is Segoe UI. Icon fonts have no dash glyph. Single allocation.
    $textFont = [System.Windows.Media.FontFamily]::new('Segoe UI')

    # Sample up to 10 rows per column for a non null value. A null first row would mistype the column.
    $probeBudget = [Math]::Min(10, $Items.Count)
    $toSwap = [System.Collections.Generic.List[object]]::new()
    foreach ($col in $DataGrid.Columns) {

        # Autodetected text columns whose values turn out to be bools, and checkbox columns the user declared explicitly. Both get glyphs. Only the checkbox keeps a native control underneath for doubleclick to edit.
        $isTextRO   = $col -is [System.Windows.Controls.DataGridTextColumn] -and $col.IsReadOnly
        $isCheckBox = $col -is [System.Windows.Controls.DataGridCheckBoxColumn]
        if (!$isTextRO -and !$isCheckBox) { continue }

        # SortMemberPath holds the actual property name. Header is sometimes a display alias, and popup columns rebind the path internally, so Binding.Path isn't reliable here either.
        $bindPath = if ($col.SortMemberPath) { [string]$col.SortMemberPath }
                    elseif ($col.Binding -and $col.Binding.Path) { [string]$col.Binding.Path.Path }
                    else { $null }
        if (!$bindPath) { continue }

        # Dotted or bracketed names pass the literal item below, but the DataTrigger and checkbox bindings parse 'Is.Active' as a path (Is into Active) and 'Active[0]' as an indexer. Neither resolves, and every row rendered the null dash over real data.
        # Skip. The column keeps its plain text cell. Same guard as New-UiDataGridTextColumn.
        if ($bindPath -match '[.\[]') { continue }

        # A CheckBox column is bool by definition so theres no point probing values for the type.
        $sample = $null
        if ($isCheckBox) { $sample = $true }
        else {
            for ($i = 0; $i -lt $probeBudget; $i++) {
                try {
                    $candidate = $Items[$i].$bindPath
                    if ($null -ne $candidate) { $sample = $candidate; break }
                }
                catch { Write-Debug "Glyph type probe failed for '$bindPath' at $i`: $_" }
            }
        }

        if ($sample -is [bool]) {
            [void]$toSwap.Add(@{ Column = $col; Path = $bindPath; IsCheckBox = $isCheckBox })
        }
    }

    # Explicit width registrations must follow the swap or Set-LastDataColumnStar treats the replacement's star as stale and wipes it to Auto. Statement if, not if expression: a one element HashSet routed through an if expression unwraps to the bare element.
    $explicitSet = $null
    if ($DataGrid.Resources.Contains('__ExplicitWidthColumns')) { $explicitSet = $DataGrid.Resources['__ExplicitWidthColumns'] }

    foreach ($entry in $toSwap) {

        $original   = $entry.Column
        $bindPath   = $entry.Path
        $isCheckBox = [bool]$entry.IsCheckBox
        $idx        = $DataGrid.Columns.IndexOf($original)
        if ($idx -lt 0) { continue }

        # The Border centres the glyph in the cell - a bare TextBlock only aligns its own text.
        $borderFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.Border])
        $borderFactory.SetValue([System.Windows.Controls.Border]::BackgroundProperty, [System.Windows.Media.Brushes]::Transparent)
        $borderFactory.SetValue([System.Windows.Controls.Border]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)
        $borderFactory.SetValue([System.Windows.Controls.Border]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Stretch)

        $tbFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.TextBlock])
        $tbFactory.SetValue([System.Windows.Controls.TextBlock]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
        $tbFactory.SetValue([System.Windows.Controls.TextBlock]::VerticalAlignmentProperty,   [System.Windows.VerticalAlignment]::Center)

        # Null state renders in $textFont (resolved above the loop). True/false triggers below swap to the icon font for check/cross.
        $style = [System.Windows.Style]::new([System.Windows.Controls.TextBlock])
        [void]$style.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::TextProperty, [string]$glyphNull))
        [void]$style.Setters.Add([System.Windows.Setter]::new( [System.Windows.Controls.TextBlock]::ForegroundProperty, [System.Windows.DynamicResourceExtension]::new('SecondaryTextBrush')))
        [void]$style.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::FontFamilyProperty, $textFont))
        [void]$style.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::FontSizeProperty, [double]14))
        [void]$style.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::FontWeightProperty, [System.Windows.FontWeights]::SemiBold))

        $trueTrigger = [System.Windows.DataTrigger]::new()
        $trueTrigger.Binding = [System.Windows.Data.Binding]::new($bindPath)
        $trueTrigger.Value   = $true
        [void]$trueTrigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::TextProperty, [string]$glyphTrue))
        [void]$trueTrigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::FontFamilyProperty, $iconFont))
        [void]$trueTrigger.Setters.Add([System.Windows.Setter]::new( [System.Windows.Controls.TextBlock]::ForegroundProperty,  [System.Windows.DynamicResourceExtension]::new('SuccessBrush')))
        [void]$style.Triggers.Add($trueTrigger)

        $falseTrigger = [System.Windows.DataTrigger]::new()
        $falseTrigger.Binding = [System.Windows.Data.Binding]::new($bindPath)
        $falseTrigger.Value   = $false
        [void]$falseTrigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::TextProperty, [string]$glyphFalse))
        [void]$falseTrigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::FontFamilyProperty, $iconFont))
        [void]$falseTrigger.Setters.Add([System.Windows.Setter]::new(  [System.Windows.Controls.TextBlock]::ForegroundProperty,  [System.Windows.DynamicResourceExtension]::new('ErrorBrush')))
        [void]$style.Triggers.Add($falseTrigger)

        # Selected row needs a different glyph color or the green/red vanishes into the selection brush.
        $selTrigger = [System.Windows.DataTrigger]::new()
        $selBinding = [System.Windows.Data.Binding]::new('IsSelected')
        $selBinding.RelativeSource = [System.Windows.Data.RelativeSource]::new(
            [System.Windows.Data.RelativeSourceMode]::FindAncestor,
            [System.Windows.Controls.DataGridRow], 1)
        $selTrigger.Binding = $selBinding
        $selTrigger.Value   = $true
        [void]$selTrigger.Setters.Add([System.Windows.Setter]::new( [System.Windows.Controls.TextBlock]::ForegroundProperty,  [System.Windows.DynamicResourceExtension]::new('SelectionTextBrush')))
        [void]$style.Triggers.Add($selTrigger)

        $tbFactory.SetValue([System.Windows.Controls.TextBlock]::StyleProperty, $style)
        $borderFactory.AppendChild($tbFactory)

        $tpl = [System.Windows.DataTemplate]::new()
        $tpl.VisualTree = $borderFactory

        # Grab DisplayIndex before Remove/Insert - that operation resets it to the collection position.
        $originalDi = $original.DisplayIndex

        $newCol = [System.Windows.Controls.DataGridTemplateColumn]::new()
        $newCol.Header         = $original.Header
        $newCol.Width          = $original.Width
        $newCol.MinWidth       = $original.MinWidth
        $newCol.SortMemberPath = $bindPath
        $newCol.IsReadOnly     = $original.IsReadOnly
        $newCol.CanUserSort    = $original.CanUserSort
        $newCol.Visibility     = $original.Visibility
        $newCol.CellTemplate   = $tpl

        # Editable bools... originally DataGridCheckBoxColumn, keep a themed CheckBox in the editing template. Glyph in display mode, native checkbox on doubleclick or F2.
        if ($isCheckBox -and !$original.IsReadOnly) {
            $editTpl   = [System.Windows.DataTemplate]::new()
            $cbFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.CheckBox])
            $cbFactory.SetValue([System.Windows.Controls.CheckBox]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
            $cbFactory.SetValue([System.Windows.Controls.CheckBox]::VerticalAlignmentProperty,   [System.Windows.VerticalAlignment]::Center)
            $cbFactory.SetValue([System.Windows.Controls.CheckBox]::CursorProperty,              [System.Windows.Input.Cursors]::Hand)
            $cbFactory.SetValue([System.Windows.Controls.CheckBox]::StyleProperty, (Get-UiDataGridCheckBoxStyle))

            $cbBinding                     = [System.Windows.Data.Binding]::new($bindPath)
            $cbBinding.Mode                = [System.Windows.Data.BindingMode]::TwoWay
            $cbBinding.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::PropertyChanged
            $cbFactory.SetBinding([System.Windows.Controls.CheckBox]::IsCheckedProperty, $cbBinding)

            $editTpl.VisualTree      = $cbFactory
            $newCol.CellEditingTemplate = $editTpl
        }

        $DataGrid.Columns.RemoveAt($idx)
        $DataGrid.Columns.Insert($idx, $newCol)
        if ($originalDi -ge 0) {
            try   { $newCol.DisplayIndex = $originalDi }
            catch { Write-Debug "Couldn't restore DisplayIndex: $_" }
        }
        if ($explicitSet -and $explicitSet.Contains($original)) {
            [void]$explicitSet.Remove($original)
            [void]$explicitSet.Add($newCol)
        }
    }
}
