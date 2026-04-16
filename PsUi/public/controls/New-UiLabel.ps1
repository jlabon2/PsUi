function New-UiLabel {
    <#
    .SYNOPSIS
        Creates a styled text label with various predefined styles.
    .DESCRIPTION
        Creates a TextBlock with formatting based on the specified style.
    .PARAMETER Text
        The text content to display.
    .PARAMETER Style
        The text style: Body, Header, SubHeader, Title, Note, Warning, or Success.
    .PARAMETER FullWidth
        Forces the label to take full width in WrapPanel layouts.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
        Allows setting any valid WPF property not explicitly exposed as a parameter.
        Invalid properties will generate warnings but not stop execution.
        Supports attached properties using dot notation (e.g., "Grid.Row").
    .EXAMPLE
        New-UiLabel -Text "Hello World" -WPFProperties @{ ToolTip = "Custom tooltip" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [ValidateSet('Body', 'Header', 'SubHeader', 'Title', 'Note', 'Warning', 'Success')]
        [string]$Style = 'Body',

        [switch]$FullWidth,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiLabel'
    Write-Debug "Text: '$Text', Style: $Style"
    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent

    $block = [System.Windows.Controls.TextBlock]@{
        Text         = $Text
        TextWrapping = 'Wrap'
        FontFamily   = [System.Windows.Media.FontFamily]::new('Segoe UI Variable, Segoe UI')
        Margin       = [System.Windows.Thickness]::new(4, 2, 4, 6)
    }

    # Apply style-specific formatting and colors
    switch ($Style) {
        'Header' {
            $block.FontSize   = 18
            $block.FontWeight = 'Bold'
            $block.Foreground = ConvertTo-UiBrush $colors.ControlFg
            $block.Margin     = [System.Windows.Thickness]::new(4, 8, 4, 4)
            $block.Tag        = 'ControlFgBrush'
        }
        'SubHeader' {
            $block.FontSize   = 14
            $block.FontWeight = 'SemiBold'
            $block.Foreground = ConvertTo-UiBrush $colors.ControlFg
            $block.Margin     = [System.Windows.Thickness]::new(4, 0, 4, 3)
            $block.Tag        = 'ControlFgBrush'
        }
        'Title' {
            $block.FontSize   = 22
            $block.FontWeight = 'Light'
            $block.Foreground = ConvertTo-UiBrush $colors.Accent
            $block.Margin     = [System.Windows.Thickness]::new(4, 0, 4, 6)
            $block.Tag        = 'AccentBrush'
        }
        'Note' {
            $block.FontSize   = 12
            $block.FontWeight = 'Regular'
            $block.FontStyle  = 'Normal'
            $block.Foreground = ConvertTo-UiBrush $colors.SecondaryText
            $block.Tag        = 'SecondaryTextBrush'
        }
        'Warning' {
            $block.FontWeight = 'SemiBold'
            $block.Foreground = ConvertTo-UiBrush $colors.Error
            $block.Tag        = 'ErrorBrush'
        }
        'Success' {
            $block.FontWeight = 'SemiBold'
            $block.Foreground = ConvertTo-UiBrush $colors.Success
            $block.Tag        = 'SuccessBrush'
        }
        Default {
            $block.FontSize   = 13
            $block.FontWeight = 'Regular'
            $block.Foreground = ConvertTo-UiBrush $colors.ControlFg
            $block.Tag        = 'ControlFgBrush'
        }
    }

    # Register with ThemeEngine for dynamic theme updates (uses Tag to determine brush)
    [PsUi.ThemeEngine]::RegisterElement($block)

    # FullWidth in WrapPanel contexts
    Set-FullWidthConstraint -Control $block -Parent $parent -FullWidth:$FullWidth

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $block -Properties $WPFProperties
    }

    # Add to parent container
    if ($parent -is [System.Windows.Controls.Panel]) {
        [void]$parent.Children.Add($block)
    }
    elseif ($parent -is [System.Windows.Controls.ItemsControl]) {
        [void]$parent.Items.Add($block)
    }
    elseif ($parent -is [System.Windows.Controls.ContentControl]) {
        $parent.Content = $block
    }
}