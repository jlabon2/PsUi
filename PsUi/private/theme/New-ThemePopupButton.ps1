function New-ThemePopupButton {
    <#
    .SYNOPSIS
        Creates a compact theme switcher popup button with grouped themes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.UIElement]$Container,
        
        [string]$CurrentTheme = 'Light'
    )
    
    $colors = Get-ThemeColors
    
    # Create the theme button - styled flat like window control buttons
    $themeButton = [System.Windows.Controls.Button]::new()
    $themeButton.Width = 46
    $themeButton.Height = 32
    $themeButton.Padding = [System.Windows.Thickness]::new(0)
    $themeButton.ToolTip = 'Change Theme'
    $themeButton.HorizontalAlignment = 'Right'
    $themeButton.VerticalAlignment = 'Center'
    $themeButton.BorderThickness = [System.Windows.Thickness]::new(0)
    $themeButton.Cursor = [System.Windows.Input.Cursors]::Hand
    
    $themeIcon = [System.Windows.Controls.TextBlock]::new()
    $themeIcon.Text = [PsUi.ModuleContext]::GetIcon('ColorBackground') 
    $themeIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $themeIcon.FontSize = 14
    $themeIcon.HorizontalAlignment = 'Center'
    $themeIcon.VerticalAlignment = 'Center'
    $themeIcon.Tag = 'ThemeButtonIcon'
    
    # Use HeaderForeground to match titlebar text
    $themeIcon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'HeaderForegroundBrush')
    
    $themeButton.Content = $themeIcon
    
    # Apply flat titlebar button style with theme-aware hover (same as min/max buttons)
    $templateXaml = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="Button">
    <Border x:Name="border" Background="Transparent">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="border" Property="Background" Value="{DynamicResource WindowControlHoverBrush}"/>
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
            <Setter TargetName="border" Property="Background" Value="{DynamicResource WindowControlHoverBrush}"/>
            <Setter TargetName="border" Property="Opacity" Value="0.7"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
'@
    $themeButton.Template = [System.Windows.Markup.XamlReader]::Parse($templateXaml)
    
    # Mark button as hit-testable within WindowChrome area
    # Fixes click issues when parent window is maximized
    [System.Windows.Shell.WindowChrome]::SetIsHitTestVisibleInChrome($themeButton, $true)
    
    # Create popup
    $popup = [System.Windows.Controls.Primitives.Popup]::new()
    $popup.PlacementTarget = $themeButton
    $popup.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
    $popup.StaysOpen = $false
    $popup.AllowsTransparency = $true
    
    $popupBorder = [System.Windows.Controls.Border]::new()
    $popupBorder.Background = ConvertTo-UiBrush $colors.ControlBg
    $popupBorder.BorderBrush = ConvertTo-UiBrush $colors.Border
    $popupBorder.BorderThickness = [System.Windows.Thickness]::new(1)
    $popupBorder.Padding = [System.Windows.Thickness]::new(8)
    $popupBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
    $popupBorder.Tag = 'PopupBorder'
    
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 12
    $shadow.ShadowDepth = 3
    $shadow.Opacity = 0.25
    $popupBorder.Effect = $shadow
    
    $themeStack = [System.Windows.Controls.StackPanel]::new()
    $themeStack.Orientation = 'Vertical'
    
    # Wire up popup structure (content built dynamically on click)
    $popupBorder.Child = $themeStack
    $popup.Child = $popupBorder
    
    # Helper to create section header - defined as scriptblock for closure capture
    $newSectionHeader = {
        param($HeaderText, $IconChar, $Colors)
        $header = [System.Windows.Controls.StackPanel]::new()
        $header.Orientation = 'Horizontal'
        $header.Margin = [System.Windows.Thickness]::new(4, 6, 4, 4)
        
        $iconBlock = [System.Windows.Controls.TextBlock]::new()
        $iconBlock.Text = $IconChar
        $iconBlock.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $iconBlock.FontSize = 12
        $iconBlock.Foreground = ConvertTo-UiBrush $Colors.SecondaryText
        $iconBlock.VerticalAlignment = 'Center'
        $iconBlock.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
        $iconBlock.Tag = 'SectionIcon'
        [void]$header.Children.Add($iconBlock)
        
        $label = [System.Windows.Controls.TextBlock]::new()
        $label.Text = $HeaderText
        $label.FontSize = 11
        $label.FontWeight = 'SemiBold'
        $label.Foreground = ConvertTo-UiBrush $Colors.SecondaryText
        $label.VerticalAlignment = 'Center'
        $label.Tag = 'SectionLabel'
        [void]$header.Children.Add($label)
        
        return $header
    }
    
    # Helper to create a theme menu item button - defined as scriptblock for closure capture
    $newThemeMenuItem = {
        param($ThemeName, $CurrentTheme, $Colors, $Popup, $ThemeStack, $PopupBorder, $ThemeIcon, $ThemeButton, $Container)
        
        $themeItem = [System.Windows.Controls.Button]::new()
        $themeItem.Height = 28
        $themeItem.MinWidth = 130
        $themeItem.HorizontalContentAlignment = 'Left'
        $themeItem.Padding = [System.Windows.Thickness]::new(8, 2, 8, 2)
        $themeItem.Margin = [System.Windows.Thickness]::new(2, 1, 2, 1)
        
        $itemStack = [System.Windows.Controls.StackPanel]::new()
        $itemStack.Orientation = 'Horizontal'
        
        $checkmark = [System.Windows.Controls.TextBlock]::new()
        $checkmark.Text = if ($ThemeName -eq $CurrentTheme) { [PsUi.ModuleContext]::GetIcon('CheckMark') } else { ' ' }
        $checkmark.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $checkmark.FontSize = 12
        $checkmark.Width = 18
        $checkmark.Foreground = ConvertTo-UiBrush $Colors.Accent
        $checkmark.VerticalAlignment = 'Center'
        $checkmark.Tag = 'AccentText'
        [void]$itemStack.Children.Add($checkmark)
        
        $themeLabel = [System.Windows.Controls.TextBlock]::new()
        $themeLabel.Text = $ThemeName
        $themeLabel.FontSize = 12
        $themeLabel.VerticalAlignment = 'Center'
        $themeLabel.Foreground = ConvertTo-UiBrush $Colors.ControlFg
        [void]$itemStack.Children.Add($themeLabel)
        
        $themeItem.Content = $itemStack
        
        # Store all state the click handler needs (avoids .GetNewClosure() which breaks module scope)
        $themeItem.Tag = @{
            ThemeName   = $ThemeName
            Checkmark   = $checkmark
            Popup       = $Popup
            ThemeStack  = $ThemeStack
            PopupBorder = $PopupBorder
            ThemeIcon   = $ThemeIcon
            ThemeButton = $ThemeButton
            Container   = $Container
        }
        
        Set-ButtonStyle -Button $themeItem
        
        # No .GetNewClosure() — scriptblock stays bound to PsUi module scope
        $themeItem.Add_Click({
            param($sender, $eventArgs)
            try {
                $tag = $sender.Tag
                if (!$tag -or !$tag.ContainsKey('ThemeName')) { return }
                $selectedTheme = $tag.ThemeName
                
                $tag.Popup.IsOpen = $false
                
                Set-ActiveTheme -Theme $selectedTheme
                $newColors = Get-ThemeColors
                
                # Update all theme buttons in the popup
                foreach ($child in $tag.ThemeStack.Children) {
                    if ($child -is [System.Windows.Controls.Button] -and 
                        $child.Tag -is [System.Collections.IDictionary] -and 
                        $child.Tag.ContainsKey('ThemeName')) {
                        
                        $isSelected = $child.Tag['ThemeName'] -eq $selectedTheme
                        $child.Tag['Checkmark'].Text = if ($isSelected) { [PsUi.ModuleContext]::GetIcon('CheckMark') } else { ' ' }
                        $child.Tag['Checkmark'].Foreground = ConvertTo-UiBrush $newColors.Accent
                        
                        $contentPanel = $child.Content
                        if ($contentPanel -is [System.Windows.Controls.StackPanel]) {
                            foreach ($tb in $contentPanel.Children) {
                                if ($tb -is [System.Windows.Controls.TextBlock]) {
                                    if ($tb.Tag -eq 'AccentText') {
                                        $tb.Foreground = ConvertTo-UiBrush $newColors.Accent
                                    }
                                    else {
                                        $tb.Foreground = ConvertTo-UiBrush $newColors.ControlFg
                                    }
                                }
                            }
                        }
                        Set-ButtonStyle -Button $child
                    }
                    elseif ($child -is [System.Windows.Controls.StackPanel]) {
                        foreach ($hc in $child.Children) {
                            if ($hc -is [System.Windows.Controls.TextBlock]) {
                                $hc.Foreground = ConvertTo-UiBrush $newColors.SecondaryText
                            }
                        }
                    }
                    elseif ($child -is [System.Windows.Controls.Border]) {
                        $child.Background = ConvertTo-UiBrush $newColors.Border
                    }
                }
                
                $tag.PopupBorder.Background = ConvertTo-UiBrush $newColors.ControlBg
                $tag.PopupBorder.BorderBrush = ConvertTo-UiBrush $newColors.Border
                $tag.ThemeIcon.Foreground = ConvertTo-UiBrush $newColors.HeaderForeground
                Set-ButtonStyle -Button $tag.ThemeButton -IconOnly

                # Update this window and its parent (Owner) if present
                $ownerWindow = [System.Windows.Window]::GetWindow($tag.Container)
                Write-Debug "ownerWindow type: $($ownerWindow.GetType().FullName), is Window: $($ownerWindow -is [System.Windows.Window])"
                if ($ownerWindow) {
                    Update-AllControlThemes -Control $ownerWindow -Colors $newColors
                    
                    # Directly update header text (it's in the first child of the window's content DockPanel)
                    $dockPanel = $ownerWindow.Content
                    if ($dockPanel -and $dockPanel.Children.Count -gt 0) {
                        $headerBorder = $dockPanel.Children[0]
                        if ($headerBorder.Child -and $headerBorder.Child.Children.Count -gt 0) {
                            $titleBlock = $headerBorder.Child.Children[0]
                            if ($titleBlock -is [System.Windows.Controls.TextBlock]) {
                                $titleBlock.Foreground = ConvertTo-UiBrush $newColors.HeaderForeground
                            }
                        }
                    }
                    
                    # Also update the parent window (Owner) if this is a child window
                    if ($ownerWindow.Owner -and $ownerWindow.Owner -is [System.Windows.Window]) {
                        Update-AllControlThemes -Control $ownerWindow.Owner -Colors $newColors
                    }
                }
            }
            catch {
                Write-Warning "Theme switch failed: $($_.Exception.Message)"
                Write-Debug "Stack: $($_.ScriptStackTrace)"
            }
        })
        
        return $themeItem
    }
    
    # Store all state the click handler needs in Tag
    # No .GetNewClosure() — scriptblock stays bound to PsUi module scope
    $themeButton.Tag = @{
        Popup              = $popup
        ThemeStack         = $themeStack
        PopupBorder        = $popupBorder
        ThemeIcon          = $themeIcon
        Container          = $Container
        SectionHeaderBuilder = $newSectionHeader
        MenuItemBuilder    = $newThemeMenuItem
    }
    
    $themeButton.Add_Click({
        $tag = $this.Tag
        try {
            # Rebuild theme list each time popup opens to pick up newly registered themes
            if (!$tag.Popup.IsOpen) {
                try {
                    $tag.ThemeStack.Children.Clear()
                    
                    $currentColors = Get-ThemeColors
                    $activeTheme   = [PsUi.ModuleContext]::ActiveTheme
                    $allThemes     = [PsUi.ModuleContext]::Themes
                    
                    # Sort themes: Light/Dark first in their respective groups, then alphabetical
                    $lightThemes = $allThemes.GetEnumerator() | 
                        Where-Object { $_.Value.Type -eq 'Light' } | 
                        ForEach-Object { $_.Key } | 
                        Sort-Object { if ($_ -eq 'Light') { '!0' } else { $_ } }
                    $darkThemes  = $allThemes.GetEnumerator() | 
                        Where-Object { $_.Value.Type -eq 'Dark' } | 
                        ForEach-Object { $_.Key } | 
                        Sort-Object { if ($_ -eq 'Dark') { '!0' } else { $_ } }
                    
                    # Add Light themes section
                    $lightHeader = & $tag.SectionHeaderBuilder 'Light Themes' ([PsUi.ModuleContext]::GetIcon('Brightness')) $currentColors
                    [void]$tag.ThemeStack.Children.Add($lightHeader)
                    
                    foreach ($themeName in $lightThemes) {
                        $menuItem = & $tag.MenuItemBuilder $themeName $activeTheme $currentColors $tag.Popup $tag.ThemeStack $tag.PopupBorder $tag.ThemeIcon $this $tag.Container
                        [void]$tag.ThemeStack.Children.Add($menuItem)
                    }
                    
                    # Separator
                    $separator = [System.Windows.Controls.Border]::new()
                    $separator.Height = 1
                    $separator.Background = ConvertTo-UiBrush $currentColors.Border
                    $separator.Margin = [System.Windows.Thickness]::new(4, 8, 4, 4)
                    [void]$tag.ThemeStack.Children.Add($separator)
                    
                    # Add Dark themes section
                    $darkHeader = & $tag.SectionHeaderBuilder 'Dark Themes' ([PsUi.ModuleContext]::GetIcon('Contrast')) $currentColors
                    [void]$tag.ThemeStack.Children.Add($darkHeader)
                    
                    foreach ($themeName in $darkThemes) {
                        $menuItem = & $tag.MenuItemBuilder $themeName $activeTheme $currentColors $tag.Popup $tag.ThemeStack $tag.PopupBorder $tag.ThemeIcon $this $tag.Container
                        [void]$tag.ThemeStack.Children.Add($menuItem)
                    }
                    
                    # Update popup border colors for current theme
                    $tag.PopupBorder.Background = ConvertTo-UiBrush $currentColors.ControlBg
                    $tag.PopupBorder.BorderBrush = ConvertTo-UiBrush $currentColors.Border
                }
                catch {
                    Write-Warning "Theme popup build failed: $_"
                }
            }
            
            # Toggle always runs even if content build had an error
            $tag.Popup.IsOpen = !$tag.Popup.IsOpen
        }
        catch { Write-Warning "Theme popup toggle failed: $_" }
    })
    
    return @{ Button = $themeButton; Popup = $popup }
}
