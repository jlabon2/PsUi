function Update-SingleControlTheme {
    <#
    .SYNOPSIS
        Applies theme styling to a single control based on its type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Control,
        [Parameter(Mandatory)]
        [hashtable]$Colors
    )

    # Window styling
    if ($Control -is [System.Windows.Window]) {
        Write-Debug "Updating Window with accent: $($Colors.Accent)"

        # Update window title bar color via DWM (only for native chrome windows)
        if ([PsUi.ModuleContext]::IsInitialized -and $Control.WindowStyle -ne 'None') {
            $headerBg = [System.Windows.Media.ColorConverter]::ConvertFromString($Colors.HeaderBackground)
            $headerFg = [System.Windows.Media.ColorConverter]::ConvertFromString($Colors.HeaderForeground)
            [PsUi.WindowManager]::SetTitleBarColor($Control, $headerBg, $headerFg)
        }

        # Skip background for transparent/borderless windows (custom chrome needs transparent background)
        if (!$Control.AllowsTransparency) {
            $Control.Background = ConvertTo-UiBrush $Colors.WindowBg
        }
        $Control.Foreground = ConvertTo-UiBrush $Colors.WindowFg

        # Regenerate window icon with new theme colors (unless custom logo is set)
        $session = Get-UiSession
        if ($session -and $session.CustomLogo -and (Test-Path $session.CustomLogo)) {
            # Custom logo is set - load it instead of regenerating themed icon
            $newIcon = Get-CustomLogoIcon -Path $session.CustomLogo
        }
        else {
            $newIcon = New-WindowIcon -Colors $Colors
        }
        if ($newIcon) {
            Write-Debug "New icon created, setting on window"
            $Control.Icon = $newIcon
            [PsUi.WindowManager]::SetTaskbarIcon($Control, $newIcon)
            
            # Update titlebar icon for custom chrome windows (Tag is a hashtable)
            $chromeInfo = $Control.Tag
            if ($chromeInfo -is [System.Collections.IDictionary] -and $chromeInfo['TitleBarIcon']) {
                $chromeInfo['TitleBarIcon'].Source = $newIcon
            }
        }

        # Update taskbar overlay if present (e.g. TextEditor document icon)
        if ($Control.Resources.Contains('OverlayGlyph')) {
            try {
                $glyph       = $Control.Resources['OverlayGlyph']
                $overlayIcon = New-TaskbarOverlayIcon -GlyphChar $glyph -Color $Colors.Accent
                if ($overlayIcon) {
                    [PsUi.WindowManager]::SetTaskbarOverlay($Control, $overlayIcon, 'Overlay')
                }
            }
            catch {
                Write-Verbose "Failed to update taskbar overlay: $_"
            }
        }
    }
    elseif ($Control -is [System.Windows.Controls.GroupBox]) {
        Set-GroupBoxStyle -GroupBox $Control
    }
    elseif ($Control -is [System.Windows.Controls.Button]) {
        # Inline button theme update logic (was Update-ButtonTheme)
        $isAccent = $false
        if ($Control.Tag -is [System.Collections.IDictionary] -and $Control.Tag['IsAccent']) {
            $isAccent = $true
        }

        # Apply base button style
        Set-ButtonStyle -Button $Control -Accent:$isAccent

        # Update button icon color (non-accent buttons use accent color for icon)
        if (!$isAccent -and $Control.Content -is [System.Windows.Controls.StackPanel]) {
            foreach ($child in $Control.Content.Children) {
                if ($child -is [System.Windows.Controls.TextBlock] -and $child.FontFamily.Source -eq 'Segoe MDL2 Assets') {
                    $child.Foreground = ConvertTo-UiBrush $Colors.Accent
                }
            }
        }

        # Update checkmark for theme menu buttons
        if ($Control.Tag -is [System.Collections.IDictionary] -and $Control.Tag.ContainsKey('ThemeName')) {
            if ($Control.Tag.ContainsKey('Checkmark') -and $Control.Tag['Checkmark']) {
                $isActive = $Control.Tag['ThemeName'] -eq [PsUi.ModuleContext]::ActiveTheme
                $Control.Tag['Checkmark'].Text = if ($isActive) { [char]0x2713 } else { ' ' }
                if ($isActive) { $Control.Tag['Checkmark'].Foreground = ConvertTo-UiBrush $Colors.Accent }
            }
        }

        # Style popup contents if button has a popup tag
        if ($Control.Tag -is [System.Windows.Controls.Primitives.Popup]) {
            $popup       = $Control.Tag
            $popupBorder = $popup.Child
            if ($popupBorder -is [System.Windows.Controls.Border]) {
                $popupBorder.Background  = ConvertTo-UiBrush $Colors.ControlBg
                $popupBorder.BorderBrush = ConvertTo-UiBrush $Colors.Border
            }
        }
    }
    elseif ($Control -is [System.Windows.Controls.TextBox]) {
        Set-TextBoxStyle -TextBox $Control
    }
    elseif ($Control -is [System.Windows.Controls.DataGrid]) {
        Set-DataGridStyle -Grid $Control
    }
    elseif ($Control -is [System.Windows.Controls.TabControl]) {
        Set-TabControlStyle -TabControl $Control
        $Control.Foreground = ConvertTo-UiBrush $Colors.ControlFg
    }
    elseif ($Control -is [System.Windows.Controls.TabItem]) {
        Set-TabItemStyle -TabItem $Control
    }
    elseif ($Control -is [System.Windows.Controls.ComboBox]) {
        Set-ComboBoxStyle -ComboBox $Control
    }
    elseif ($Control -is [System.Windows.Controls.RadioButton]) {
        # Wrap in try/catch - internal template RadioButtons may fail
        try { Set-RadioButtonStyle -RadioButton $Control }
        catch { Write-Debug "RadioButton style skipped: $_" }
    }
    elseif ($Control -is [System.Windows.Controls.ListBox]) {
        Set-ListBoxStyle -ListBox $Control
    }
    elseif ($Control -is [System.Windows.Controls.DatePicker]) {
        Set-DatePickerStyle -DatePicker $Control
    }
    elseif ($Control -is [System.Windows.Controls.TextBlock]) {
        # Inline TextBlock theme update logic (was Update-TextBlockTheme)
        switch ($Control.Tag) {
            'AccentBrush'               { $Control.Foreground = ConvertTo-UiBrush $Colors.Accent }
            'AccentHeaderForegroundBrush' { $Control.Foreground = ConvertTo-UiBrush $Colors.AccentHeaderFg }
            'ControlFgBrush'            { $Control.Foreground = ConvertTo-UiBrush $Colors.ControlFg }
            'SecondaryTextBrush'        { $Control.Foreground = ConvertTo-UiBrush $Colors.SecondaryText }
            'SuccessBrush'              { $Control.Foreground = ConvertTo-UiBrush $Colors.Success }
            'ErrorBrush'                { $Control.Foreground = ConvertTo-UiBrush $Colors.Error }
            'AccentText'                { $Control.Foreground = ConvertTo-UiBrush $Colors.Accent }
            'AccentButtonIcon'          { $Control.Foreground = ConvertTo-UiBrush $Colors.AccentHeaderFg }
            'AccentButtonText'          { $Control.Foreground = ConvertTo-UiBrush $Colors.AccentHeaderFg }
            'ThemeButtonIcon'           { $Control.Foreground = ConvertTo-UiBrush $Colors.HeaderForeground }
            'HeaderText'                { $Control.Foreground = ConvertTo-UiBrush $Colors.HeaderForeground }
            { $_ -in @('TimePickerLabel', 'TimePickerText', 'TimePickerArrowIcon', 'TimePickerColon') } {
                $Control.Foreground = ConvertTo-UiBrush $Colors.ControlFg
            }
            { $_ -in @('CardHeaderIcon', 'CardHeaderText') } {
                # Card header text/icon - look at parent for accent info
                $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($Control)
                while ($parent -and !($parent.Tag -is [System.Collections.IDictionary])) {
                    $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($parent)
                }
                if ($parent -and $parent.Tag -is [System.Collections.IDictionary] -and $parent.Tag['IsAccent']) {
                    $bgColor = if ($parent.Tag['CustomColor']) { $parent.Tag['CustomColor'] } else { $Colors.Accent }
                    $Control.Foreground = ConvertTo-UiBrush (Get-ContrastColor -HexColor $bgColor)
                }
                else {
                    $Control.Foreground = ConvertTo-UiBrush $Colors.ControlFg
                }
            }
            default {
                # Regular text (not an icon font)
                if ($Control.FontFamily.Source -ne 'Segoe MDL2 Assets') {
                    $Control.Foreground = ConvertTo-UiBrush $Colors.ControlFg
                }
            }
        }
    }
    elseif ($Control -is [System.Windows.Controls.Border]) {
        # Inline Border theme update logic (was Update-BorderTheme)
        switch ($Control.Tag) {
            'HeaderBorder' {
                $Control.Background = ConvertTo-UiBrush $Colors.HeaderBackground
            }
            'StatusBar' {
                $Control.Background  = ConvertTo-UiBrush $Colors.ControlBg
                $Control.BorderBrush = ConvertTo-UiBrush $Colors.Border
            }
            'PopupBorder' {
                $Control.Background  = ConvertTo-UiBrush $Colors.ControlBg
                $Control.BorderBrush = ConvertTo-UiBrush $Colors.Border
            }
            'CardBorder' {
                $Control.Background  = ConvertTo-UiBrush $Colors.ControlBg
                $Control.BorderBrush = ConvertTo-UiBrush $Colors.Border
            }
            'CardSeparator' {
                $Control.Background = ConvertTo-UiBrush $Colors.Border
            }
            'ConsoleGutter' {
                $Control.Background  = ConvertTo-UiBrush $Colors.WindowBg
                $Control.BorderBrush = ConvertTo-UiBrush $Colors.Border
            }
            { $_ -in @('TimePickerBorder', 'TimePickerArrowBorder', 'TimePickerPopupBorder') } {
                $Control.Background  = ConvertTo-UiBrush $Colors.ControlBg
                $Control.BorderBrush = ConvertTo-UiBrush $Colors.Border
            }
            'TimePickerSeparator' {
                $Control.Background = ConvertTo-UiBrush $Colors.Border
            }
            'Separator_Solid' {
                $Control.Background = ConvertTo-UiBrush $Colors.Border
            }
            'Separator_Fade' {
                # Recreate fade gradient with new border color
                $borderColor       = [System.Windows.Media.ColorConverter]::ConvertFromString($Colors.Border)
                $transparentBorder = [System.Windows.Media.Color]::FromArgb(0, $borderColor.R, $borderColor.G, $borderColor.B)
                $gradient          = [System.Windows.Media.LinearGradientBrush]::new()
                $gradient.StartPoint = [System.Windows.Point]::new(0, 0.5)
                $gradient.EndPoint   = [System.Windows.Point]::new(1, 0.5)
                [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($transparentBorder, 0))
                [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($borderColor, 0.1))
                [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($borderColor, 0.9))
                [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($transparentBorder, 1))
                $Control.Background = $gradient
            }
            'Separator_Accent' {
                # Recreate accent fade gradient
                $accentColor       = [System.Windows.Media.ColorConverter]::ConvertFromString($Colors.Accent)
                $transparentAccent = [System.Windows.Media.Color]::FromArgb(0, $accentColor.R, $accentColor.G, $accentColor.B)
                $gradient          = [System.Windows.Media.LinearGradientBrush]::new()
                $gradient.StartPoint = [System.Windows.Point]::new(0, 0.5)
                $gradient.EndPoint   = [System.Windows.Point]::new(1, 0.5)
                [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($transparentAccent, 0))
                [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($accentColor, 0.15))
                [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($accentColor, 0.85))
                [void]$gradient.GradientStops.Add([System.Windows.Media.GradientStop]::new($transparentAccent, 1))
                $Control.Background = $gradient
            }
        }

        # Hashtable tags (card headers with accent/custom colors)
        if ($Control.Tag -is [System.Collections.IDictionary]) {
            $tagType = $Control.Tag['Type']
            if ($tagType -eq 'CardHeader') {
                if ($Control.Tag['CustomColor']) {
                    $Control.Background = ConvertTo-UiBrush $Control.Tag['CustomColor']
                }
                elseif ($Control.Tag['IsAccent']) {
                    $Control.Background = ConvertTo-UiBrush $Colors.Accent
                }
                else {
                    $headerBgColor = if ($Colors.GroupBoxBg) { $Colors.GroupBoxBg } else { $Colors.WindowBg }
                    $Control.Background = ConvertTo-UiBrush $headerBgColor
                }
            }
        }
    }
    elseif ($Control -is [System.Windows.Controls.PasswordBox]) {
        $Control.Background  = ConvertTo-UiBrush $Colors.ControlBg
        $Control.Foreground  = ConvertTo-UiBrush $Colors.ControlFg
        $Control.BorderBrush = ConvertTo-UiBrush $Colors.Border
    }
    elseif ($Control -is [System.Windows.Controls.CheckBox]) {
        Set-CheckBoxStyle -CheckBox $Control
    }
    elseif ($Control -is [System.Windows.Controls.RichTextBox]) {
        $Control.Background  = ConvertTo-UiBrush $Colors.ControlBg
        $Control.Foreground  = ConvertTo-UiBrush $Colors.ControlFg
        $Control.BorderBrush = ConvertTo-UiBrush $Colors.Border
        $highlightColor      = if ($Colors.TextHighlight) { $Colors.TextHighlight } else { $Colors.Selection }
        $Control.SelectionBrush = ConvertTo-UiBrush $highlightColor
    }
    elseif ($Control -is [System.Windows.Controls.ProgressBar]) {
        Set-ProgressBarStyle -ProgressBar $Control
    }
    elseif ($Control -is [System.Windows.Controls.Slider]) {
        Set-SliderStyle -Slider $Control
    }
    elseif ($Control -is [System.Windows.Controls.StackPanel]) {
        if ($Control.Tag -eq 'ProgressPanel') {
            $Control.Background = ConvertTo-UiBrush $Colors.ControlBg
        }
    }

    # Update ContextMenu if present (not in visual tree)
    if ($Control -is [System.Windows.FrameworkElement] -and $Control.ContextMenu) {
        Set-ContextMenuStyle -ContextMenu $Control.ContextMenu
    }
}
