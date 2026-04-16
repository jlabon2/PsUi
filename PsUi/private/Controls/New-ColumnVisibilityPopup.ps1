function New-ColumnVisibilityPopup {
    <#
    .SYNOPSIS
        Creates a popup button for toggling DataGrid column visibility.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [Parameter(Mandatory)]
        [string[]]$DefaultProperties,

        [Parameter(Mandatory)]
        [string[]]$AllProperties,

        [string[]]$PopulatedProperties
    )

    $colors = Get-ThemeColors

    $colButton = [System.Windows.Controls.Button]@{
        Content = [System.Windows.Controls.TextBlock]@{
            Text       = [PsUi.ModuleContext]::GetIcon('AllApps')
            FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        }
        Padding = 0
        Width   = 32
        Height  = 32
        ToolTip = 'Show/Hide Columns'
        Margin  = [System.Windows.Thickness]::new(0, 0, 4, 0)
    }
    Set-ButtonStyle -Button $colButton -IconOnly

    $popup = [System.Windows.Controls.Primitives.Popup]@{
        PlacementTarget    = $colButton
        Placement          = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
        StaysOpen          = $false
        AllowsTransparency = $true
    }

    $popupBorder = [System.Windows.Controls.Border]@{
        Background      = ConvertTo-UiBrush $colors.ControlBg
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
        Padding         = [System.Windows.Thickness]::new(8)
        CornerRadius    = [System.Windows.CornerRadius]::new(4)
        Tag             = 'PopupBorder'
        MaxHeight       = 400
        Effect          = [System.Windows.Media.Effects.DropShadowEffect]@{
            BlurRadius  = 10
            ShadowDepth = 2
            Opacity     = 0.3
        }
    }

    $scrollViewer = [System.Windows.Controls.ScrollViewer]@{
        VerticalScrollBarVisibility   = 'Auto'
        HorizontalScrollBarVisibility = 'Disabled'
    }

    $checkStack = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Vertical'
    }

    $headerLabel = [System.Windows.Controls.TextBlock]@{
        Text       = 'Visible Columns'
        FontWeight = [System.Windows.FontWeights]::SemiBold
        FontSize   = 12
        Foreground = ConvertTo-UiBrush $colors.ControlFg
        Margin     = [System.Windows.Thickness]::new(0, 0, 0, 8)
    }
    [void]$checkStack.Children.Add($headerLabel)

    # Select All / Unselect All / Default Only buttons
    $buttonPanel = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Horizontal'
        Margin      = [System.Windows.Thickness]::new(0, 0, 0, 4)
    }

    $selectAllBtn = [System.Windows.Controls.Button]@{
        Content = 'All'
        FontSize = 11
        Padding = [System.Windows.Thickness]::new(6, 2, 6, 2)
        Margin  = [System.Windows.Thickness]::new(0, 0, 4, 0)
        ToolTip = 'Show all columns'
    }
    Set-ButtonStyle -Button $selectAllBtn

    $unselectAllBtn = [System.Windows.Controls.Button]@{
        Content = 'None'
        FontSize = 11
        Padding = [System.Windows.Thickness]::new(6, 2, 6, 2)
        Margin  = [System.Windows.Thickness]::new(0, 0, 4, 0)
        ToolTip = 'Hide all columns (except primary)'
    }
    Set-ButtonStyle -Button $unselectAllBtn

    $defaultOnlyBtn = [System.Windows.Controls.Button]@{
        Content = 'Default'
        FontSize = 11
        Padding = [System.Windows.Thickness]::new(6, 2, 6, 2)
        Margin  = [System.Windows.Thickness]::new(0, 0, 4, 0)
        ToolTip = 'Show only default columns'
    }
    Set-ButtonStyle -Button $defaultOnlyBtn

    $populatedBtn = [System.Windows.Controls.Button]@{
        Content = 'Has Data'
        FontSize = 11
        Padding = [System.Windows.Thickness]::new(6, 2, 6, 2)
        ToolTip = 'Show only columns with values'
    }
    Set-ButtonStyle -Button $populatedBtn

    [void]$buttonPanel.Children.Add($selectAllBtn)
    [void]$buttonPanel.Children.Add($unselectAllBtn)
    [void]$buttonPanel.Children.Add($defaultOnlyBtn)
    [void]$buttonPanel.Children.Add($populatedBtn)
    [void]$checkStack.Children.Add($buttonPanel)

    $separator = [System.Windows.Controls.Border]@{
        Height     = 1
        Background = ConvertTo-UiBrush $colors.Border
        Margin     = [System.Windows.Thickness]::new(0, 4, 0, 8)
    }
    [void]$checkStack.Children.Add($separator)

    # Track all checkboxes for Select All / Unselect All
    $allCheckboxes = [System.Collections.Generic.List[System.Windows.Controls.CheckBox]]::new()

    # Create checkbox for each property
    $isFirst = $true
    foreach ($propName in $AllProperties) {
        $checkBox = [System.Windows.Controls.CheckBox]@{
            Content    = $propName
            FontSize   = 12
            Foreground = ConvertTo-UiBrush $colors.ControlFg
            Margin     = [System.Windows.Thickness]::new(0, 2, 0, 2)
            MinWidth   = 150
        }

        # Default properties are shown initially; others start hidden
        $isDefault = $DefaultProperties -contains $propName

        # Sync checkbox state with actual column visibility
        $isVisible = $true
        foreach ($col in $DataGrid.Columns) {
            if ($col.Header -eq $propName) {
                $isVisible = ($col.Visibility -eq [System.Windows.Visibility]::Visible)
                break
            }
        }
        $checkBox.IsChecked = $isVisible

        # Store property name AND default state in tag for the event handlers
        $checkBox.Tag = @{ Name = $propName; IsDefault = $isDefault }

        # First property cannot be unchecked
        if ($isFirst) {
            $checkBox.IsEnabled = $false
            $checkBox.IsChecked = $true
            $checkBox.ToolTip   = 'Primary column cannot be hidden'
            $isFirst            = $false
        }
        else { [void]$allCheckboxes.Add($checkBox) }

        # Wire up the checked/unchecked events
        $checkBox.Add_Checked({
            $propertyName = $this.Tag.Name
            foreach ($col in $DataGrid.Columns) {
                if ($col.Header -eq $propertyName) {
                    $col.Visibility = [System.Windows.Visibility]::Visible
                    break
                }
            }
        }.GetNewClosure())

        $checkBox.Add_Unchecked({
            $propertyName = $this.Tag.Name
            foreach ($col in $DataGrid.Columns) {
                if ($col.Header -eq $propertyName) {
                    $col.Visibility = [System.Windows.Visibility]::Collapsed
                    break
                }
            }
        }.GetNewClosure())

        Set-CheckBoxStyle -CheckBox $checkBox
        [void]$checkStack.Children.Add($checkBox)
    }

    # Wire up Select All button
    $selectAllBtn.Add_Click({
        foreach ($checkbox in $allCheckboxes) {
            $checkbox.IsChecked = $true
        }
    }.GetNewClosure())

    # Wire up Unselect All button
    $unselectAllBtn.Add_Click({
        foreach ($checkbox in $allCheckboxes) {
            $checkbox.IsChecked = $false
        }
    }.GetNewClosure())

    # Wire up Default Only button
    $defaultOnlyBtn.Add_Click({
        foreach ($checkbox in $allCheckboxes) {
            $checkbox.IsChecked = $checkbox.Tag.IsDefault
        }
    }.GetNewClosure())

    # Wire up Has Data button - uses pre-computed populated properties for instant response
    $populatedSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$PopulatedProperties,
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $populatedBtn.Add_Click({
        foreach ($checkbox in $allCheckboxes) {
            $propName = $checkbox.Tag.Name
            $checkbox.IsChecked = $populatedSet.Contains($propName)
        }
    }.GetNewClosure())

    $scrollViewer.Content = $checkStack
    $popupBorder.Child = $scrollViewer
    $popup.Child = $popupBorder
    $colButton.Tag = $popup

    $colButton.Add_Click({
        try { $popup.IsOpen = !$popup.IsOpen }
        catch {
            Write-Verbose "Failed to toggle popup: $_"
        }
    }.GetNewClosure())

    return @{ Button = $colButton; Popup = $popup }
}
