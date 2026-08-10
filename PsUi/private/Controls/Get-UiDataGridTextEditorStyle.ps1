function Get-UiDataGridTextEditorStyle {
    <#
    .SYNOPSIS
        Cell editor style for TextBox/DatePicker/ComboBox that keeps row height stable during editing.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('TextBox', 'DatePicker', 'ComboBox')]
        [string]$EditorKind = 'TextBox'
    )

    # Same style every call for a given EditorKind. Cache by kind.
    if ($null -eq $script:_TextEditorStyleCache) { $script:_TextEditorStyleCache = @{} }
    if ($script:_TextEditorStyleCache.ContainsKey($EditorKind)) { return $script:_TextEditorStyleCache[$EditorKind] }

    $resourceKey = switch ($EditorKind) {
        'TextBox'    { 'ModernTextBoxStyle' }
        'DatePicker' { 'ModernDatePickerStyle' }
        'ComboBox'   { 'ModernComboBoxStyle' }
    }

    $targetType = switch ($EditorKind) {
        'TextBox'    { [System.Windows.Controls.TextBox] }
        'DatePicker' { [System.Windows.Controls.DatePicker] }
        'ComboBox'   { [System.Windows.Controls.ComboBox] }
    }

    $baseStyle = $null
    try {
        if ($null -ne [System.Windows.Application]::Current) {
            $baseStyle = [System.Windows.Application]::Current.TryFindResource($resourceKey)
        }
    }
    catch { Write-Debug "Lookup of '$resourceKey' failed: $_" }

    $style = if ($baseStyle) { [System.Windows.Style]::new($targetType, $baseStyle) }
             else { [System.Windows.Style]::new($targetType) }

    # MinHeight stops the editor's internal padding from clipping text. TextBox and ComboBox need 26px. DatePicker chrome adds its own height. 0 here lets it use its builtin.
    $editorMinHeight = switch ($EditorKind) {
        'TextBox'    { [double]26 }
        'ComboBox'   { [double]26 }
        default      { [double]0 }
    }

    # Padding offsets the editor's own padding so the text doesn't shift when editing starts. TextBox 0 lines up with the display text, ComboBox -1 cancels its builtin 1px padding.
    $editorPadding = switch ($EditorKind) {
        'TextBox'    { [System.Windows.Thickness]::new(0, 0, 0, 0) }
        'ComboBox'   { [System.Windows.Thickness]::new(-1, 0, -1, 0) }
        default      { [System.Windows.Thickness]::new(2, 0, 2, 0) }
    }

    # Without these overrides the themed border shoots out the row every time a cell goes into edit mode. Looks like garbo.
    $overrides = @(
        @{ Prop = 'BorderThickness';            Value = [System.Windows.Thickness]::new(0) }
        @{ Prop = 'Padding';                    Value = $editorPadding }
        @{ Prop = 'Margin';                     Value = [System.Windows.Thickness]::new(0) }
        @{ Prop = 'HorizontalContentAlignment'; Value = [System.Windows.HorizontalAlignment]::Left }
        @{ Prop = 'VerticalAlignment';          Value = [System.Windows.VerticalAlignment]::Stretch }
        @{ Prop = 'VerticalContentAlignment';   Value = [System.Windows.VerticalAlignment]::Center }
        @{ Prop = 'MinHeight';                  Value = $editorMinHeight }
    )

    foreach ($override in $overrides) {

        $field = $targetType.GetField($override.Prop + 'Property', [System.Reflection.BindingFlags]'Public, Static, FlattenHierarchy')
        $dp = if ($field) { $field.GetValue($null) }
        if ($null -ne $dp) { [void]$style.Setters.Add([System.Windows.Setter]::new($dp, $override.Value)) }
    }

    $script:_TextEditorStyleCache[$EditorKind] = $style
    return $style
}
