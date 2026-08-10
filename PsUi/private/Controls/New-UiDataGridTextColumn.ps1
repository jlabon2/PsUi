function New-UiDataGridTextColumn {
    <#
    .SYNOPSIS
        Builds a DataGrid column. Probes row values to pick Text/CheckBox/ComboBox/DatePicker when editable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$FirstItem,

        [hashtable]$Column,

        [switch]$Editable,

        # Extra rows Build-UiDataGridColumns hands in so a column whose first row is null doesn't fall back to readonly Text just because row 0 happens to be empty.
        [object[]]$SampleItems
    )

    $header = if ($Column -and $Column.Header) { [string]$Column.Header } else { $Name }

    # ReadOnly = $true wins outright. Otherwise per column Editable (bool, scriptblock, or property name) overrides the grid wide -Editable. Anything nonboolean will be editable here. The actual percell check runs later.
    $perColRO = $Column -and $Column.ContainsKey('ReadOnly') -and $Column['ReadOnly']
    $isEditable = [bool]$Editable
    
    if ($Column -and $Column.ContainsKey('Editable')) {
        $editVal = $Column['Editable']
        if ($editVal -is [bool])         { $isEditable = $editVal }
        elseif ($editVal -is [scriptblock] -or $editVal -is [string]) { $isEditable = $true }
    }

    if ($perColRO) { $isEditable = $false }
    $editorType = if ($Column -and $Column.EditorType) { [string]$Column.EditorType } else { 'Auto' }

    # Probe rows to pick an editor type. Only runs when EditorType='Auto'. First non null wins, so an enum/datetime column with a null in row 0 still resolves correctly. Cap at 10 rows so a 100k row seed doesn't pay a column build cost proportional to the data size.
    $valueType = $null

    $probeSet  = @(if ($SampleItems) { $SampleItems } else { $FirstItem })
    $probeMax  = [Math]::Min(10, $probeSet.Count)
    for ($i = 0; $i -lt $probeMax; $i++) {

        $row = $probeSet[$i]
        if ($null -eq $row) { continue }
        try {
            $prop = $row.PSObject.Properties[$Name]
            if ($null -eq $prop) { continue }
            $sampleVal = $prop.Value
            if ($null -ne $sampleVal) { $valueType = $sampleVal.GetType(); break }
        }
        catch { Write-Debug "Type probe failed for '$Name' at row $i`: $_" }
    }

    $resolved = $editorType
    
    if ($isEditable -and $editorType -eq 'Auto') {
        if ($valueType -eq [bool])                       { $resolved = 'CheckBox' }
        elseif ($valueType -and $valueType.IsEnum)       { $resolved = 'ComboBox' }
        elseif ($valueType -eq [datetime])               { $resolved = 'DatePicker' }
        elseif ($valueType -eq [string] -or $valueType -eq [decimal] -or ($valueType -and $valueType.IsPrimitive)) { $resolved = 'Text' }
        else {
            # Complex object, null first row, or just an unsupported type? downgrade to readonly.
            # Pass EditorType='Text' on the column hashtable to override and force an editable text cell.
            Write-Debug "Column '$Name' has unsupported edit type ($valueType); forcing read-only text."
            $resolved   = 'Text'
            $isEditable = $false
        }
    }

    # Alias columns (Add-Member AliasProperty rows) display through the referenced member, but a SortMemberPath pointing at the alias name matches nothing and the sort silently dies. Resolve once here so every branch binds and sorts the real path.
    $bindPath = $Name
    try {
        $prop = $FirstItem.PSObject.Properties[$Name]
        if ($prop -is [System.Management.Automation.PSAliasProperty]) { $bindPath = $prop.ReferencedMemberName }
    }
    catch { Write-Debug "Alias check failed for '$Name': $_" }

    switch ($resolved) {

        'CheckBox' {
            $col = [System.Windows.Controls.DataGridCheckBoxColumn]::new()
            $col.Header         = $header
            $col.SortMemberPath = $bindPath
            $binding = [System.Windows.Data.Binding]::new($bindPath)
            $binding.Mode = if ($isEditable) { [System.Windows.Data.BindingMode]::TwoWay } else { [System.Windows.Data.BindingMode]::OneWay }

            # $null in a bool column renders the indeterminate dash, which reads as a tristate.
            # TargetNullValue collapses null to false at the binding. IsThreeState=$false stops the click cycle from reintroducing it.
            $binding.TargetNullValue = $false
            $col.Binding      = $binding
            $col.IsReadOnly   = !$isEditable
            $col.IsThreeState = $false

            # Default DataGridCheckBoxColumn renders the raw OS checkbox - looks straight out of 2003 next to themed controls. Reskin with the same template Set-CheckBoxStyle uses.
            $cbStyle = Get-UiDataGridCheckBoxStyle
            $col.ElementStyle        = $cbStyle
            $col.EditingElementStyle = $cbStyle
        }

        'ComboBox' {
            $col = [System.Windows.Controls.DataGridComboBoxColumn]::new()
            $col.Header         = $header
            $col.SortMemberPath = $bindPath
            $col.IsReadOnly     = !$isEditable

            $choices = if ($Column -and $Column.Choices) { @($Column.Choices) }
                       elseif ($valueType -and $valueType.IsEnum) { [enum]::GetValues($valueType) }
                       else { @() }
            $col.ItemsSource = $choices

            # SelectedValueBinding (not SelectedItemBinding) so a string Choices array against a typed property doesn't write a string back. For enums the default SelectedValuePath is fine. ComboBox handles the value coercion.
            $sel = [System.Windows.Data.Binding]::new($bindPath)
            $sel.Mode = if ($isEditable) { [System.Windows.Data.BindingMode]::TwoWay } else { [System.Windows.Data.BindingMode]::OneWay }
            $sel.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::PropertyChanged
            $col.SelectedValueBinding = $sel

            # Enums are self coercing through SelectedValuePath. Flat string Choices against a typed prop write a string back unless you pass @{Value=;Display=} hashtables and set the paths.
            if ($Column -and $Column.Choices -and !($valueType -and $valueType.IsEnum)) {
                Write-Debug "Column '$Name': flat Choices array. Pass @{Value=...; Display=...} hashtables + SelectedValuePath/SelectedDisplayMemberPath if the prop is typed."
            }

            if ($isEditable) {
                $col.EditingElementStyle = Get-UiDataGridTextEditorStyle -EditorKind ComboBox
            }
        }

        'DatePicker' {
            $col = [System.Windows.Controls.DataGridTemplateColumn]::new()
            $col.Header         = $header
            $col.SortMemberPath = $bindPath

            $displayTpl     = [System.Windows.DataTemplate]::new()
            $displayFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.TextBlock])
            $displayBinding = [System.Windows.Data.Binding]::new($bindPath)
            $displayBinding.Mode = [System.Windows.Data.BindingMode]::OneWay

            if ($Column -and $Column.Format) { $displayBinding.StringFormat = [string]$Column.Format }
            $displayFactory.SetBinding([System.Windows.Controls.TextBlock]::TextProperty, $displayBinding)
            $displayFactory.SetValue([System.Windows.Controls.TextBlock]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
            $displayTpl.VisualTree = $displayFactory
            $col.CellTemplate = $displayTpl

            if ($isEditable) {
                $editTpl       = [System.Windows.DataTemplate]::new()
                $editFactory   = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.DatePicker])
                $editBinding   = [System.Windows.Data.Binding]::new($bindPath)
                $editBinding.Mode = [System.Windows.Data.BindingMode]::TwoWay
                $editBinding.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::LostFocus
                $editFactory.SetBinding([System.Windows.Controls.DatePicker]::SelectedDateProperty, $editBinding)
                $dpStyle = Get-UiDataGridTextEditorStyle -EditorKind DatePicker
                $editFactory.SetValue([System.Windows.Controls.DatePicker]::StyleProperty, $dpStyle)
                $editTpl.VisualTree = $editFactory
                $col.CellEditingTemplate = $editTpl
            }
            $col.IsReadOnly = !$isEditable
        }

        default {
            $col = [System.Windows.Controls.DataGridTextColumn]::new()
            $col.Header         = $header
            $col.SortMemberPath = $bindPath

            if ($bindPath -match '[.\[]') {
                Write-Warning "Column '$Name': property name contains '.' or '[' which WPF Binding interprets as a path. The column will render blank. Rename the property or pre-flatten it."
            }

            # Plain binding. The upstream snapshot in New-UiDataGrid flattens objects into PSCustomObjects, so PowerShell added properties show up like regular ones, no per cell cost.
            $binding = [System.Windows.Data.Binding]::new($bindPath)
            $binding.Mode = if ($isEditable) { [System.Windows.Data.BindingMode]::TwoWay } else { [System.Windows.Data.BindingMode]::OneWay }
            if ($isEditable) { $binding.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::LostFocus }
            if ($Column -and $Column.Format) { $binding.StringFormat = [string]$Column.Format }
            $col.Binding    = $binding
            $col.IsReadOnly = !$isEditable

            if ($isEditable) { $col.EditingElementStyle = Get-UiDataGridTextEditorStyle }
        }
    }

    $col.Width = if ($Column -and $Column.Width) { ConvertTo-UiDataGridLength $Column.Width } else { [System.Windows.Controls.DataGridLength]::Auto }

    # MinWidth floor. Keeps the header text from truncating into ellipses AND keeps editable cells large enough to land a click on. Matches Add-DataGridColumns. $Column.MinWidth overrides if you want something else.
    $headerMin    = [Math]::Max(60, ($header.Length * 7) + 30)
    $col.MinWidth = if ($Column -and $Column.MinWidth) { [double]$Column.MinWidth } else { $headerMin }

    return $col
}
