<#
.SYNOPSIS
    Creates a DataGrid template column for expandable dictionary/array values.
#>
function New-ExpandableValueColumn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Colors,
        
        [string]$Header = 'Value',
        
        [string]$ValueBinding = 'Value',
        
        [string]$RawValueBinding = '_RawValue',
        
        [string]$IsExpandableBinding = '_IsExpandable'
    )
    
    $valCol = [System.Windows.Controls.DataGridTemplateColumn]::new()
    $valCol.Header = $Header
    
    # Create cell template with styled TextBlock
    $cellTemplate = [System.Windows.DataTemplate]::new()
    $textBlockFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.TextBlock])
    
    # Bind Text to Value property
    $textBinding = [System.Windows.Data.Binding]::new($ValueBinding)
    $textBinding.Mode = 'OneWay'
    $textBlockFactory.SetBinding([System.Windows.Controls.TextBlock]::TextProperty, $textBinding)
    
    # Bind Tag to _RawValue for popup access
    $tagBinding = [System.Windows.Data.Binding]::new($RawValueBinding)
    $tagBinding.Mode = 'OneWay'
    $textBlockFactory.SetBinding([System.Windows.FrameworkElement]::TagProperty, $tagBinding)
    
    # Bind tooltip to _RawValue with converter for preview
    $tooltipBinding = [System.Windows.Data.Binding]::new($RawValueBinding)
    $tooltipBinding.Mode = 'OneWay'
    $tooltipBinding.Converter = [PsUi.ExpandableValueTooltipConverter]::new()
    $textBlockFactory.SetBinding([System.Windows.FrameworkElement]::ToolTipProperty, $tooltipBinding)
    
    # Create style with DataTrigger for conditional expandable styling
    $linkBrush = ConvertTo-UiBrush $Colors.Link
    $textBlockStyle = [System.Windows.Style]::new([System.Windows.Controls.TextBlock])
    
    $expandableTrigger = [System.Windows.DataTrigger]::new()
    $expandableTrigger.Binding = [System.Windows.Data.Binding]::new($IsExpandableBinding)
    $expandableTrigger.Value = $true
    [void]$expandableTrigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::ForegroundProperty, $linkBrush))
    [void]$expandableTrigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::CursorProperty, [System.Windows.Input.Cursors]::Hand))
    [void]$expandableTrigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::FontStyleProperty, [System.Windows.FontStyles]::Italic))
    [void]$textBlockStyle.Triggers.Add($expandableTrigger)
    
    $textBlockFactory.SetValue([System.Windows.FrameworkElement]::StyleProperty, $textBlockStyle)
    
    $cellTemplate.VisualTree = $textBlockFactory
    $valCol.CellTemplate = $cellTemplate
    
    return $valCol
}
