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

    # Fallback defaults for the two types PowerShell most often dumps into a grid.
    if (!$hasDefaultSet -and $itemTypeName -match '(^|\.)Process$') {
        $defaultProps.AddRange(@('ProcessName', 'Id', 'CPU', 'Handles', 'WorkingSet64'))
        $hasDefaultSet = $true
    }
    elseif (!$hasDefaultSet -and $itemTypeName -match '(^|\.)ServiceController$') {
        $defaultProps.AddRange(@('Status', 'Name', 'DisplayName'))
        $hasDefaultSet = $true
    }

    # Create array display converters
    $arrayConverter = [PsUi.ArrayDisplayConverter]::new()
    $tooltipConverter = [PsUi.ArrayTooltipConverter]::new()

    # Collect column adds into a single layout pass.
    # Can't use try/catch/finally with the begininit() call outside the pipeline (a -NoAsync button runs as a WPF event, not pipeline), and a finally block's exit NREs.
    # Trap covers this after BeginInit is called. The tail EndInit covers success. This is like the second time I've ever used a trap.
    $DataGrid.BeginInit()
    trap {
        $DataGrid.EndInit()
        Write-Debug "Add-DataGridColumns build failed: $($_.Exception.Message)"
        break
    }

    if ($FirstItem -is [string] -or $FirstItem -is [System.ValueType]) {
        # Bare scalars show as zero columns. Strings are worse and only show their length. One 'Value' column bound to the item covers both. Header sort still works, the empty path compares items.
        $col = [System.Windows.Controls.DataGridTextColumn]::new()
        $col.Header       = 'Value'
        $col.Binding      = [System.Windows.Data.Binding]::new('.')
        $col.Binding.Mode = 'OneWay'
        $col.MinWidth     = 80
        $col.IsReadOnly   = $true
        $DataGrid.Columns.Add($col)
        [void]$allProps.Add('Value')
    }
    else {
        foreach ($prop in $FirstItem.PSObject.Properties) {
            $name = $prop.Name
            if ($name.StartsWith('_')) { continue }

            [void]$allProps.Add($name)

            # Aliases bind to the actual .NET property, not the PowerShell alias
            $bindPath = if ($prop -is [System.Management.Automation.PSAliasProperty]) { $prop.ReferencedMemberName } else { $name }

            # Arrays get click to expand template columns instead of plain text
            $typeName2 = $prop.TypeNameOfValue
            $isArrayType = $typeName2 -and ($typeName2.EndsWith('[]') -or
                           ($typeName2 -match 'Collection|List|Array|IEnumerable' -and
                           $typeName2 -notmatch 'String'))

            if ($isArrayType) {
                # Create template column for arrays with click to expand
                $col = [System.Windows.Controls.DataGridTemplateColumn]::new()
                $col.Header = $name

                # Apparently deprecated API but still the only way to build data templates in code
                $cellTemplate = [System.Windows.DataTemplate]::new()
                $textBlockFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.TextBlock])

                $binding = [System.Windows.Data.Binding]::new($bindPath)
                $binding.Mode = 'OneWay'
                $binding.Converter = $arrayConverter
                $textBlockFactory.SetBinding([System.Windows.Controls.TextBlock]::TextProperty, $binding)

                # Foreground goes through a style so the selection color swapsm otherwise the link color disappears into the selection highlight.
                $textBlockFactory.SetValue([System.Windows.Controls.TextBlock]::CursorProperty, [System.Windows.Input.Cursors]::Hand)
                $textBlockFactory.SetValue([System.Windows.Controls.TextBlock]::FontStyleProperty, [System.Windows.FontStyles]::Italic)

                # LinkBrush is a DynamicResource (Set-ActiveTheme sets it). ConvertTo-UiBrush freezes the color when built.
                $arrLinkStyle = [System.Windows.Style]::new([System.Windows.Controls.TextBlock])
                [void]$arrLinkStyle.Setters.Add([System.Windows.Setter]::new( [System.Windows.Controls.TextBlock]::ForegroundProperty, [System.Windows.DynamicResourceExtension]::new('LinkBrush')))
                [void]$arrLinkStyle.Triggers.Add((New-SelectedRowForegroundTrigger))

                $textBlockFactory.SetValue([System.Windows.Controls.TextBlock]::StyleProperty, $arrLinkStyle)

                $tooltipBinding = [System.Windows.Data.Binding]::new($bindPath)
                $tooltipBinding.Mode = 'OneWay'
                $tooltipBinding.Converter = $tooltipConverter
                $textBlockFactory.SetBinding([System.Windows.FrameworkElement]::ToolTipProperty, $tooltipBinding)

                $tagBinding = [System.Windows.Data.Binding]::new($bindPath)
                $tagBinding.Mode = 'OneWay'
                $textBlockFactory.SetBinding([System.Windows.FrameworkElement]::TagProperty, $tagBinding)

                $cellTemplate.VisualTree = $textBlockFactory
                $col.CellTemplate = $cellTemplate

                # No SortMemberPath on purpose (sorting arrays throws on mixed IComparable, but copy/export resolve paths through Get-UiDataGridVisibleColumnPaths
                $col.ClipboardContentBinding = [System.Windows.Data.Binding]::new($bindPath)

                $headerMinWidth = [Math]::Max(80, ($name.Length * 7) + 30)
                $col.MinWidth = $headerMinWidth
            }
            else {
                # Standard text column. New-UiDataGrid snapshots items into PSCustomObject so extended members still work.
                # Show-UiOutput skips that snapshot so these cells stay empty.
                $col = [System.Windows.Controls.DataGridTextColumn]::new()
                $col.Header = $name
                $col.SortMemberPath = $bindPath
                $col.Binding = [System.Windows.Data.Binding]::new($bindPath)
                $col.Binding.Mode = 'OneWay'

                $headerMinWidth = [Math]::Max(60, ($name.Length * 7) + 30)
                $col.MinWidth = $headerMinWidth
            }

            $col.Width = [System.Windows.Controls.DataGridLength]::Auto
            $col.IsReadOnly = $true

            # Hide columns outside the default set when one exists
            if ($hasDefaultSet -and $defaultProps -notcontains $name) {
                $col.Visibility = [System.Windows.Visibility]::Collapsed
            }

            $DataGrid.Columns.Add($col)
        }
    }

    # If no default set, all properties are default.
    if (!$hasDefaultSet) {
        $defaultProps = [System.Collections.Generic.List[object]]::new($allProps)
    }

    # Add Action Status column if requested. Binds to the _ActionStatus hidden property added by the AsyncExecutor, which inturn is updated by actions attached to the items using -ResultAction.
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

    $DataGrid.EndInit()

    return @{
        AllProperties     = $allProps
        DefaultProperties = $defaultProps
    }
}
