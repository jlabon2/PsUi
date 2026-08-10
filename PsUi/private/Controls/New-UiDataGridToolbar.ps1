function New-UiDataGridToolbar {
    <#
    .SYNOPSIS
        Builds the filter/copy/export/column picker toolbar that sits above an embedded DataGrid.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [Parameter(Mandatory)]
        [hashtable]$Colors,

        [switch]$NoFilter,

        [switch]$NoExport,

        [switch]$NoCopy,

        [switch]$NoColumnPicker,

        [string[]]$AllProperties,

        [string[]]$DefaultProperties,

        [string[]]$PopulatedProperties,

        [scriptblock]$ItemsProvider
    )

    $toolbar = [System.Windows.Controls.Grid]@{
        Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
    }

    $colIdx          = 0
    $iconColIdx      = -1
    $filterColIdx    = -1
    $countColIdx     = -1
    $colsBtnColIdx   = -1
    $copyBtnColIdx   = -1
    $exportBtnColIdx = -1

    if (!$NoFilter) {
        $iconCol = [System.Windows.Controls.ColumnDefinition]::new()
        $iconCol.Width = [System.Windows.GridLength]::Auto
        [void]$toolbar.ColumnDefinitions.Add($iconCol)
        $iconColIdx = $colIdx; $colIdx++

        $filterCol = [System.Windows.Controls.ColumnDefinition]::new()
        $filterCol.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        [void]$toolbar.ColumnDefinitions.Add($filterCol)
        $filterColIdx = $colIdx; $colIdx++
    }
    else {
        $spacerCol = [System.Windows.Controls.ColumnDefinition]::new()
        $spacerCol.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        [void]$toolbar.ColumnDefinitions.Add($spacerCol)
        $colIdx++
    }

    # Row count sits between the filter and the icon buttons. Autowidth so the filter keeps the star slot and the count never encroaches the buttons.
    $countCol = [System.Windows.Controls.ColumnDefinition]::new()
    $countCol.Width = [System.Windows.GridLength]::Auto
    [void]$toolbar.ColumnDefinitions.Add($countCol)
    $countColIdx = $colIdx; $colIdx++

    if (!$NoColumnPicker) {
        $cbCol = [System.Windows.Controls.ColumnDefinition]::new()
        $cbCol.Width = [System.Windows.GridLength]::Auto
        [void]$toolbar.ColumnDefinitions.Add($cbCol)
        $colsBtnColIdx = $colIdx; $colIdx++
    }
    if (!$NoCopy) {
        $cpCol = [System.Windows.Controls.ColumnDefinition]::new()
        $cpCol.Width = [System.Windows.GridLength]::Auto
        [void]$toolbar.ColumnDefinitions.Add($cpCol)
        $copyBtnColIdx = $colIdx; $colIdx++
    }
    if (!$NoExport) {
        $exCol = [System.Windows.Controls.ColumnDefinition]::new()
        $exCol.Width = [System.Windows.GridLength]::Auto
        [void]$toolbar.ColumnDefinitions.Add($exCol)
        $exportBtnColIdx = $colIdx; $colIdx++
    }

    $filterBox = $null

    if (!$NoFilter) {
        $searchIcon = [System.Windows.Controls.TextBlock]@{
            Text              = [PsUi.ModuleContext]::GetIcon('Search')
            FontFamily        = [PsUi.ModuleContext]::ActiveIconFontFamily
            FontSize          = 14
            VerticalAlignment = 'Center'
            Foreground        = ConvertTo-UiBrush $Colors.SecondaryText
            Margin            = [System.Windows.Thickness]::new(0, 0, 6, 0)
            Tag               = 'SecondaryTextBrush'
        }
        [PsUi.ThemeEngine]::RegisterElement($searchIcon)
        [System.Windows.Controls.Grid]::SetColumn($searchIcon, $iconColIdx)
        [void]$toolbar.Children.Add($searchIcon)

        $filterResult = New-FilterBoxWithClear -Width 0 -Height 26 -AdditionalTagData @{
            Grid  = $DataGrid
            Timer = $null
        }

        # New-FilterBoxWithClear sets a fixed width - undo it for the Grid column stretch.
        $filterResult.Container.Width = [double]::NaN
        $filterResult.Container.HorizontalAlignment = 'Stretch'

        # Push the trailing icon buttons off the filter's clear icon.
        $filterResult.Container.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)

        [System.Windows.Controls.Grid]::SetColumn($filterResult.Container, $filterColIdx)
        [void]$toolbar.Children.Add($filterResult.Container)
        $filterBox = $filterResult.TextBox
    }

    # "12 of 142" when filtered, "142" otherwise. Not all views expose Count.
    $countTextBlock = [System.Windows.Controls.TextBlock]@{
        VerticalAlignment = 'Center'
        Margin            = [System.Windows.Thickness]::new(8, 0, 8, 0)
        FontSize          = 12
        Tag               = 'SecondaryTextBrush'
    }
    $countTextBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'SecondaryTextBrush')
    [PsUi.ThemeEngine]::RegisterElement($countTextBlock)
    [System.Windows.Controls.Grid]::SetColumn($countTextBlock, $countColIdx)
    [void]$toolbar.Children.Add($countTextBlock)

    $countGridRef     = $DataGrid
    $countTbRef       = $countTextBlock
    $countProviderRef = $ItemsProvider

    $updateCount = {
        try {
            if ($null -eq $countTbRef) { return }
            $coll = if ($countProviderRef) { & $countProviderRef } else { $null }
            $total = if ($coll -is [System.Collections.ICollection]) { $coll.Count }
                     elseif ($coll) { @($coll).Count }
                     else { 0 }

            $view = $countGridRef.ItemsSource -as [System.ComponentModel.ICollectionView]
            $shown = $total
            if ($view) {
                $listView = $view -as [System.Windows.Data.ListCollectionView]
                if ($listView) { $shown = $listView.Count }
                else {
                    $shown = 0
                    foreach ($entry in $view) { $shown++ }
                }
            }

            $countTbRef.Text = if ($shown -eq $total) { [string]$total } else { "$shown of $total" }
        }
        catch { Write-Debug "Row count update failed: $_" }
    }.GetNewClosure()

    $countTextBlock.Add_Loaded({ & $updateCount }.GetNewClosure())

    # CollectionChanged needs to follow ItemsSource swaps. Old view stays subscribed and the new view's mutations get ignored otherwise. Mirrors the pattern in Add-UiDataGridEmptyOverlay.
    $countSubState = @{ View = $null }
    $countHandler  = { & $updateCount }.GetNewClosure()

    $countAttach = {
        if ($countSubState.View) {
            try { $countSubState.View.remove_CollectionChanged($countHandler) } catch { }
            $countSubState.View = $null
        }
        $view = $DataGrid.ItemsSource -as [System.ComponentModel.ICollectionView]
        if (!$view) { return }
        try {
            $view.add_CollectionChanged($countHandler)
            $countSubState.View = $view
        }
        catch { Write-Debug "Row count subscribe failed: $_" }
        & $updateCount
    }.GetNewClosure()

    # DependencyPropertyDescriptor.AddValueChanged fires on ItemsSource swap. Leak prone (static dictionary, holds a strong reference to the DataGrid) so hook subscribe + Closed cleanup together inside Loaded.
    $itemsSourcePropDesc = [System.ComponentModel.DependencyPropertyDescriptor]::FromProperty(
        [System.Windows.Controls.ItemsControl]::ItemsSourceProperty,
        [System.Windows.Controls.DataGrid])
    $itemsSourceChangedHandler = [System.EventHandler]{
        param($sender, $eventArgs)
        & $countAttach
    }.GetNewClosure()

    # Window.Closed beats Unloaded - tab virtualization unloads on tab switch and would freeze the count.
    $onWindowClosed = {
        try { $itemsSourcePropDesc.RemoveValueChanged($DataGrid, $itemsSourceChangedHandler) }
        catch { Write-Debug "Row count DPD detach failed: $_" }
        if ($countSubState.View) {
            try { $countSubState.View.remove_CollectionChanged($countHandler) } catch { }
            $countSubState.View = $null
        }
    }.GetNewClosure()

    $countHooked = @{ Value = $false }
    $DataGrid.Add_Loaded({
        & $countAttach
        if ($countHooked.Value) { return }
        $window = [System.Windows.Window]::GetWindow($this)
        if (!$window) { return }
        $countHooked.Value = $true
        $itemsSourcePropDesc.AddValueChanged($DataGrid, $itemsSourceChangedHandler)
        $window.Add_Closed($onWindowClosed)
    }.GetNewClosure())

    $colButton = $null
    if (!$NoColumnPicker) {
        # Pull model provider so the picker reflects whatever columns the grid currently has, including columns that arrive later via the seed handler on initially empty -ItemsSource grids. Falls back to grid.Columns headers when Tag isn't a hashtable yet.
        $gridForPicker  = $DataGrid
        $allFallback    = $AllProperties
        $defFallback    = $DefaultProperties
        $popFallback    = $PopulatedProperties
        $propertiesProvider = {
            $tag = $gridForPicker.Tag
            $all = if ($tag -is [hashtable] -and $tag.AllProperties)       { @($tag.AllProperties) }
                   elseif ($allFallback)                                   { @($allFallback) }
                   else                                                    { @($gridForPicker.Columns | ForEach-Object { [string]$_.Header } | Where-Object { $_ }) }
            $def = if ($tag -is [hashtable] -and $tag.DefaultProperties)   { @($tag.DefaultProperties) }
                   elseif ($defFallback)                                   { @($defFallback) }
                   else                                                    { @() }
            $pop = if ($tag -is [hashtable] -and $tag.PopulatedProperties) { @($tag.PopulatedProperties) }
                   elseif ($popFallback)                                   { @($popFallback) }
                   else                                                    { @() }
            @{ All = $all; Default = $def; Populated = $pop }
        }.GetNewClosure()

        $popupParams = @{
            DataGrid           = $DataGrid
            PropertiesProvider = $propertiesProvider
        }
        if ($ItemsProvider) { $popupParams.ItemsProvider = $ItemsProvider }
        $popupResult = New-ColumnVisibilityPopup @popupParams
        $colButton = $popupResult.Button
        [System.Windows.Controls.Grid]::SetColumn($colButton, $colsBtnColIdx)
        [void]$toolbar.Children.Add($colButton)
    }

    # Same copy/export helpers the context menu uses - one place strips the _* columns.
    $copyButton = $null
    if (!$NoCopy) {
        $copyButton = New-UiDataGridToolbarIconButton -Icon 'Copy' -ToolTip 'Copy selected rows to clipboard'
        [System.Windows.Controls.Grid]::SetColumn($copyButton, $copyBtnColIdx)
        [void]$toolbar.Children.Add($copyButton)

        $gridRef = $DataGrid
        $copyButton.Add_Click({
            Invoke-UiDataGridCopyToClipboard -DataGrid $gridRef
        }.GetNewClosure())

        # Copy with zero selection does nothing, silently. Disable until the user picks a row.
        $copyButton.IsEnabled = ($DataGrid.SelectedItems.Count -gt 0)
        $copyBtnRef = $copyButton
        $DataGrid.add_SelectionChanged({
            $copyBtnRef.IsEnabled = ($gridRef.SelectedItems.Count -gt 0)
        }.GetNewClosure())
    }

    # Export stays enabled with nothing selected.
    $exportButton = $null
    if (!$NoExport) {
        $exportButton = New-UiDataGridToolbarIconButton -Icon 'SaveLocal' -ToolTip 'Export to CSV'
        [System.Windows.Controls.Grid]::SetColumn($exportButton, $exportBtnColIdx)
        [void]$toolbar.Children.Add($exportButton)

        $gridRef = $DataGrid
        $exportButton.Add_Click({ Invoke-UiDataGridExportToCsv -DataGrid $gridRef  }.GetNewClosure())
    }

    return @{
        Container    = $toolbar
        FilterBox    = $filterBox
        ColumnButton = $colButtona
        CopyButton   = $copyButton
        ExportButton = $exportButton
    }
}
