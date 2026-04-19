function New-UiExpander {
    <#
    .SYNOPSIS
        Creates a collapsible expander section with a header and content area.
    .DESCRIPTION
        Creates a theme-aware collapsible section. Click the header to toggle visibility
        of the content. Built from primitives for proper dark theme support.
    .PARAMETER Header
        The text displayed in the expander header.
    .PARAMETER Content
        Scriptblock containing the UI elements to show when expanded.
    .PARAMETER IsExpanded
        Start with the expander open. Default is collapsed.
    .PARAMETER Variable
        Variable name for accessing this control in button actions.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
    .EXAMPLE
        New-UiExpander -Header 'Advanced Options' -Content {
            New-UiToggle -Text 'Enable logging' -Variable 'enableLog'
            New-UiToggle -Text 'Verbose mode' -Variable 'verbose'
        }
    .EXAMPLE
        New-UiExpander -Header 'Details' -IsExpanded -Content {
            New-UiLabel -Text 'This section starts open'
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Header,

        [Parameter(Mandatory)]
        [scriptblock]$Content,

        [switch]$IsExpanded,

        [Parameter()]
        [string]$Variable,

        [Parameter()]
        [object]$EnabledWhen,

        [switch]$ClearIfDisabled,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    # Grab session and theme context
    $session = Assert-UiSession -CallerName 'New-UiExpander'
    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent

    # Build the outer container with themed border
    $container = [System.Windows.Controls.Border]@{
        BorderThickness = [System.Windows.Thickness]::new(1)
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        Background      = ConvertTo-UiBrush $colors.ControlBg
        CornerRadius    = [System.Windows.CornerRadius]::new(4)
        Margin          = [System.Windows.Thickness]::new(4)
        Tag             = 'ControlBgBrush'
    }

    # Stack panel holds header row and collapsible content
    $outerStack      = [System.Windows.Controls.StackPanel]::new()
    $container.Child = $outerStack

    # Chevron glyph rotates 90deg when content is visible
    $chevron = [System.Windows.Controls.TextBlock]@{
        Text                  = [PsUi.ModuleContext]::GetIcon('ChevronRight')
        FontFamily            = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize              = 12
        Foreground            = ConvertTo-UiBrush $colors.SecondaryText
        VerticalAlignment     = 'Center'
        Margin                = [System.Windows.Thickness]::new(0, 0, 8, 0)
        RenderTransformOrigin = '0.5,0.5'
    }
    $chevron.RenderTransform = [System.Windows.Media.RotateTransform]::new(0)

    # Header label with semibold weight
    $headerText = [System.Windows.Controls.TextBlock]@{
        Text              = $Header
        FontFamily        = [System.Windows.Media.FontFamily]::new('Segoe UI Variable, Segoe UI')
        FontSize          = 13
        FontWeight        = 'SemiBold'
        Foreground        = ConvertTo-UiBrush $colors.ControlFg
        VerticalAlignment = 'Center'
        Tag               = 'ControlFgBrush'
    }

    # Clickable header row with chevron and label
    $headerPanel = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Horizontal'
        Cursor      = 'Hand'
        Background  = [System.Windows.Media.Brushes]::Transparent
        Margin      = [System.Windows.Thickness]::new(10, 8, 10, 8)
    }
    [void]$headerPanel.Children.Add($chevron)
    [void]$headerPanel.Children.Add($headerText)
    [void]$outerStack.Children.Add($headerPanel)

    # Content area - hidden by default unless IsExpanded
    $contentPanel = [System.Windows.Controls.StackPanel]@{
        Margin     = [System.Windows.Thickness]::new(12, 0, 12, 10)
        Visibility = if ($IsExpanded) { 'Visible' } else { 'Collapsed' }
    }
    [void]$outerStack.Children.Add($contentPanel)

    if ($IsExpanded) { $chevron.RenderTransform.Angle = 90 }

    # Toggle visibility and rotate chevron on click
    $headerPanel.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        $outerStack   = $sender.Parent
        $contentPanel = $outerStack.Children[1]
        $chevronGlyph = $sender.Children[0]

        if ($contentPanel.Visibility -eq 'Collapsed') {
            $contentPanel.Visibility = 'Visible'
            $chevronGlyph.RenderTransform.Angle = 90
        }
        else {
            $contentPanel.Visibility = 'Collapsed'
            $chevronGlyph.RenderTransform.Angle = 0
        }
    })

    # Hover feedback on header row
    $headerPanel.Add_MouseEnter({ param($sender, $eventArgs) $sender.Opacity = 0.7 })
    $headerPanel.Add_MouseLeave({ param($sender, $eventArgs) $sender.Opacity = 1.0 })

    # Register control for variable hydration if name provided
    if ($Variable) { $session.AddControlSafe($Variable, $container) }

    # Register themed elements for dynamic switching
    [PsUi.ThemeEngine]::RegisterElement($container)
    [PsUi.ThemeEngine]::RegisterElement($headerText)

    # Attach to parent container
    if ($parent -is [System.Windows.Controls.Panel]) {
        [void]$parent.Children.Add($container)
    }
    elseif ($parent -is [System.Windows.Controls.ItemsControl]) {
        [void]$parent.Items.Add($container)
    }
    elseif ($parent -is [System.Windows.Controls.ContentControl]) {
        $parent.Content = $container
    }

    # Execute content scriptblock with inner panel as parent context
    $previousParent = $session.CurrentParent
    $session.CurrentParent = $contentPanel
    try { & $Content }
    finally { $session.CurrentParent = $previousParent }

    if ($WPFProperties) {
        Set-UiProperties -Control $container -Properties $WPFProperties
    }

    if ($EnabledWhen) {
        Register-UiCondition -TargetControl $container -Condition $EnabledWhen -ClearIfDisabled:$ClearIfDisabled
    }
}
