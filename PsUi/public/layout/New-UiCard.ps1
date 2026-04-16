function New-UiCard {
    <#
    .SYNOPSIS
        Creates a bordered card container for content display.
    .DESCRIPTION
        Creates a styled card container with optional header, icon, and accent color.
        Ideal for dashboard tiles, summary boxes, status displays, and grouped information.
    .PARAMETER Header
        Optional header text displayed at the top of the card.
    .PARAMETER Content
        ScriptBlock containing the card's content controls.
    .PARAMETER Icon
        Optional icon name from Segoe MDL2 Assets to display in the header.
    .PARAMETER Accent
        Use the theme's accent color for the card header/border.
    .PARAMETER HeaderBackground
        Custom background color for the header (hex color like '#0078D4').
    .PARAMETER MinWidth
        Minimum width of the card. Default is 200.
    .PARAMETER MinHeight
        Minimum height of the card.
    .PARAMETER FullWidth
        When present, the card expands to fill the full width of its container.
    .PARAMETER Stretch
        When present, the card participates in the responsive column system.
        Cards will resize dynamically based on window width and MaxColumns setting.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
    .EXAMPLE
        New-UiCard -Header "System Status" -Icon "Info" -Content {
            New-UiLabel -Text "All systems operational" -Style Body
        }
    .EXAMPLE
        New-UiCard -Header "Statistics" -Accent -Content {
            New-UiLabel -Text "Users: 142" -Style SubHeader
            New-UiLabel -Text "Active sessions: 28" -Style Body
        }
    .EXAMPLE
        New-UiCard -Content {
            New-UiLabel -Text "Simple card without header" -Style Body
        }
    #>
    [CmdletBinding()]
    param(
        [string]$Header,

        [Parameter(Mandatory)]
        [scriptblock]$Content,

        [switch]$Accent,

        [string]$HeaderBackground,

        [int]$MinWidth = 200,

        [int]$MinHeight,

        [switch]$FullWidth,

        [switch]$Stretch,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    DynamicParam {
        Get-IconDynamicParameter -ParameterName 'Icon'
    }

    begin {
        $Icon = $PSBoundParameters['Icon']
    }

    process {

    $session = Assert-UiSession -CallerName 'New-UiCard'
    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent
    Write-Debug "Header: '$Header', Accent: $($Accent.IsPresent), Parent: $($parent.GetType().Name)"

    # Create outer border (the card container)
    $card = [System.Windows.Controls.Border]@{
        BorderThickness = [System.Windows.Thickness]::new(1)
        CornerRadius    = [System.Windows.CornerRadius]::new(4)
        Margin          = [System.Windows.Thickness]::new(4)
        MinWidth        = $MinWidth
        Background      = ConvertTo-UiBrush $colors.ControlBg
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        SnapsToDevicePixels = $true
        Tag             = 'CardBorder'
    }

    if ($MinHeight -gt 0) {
        $card.MinHeight = $MinHeight
    }

    # Add subtle shadow effect
    try {
        $shadow = [System.Windows.Media.Effects.DropShadowEffect]@{
            BlurRadius  = 8
            ShadowDepth = 2
            Opacity     = 0.15
            Color       = [System.Windows.Media.Colors]::Black
        }
        $card.Effect = $shadow
    }
    catch {
        Write-Verbose "Failed to apply shadow effect: $_"
    }

    # Main content container
    $mainStack = [System.Windows.Controls.StackPanel]::new()

    # Add header if specified
    if ($Header) {
        # Store whether this is an accent header for theme updates
        $isAccentHeader = $Accent -or ($HeaderBackground -ne $null -and $HeaderBackground -ne '')

        $headerBorder = [System.Windows.Controls.Border]@{
            Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
            CornerRadius = [System.Windows.CornerRadius]::new(3, 3, 0, 0)
            Tag = @{ Type = 'CardHeader'; IsAccent = $isAccentHeader; CustomColor = $HeaderBackground }
        }

        # Determine header background color
        if ($HeaderBackground) {
            $headerBorder.Background = ConvertTo-UiBrush $HeaderBackground
        }
        elseif ($Accent) {
            $headerBorder.Background = ConvertTo-UiBrush $colors.Accent
        }
        else {
            # Subtle header background
            $headerBgColor = if ($colors.GroupBoxBg) { $colors.GroupBoxBg } else { $colors.WindowBg }
            $headerBorder.Background = ConvertTo-UiBrush $headerBgColor
        }

        # Header content (icon + text)
        $headerPanel = [System.Windows.Controls.StackPanel]@{
            Orientation = [System.Windows.Controls.Orientation]::Horizontal
        }

        # Add icon if specified
        if ($Icon) {
            # Get icon character from cached module context
            $iconChar = [PsUi.ModuleContext]::GetIcon($Icon)

            if ($iconChar) {
                # Icon color logic:
                # If Accent is used, the header background is the accent color.
                # Use AccentHeaderForegroundBrush for contrast against accent bg.
                # If NOT Accent, we use the Accent color for the icon to make it pop.
                
                $iconBrushKey = 'AccentBrush'
                $iconForeground = $null

                if ($Accent) {
                    # Header is Accent -> Icon needs contrast against accent background
                    $iconForeground = ConvertTo-UiBrush $colors.AccentHeaderFg
                    $iconBrushKey = 'AccentHeaderForegroundBrush'
                }
                else {
                    # Header is Neutral -> Icon is Accent
                    $iconForeground = ConvertTo-UiBrush $colors.Accent
                    $iconBrushKey = 'AccentBrush'
                }

                $iconBlock = [System.Windows.Controls.TextBlock]@{
                    Text       = $iconChar
                    FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
                    FontSize   = 16
                    Foreground = $iconForeground
                    VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                    Margin     = [System.Windows.Thickness]::new(0, 0, 8, 0)
                    Tag        = $iconBrushKey
                }
                [PsUi.ThemeEngine]::RegisterElement($iconBlock)
                [void]$headerPanel.Children.Add($iconBlock)
            }
        }

        # Header text
        $headerBgForText = if ($HeaderBackground) { $HeaderBackground } else { $colors.Accent }
        
        # Determine text brush key for theme updates
        $textBrushKey = 'ControlFgBrush'
        $headerForeground = $null

        if ($Accent -and !$HeaderBackground) {
            # Accent Header -> Text needs contrast against accent background
            $headerForeground = ConvertTo-UiBrush $colors.AccentHeaderFg
            $textBrushKey = 'AccentHeaderForegroundBrush'
        }
        elseif ($HeaderBackground) {
            # Custom Header -> Calculate contrast
            $headerForeground = ConvertTo-UiBrush (Get-ContrastColor -HexColor $HeaderBackground)
            # No brush key for custom colors
        }
        else {
            # Standard Header -> Standard Text
            $headerForeground = ConvertTo-UiBrush $colors.ControlFg
            $textBrushKey = 'ControlForegroundBrush'
        }

        $headerText = [System.Windows.Controls.TextBlock]@{
            Text       = $Header
            FontSize   = 14
            FontWeight = [System.Windows.FontWeights]::SemiBold
            Foreground = $headerForeground
            VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            Tag        = $textBrushKey
        }
        # Only register if not using custom color
        if (!$HeaderBackground) {
            [PsUi.ThemeEngine]::RegisterElement($headerText)
        }
        [void]$headerPanel.Children.Add($headerText)

        # Store accent info on header panel for theme updates
        $headerPanel.Tag = @{ Type = 'CardHeaderPanel'; IsAccent = $isAccentHeader; CustomColor = $HeaderBackground }

        $headerBorder.Child = $headerPanel
        
        # Register header border for theme updates (unless using custom color)
        if (!$HeaderBackground) {
            [PsUi.ThemeEngine]::RegisterElement($headerBorder)
        }
        [void]$mainStack.Children.Add($headerBorder)

        # Add separator line
        $separator = [System.Windows.Controls.Border]@{
            Height     = 1
            Background = ConvertTo-UiBrush $colors.Border
            Tag        = 'CardSeparator'
        }
        [PsUi.ThemeEngine]::RegisterElement($separator)
        [void]$mainStack.Children.Add($separator)
    }

    $contentPanel = [System.Windows.Controls.StackPanel]@{
        Margin = [System.Windows.Thickness]::new(12, 10, 12, 12)
    }

    # Set content panel as current parent and execute content
    $oldParent = $session.CurrentParent
    $session.CurrentParent = $contentPanel

    # Execute content - restore parent outside try/finally for PS 5.1 closure compatibility
    try {
        Invoke-UiContent -Content $Content -CallerName 'New-UiCard' -ErrorAction Stop
    }
    catch {
        # Restore parent before re-throwing
        $session.CurrentParent = $oldParent
        throw
    }
    
    # Restore parent after successful content execution
    $session.CurrentParent = $oldParent

    [void]$mainStack.Children.Add($contentPanel)
    $card.Child = $mainStack

    # Width constraints
    if ($parent -is [System.Windows.Controls.WrapPanel]) {
        $card.HorizontalAlignment = 'Stretch'

        # FullWidth in WrapPanel context means span the entire panel width
        if ($FullWidth) {
            Set-FullWidthConstraint -Control $card -Parent $parent -FullWidth
        }
    }
    elseif ($Stretch) {
        # Use responsive column system - card will resize with window
        Set-ResponsiveConstraints -Control $card -FullWidth:$FullWidth
    }
    elseif ($FullWidth) {
        # Full width only (no responsive columns)
        Set-FullWidthConstraint -Control $card -Parent $parent -FullWidth:$FullWidth
    }

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $card -Properties $WPFProperties
    }

    [void]$parent.Children.Add($card)
    Write-Debug "Card added to parent"

    # Register with ThemeEngine for theme updates
    try {
        [PsUi.ThemeEngine]::RegisterElement($card)
    }
    catch {
        Write-Verbose "Failed to register Card with ThemeEngine: $_"
    }
    }
}
