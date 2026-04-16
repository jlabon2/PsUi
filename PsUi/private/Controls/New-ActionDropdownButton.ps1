function New-ActionDropdownButton {
    <#
    .SYNOPSIS
        Creates a dropdown button containing multiple action items.
        This is what appears in SHow-UIOutput to select added actions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable[]]$Actions,

        [string]$ButtonText = 'Actions',

        [string]$ButtonIcon = 'ActionCenter',

        [string]$Tooltip = 'Available actions',

        [switch]$NoDefaultClickHandler
    )

    $colors = Get-ThemeColors

    $button = [System.Windows.Controls.Button]@{
        Width   = 120
        Height  = 32
        Padding = [System.Windows.Thickness]::new(8, 2, 8, 2)
        Margin  = [System.Windows.Thickness]::new(0, 0, 4, 0)
        ToolTip = $Tooltip
    }

    $buttonStack = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Horizontal'
    }

    $iconChar = [PsUi.ModuleContext]::GetIcon($ButtonIcon)
    if ($iconChar) {
        $iconText = [System.Windows.Controls.TextBlock]@{
            Text       = $iconChar
            FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            FontSize   = 14
            Margin     = [System.Windows.Thickness]::new(0, 0, 6, 0)
            VerticalAlignment = 'Center'
        }
        [void]$buttonStack.Children.Add($iconText)
    }

    $textBlock = [System.Windows.Controls.TextBlock]@{
        Text              = $ButtonText
        VerticalAlignment = 'Center'
    }
    [void]$buttonStack.Children.Add($textBlock)

    $chevron = [System.Windows.Controls.TextBlock]@{
        Text       = [PsUi.ModuleContext]::GetIcon('ChevronDown')
        FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize   = 10
        Margin     = [System.Windows.Thickness]::new(6, 0, 0, 0)
        VerticalAlignment = 'Center'
    }
    [void]$buttonStack.Children.Add($chevron)

    $button.Content = $buttonStack
    Set-ButtonStyle -Button $button

    $popup = [System.Windows.Controls.Primitives.Popup]@{
        PlacementTarget    = $button
        Placement          = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
        StaysOpen          = $false
        AllowsTransparency = $true
    }

    $popupBorder = [System.Windows.Controls.Border]@{
        Background      = ConvertTo-UiBrush $colors.ControlBg
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
        Padding         = [System.Windows.Thickness]::new(4)
        CornerRadius    = [System.Windows.CornerRadius]::new(4)
        Tag             = 'PopupBorder'
        Effect          = [System.Windows.Media.Effects.DropShadowEffect]@{
            BlurRadius  = 10
            ShadowDepth = 2
            Opacity     = 0.3
        }
    }

    $menuStack = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Vertical'
    }

    # Create menu items for each action
    foreach ($actionDef in $Actions) {
        if (!$actionDef.Text -or !$actionDef.Action) { continue }

        $menuItem = [System.Windows.Controls.Button]@{
            Height                     = 32
            MinWidth                   = 140
            HorizontalContentAlignment = 'Left'
            Padding                    = [System.Windows.Thickness]::new(8, 4, 12, 4)
            Margin                     = [System.Windows.Thickness]::new(2)
        }

        $itemStack = [System.Windows.Controls.StackPanel]@{
            Orientation = 'Horizontal'
        }

        $actionIconChar = [PsUi.ModuleContext]::GetIcon($actionDef.Icon)
        if ($actionIconChar) {

            $actionIcon = [System.Windows.Controls.TextBlock]@{
                Text       = $actionIconChar
                FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
                FontSize   = 14
                Width      = 24
                VerticalAlignment = 'Center'
            }

            [void]$itemStack.Children.Add($actionIcon)
        }
        else {
            # Spacer for alignment when no icon
            [void]$itemStack.Children.Add([System.Windows.Controls.Border]@{ Width = 24 })
        }

        $actionText = [System.Windows.Controls.TextBlock]@{
            Text              = $actionDef.Text
            FontSize          = 12
            VerticalAlignment = 'Center'
        }
        [void]$itemStack.Children.Add($actionText)

        $menuItem.Content = $itemStack
        $menuItem.Tag     = $actionDef
        Set-ButtonStyle -Button $menuItem

        # Click handlers wired by caller (Show-UiOutput) for async execution
        [void]$menuStack.Children.Add($menuItem)
    }

    $popupBorder.Child = $menuStack
    $popup.Child = $popupBorder

    # Toggle popup on button click (unless caller wants custom handling)
    if (!$NoDefaultClickHandler) {
        $button.Add_Click({ $popup.IsOpen = !$popup.IsOpen }.GetNewClosure())
    }

    return @{
        Button    = $button
        Popup     = $popup
        MenuStack = $menuStack
    }
}
