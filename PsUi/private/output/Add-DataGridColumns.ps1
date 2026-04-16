function Add-DataGridColumns {
    <#
    .SYNOPSIS
        Generates DataGrid columns from the first item's properties with array support.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [Parameter(Mandatory)]
        [object]$FirstItem,

        [Parameter(Mandatory)]
        [hashtable]$Colors,

        [switch]$IncludeActionStatus
    )

    $allProps     = [System.Collections.Generic.List[object]]::new()
    $defaultProps = [System.Collections.Generic.List[object]]::new()

    # Check for DefaultDisplayPropertySet
    $hasDefaultSet = $false
    try {
        $stdMembers = $FirstItem.PSStandardMembers
        if ($stdMembers -and $stdMembers.DefaultDisplayPropertySet) {
            $defaultSet = $stdMembers.DefaultDisplayPropertySet
            if ($defaultSet.ReferencedPropertyNames) {
                $defaultProps.AddRange(@($defaultSet.ReferencedPropertyNames))
                $hasDefaultSet = $true
            }
        }
    }
    catch { Write-Debug "Suppressed DefaultDisplayPropertySet lookup: $_" }

    # Get type name for fallback logic
    $itemTypeName = $FirstItem.PSObject.TypeNames[0]
    if (!$itemTypeName) { $itemTypeName = $FirstItem.GetType().FullName }

    # Fallback defaults for known types
    if (!$hasDefaultSet -and $itemTypeName -match 'Process') {
        $defaultProps.AddRange(@('ProcessName', 'Id', 'CPU', 'Handles', 'WorkingSet64'))
        $hasDefaultSet = $true
    }
    elseif (!$hasDefaultSet -and $itemTypeName -match 'Service') {
        $defaultProps.AddRange(@('Status', 'Name', 'DisplayName'))
        $hasDefaultSet = $true
    }

    # Create array display converters
    $arrayConverter = [PsUi.ArrayDisplayConverter]::new()
    $tooltipConverter = [PsUi.ArrayTooltipConverter]::new()
    $arrayLinkBrush = ConvertTo-UiBrush $Colors.Link

    foreach ($prop in $FirstItem.PSObject.Properties) {

        $name = $prop.Name
        if ($name.StartsWith('_')) { continue }

        [void]$allProps.Add($name)

        # Aliases bind to the actual .NET property, not the PowerShell alias
        $bindPath = if ($prop -is [System.Management.Automation.PSAliasProperty]) { $prop.ReferencedMemberName } else { $name }

        # Arrays get click-to-expand template columns instead of plain text
        $typeName2 = $prop.TypeNameOfValue
        $isArrayType = $typeName2 -and ($typeName2.EndsWith('[]') -or
                       ($typeName2 -match 'Collection|List|Array|IEnumerable' -and
                       $typeName2 -notmatch 'String'))

        if ($isArrayType) {
            # Create template column for arrays with click-to-expand
            $col = [System.Windows.Controls.DataGridTemplateColumn]::new()
            $col.Header = $name

            # FrameworkElementFactory created - its deprecated but still afaik the best way to create 
            # datatemplates programatically...
            $cellTemplate = [System.Windows.DataTemplate]::new()
            $textBlockFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.TextBlock])

            $binding = [System.Windows.Data.Binding]::new($bindPath)
            $binding.Mode = 'OneWay'
            $binding.Converter = $arrayConverter
            $textBlockFactory.SetBinding([System.Windows.Controls.TextBlock]::TextProperty, $binding)

            $textBlockFactory.SetValue([System.Windows.Controls.TextBlock]::ForegroundProperty, $arrayLinkBrush)
            $textBlockFactory.SetValue([System.Windows.Controls.TextBlock]::CursorProperty, [System.Windows.Input.Cursors]::Hand)
            $textBlockFactory.SetValue([System.Windows.Controls.TextBlock]::FontStyleProperty, [System.Windows.FontStyles]::Italic)

            $tooltipBinding = [System.Windows.Data.Binding]::new($bindPath)
            $tooltipBinding.Mode = 'OneWay'
            $tooltipBinding.Converter = $tooltipConverter
            $textBlockFactory.SetBinding([System.Windows.FrameworkElement]::ToolTipProperty, $tooltipBinding)

            $tagBinding = [System.Windows.Data.Binding]::new($bindPath)
            $tagBinding.Mode = 'OneWay'
            $textBlockFactory.SetBinding([System.Windows.FrameworkElement]::TagProperty, $tagBinding)

            $cellTemplate.VisualTree = $textBlockFactory
            $col.CellTemplate = $cellTemplate

            $headerMinWidth = [Math]::Max(80, ($name.Length * 7) + 30)
            $col.MinWidth = $headerMinWidth
        }
        else {

            # Standard text column for non-array properties
            $col = [System.Windows.Controls.DataGridTextColumn]::new()
            $col.Header = $name
            $col.Binding = [System.Windows.Data.Binding]::new($bindPath)
            $col.Binding.Mode = 'OneWay'

            $headerMinWidth = [Math]::Max(60, ($name.Length * 7) + 30)
            $col.MinWidth = $headerMinWidth
        }

        $col.Width = [System.Windows.Controls.DataGridLength]::Auto
        $col.IsReadOnly = $true

        # Hide non-default columns if we have a default set
        if ($hasDefaultSet -and $defaultProps -notcontains $name) {
            $col.Visibility = [System.Windows.Visibility]::Collapsed
        }

        $DataGrid.Columns.Add($col)
    }

    # If no default set, all properties are default
    if (!$hasDefaultSet) {
        $defaultProps = $allProps.Clone()
    }

    # Add Action Status column if requested
    # This will bind to the _ActionStatus hidden property added by the executor, which
    # inturn is updated by actions attached to the items using -ResultAction
    if ($IncludeActionStatus) {
        $statusCol = [System.Windows.Controls.DataGridTextColumn]::new()
        $statusCol.Header = "Action Status"
        $statusCol.Binding = [System.Windows.Data.Binding]::new("_ActionStatus")
        $statusCol.Binding.Mode = 'OneWay'
        $statusCol.Width = [System.Windows.Controls.DataGridLength]::new(150)
        $statusCol.MinWidth = 100
        $statusCol.IsReadOnly = $true
        $DataGrid.Columns.Add($statusCol)
    }

    return @{
        AllProperties     = $allProps
        DefaultProperties = $defaultProps
    }
}
