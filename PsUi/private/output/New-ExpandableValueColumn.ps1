<#
.SYNOPSIS
    Creates a DataGrid template column for expandable dictionary/array values.
#>
function New-ExpandableValueColumn {
    [CmdletBinding()]
    param(
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

    $textBinding = [System.Windows.Data.Binding]::new($ValueBinding)
    $textBinding.Mode = 'OneWay'
    $textBlockFactory.SetBinding([System.Windows.Controls.TextBlock]::TextProperty, $textBinding)

    $tagBinding = [System.Windows.Data.Binding]::new($RawValueBinding)
    $tagBinding.Mode = 'OneWay'
    $textBlockFactory.SetBinding([System.Windows.FrameworkElement]::TagProperty, $tagBinding)

    $tooltipBinding = [System.Windows.Data.Binding]::new($RawValueBinding)
    $tooltipBinding.Mode = 'OneWay'
    $tooltipBinding.Converter = [PsUi.ExpandableValueTooltipConverter]::new()
    $textBlockFactory.SetBinding([System.Windows.FrameworkElement]::ToolTipProperty, $tooltipBinding)

    $textBlockStyle = [System.Windows.Style]::new([System.Windows.Controls.TextBlock])

    $expandableTrigger = [System.Windows.DataTrigger]::new()
    $expandableTrigger.Binding = [System.Windows.Data.Binding]::new($IsExpandableBinding)
    $expandableTrigger.Value = $true
    [void]$expandableTrigger.Setters.Add([System.Windows.Setter]::new( [System.Windows.Controls.TextBlock]::ForegroundProperty, [System.Windows.DynamicResourceExtension]::new('LinkBrush')))
    [void]$expandableTrigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::CursorProperty, [System.Windows.Input.Cursors]::Hand))
    [void]$expandableTrigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::FontStyleProperty, [System.Windows.FontStyles]::Italic))
    [void]$textBlockStyle.Triggers.Add($expandableTrigger)

    [void]$textBlockStyle.Triggers.Add((New-SelectedRowForegroundTrigger))

    $textBlockFactory.SetValue([System.Windows.FrameworkElement]::StyleProperty, $textBlockStyle)

    $cellTemplate.VisualTree = $textBlockFactory
    $valCol.CellTemplate = $cellTemplate

    return $valCol
}
