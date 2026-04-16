function New-UiGlyph {
    <#
    .SYNOPSIS
        Creates a glyph icon from the Segoe MDL2 Assets font.
    .DESCRIPTION
        Displays an icon from the built-in icon library with optional tooltip showing the glyph name.
        Useful for adding visual indicators, status icons, or decorative elements.
    .PARAMETER Name
        The name of the glyph to display (e.g., 'Star', 'Heart', 'Gear').
        Use Show-UiGlyphBrowser to see all available glyphs.
    .PARAMETER Size
        Font size for the glyph. Default is 16.
    .PARAMETER Color
        Color for the glyph. Can be a color name ('Red'), hex ('#FF0000'), or theme key ('Accent').
        Defaults to the current theme's ControlFg color.
    .PARAMETER ShowTooltip
        If specified, shows the glyph name as a tooltip on hover.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
    .EXAMPLE
        New-UiGlyph -Name 'Star' -Size 24 -Color 'Gold'
    .EXAMPLE
        New-UiGlyph -Name 'Gear' -ShowTooltip
    .EXAMPLE
        New-UiPanel -Direction Horizontal {
            New-UiGlyph -Name 'CircleCheck' -Color 'Green' -Size 20
            New-UiLabel -Text 'Operation completed successfully'
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [double]$Size = 16,

        [string]$Color,

        [switch]$ShowTooltip,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiGlyph'
    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent
    Write-Debug "Name='$Name', Size=$Size, Parent: $($parent.GetType().Name)"

    $glyphChar = [PsUi.ModuleContext]::GetIcon($Name)
    if (!$glyphChar) {
        Write-Warning "Glyph '$Name' not found. Using placeholder."
        $glyphChar = [PsUi.ModuleContext]::GetIcon('Error')  # Fallback icon
    }

    $brush = $null
    $brushTag = 'ControlFgBrush'
    if ($Color) {
        # Color could be a theme key like 'Primary' or a literal color value
        if ($colors.ContainsKey($Color)) {
            $brush = ConvertTo-UiBrush $colors[$Color]
            $brushTag = "${Color}Brush"
        }
        else {
            $brush = ConvertTo-UiBrush $Color
            $brushTag = $null  # Custom color, no theme tracking
        }
    }
    else {
        $brush = ConvertTo-UiBrush $colors.ControlFg
    }

    $glyph = [System.Windows.Controls.TextBlock]@{
        Text              = $glyphChar
        FontFamily        = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize          = $Size
        Foreground        = $brush
        TextAlignment     = 'Center'
        VerticalAlignment = 'Center'
        Margin            = [System.Windows.Thickness]::new(2)
    }

    # Track for theme changes if using theme color
    if ($brushTag) {
        $glyph.Tag = $brushTag
        try { [PsUi.ThemeEngine]::RegisterElement($glyph) } catch { Write-Debug "ThemeEngine registration failed: $_" }
    }

    if ($ShowTooltip) {
        $glyph.ToolTip = $Name
    }

    if ($WPFProperties) {
        Set-UiProperties -Control $glyph -Properties $WPFProperties
    }

    Write-Debug "Adding glyph '$Name' to parent"
    $parent.Children.Add($glyph) | Out-Null

    return $glyph
}
