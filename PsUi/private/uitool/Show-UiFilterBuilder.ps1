function Show-UiFilterBuilder {
    <#
    .SYNOPSIS
        Shows a filter pattern builder popup and returns the selected pattern.
    .PARAMETER CurrentValue
        The current filter value to pre-populate.
    .PARAMETER Mode
        The type of filter syntax: File, AD, WMI, or Generic.
    .PARAMETER ThemeColors
        Optional theme colors hashtable. If not provided, uses active theme.
    #>
    [CmdletBinding()]
    param(
        [string]$CurrentValue,
        
        [ValidateSet('File', 'AD', 'WMI', 'Generic')]
        [string]$Mode = 'Generic',
        
        [hashtable]$ThemeColors
    )
    
    $colors = $ThemeColors
    if (!$colors -or !$colors.WindowBg) {
        $colors = Get-ThemeColors
    }
    if (!$colors -or !$colors.WindowBg) {
        $themeName = [PsUi.ModuleContext]::ActiveTheme
        if (!$themeName) { $themeName = 'Light' }
        $colors = Initialize-UITheme -Theme $themeName
    }
    
    # Define presets and syntax help based on mode
    switch ($Mode) {
        'File' {
            $presets = [ordered]@{
                'All Files'      = '*.*'
                'PowerShell'     = '*.ps1'
                'Scripts'        = '*.ps1, *.psm1, *.psd1'
                'Text Files'     = '*.txt'
                'Log Files'      = '*.log'
                'Config Files'   = '*.json, *.xml, *.yaml, *.yml, *.ini, *.config'
                'Documents'      = '*.docx, *.doc, *.pdf, *.xlsx, *.xls'
                'Images'         = '*.png, *.jpg, *.jpeg, *.gif, *.bmp, *.ico'
                'Code Files'     = '*.cs, *.js, *.ts, *.py, *.java, *.cpp, *.h'
                'Web Files'      = '*.html, *.htm, *.css, *.js'
                'Archives'       = '*.zip, *.7z, *.rar, *.tar, *.gz'
                'Executables'    = '*.exe, *.dll, *.msi'
            }
            $syntaxHelp = @(
                @{ Symbol = '*';  Desc = 'Any characters' }
                @{ Symbol = '?';  Desc = 'Single character' }
            )
            $exampleText  = 'e.g. *.txt, file*.log, *report*'
            $syntaxTitle  = 'Wildcards'
            $popupTitle   = 'File Filter Builder'
            $popupHeight  = 380
        }
        
        'AD' {
            $presets = [ordered]@{
                'All Users'           = '*'
                'Enabled Users'       = 'Enabled -eq $true'
                'Disabled Users'      = 'Enabled -eq $false'
                'Name Starts With'    = 'Name -like "A*"'
                'Name Contains'       = 'Name -like "*john*"'
                'Email Domain'        = 'EmailAddress -like "*@contoso.com"'
                'Department'          = 'Department -eq "IT"'
                'Title Contains'      = 'Title -like "*Manager*"'
                'Created Recently'    = 'Created -ge "2024-01-01"'
                'Password Expired'    = 'PasswordExpired -eq $true'
                'Locked Out'          = 'LockedOut -eq $true'
                'In OU'               = 'DistinguishedName -like "*OU=Sales,*"'
            }
            $syntaxHelp = @(
                @{ Symbol = '-eq';   Desc = 'Equals' }
                @{ Symbol = '-ne';   Desc = 'Not equal' }
                @{ Symbol = '-like'; Desc = 'Wildcard match (* for any)' }
                @{ Symbol = '-gt';   Desc = 'Greater than' }
                @{ Symbol = '-lt';   Desc = 'Less than' }
                @{ Symbol = '-and';  Desc = 'Both must match' }
                @{ Symbol = '-or';   Desc = 'Either can match' }
            )
            $exampleText  = 'e.g. Name -like "John*", Enabled -eq $true'
            $syntaxTitle  = 'Filter Operators'
            $popupTitle   = 'AD Filter Builder'
            $popupHeight  = 480
        }
        
        'WMI' {
            $presets = [ordered]@{
                'All Instances'      = '*'
                'Name Equals'        = "Name = 'value'"
                'Name Like'          = "Name LIKE '%pattern%'"
                'Status Running'     = "State = 'Running'"
                'Status Stopped'     = "State = 'Stopped'"
                'DriveType Fixed'    = 'DriveType = 3'
                'DriveType Removable'= 'DriveType = 2'
                'Not Null'           = 'PropertyName IS NOT NULL'
            }
            $syntaxHelp = @(
                @{ Symbol = '=';       Desc = 'Equals' }
                @{ Symbol = '<>';      Desc = 'Not equal' }
                @{ Symbol = 'LIKE';    Desc = 'Wildcard match (% for any)' }
                @{ Symbol = 'AND';     Desc = 'Both must match' }
                @{ Symbol = 'OR';      Desc = 'Either can match' }
                @{ Symbol = 'IS NULL'; Desc = 'Null check' }
            )
            $exampleText  = "e.g. Name = 'notepad.exe', State = 'Running'"
            $syntaxTitle  = 'WQL Operators'
            $popupTitle   = 'WMI Filter Builder'
            $popupHeight  = 460
        }
        
        default {
            # Generic mode - PowerShell-style operators
            $presets = [ordered]@{
                'All'                = '*'
                'Equals'             = 'Property -eq "value"'
                'Not Equals'         = 'Property -ne "value"'
                'Like (Wildcard)'    = 'Property -like "*pattern*"'
                'Greater Than'       = 'Property -gt 100'
                'Less Than'          = 'Property -lt 100'
                'Contains'           = 'Property -contains "value"'
                'Multiple Conditions'= '(Prop1 -eq "a") -and (Prop2 -gt 10)'
            }
            $syntaxHelp = @(
                @{ Symbol = '-eq';       Desc = 'Equals' }
                @{ Symbol = '-ne';       Desc = 'Not equal' }
                @{ Symbol = '-like';     Desc = 'Wildcard (* and ?)' }
                @{ Symbol = '-match';    Desc = 'Regex' }
                @{ Symbol = '-gt / -lt'; Desc = 'Greater / less than' }
                @{ Symbol = '-and/-or';  Desc = 'Combine filters' }
            )
            $exampleText  = 'e.g. Name -eq "Test", Value -gt 100'
            $syntaxTitle  = 'Filter Operators'
            $popupTitle   = 'Filter Builder'
            $popupHeight  = 440
        }
    }
    
    $popup = [System.Windows.Window]@{
        Title                 = $popupTitle
        Width                 = 420
        Height                = $popupHeight + 32
        WindowStartupLocation = 'CenterScreen'
        ResizeMode            = 'NoResize'
        WindowStyle           = 'None'
        AllowsTransparency    = $true
        FontFamily            = [System.Windows.Media.FontFamily]::new('Segoe UI')
        Background            = [System.Windows.Media.Brushes]::Transparent
        Foreground            = ConvertTo-UiBrush $colors.WindowFg
        Opacity               = 0
    }
    
    $mainBorder = [System.Windows.Controls.Border]@{
        Margin          = [System.Windows.Thickness]::new(16)
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
        Background      = ConvertTo-UiBrush $colors.WindowBg
    }

    $shadow = [System.Windows.Media.Effects.DropShadowEffect]@{
        BlurRadius  = 16
        ShadowDepth = 4
        Opacity     = 0.35
        Color       = [System.Windows.Media.Colors]::Black
        Direction   = 270
    }
    $mainBorder.Effect = $shadow
    $popup.Content = $mainBorder
    
    $outerPanel = [System.Windows.Controls.DockPanel]@{
        LastChildFill = $true
    }
    $mainBorder.Child = $outerPanel
    
    # Custom titlebar (no padding so close button extends to edge)
    $titleBar = [System.Windows.Controls.Border]@{
        Background = ConvertTo-UiBrush $colors.HeaderBackground
        Height     = 36
    }
    [System.Windows.Controls.DockPanel]::SetDock($titleBar, 'Top')
    
    $titleGrid = [System.Windows.Controls.Grid]::new()
    $titleBar.Child = $titleGrid
    
    # Title text with left margin for visual spacing
    $titleText = [System.Windows.Controls.TextBlock]@{
        Text              = $popupTitle
        FontSize          = 14
        FontWeight        = 'SemiBold'
        Foreground        = ConvertTo-UiBrush $colors.HeaderForeground
        VerticalAlignment = 'Center'
        Margin            = [System.Windows.Thickness]::new(12, 0, 0, 0)
    }
    [void]$titleGrid.Children.Add($titleText)
    
    # Close button - foreground is set inside the template to avoid local value precedence issues
    $closeBtn = [System.Windows.Controls.Button]@{
        Content             = [PsUi.ModuleContext]::GetIcon('Close')
        FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize            = 12
        Width               = 36
        Height              = 36
        HorizontalAlignment = 'Right'
        Background          = [System.Windows.Media.Brushes]::Transparent
        BorderThickness     = [System.Windows.Thickness]::new(0)
        Cursor              = [System.Windows.Input.Cursors]::Hand
    }
    $closeBtn.OverridesDefaultStyle = $true
    
    # Apply hover template (red background, white foreground on hover)
    $closeBtnTemplate = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="Button">
    <Border x:Name="border" Background="Transparent">
        <ContentPresenter x:Name="content" HorizontalAlignment="Center" VerticalAlignment="Center"
                          TextElement.Foreground="{DynamicResource HeaderForegroundBrush}"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="border" Property="Background" Value="#E81123"/>
            <Setter TargetName="content" Property="TextElement.Foreground" Value="White"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
'@
    $closeBtn.Template = [System.Windows.Markup.XamlReader]::Parse($closeBtnTemplate)
    $closeBtn.Add_Click({ $popup.DialogResult = $false; $popup.Close() }.GetNewClosure())
    [void]$titleGrid.Children.Add($closeBtn)
    
    # Enable window dragging
    $titleBar.Add_MouseLeftButtonDown({ $popup.DragMove() }.GetNewClosure())
    [void]$outerPanel.Children.Add($titleBar)
    
    $mainPanel = [System.Windows.Controls.StackPanel]::new()
    $mainPanel.Margin = [System.Windows.Thickness]::new(16)
    
    # Presets section
    $presetsLabel = [System.Windows.Controls.TextBlock]::new()
    $presetsLabel.Text = 'Quick Presets'
    $presetsLabel.FontWeight = 'SemiBold'
    $presetsLabel.FontSize = 14
    $presetsLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $presetsLabel.Foreground = ConvertTo-UiBrush $colors.WindowFg
    [void]$mainPanel.Children.Add($presetsLabel)
    
    $presetsCombo = [System.Windows.Controls.ComboBox]::new()
    $presetsCombo.Height = 32
    $presetsCombo.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    Set-ComboBoxStyle -ComboBox $presetsCombo
    
    [void]$presetsCombo.Items.Add('(Select a preset...)')
    foreach ($key in $presets.Keys) {
        [void]$presetsCombo.Items.Add($key)
    }
    $presetsCombo.SelectedIndex = 0
    [void]$mainPanel.Children.Add($presetsCombo)
    
    # Custom pattern section
    $customLabel = [System.Windows.Controls.TextBlock]::new()
    $customLabel.Text = 'Custom Filter'
    $customLabel.FontWeight = 'SemiBold'
    $customLabel.FontSize = 14
    $customLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $customLabel.Foreground = ConvertTo-UiBrush $colors.WindowFg
    [void]$mainPanel.Children.Add($customLabel)
    
    $patternBox = [System.Windows.Controls.TextBox]::new()
    $patternBox.Height = 32
    $patternBox.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $patternBox.VerticalContentAlignment = 'Center'
    $patternBox.Text = if ($CurrentValue) { $CurrentValue } else { '' }
    Set-TextBoxStyle -TextBox $patternBox
    [void]$mainPanel.Children.Add($patternBox)
    
    # Help text
    $helpText = [System.Windows.Controls.TextBlock]::new()
    $helpText.Text = $exampleText
    $helpText.FontSize = 11
    $helpText.Opacity = 0.7
    $helpText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $helpText.Foreground = ConvertTo-UiBrush $colors.WindowFg
    [void]$mainPanel.Children.Add($helpText)
    
    # Syntax reference
    $refLabel = [System.Windows.Controls.TextBlock]::new()
    $refLabel.Text = $syntaxTitle
    $refLabel.FontWeight = 'SemiBold'
    $refLabel.FontSize = 14
    $refLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $refLabel.Foreground = ConvertTo-UiBrush $colors.WindowFg
    [void]$mainPanel.Children.Add($refLabel)
    
    # Build syntax reference grid
    $refGrid = [System.Windows.Controls.Grid]::new()
    $refGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 20)
    $col1 = [System.Windows.Controls.ColumnDefinition]::new()
    $col1.Width = [System.Windows.GridLength]::new(80)
    $col2 = [System.Windows.Controls.ColumnDefinition]::new()
    [void]$refGrid.ColumnDefinitions.Add($col1)
    [void]$refGrid.ColumnDefinitions.Add($col2)
    
    $row = 0
    foreach ($item in $syntaxHelp) {
        $refGrid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new())
        
        $symText = [System.Windows.Controls.TextBlock]::new()
        $symText.Text = $item.Symbol
        $symText.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
        $symText.FontWeight = 'Bold'
        $symText.Foreground = ConvertTo-UiBrush $colors.Accent
        [System.Windows.Controls.Grid]::SetRow($symText, $row)
        [System.Windows.Controls.Grid]::SetColumn($symText, 0)
        [void]$refGrid.Children.Add($symText)
        
        $descText = [System.Windows.Controls.TextBlock]::new()
        $descText.Text = $item.Desc
        $descText.FontSize = 12
        $descText.Opacity = 0.8
        $descText.Foreground = ConvertTo-UiBrush $colors.WindowFg
        [System.Windows.Controls.Grid]::SetRow($descText, $row)
        [System.Windows.Controls.Grid]::SetColumn($descText, 1)
        [void]$refGrid.Children.Add($descText)
        
        $row++
    }
    [void]$mainPanel.Children.Add($refGrid)
    
    # Buttons panel
    $buttonPanel = [System.Windows.Controls.StackPanel]::new()
    $buttonPanel.Orientation = 'Horizontal'
    $buttonPanel.HorizontalAlignment = 'Right'
    
    # OK button
    $okButton = [System.Windows.Controls.Button]::new()
    $okButton.Content = 'Apply'
    $okButton.Width = 80
    $okButton.Height = 32
    $okButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $okButton.IsDefault = $true
    Set-ButtonStyle -Button $okButton -Accent
    [void]$buttonPanel.Children.Add($okButton)
    
    # Cancel button
    $cancelButton = [System.Windows.Controls.Button]::new()
    $cancelButton.Content = 'Cancel'
    $cancelButton.Width = 80
    $cancelButton.Height = 32
    $cancelButton.IsCancel = $true
    Set-ButtonStyle -Button $cancelButton
    [void]$buttonPanel.Children.Add($cancelButton)
    
    [void]$mainPanel.Children.Add($buttonPanel)
    
    # Add main panel to outer layout
    [void]$outerPanel.Children.Add($mainPanel)
    
    # Wire up preset selection
    $presetsCombo.Add_SelectionChanged({
        param($sender, $eventArgs)
        if ($sender.SelectedIndex -gt 0) {
            $selectedKey = $sender.SelectedItem
            if ($presets.Contains($selectedKey)) {
                $patternBox.Text = $presets[$selectedKey]
            }
        }
    }.GetNewClosure())
    
    # Wire up OK button
    $okButton.Add_Click({
        $result = $patternBox.Text
        $popup.Tag = $result
        $popup.DialogResult = $true
        $popup.Close()
    }.GetNewClosure())
    
    # Wire up Cancel button
    $cancelButton.Add_Click({
        $popup.DialogResult = $false
        $popup.Close()
    }.GetNewClosure())
    
    # Fade-in animation
    Start-UIFadeIn -Window $popup
    
    # Show dialog
    $dialogResult = $popup.ShowDialog()
    
    if ($dialogResult -eq $true) {
        return $popup.Tag
    }
    
    return $null
}
