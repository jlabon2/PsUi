
function New-ErrorsTab {
    <#
    .SYNOPSIS
        Creates the Errors tab with DataGrid for error records.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Colors
    )

    $errorsTab = [System.Windows.Controls.TabItem]@{
        Header     = "Errors"
        Visibility = 'Collapsed'
    }
    Set-TabItemStyle -TabItem $errorsTab

    # Container for errors display with toolbar, DataGrid and detail panel
    $errorsContainer = [System.Windows.Controls.Grid]::new()
    $errorsContainer.RowDefinitions.Add([System.Windows.Controls.RowDefinition]@{ Height = [System.Windows.GridLength]::Auto })
    $errorsContainer.RowDefinitions.Add([System.Windows.Controls.RowDefinition]@{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })
    $errorsContainer.RowDefinitions.Add([System.Windows.Controls.RowDefinition]@{ Height = [System.Windows.GridLength]::Auto })

    # Errors toolbar - DockPanel for left/right alignment
    $errorsToolbar = [System.Windows.Controls.DockPanel]@{
        Margin = [System.Windows.Thickness]::new(8, 8, 8, 4)
    }
    [System.Windows.Controls.Grid]::SetRow($errorsToolbar, 0)

    $filterPanel = [System.Windows.Controls.StackPanel]@{
        Orientation       = 'Horizontal'
        VerticalAlignment = 'Center'
    }
    [System.Windows.Controls.DockPanel]::SetDock($filterPanel, 'Left')

    $filterResult    = New-FilterBoxWithClear -Width 180 -Height 26 -IncludeIcon
    $errorsFilterBox = $filterResult.TextBox
    [void]$filterPanel.Children.Add($filterResult.Icon)
    [void]$filterPanel.Children.Add($filterResult.Container)
    [void]$errorsToolbar.Children.Add($filterPanel)

    $rightPanel = [System.Windows.Controls.StackPanel]@{
        Orientation         = 'Horizontal'
        HorizontalAlignment = 'Right'
        VerticalAlignment   = 'Center'
    }
    [System.Windows.Controls.DockPanel]::SetDock($rightPanel, 'Right')

    $errorsCopyInfo = New-UiIconButton -IconChar ([PsUi.ModuleContext]::GetIcon('Copy')) -ToolTip 'Copy All Errors' -Margin ([System.Windows.Thickness]::new(0, 0, 4, 0)) -ReturnIcon
    $errorsCopyBtn  = $errorsCopyInfo.Button
    $errorsCopyIcon = $errorsCopyInfo.Icon
    [void]$rightPanel.Children.Add($errorsCopyBtn)

    $errorsExportInfo = New-UiIconButton -IconChar ([PsUi.ModuleContext]::GetIcon('Export')) -ToolTip 'Export Errors to CSV' -ReturnIcon
    $errorsExportBtn  = $errorsExportInfo.Button
    $errorsExportIcon = $errorsExportInfo.Icon
    [void]$rightPanel.Children.Add($errorsExportBtn)

    [void]$errorsToolbar.Children.Add($rightPanel)
    [void]$errorsContainer.Children.Add($errorsToolbar)

    # Collection to hold error records for the DataGrid
    $errorsList = [System.Collections.ObjectModel.ObservableCollection[PSObject]]::new()

    # Create errors DataGrid
    $errorsDataGrid = [System.Windows.Controls.DataGrid]@{
        IsReadOnly                   = $true
        AutoGenerateColumns          = $false
        CanUserAddRows               = $false
        CanUserDeleteRows            = $false
        CanUserReorderColumns        = $false
        SelectionMode                = 'Extended'
        GridLinesVisibility          = 'Horizontal'
        Background                   = ConvertTo-UiBrush $Colors.ControlBg
        BorderBrush                  = ConvertTo-UiBrush $Colors.Border
        RowBackground                = ConvertTo-UiBrush $Colors.ControlBg
        AlternatingRowBackground     = ConvertTo-UiBrush $(if ($Colors.AlternateBg) { $Colors.AlternateBg } else { $Colors.ControlBg })
        HorizontalGridLinesBrush     = ConvertTo-UiBrush $Colors.Border
        HeadersVisibility            = 'Column'
    }

    $timeColumn         = [System.Windows.Controls.DataGridTextColumn]::new()
    $timeColumn.Header  = "Time"
    $timeColumn.Width   = [System.Windows.Controls.DataGridLength]::new(75)
    $timeColumn.Binding = [System.Windows.Data.Binding]::new("Time")
    [void]$errorsDataGrid.Columns.Add($timeColumn)

    $lineColumn         = [System.Windows.Controls.DataGridTextColumn]::new()
    $lineColumn.Header  = "Line"
    $lineColumn.Width   = [System.Windows.Controls.DataGridLength]::new(50)
    $lineColumn.Binding = [System.Windows.Data.Binding]::new("LineNumber")
    [void]$errorsDataGrid.Columns.Add($lineColumn)

    $categoryColumn         = [System.Windows.Controls.DataGridTextColumn]::new()
    $categoryColumn.Header  = "Category"
    $categoryColumn.Width   = [System.Windows.Controls.DataGridLength]::new(100)
    $categoryColumn.Binding = [System.Windows.Data.Binding]::new("Category")
    [void]$errorsDataGrid.Columns.Add($categoryColumn)

    $messageColumn         = [System.Windows.Controls.DataGridTextColumn]::new()
    $messageColumn.Header  = "Message"
    $messageColumn.Width   = [System.Windows.Controls.DataGridLength]::new(1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
    $messageColumn.Binding = [System.Windows.Data.Binding]::new("Message")
    [void]$errorsDataGrid.Columns.Add($messageColumn)

    $errorsDataGrid.ItemsSource = $errorsList
    Set-DataGridStyle -Grid $errorsDataGrid
    New-DataGridContextMenu -DataGrid $errorsDataGrid
    [System.Windows.Controls.Grid]::SetRow($errorsDataGrid, 1)
    [void]$errorsContainer.Children.Add($errorsDataGrid)

    # Track unfiltered errors for collection-based filtering
    $unfilteredErrors = [System.Collections.Generic.List[object]]::new()

    $originalTag = $errorsFilterBox.Tag
    $errorsFilterBox.Tag = @{
        DataGrid         = $errorsDataGrid
        Timer            = $null
        ClearButton      = $originalTag.ClearButton
        Watermark        = $originalTag.Watermark
        UnfilteredErrors = $unfilteredErrors
        ErrorsList       = $errorsList
    }

    $errorsFilterBox.Add_TextChanged({
        $tag = $this.Tag

        # Show/hide clear button and watermark
        $isEmpty = [string]::IsNullOrEmpty($this.Text)
        if ($tag.ClearButton) {
            $tag.ClearButton.Visibility = if ($isEmpty) { 'Collapsed' } else { 'Visible' }
        }
        if ($tag.Watermark) {
            $tag.Watermark.Visibility = if ($isEmpty) { 'Visible' } else { 'Collapsed' }
        }

        if ($tag.Timer) {
            $tag.Timer.Stop()
            $tag.Timer = $null
        }

        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(250)
        $timer.Tag = $this
        $tag.Timer = $timer

        $timer.Add_Tick({
            $this.Stop()
            $filterBox = $this.Tag
            $grid      = $filterBox.Tag.DataGrid
            $text      = $filterBox.Text.Trim().ToLower()
            $unfilteredList = $filterBox.Tag.UnfilteredErrors
            $errorsList     = $filterBox.Tag.ErrorsList

            # Sync unfiltered list with any new errors added since last filter
            # (errors are added to errorsList dynamically)
            foreach ($item in $errorsList) {
                if (!$unfilteredList.Contains($item)) {
                    [void]$unfilteredList.Add($item)
                }
            }

            # Capture sort state before rebuild
            $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($errorsList)
            $sortDescriptions = @()
            if ($view) {
                foreach ($sd in $view.SortDescriptions) {
                    $sortDescriptions += $sd
                }
            }

            # Clear and repopulate
            $errorsList.Clear()

            foreach ($item in $unfilteredList) {
                if ([string]::IsNullOrEmpty($text)) {
                    [void]$errorsList.Add($item)
                }
                else {
                    $details = if ($item._ErrorDetails) { $item._ErrorDetails.ToString().ToLower() } else { '' }
                    if ($details -like "*$text*") {
                        [void]$errorsList.Add($item)
                    }
                }
            }

            # Reapply sort
            if ($view -and $sortDescriptions.Count -gt 0) {
                $view.SortDescriptions.Clear()
                foreach ($sd in $sortDescriptions) {
                    $view.SortDescriptions.Add($sd)
                }
            }
        }.GetNewClosure())
        $timer.Start()
    }.GetNewClosure())

    $errorsTab.Content = $errorsContainer

    return @{
        Tab           = $errorsTab
        Container     = $errorsContainer
        DataGrid      = $errorsDataGrid
        List          = $errorsList
        FilterBox     = $errorsFilterBox
        CopyButton    = $errorsCopyBtn
        ExportButton  = $errorsExportBtn
    }
}
