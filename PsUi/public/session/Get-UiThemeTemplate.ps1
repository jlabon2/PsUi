function Get-UiThemeTemplate {
    <#
    .SYNOPSIS
        Returns a template hashtable showing all available theme color keys.
    .DESCRIPTION
        Outputs a hashtable with all theme keys and their descriptions. Copy and modify
        this template to create custom themes with Register-UiTheme.
    .PARAMETER Type
        Generate template for 'Light' or 'Dark' base theme. Defaults to 'Dark'.
    .PARAMETER AsHashtable
        Return raw hashtable instead of formatted output. Useful for scripting.
    .EXAMPLE
        Get-UiThemeTemplate -Type Dark
    .EXAMPLE
        $template = Get-UiThemeTemplate -AsHashtable
        $template.Accent = '#FF6B6B'
        Register-UiTheme -Name 'MyTheme' -Colors $template
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Light', 'Dark')]
        [string]$Type = 'Dark',

        [switch]$AsHashtable
    )

    # All available theme keys with descriptions
    $template = [ordered]@{
        # Required: theme classification (affects default fallbacks)
        Type              = $Type
        DisabledOpacity   = if ($Type -eq 'Dark') { 0.35 } else { 0.2 }

        # Window backgrounds and text
        WindowBg          = if ($Type -eq 'Dark') { '#202020' } else { '#FAFAFA' }
        WindowFg          = if ($Type -eq 'Dark') { '#E0E0E0' } else { '#383A42' }

        # Controls (textboxes, dropdowns, listboxes)
        ControlBg         = if ($Type -eq 'Dark') { '#2D2D2D' } else { '#FFFFFF' }
        ControlFg         = if ($Type -eq 'Dark') { '#E0E0E0' } else { '#383A42' }

        # Buttons
        ButtonBg          = if ($Type -eq 'Dark') { '#383838' } else { '#FFFFFF' }
        ButtonFg          = if ($Type -eq 'Dark') { '#FFFFFF' } else { '#383A42' }
        ButtonHover       = if ($Type -eq 'Dark') { '#454545' } else { '#EAEAEB' }

        # Borders and separators
        Border            = if ($Type -eq 'Dark') { '#404040' } else { '#D3D3D4' }

        # Primary accent color (used for selection, links, checkmarks)
        Accent            = if ($Type -eq 'Dark') { '#78B802' } else { '#4078F2' }

        # Headers (window titlebar, DataGrid headers)
        HeaderBackground  = if ($Type -eq 'Dark') { '#1A1A1A' } else { '#EAEAEB' }
        HeaderForeground  = if ($Type -eq 'Dark') { '#FFFFFF' } else { '#383A42' }

        # Accent-colored headers (New-UiCard -Accent)
        AccentHeaderBg    = if ($Type -eq 'Dark') { '#78B802' } else { '#4078F2' }
        AccentHeaderFg    = if ($Type -eq 'Dark') { '#202020' } else { '#FFFFFF' }

        # Status colors
        Success           = if ($Type -eq 'Dark') { '#6CCB5F' } else { '#50A14F' }
        Warning           = if ($Type -eq 'Dark') { '#FCE100' } else { '#C18401' }
        Error             = if ($Type -eq 'Dark') { '#FF99A4' } else { '#E45649' }

        # DataGrid
        GridAlt           = if ($Type -eq 'Dark') { '#252525' } else { '#F5F5F5' }
        GridLine          = if ($Type -eq 'Dark') { '#3A3A3A' } else { '#E0E0E0' }

        # Disabled state (uses DisabledOpacity applied to control, not a separate background)
        Disabled          = if ($Type -eq 'Dark') { '#707070' } else { '#A0A1A7' }
        SecondaryText     = if ($Type -eq 'Dark') { '#A0A0A0' } else { '#696C77' }

        # Selection and hover
        ItemHover         = if ($Type -eq 'Dark') { '#3A3A3A' } else { '#EDF2FC' }
        Selection         = if ($Type -eq 'Dark') { '#78B802' } else { '#4078F2' }
        SelectionBackground = if ($Type -eq 'Dark') { '#9DD035' } else { '#3267D6' }
        SelectionFg       = if ($Type -eq 'Dark') { '#1A1A1A' } else { '#FFFFFF' }

        # Text search highlighting
        FindHighlight     = if ($Type -eq 'Dark') { '#4CC2FF' } else { '#E5C07B' }
        TextHighlight     = if ($Type -eq 'Dark') { '#78B802' } else { '#D5E4FC' }
        TextHighlightFg   = if ($Type -eq 'Dark') { '#FFFFFF' } else { '#2E4688' }

        # Tab control
        SelectedTabBg     = if ($Type -eq 'Dark') { '#383838' } else { '#E8EEFA' }
        TabHoverBg        = if ($Type -eq 'Dark') { '#383838' } else { '#E8EEFA' }

        # Status text in output panels
        ErrorText         = if ($Type -eq 'Dark') { '#F08080' } else { '#E45649' }
        WarningText       = if ($Type -eq 'Dark') { '#FFB366' } else { '#C18401' }
        SuccessText       = if ($Type -eq 'Dark') { '#90EE90' } else { '#50A14F' }

        # Hyperlinks
        Link              = if ($Type -eq 'Dark') { '#FFFFFF' } else { '#4078F2' }

        # GroupBox containers
        GroupBoxBg        = if ($Type -eq 'Dark') { '#252525' } else { '#FFFFFF' }
        GroupBoxBorder    = if ($Type -eq 'Dark') { '#3A3A3A' } else { '#E5E5E6' }
    }

    if ($AsHashtable) { return $template }

    # Format output as a copyable hashtable definition
    $output = "@{`n"
    foreach ($key in $template.Keys) {
        $value = $template[$key]
        if ($value -is [string]) {
            $output += "    $key = '$value'`n"
        }
        else {
            $output += "    $key = $value`n"
        }
    }
    $output += "}"
    
    Write-Host $output
}
