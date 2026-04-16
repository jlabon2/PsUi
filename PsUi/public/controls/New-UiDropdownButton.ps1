function New-UiDropdownButton {
    <#
    .SYNOPSIS
        Creates a compact popup button with selectable items.
    .DESCRIPTION
        Creates a button that displays a dropdown popup with selectable items when clicked.
        Similar to a ComboBox but styled as a compact icon button, ideal for panel headers
        or toolbar-style UIs. Supports an OnChange callback when the selection changes.
    .PARAMETER Items
        Array of items to display in the popup.
    .PARAMETER Default
        The default selected item.
    .PARAMETER Variable
        Variable name to register the control with for hydration access.
    .PARAMETER Icon
        Icon name from Segoe MDL2 Assets (e.g., 'ChevronDown', 'Settings', 'Filter').
        Default is 'ChevronDown'.
    .PARAMETER Tooltip
        Tooltip text shown on hover.
    .PARAMETER OnChange
        ScriptBlock to execute when selection changes. Receives the new selection as parameter.
    .PARAMETER Width
        Button width in pixels. Default is 32.
    .PARAMETER Height
        Button height in pixels. Default is 32.
    .PARAMETER ShowText
        Show the selected item text next to the icon.
    .PARAMETER NoAutoAdd
        Don't automatically add the dropdown to the current layout panel.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to apply to the container.
    .EXAMPLE
        New-UiDropdownButton -Items @('Option1', 'Option2', 'Option3') -Default 'Option1' -Tooltip "Select Option"
    .EXAMPLE
        New-UiDropdownButton -Items $parameterSets -Variable 'selectedSet' -Icon 'Filter' -OnChange {
            param($newValue)
            Write-Host "Selected: $newValue"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Items,

        [string]$Default,

        [string]$Variable,

        [string]$Tooltip,

        [scriptblock]$OnChange,

        [int]$Width = 32,

        [int]$Height = 32,

        [switch]$ShowText,

        [switch]$NoAutoAdd,

        [hashtable]$WPFProperties
    )

    DynamicParam {
        Get-IconDynamicParameter -ParameterName 'Icon' -DefaultValue 'ChevronDown'
    }

    begin {
        $Icon = if ($PSBoundParameters.ContainsKey('Icon')) { $PSBoundParameters['Icon'] } else { 'ChevronDown' }
    }

    process {

    # Grab session context and theme colors
    $colors  = Get-ThemeColors
    $session = Get-UiSession
    $parent  = $session.CurrentParent
    Write-Debug "Creating dropdown button with $($Items.Count) items"

    # Determine initial selection
    $currentSelection = if ($Default -and $Items -contains $Default) { $Default } else { $Items[0] }
    Write-Debug "Initial selection: $currentSelection"

    $container = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Horizontal'
        Margin      = [System.Windows.Thickness]::new(0, 0, 4, 0)
        Tag         = @{ SelectedItem = $currentSelection; ControlType = 'ComboButton' }
    }

    $button = [System.Windows.Controls.Button]@{
        Height            = $Height
        Padding           = [System.Windows.Thickness]::new(0)
        VerticalAlignment = 'Center'
    }
    if ($Tooltip) { $button.ToolTip = $Tooltip }

    $buttonContent = [System.Windows.Controls.StackPanel]@{
        Orientation       = 'Horizontal'
        VerticalAlignment = 'Center'
    }

    if ($ShowText) {
        $button.Width = [double]::NaN
        $button.Padding = [System.Windows.Thickness]::new(8, 4, 8, 4)

        $textBlock = [System.Windows.Controls.TextBlock]@{
            Text              = $currentSelection
            VerticalAlignment = 'Center'
            Margin            = [System.Windows.Thickness]::new(0, 0, 6, 0)
            Tag               = 'ComboButtonText'
        }
        [PsUi.ThemeEngine]::RegisterElement($textBlock)
        [void]$buttonContent.Children.Add($textBlock)
    }
    else {
        $button.Width = $Width
    }

    # Icon
    $iconBlock = [System.Windows.Controls.TextBlock]@{
        FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize            = 12
        HorizontalAlignment = 'Center'
        VerticalAlignment   = 'Center'
    }

    # Map icon name to character
    $iconChar = [PsUi.ModuleContext]::GetIcon($Icon)
    if (!$iconChar) {
        # Fallback for legacy icon names
        $iconChar = switch ($Icon) {
            'ChevronDown' { [PsUi.ModuleContext]::GetIcon('ChevronDown') }
            'Filter'      { [PsUi.ModuleContext]::GetIcon('Filter') }
            'Settings'    { [PsUi.ModuleContext]::GetIcon('Settings') }
            'List'        { [PsUi.ModuleContext]::GetIcon('BulletList') }
            'More'        { [PsUi.ModuleContext]::GetIcon('More') }
            default       { [PsUi.ModuleContext]::GetIcon('ChevronDown') }
        }
    }
    $iconBlock.Text = $iconChar
    $iconBlock.Tag = 'ComboButtonText'
    [PsUi.ThemeEngine]::RegisterElement($iconBlock)
    [void]$buttonContent.Children.Add($iconBlock)

    $button.Content = $buttonContent
    Set-ButtonStyle -Button $button -IconOnly:(!$ShowText)

    # Create popup
    $popup = [System.Windows.Controls.Primitives.Popup]@{
        PlacementTarget    = $button
        Placement          = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
        StaysOpen          = $false
        AllowsTransparency = $true
    }

    # Popup border with shadow - use ControlBg for themed background (matches theme popup)
    $popupBorder = [System.Windows.Controls.Border]@{
        Background      = ConvertTo-UiBrush $colors.ControlBg
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
        Padding         = [System.Windows.Thickness]::new(4)
        CornerRadius    = [System.Windows.CornerRadius]::new(4)
        Tag             = 'PopupBorder'
    }

    $shadow = [System.Windows.Media.Effects.DropShadowEffect]@{
        BlurRadius  = 10
        ShadowDepth = 2
        Opacity     = 0.3
    }
    $popupBorder.Effect = $shadow

    # Items stack
    $itemsStack = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Vertical'
    }

    foreach ($item in $Items) {
        $itemButton = [System.Windows.Controls.Button]@{
            Height                      = 32
            MinWidth                    = 120
            HorizontalContentAlignment  = 'Left'
            Padding                     = [System.Windows.Thickness]::new(8, 4, 8, 4)
            Margin                      = [System.Windows.Thickness]::new(2)
        }

        $itemStack = [System.Windows.Controls.StackPanel]@{
            Orientation = 'Horizontal'
        }

        # Checkmark for selected item
        $checkmark = [System.Windows.Controls.TextBlock]@{
            Text       = if ($item -eq $currentSelection) { [char]0x2713 } else { ' ' }
            FontSize   = 14
            Width      = 20
            Foreground = ConvertTo-UiBrush $colors.Accent
            Tag        = 'AccentText'
        }
        [void]$itemStack.Children.Add($checkmark)

        # Item text
        $itemLabel = [System.Windows.Controls.TextBlock]@{
            Text              = $item
            FontSize          = 12
            VerticalAlignment = 'Center'
            Foreground        = ConvertTo-UiBrush $colors.ControlFg
        }
        [void]$itemStack.Children.Add($itemLabel)

        $itemButton.Content = $itemStack
        $itemButton.Tag = @{
            ItemValue = $item
            Checkmark = $checkmark
            Container = $container
            TextBlock = if ($ShowText) { $textBlock } else { $null }
            ItemsStack = $itemsStack
            OnChange = $OnChange
        }

        Set-ButtonStyle -Button $itemButton

        # Click handler for item selection
        $itemButton.Add_Click({
            $tag = $this.Tag
            $selectedValue = $tag.ItemValue
            $containerRef = $tag.Container

            # Update container's selected item
            $containerRef.Tag.SelectedItem = $selectedValue

            # Update checkmarks in all items
            foreach ($child in $tag.ItemsStack.Children) {
                if ($child -is [System.Windows.Controls.Button] -and $child.Tag) {
                    $childTag = $child.Tag
                    if ($childTag.Checkmark) {
                        $childTag.Checkmark.Text = if ($childTag.ItemValue -eq $selectedValue) { [char]0x2713 } else { ' ' }
                    }
                }
            }

            # Update button text if ShowText
            if ($tag.TextBlock) {
                $tag.TextBlock.Text = $selectedValue
            }

            # Close popup
            $popup.IsOpen = $false

            # Fire OnChange callback
            if ($tag.OnChange) {
                try {
                    & $tag.OnChange $selectedValue
                }
                catch {
                    Write-Warning "OnChange callback error: $_"
                }
            }
        }.GetNewClosure())

        [void]$itemsStack.Children.Add($itemButton)
    }

    $popupBorder.Child = $itemsStack
    $popup.Child = $popupBorder
    $button.Tag = $popup

    # Refresh colors when popup opens (handles theme changes after initial creation)
    $popup.Add_Opened({
        $freshColors = Get-ThemeColors
        $popupBorder.Background = ConvertTo-UiBrush $freshColors.ControlBg
        $popupBorder.BorderBrush = ConvertTo-UiBrush $freshColors.Border

        # Update text colors in all items
        foreach ($child in $itemsStack.Children) {
            if ($child -is [System.Windows.Controls.Button]) {
                $content = $child.Content
                if ($content -is [System.Windows.Controls.StackPanel]) {
                    foreach ($textElem in $content.Children) {
                        if ($textElem -is [System.Windows.Controls.TextBlock]) {
                            if ($textElem.Tag -eq 'AccentText') {
                                $textElem.Foreground = ConvertTo-UiBrush $freshColors.Accent
                            }
                            else {
                                $textElem.Foreground = ConvertTo-UiBrush $freshColors.ControlFg
                            }
                        }
                    }
                }
            }
        }
    }.GetNewClosure())

    # Button click toggles popup
    $button.Add_Click({
        try { $popup.IsOpen = !$popup.IsOpen }
        catch { Write-Verbose "Failed to toggle popup: $_" }
    }.GetNewClosure())

    [void]$container.Children.Add($button)

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $container -Properties $WPFProperties
    }

    # Register with session if Variable provided
    if ($Variable) {
        Write-Debug "Registering as '$Variable'"
        $session.AddControlSafe($Variable, $container)
    }

    # Add to parent panel unless caller wants manual placement
    if (!$NoAutoAdd) {
        [void]$parent.Children.Add($container)
    }

    return @{
        Container = $container
        Button = $button
        Popup = $popup
        GetValue = { $container.Tag.SelectedItem }.GetNewClosure()
        SetValue = {
            param($newValue)
            if ($Items -contains $newValue) {
                $container.Tag.SelectedItem = $newValue
                if ($ShowText -and $textBlock) { $textBlock.Text = $newValue }
                foreach ($child in $itemsStack.Children) {
                    if ($child -is [System.Windows.Controls.Button] -and $child.Tag) {
                        $child.Tag.Checkmark.Text = if ($child.Tag.ItemValue -eq $newValue) { [char]0x2713 } else { ' ' }
                    }
                }
            }
        }.GetNewClosure()
    }
    }
}
