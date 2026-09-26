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

        [switch]$IncludeActionStatus,

        [switch]$PlainRows
    )

    $allProps     = [System.Collections.Generic.List[object]]::new()
    $defaultProps = [System.Collections.Generic.List[object]]::new()

    $setNames = @()
    try {
        $stdMembers = $FirstItem.PSStandardMembers
        if ($stdMembers -and $stdMembers.DefaultDisplayPropertySet) {
            $setNames = @($stdMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
        }
    }
    catch { Write-Debug "Suppressed DefaultDisplayPropertySet lookup: $_" }

    $itemTypeName = $FirstItem.PSObject.TypeNames[0]
    if (!$itemTypeName) { $itemTypeName = $FirstItem.GetType().FullName }

    # The console's table columns. DirectoryInfo has no default set, and FileInfo's leaves out Mode.
    # Only the real types because this replaces whatever set the row brings. Item.FileInfo and Selected.System.IO.FileInfo keep theirs.
    if ($itemTypeName -match '^(Deserialized\.)?System\.IO\.(FileInfo|DirectoryInfo)$') {
        $setNames = @('Mode', 'LastWriteTime', 'Length', 'Name')
    }

    # PSPath, Mode, and CPU read blank on a plain row
    $psOnly = [System.Collections.Generic.List[string]]::new()
    if ($PlainRows) {
        $clrNames    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $descriptors = [System.ComponentModel.TypeDescriptor]::GetProperties($FirstItem)
        foreach ($clrProp in $descriptors) { [void]$clrNames.Add($clrProp.Name) }

        # WPF finds IsNew and Row w reflection
        foreach ($clrProp in $FirstItem.GetType().GetProperties()) { [void]$clrNames.Add($clrProp.Name) }

        foreach ($prop in $FirstItem.PSObject.Properties) {
            $clrName = if ($prop -is [System.Management.Automation.PSAliasProperty]) { $prop.ReferencedMemberName } else { $prop.Name }
            if (!$clrNames.Contains($clrName)) { $psOnly.Add($prop.Name) }
        }
    }

    # Folders drop Length, and the flood prompt counts these
    foreach ($setName in $setNames) {
        $setProp = $FirstItem.PSObject.Properties[[string]$setName]
        if (!$setProp -or $psOnly.Contains($setProp.Name)) { continue }
        if (!$defaultProps.Contains($setProp.Name)) { $defaultProps.Add($setProp.Name) }
    }
    $hasDefaultSet = $defaultProps.Count -gt 0

    $arrayConverter      = [PsUi.ArrayDisplayConverter]::new()
    $tooltipConverter    = [PsUi.ArrayTooltipConverter]::new()
    $expandableConverter = [PsUi.IsExpandableConverter]::new()
    $singleLine          = [PsUi.SingleLineConverter]::new()

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
        # Plain scalars show as zero columns and strings only show their length, so one 'Value' column bound to the item covers both. Header sort still works, since the empty path compares the items themselves.
        $col = [System.Windows.Controls.DataGridTextColumn]::new()
        $col.Header            = 'Value'
        $col.Binding           = [System.Windows.Data.Binding]::new('.')
        $col.Binding.Mode      = 'OneWay'
        $col.Binding.Converter = $singleLine
        $col.MinWidth          = 80
        $col.IsReadOnly        = $true
        $DataGrid.Columns.Add($col)
        [void]$allProps.Add('Value')
    }
    else {
        $orderedProps = $FirstItem.PSObject.Properties
        if ($hasDefaultSet -or $psOnly.Count) {
            $orderedProps = [System.Collections.Generic.List[object]]::new()
            foreach ($defaultName in $defaultProps) {
                $orderedProps.Add($FirstItem.PSObject.Properties[$defaultName])
            }
            foreach ($prop in $FirstItem.PSObject.Properties) {
                if ($defaultProps.Contains($prop.Name) -or $psOnly.Contains($prop.Name)) { continue }
                $orderedProps.Add($prop)
            }

            foreach ($psName in $psOnly) { $orderedProps.Add($FirstItem.PSObject.Properties[$psName]) }
        }

        foreach ($prop in $orderedProps) {
            $name = $prop.Name
            if ($name.StartsWith('_')) { continue }

            [void]$allProps.Add($name)

            # Handles points at 'Handlecount' and WPF matches paths case sensitively on a plain row
            $bindPath = $name
            if ($prop -is [System.Management.Automation.PSAliasProperty]) {
                $target   = $FirstItem.PSObject.Properties[$prop.ReferencedMemberName]
                $bindPath = if ($target) { $target.Name } else { $prop.ReferencedMemberName }
            }

            # Arrays get click to expand template columns instead of plain text
            # No String exclusion here, since one throws out List[string] along with the string and FileInfo.Target then renders as a raw List`1[System.String]. A plain System.String never matches the pattern below anyway.
            $typeName2   = $prop.TypeNameOfValue
            $isArrayType = $typeName2 -and ($typeName2.EndsWith('[]') -or $typeName2 -match 'Collection|List|Array|IEnumerable')

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

                # The link look rides a trigger on the value, so an empty list or a one pass reader reads as plain text and offers no click.
                # Add-ArrayCellPopupHandler reads the italic to tell a list cell from the rest.
                # LinkBrush is a DynamicResource (Set-ActiveTheme sets it). ConvertTo-UiBrush freezes the color when built.
                # Foreground goes through the style so the selection color swaps, otherwise the link color disappears into the selection highlight.
                $linkBinding           = [System.Windows.Data.Binding]::new($bindPath)
                $linkBinding.Mode      = 'OneWay'
                $linkBinding.Converter = $expandableConverter
                $linkTrigger           = [System.Windows.DataTrigger]::new()
                $linkTrigger.Binding   = $linkBinding
                $linkTrigger.Value     = $true
                [void]$linkTrigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::ForegroundProperty, [System.Windows.DynamicResourceExtension]::new('LinkBrush')))
                [void]$linkTrigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::CursorProperty, [System.Windows.Input.Cursors]::Hand))
                [void]$linkTrigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::FontStyleProperty, [System.Windows.FontStyles]::Italic))

                $arrLinkStyle = [System.Windows.Style]::new([System.Windows.Controls.TextBlock])
                [void]$arrLinkStyle.Triggers.Add($linkTrigger)
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

                # No SortMemberPath, since sorting arrays throws on mixed IComparable. Copy and export resolve the path through this binding instead.
                $col.ClipboardContentBinding = [System.Windows.Data.Binding]::new($bindPath)

                $headerMinWidth = [Math]::Max(80, ($name.Length * 7) + 30)
                $col.MinWidth = $headerMinWidth
            }
            else {
                # Extended members only bind on a PSObject row
                $col = [System.Windows.Controls.DataGridTextColumn]::new()
                $col.Header = $name
                $col.SortMemberPath = $bindPath
                $col.Binding = [System.Windows.Data.Binding]::new($bindPath)
                $col.Binding.Mode = 'OneWay'
                $col.Binding.Converter = $singleLine

                $headerMinWidth = [Math]::Max(60, ($name.Length * 7) + 30)
                $col.MinWidth = $headerMinWidth
            }

            $col.Width = [System.Windows.Controls.DataGridLength]::Auto
            $col.IsReadOnly = $true

            # Outside the default set or blank on a plain row
            $hidden = $psOnly.Contains($name) -or ($hasDefaultSet -and $defaultProps -notcontains $name)
            if ($hidden) { $col.Visibility = [System.Windows.Visibility]::Collapsed }

            $DataGrid.Columns.Add($col)
        }
    }

    # Without a default set, every column WPF can read is a default
    if (!$hasDefaultSet) {
        $defaultProps = [System.Collections.Generic.List[object]]::new()
        foreach ($propName in $allProps) {
            if (!$psOnly.Contains([string]$propName)) { $defaultProps.Add($propName) }
        }
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
        PsOnlyProperties  = $psOnly
    }
}
