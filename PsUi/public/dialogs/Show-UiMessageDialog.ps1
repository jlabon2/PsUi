function Show-UiMessageDialog {
    <#
    .SYNOPSIS
        Displays a themed message dialog with customizable buttons and icons.
    .DESCRIPTION
        Shows a custom WPF dialog that respects the current theme. Replaces standard MessageBox.
    .PARAMETER Title
        Dialog window title.
    .PARAMETER Message
        Message text to display.
    .PARAMETER Buttons
        Button configuration: OK, OKCancel, YesNo, or YesNoCancel.
    .PARAMETER Icon
        Icon type: Info, Warning, Error, Question, or None.
    .PARAMETER PowerShell
        When used, displays the message in a PowerShell console-styled code viewer.
        Uses Consolas font, blue background (#012456), white text, and makes the dialog
        larger (700x500) and resizable with horizontal/vertical scrollbars.
        Ideal for displaying source code or command snippets.
    .PARAMETER CustomButtons
        Array of hashtables defining custom buttons. Each hashtable should have:
        - Label: The button text (required)
        - Value: The value returned when clicked (required)
        - IsDefault: If true, this button is the default (optional)
        - IsAccent: If true, button uses accent color (optional)
        When provided, the -Buttons parameter is ignored.
    .PARAMETER ThemeColors
        Override theme colors for this dialog. Pass a colors hashtable directly.
    .EXAMPLE
        Show-UiMessageDialog -Title 'Confirmation' -Message 'Are you sure?' -Buttons YesNo -Icon Question
    .EXAMPLE
        $buttons = @(
            @{ Label = 'Save'; Value = 'Save'; IsAccent = $true; IsDefault = $true }
            @{ Label = 'Discard'; Value = 'Discard' }
            @{ Label = 'Cancel'; Value = 'Cancel' }
        )
        Show-UiMessageDialog -Title 'Unsaved Changes' -Message 'Save changes?' -CustomButtons $buttons -Icon Question
    .EXAMPLE
        $result = Show-UiMessageDialog -Title 'Success' -Message 'Operation completed!' -Buttons OK -Icon Info
    .EXAMPLE
        Show-UiMessageDialog -Title 'Source Code' -Message $scriptBlock.ToString() -PowerShell
    #>
    [CmdletBinding()]
    param(
        [string]$Title = 'Message',
        
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('OK', 'OKCancel', 'YesNo', 'YesNoCancel')]
        [string]$Buttons = 'OK',
        
        [ValidateSet('Info', 'Warning', 'Error', 'Question', 'None')]
        [string]$Icon = 'Info',

        [object]$ThemeColors,
        
        [switch]$PowerShell,

        [array]$CustomButtons
    )

    Write-Debug "Title='$Title' Buttons='$Buttons' Icon='$Icon' PowerShell=$PowerShell"

    # Calculate width based on button count - each button is ~90px wide
    $buttonCount   = if ($CustomButtons) { $CustomButtons.Count } else { 3 }
    $minForButtons = [Math]::Max(420, ($buttonCount * 90) + 50)

    # PowerShell mode uses fixed size; standard mode sizes to content
    $dialogParams = @{
        Title         = $Title
        Width         = if ($PowerShell) { 700 } else { $minForButtons }
        Height        = if ($PowerShell) { 500 } else { 0 }
        MaxHeight     = if ($PowerShell) { 10000 } else { 800 }
        SizeToContent = if ($PowerShell) { 'Manual' } else { 'Height' }
        ResizeMode    = if ($PowerShell) { 'CanResizeWithGrip' } else { 'NoResize' }
        AppIdSuffix   = 'Message'
        ThemeColors   = $ThemeColors
    }

    # Set overlay icon based on message type
    $overlayGlyph = switch ($Icon) {
        'Info'     { [PsUi.ModuleContext]::GetIcon('Info') }
        'Warning'  { [PsUi.ModuleContext]::GetIcon('Alert') }
        'Error'    { [PsUi.ModuleContext]::GetIcon('Error') }
        'Question' { [PsUi.ModuleContext]::GetIcon('Help') }
        default    { [PsUi.ModuleContext]::GetIcon('Info') }
    }
    $dialogParams['OverlayGlyph'] = $overlayGlyph

    # Use standard helper to create the window shell
    $dialog       = New-DialogWindow @dialogParams
    $window       = $dialog.Window
    $contentPanel = $dialog.ContentPanel
    $colors       = $dialog.Colors

    # Color for icon matches overlay
    $iconColor = switch ($Icon) {
        'Info'     { $colors.Accent }
        'Warning'  { $colors.Warning }
        'Error'    { $colors.Error }
        'Question' { $colors.Accent }
        default    { $colors.Accent }
    }
    
    # Button panel at bottom using Grid for left/right alignment
    $buttonBar = [System.Windows.Controls.Grid]::new()
    $buttonBar.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
    [void]$buttonBar.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]@{ Width = '*' })
    [void]$buttonBar.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]@{ Width = 'Auto' })
    [System.Windows.Controls.DockPanel]::SetDock($buttonBar, 'Bottom')
    [void]$contentPanel.Children.Add($buttonBar)
    
    # Add copy button for informational dialogs (not Question/choice dialogs)
    $showCopyButton = $Icon -in @('Info', 'Warning', 'Error') -or $PowerShell
    if ($showCopyButton) {
        $copyBtn = [System.Windows.Controls.Button]@{
            Height              = 28
            Padding             = [System.Windows.Thickness]::new(10, 4, 10, 4)
            ToolTip             = 'Copy message to clipboard'
            HorizontalAlignment = 'Left'
        }
        
        # Icon + text content for copy button
        $copyContent = [System.Windows.Controls.StackPanel]@{ Orientation = 'Horizontal' }
        $copyIcon = [System.Windows.Controls.TextBlock]@{
            Text              = [PsUi.ModuleContext]::GetIcon('Copy')
            FontFamily        = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            FontSize          = 12
            Margin            = [System.Windows.Thickness]::new(0, 0, 6, 0)
            VerticalAlignment = 'Center'
        }
        $copyText = [System.Windows.Controls.TextBlock]@{
            Text              = 'Copy'
            VerticalAlignment = 'Center'
        }
        [void]$copyContent.Children.Add($copyIcon)
        [void]$copyContent.Children.Add($copyText)
        $copyBtn.Content = $copyContent
        
        # Apply standard styling and wire up click
        Set-ButtonStyle -Button $copyBtn
        $copyBtn.Tag = $Message
        $copyBtn.Add_Click({
            [System.Windows.Clipboard]::SetText($this.Tag)
            
            # Brief visual feedback - change icon to checkmark
            $panel     = $this.Content
            $iconBlock = $panel.Children[0]
            $originalIcon = $iconBlock.Text
            $iconBlock.Text = [PsUi.ModuleContext]::GetIcon('Accept')
            
            # Reset after 1.5 seconds
            $timer = [System.Windows.Threading.DispatcherTimer]::new()
            $timer.Interval = [TimeSpan]::FromMilliseconds(1500)
            $capturedIconBlock = $iconBlock
            $capturedOriginal  = $originalIcon
            $timer.Add_Tick({
                $capturedIconBlock.Text = $capturedOriginal
                $this.Stop()
            }.GetNewClosure())
            $timer.Start()
        })
        
        [System.Windows.Controls.Grid]::SetColumn($copyBtn, 0)
        [void]$buttonBar.Children.Add($copyBtn)
    }
    
    # Right-aligned button panel for action buttons
    $buttonPanel = [System.Windows.Controls.StackPanel]@{
        Orientation         = 'Horizontal'
        HorizontalAlignment = 'Right'
    }
    [System.Windows.Controls.Grid]::SetColumn($buttonPanel, 1)
    [void]$buttonBar.Children.Add($buttonPanel)

    # Build message content area - different for PowerShell vs standard mode
    if ($PowerShell) {
        # PowerShell console-styled TextBox
        $codeBox = [System.Windows.Controls.TextBox]@{
            Text                          = $Message
            IsReadOnly                    = $true
            AcceptsReturn                 = $true
            TextWrapping                  = 'NoWrap'
            VerticalContentAlignment      = 'Top'
            HorizontalScrollBarVisibility = 'Auto'
            VerticalScrollBarVisibility   = 'Auto'
            FontFamily                    = [System.Windows.Media.FontFamily]::new('Consolas')
            FontSize                      = 13
            Background                    = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#012456')
            Foreground                    = [System.Windows.Media.Brushes]::White
            BorderThickness               = [System.Windows.Thickness]::new(1)
            BorderBrush                   = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#1E3A5F')
            Padding                       = [System.Windows.Thickness]::new(5)
            Margin                        = [System.Windows.Thickness]::new(0, 0, 0, 12)
        }
        
        # Add themed context menu for copy/select all
        $codeBox.ContextMenu = New-TextBoxContextMenu -ReadOnly
        [void]$contentPanel.Children.Add($codeBox)
    }
    else {
        # Standard message area with optional icon, wrapped in ScrollViewer
        $scrollViewer = [System.Windows.Controls.ScrollViewer]@{
            VerticalScrollBarVisibility   = 'Auto'
            HorizontalScrollBarVisibility = 'Disabled'
            Padding                       = [System.Windows.Thickness]::new(0, 0, 8, 0)
        }
        
        $messageGrid = [System.Windows.Controls.Grid]::new()
        [void]$messageGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
        [void]$messageGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
        
        $hasIcon = $Icon -ne 'None'
        if ($hasIcon) {
            $messageGrid.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(48)
        }
        else {
            $messageGrid.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(0)
        }
        $messageGrid.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)

        # Add icon if needed
        if ($hasIcon) {
            $iconBlock = [System.Windows.Controls.TextBlock]@{
                Text                = $overlayGlyph
                FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
                FontSize            = 32
                Foreground          = ConvertTo-UiBrush $iconColor
                VerticalAlignment   = 'Center'
                HorizontalAlignment = 'Center'
                Margin              = [System.Windows.Thickness]::new(0, 0, 12, 0)
            }
            [System.Windows.Controls.Grid]::SetColumn($iconBlock, 0)
            [void]$messageGrid.Children.Add($iconBlock)
        }
        
        $messageText = [System.Windows.Controls.TextBlock]@{
            Text              = $Message
            FontSize          = 13
            TextWrapping      = 'Wrap'
            Foreground        = ConvertTo-UiBrush $colors.ControlFg
            VerticalAlignment = 'Top'
            Margin            = [System.Windows.Thickness]::new(0, 0, 0, 0)
        }
        [System.Windows.Controls.Grid]::SetColumn($messageText, 1)
        [void]$messageGrid.Children.Add($messageText)
        
        $scrollViewer.Content = $messageGrid
        [void]$contentPanel.Children.Add($scrollViewer)
    }

    # Add buttons - either custom buttons or standard button sets
    if ($CustomButtons -and $CustomButtons.Count -gt 0) {
        foreach ($btnDef in $CustomButtons) {
            $btn = [System.Windows.Controls.Button]@{
                Content  = $btnDef.Label
                MinWidth = 70
                Height   = 28
                Margin   = [System.Windows.Thickness]::new(6, 0, 0, 0)
                Padding  = [System.Windows.Thickness]::new(14, 4, 14, 4)
            }
            
            if ($btnDef.IsAccent) {
                Set-ButtonStyle -Button $btn -Accent
            }
            else {
                Set-ButtonStyle -Button $btn
            }
            
            # Store value AND window reference to avoid closure issues
            $btn.Tag = @{ Value = $btnDef.Value; Window = $window }
            $btn.Add_Click({
                $this.Tag.Window.Tag = $this.Tag.Value
                $this.Tag.Window.Close()
            })
            
            [void]$buttonPanel.Children.Add($btn)
            
            if ($btnDef.IsDefault) { $btn.IsDefault = $true }
            if ($btnDef.IsCancel) { $btn.IsCancel = $true }
        }
    }
    else {
        # Standard button configurations - helper to create styled button
        $createButton = {
            param($Text, $IsAccent, $Result, $TargetWindow)
            $btn = [System.Windows.Controls.Button]@{
                Content = $Text
                Width   = 80
                Height  = 28
                Margin  = [System.Windows.Thickness]::new(4, 0, 0, 0)
            }
            if ($IsAccent) { Set-ButtonStyle -Button $btn -Accent }
            else { Set-ButtonStyle -Button $btn }
            $btn.Tag = @{ Result = $Result; Window = $TargetWindow }
            $btn.Add_Click({ $this.Tag.Window.Tag = $this.Tag.Result; $this.Tag.Window.Close() })
            return $btn
        }

        switch ($Buttons) {
            'OK' {
                $okBtn = & $createButton 'OK' $true 'OK' $window
                $okBtn.IsDefault = $true
                [void]$buttonPanel.Children.Add($okBtn)
            }
            'OKCancel' {
                $okBtn = & $createButton 'OK' $true 'OK' $window
                $okBtn.IsDefault = $true
                [void]$buttonPanel.Children.Add($okBtn)

                $cancelBtn = & $createButton 'Cancel' $false 'Cancel' $window
                $cancelBtn.IsCancel = $true
                [void]$buttonPanel.Children.Add($cancelBtn)
            }
            'YesNo' {
                $yesBtn = & $createButton 'Yes' $true 'Yes' $window
                $yesBtn.IsDefault = $true
                [void]$buttonPanel.Children.Add($yesBtn)

                $noBtn = & $createButton 'No' $false 'No' $window
                $noBtn.IsCancel = $true
                [void]$buttonPanel.Children.Add($noBtn)
            }
            'YesNoCancel' {
                $yesBtn = & $createButton 'Yes' $true 'Yes' $window
                $yesBtn.IsDefault = $true
                [void]$buttonPanel.Children.Add($yesBtn)

                $noBtn = & $createButton 'No' $false 'No' $window
                [void]$buttonPanel.Children.Add($noBtn)

                $cancelBtn = & $createButton 'Cancel' $false 'Cancel' $window
                $cancelBtn.IsCancel = $true
                [void]$buttonPanel.Children.Add($cancelBtn)
            }
        }
    }

    # Wire up standard fade-in behavior
    Initialize-UiWindowLoaded -Window $window -TitleBarBackground $colors.HeaderBackground -TitleBarForeground $colors.HeaderForeground

    # Position and show
    Set-UiDialogPosition -Dialog $window
    Write-Debug "Showing modal dialog"
    [void]$window.ShowDialog()
    
    $result = $window.Tag
    Write-Debug "Result: $result"
    return $result
}
