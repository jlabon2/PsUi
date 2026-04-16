function New-ResultsToolbar {
    <#
    .SYNOPSIS
        Creates the Results tab toolbar with action buttons.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Colors,

        [array]$ResultActions
    )

    $resultsTab = [System.Windows.Controls.TabItem]::new()
    Set-TabItemStyle -TabItem $resultsTab

    $resultsPanel = [System.Windows.Controls.DockPanel]::new()
    $resultsPanel.LastChildFill = $true

    $toolbar = [System.Windows.Controls.StackPanel]::new()
    $toolbar.Orientation = 'Horizontal'
    $toolbar.Margin = [System.Windows.Thickness]::new(12, 12, 12, 8)
    [System.Windows.Controls.DockPanel]::SetDock($toolbar, 'Top')

    $actionDropdownMenuStack = $null
    $dropdownPopup = $null

    if ($ResultActions -and $ResultActions.Count -gt 0) {
        $dropdownParams = @{
            Actions    = $ResultActions
            ButtonText = 'Actions'
            ButtonIcon = 'ActionCenter'
            Tooltip    = 'Available actions for selected items'
        }
        $dropdownResult = New-ActionDropdownButton @dropdownParams
        $dropdownPopup = $dropdownResult.Popup
        $actionDropdownMenuStack = $dropdownResult.MenuStack
        [void]$toolbar.Children.Add($dropdownResult.Button)
    }

    $toolbar2 = [System.Windows.Controls.DockPanel]::new()
    $toolbar2.LastChildFill = $false
    $toolbar2.Margin = [System.Windows.Thickness]::new(12, 12, 12, 8)
    [System.Windows.Controls.DockPanel]::SetDock($toolbar2, 'Top')

    [System.Windows.Controls.DockPanel]::SetDock($toolbar, 'Left')
    [void]$toolbar2.Children.Add($toolbar)

    $rightToolbar = [System.Windows.Controls.StackPanel]::new()
    $rightToolbar.Orientation = 'Horizontal'
    [System.Windows.Controls.DockPanel]::SetDock($rightToolbar, 'Right')

    $exportBtnInfo = New-UiIconButton -IconChar ([PsUi.ModuleContext]::GetIcon('Export')) -ToolTip 'Export to CSV' -Margin ([System.Windows.Thickness]::new(0, 0, 4, 0)) -ReturnIcon
    $exportButton = $exportBtnInfo.Button
    $exportButton.Visibility = 'Collapsed'
    [void]$rightToolbar.Children.Add($exportButton)

    $copyBtnInfo = New-UiIconButton -IconChar ([PsUi.ModuleContext]::GetIcon('Copy')) -ToolTip 'Copy to Clipboard' -ReturnIcon
    $copyButton = $copyBtnInfo.Button
    [void]$rightToolbar.Children.Add($copyButton)

    $closeButton = New-UiIconButton -IconChar ([PsUi.ModuleContext]::GetIcon('Cancel')) -ToolTip 'Close' -Margin ([System.Windows.Thickness]::new(4, 0, 0, 0))
    $closeButton.Add_Click({ Close-UiParentWindow -Control $this }.GetNewClosure())
    [void]$rightToolbar.Children.Add($closeButton)

    [void]$toolbar2.Children.Add($rightToolbar)

    $filterPanel = [System.Windows.Controls.StackPanel]::new()
    $filterPanel.Orientation = 'Horizontal'
    $filterPanel.VerticalAlignment = 'Center'
    $filterPanel.HorizontalAlignment = 'Left'

    [void]$resultsPanel.Children.Add($toolbar2)

    $resultsBorder = [System.Windows.Controls.Border]::new()
    $resultsBorder.BorderBrush = ConvertTo-UiBrush $Colors.Border
    $resultsBorder.BorderThickness = [System.Windows.Thickness]::new(1)
    $resultsBorder.Background = ConvertTo-UiBrush $Colors.WindowBg
    $resultsBorder.Margin = [System.Windows.Thickness]::new(12, 0, 12, 12)
    [void]$resultsPanel.Children.Add($resultsBorder)

    return @{
        Tab                     = $resultsTab
        Panel                   = $resultsPanel
        Toolbar                 = $toolbar
        Toolbar2                = $toolbar2
        RightToolbar            = $rightToolbar
        FilterPanel             = $filterPanel
        ResultsBorder           = $resultsBorder
        ExportButton            = $exportButton
        CopyButton              = $copyButton
        CloseButton             = $closeButton
        DropdownPopup           = $dropdownPopup
        ActionDropdownMenuStack = $actionDropdownMenuStack
    }
}
