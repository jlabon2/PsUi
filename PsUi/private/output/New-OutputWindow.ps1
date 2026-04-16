
function New-OutputWindow {
    <#
    .SYNOPSIS
        Creates a themed output window with custom chrome (no white flash on dark themes).
    #>
    [CmdletBinding()]
    param(
        [string]$Title = 'Output',
        [int]$Width = 900,
        [int]$Height = 600,
        [System.Windows.Window]$ParentWindow,
        [hashtable]$Colors,
        [string]$CustomLogo
    )

    # Shadow adds padding around the visible window
    $shadowPadding = 16
    
    # Create borderless transparent window for custom chrome
    $window = [System.Windows.Window]@{
        Title                 = $Title
        Width                 = $Width + ($shadowPadding * 2)
        Height                = $Height + ($shadowPadding * 2)
        MinWidth              = 850 + ($shadowPadding * 2)
        MinHeight             = 300 + ($shadowPadding * 2)
        WindowStartupLocation = 'CenterScreen'
        FontFamily            = [System.Windows.Media.FontFamily]::new('Segoe UI')
        Background            = [System.Windows.Media.Brushes]::Transparent
        Foreground            = ConvertTo-UiBrush $Colors.ControlFg
        ResizeMode            = 'CanResize'
        WindowStyle           = 'None'
        AllowsTransparency    = $true
        Opacity               = 0
    }

    if ($ParentWindow) {
        try {
            $window.Owner = $ParentWindow
        }
        catch {
            Write-Verbose "[New-OutputWindow] Could not set Owner: $_"
        }
        
        # Use manual centering - CenterOwner doesn't work reliably with borderless windows
        [PsUi.WindowManager]::CenterOnParent($window, $ParentWindow)
    }

    # Set unique AppUserModelID to separate from PowerShell in taskbar
    $appId = "PsUi.OutputWindow." + [Guid]::NewGuid().ToString("N").Substring(0, 8)
    [PsUi.WindowManager]::SetWindowAppId($window, $appId)
    
    # Hook WM_GETMINMAXINFO to enable proper maximize behavior (respects taskbar)
    [PsUi.WindowManager]::EnableBorderlessMaximize($window)

    # Attach WindowChrome for resize borders on borderless window
    $windowChrome = [System.Windows.Shell.WindowChrome]@{
        CaptionHeight         = 0
        ResizeBorderThickness = [System.Windows.Thickness]::new($shadowPadding + 4)
        GlassFrameThickness   = [System.Windows.Thickness]::new(0)
        CornerRadius          = [System.Windows.CornerRadius]::new(0)
    }
    [System.Windows.Shell.WindowChrome]::SetWindowChrome($window, $windowChrome)

    $shadowBorder = [System.Windows.Controls.Border]@{
        Margin          = [System.Windows.Thickness]::new($shadowPadding)
        Background      = ConvertTo-UiBrush $Colors.WindowBg
        BorderBrush     = ConvertTo-UiBrush $Colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
    }

    $shadow = [System.Windows.Media.Effects.DropShadowEffect]@{
        BlurRadius  = 16
        ShadowDepth = 2
        Opacity     = 0.3
        Color       = [System.Windows.Media.Colors]::Black
        Direction   = 270
    }
    $shadowBorder.Effect = $shadow
    $window.Content = $shadowBorder

    $mainGrid = [System.Windows.Controls.Grid]::new()
    $mainGrid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]@{ Height = 'Auto' })
    $mainGrid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]@{ Height = '*' })
    $shadowBorder.Child = $mainGrid

    $titleBar = [System.Windows.Controls.Border]@{
        Height = 32
        Tag    = 'HeaderBorder'
    }
    # Use DynamicResource for background so it updates with theme
    $titleBar.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'HeaderBackgroundBrush')
    [System.Windows.Controls.Grid]::SetRow($titleBar, 0)

    $titleBarGrid = [System.Windows.Controls.Grid]::new()
    $titleBarGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]@{ Width = 'Auto' })
    $titleBarGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]@{ Width = '*' })
    $titleBarGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]@{ Width = 'Auto' })
    $titleBar.Child = $titleBarGrid

    # Titlebar icon image (set later once we have the icon)
    $titleBarIcon = [System.Windows.Controls.Image]@{
        Width             = 16
        Height            = 16
        Margin            = [System.Windows.Thickness]::new(10, 0, 0, 0)
        VerticalAlignment = 'Center'
    }
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($titleBarIcon, 'HighQuality')
    [System.Windows.Controls.Grid]::SetColumn($titleBarIcon, 0)
    [void]$titleBarGrid.Children.Add($titleBarIcon)

    $titleText = [System.Windows.Controls.TextBlock]@{
        Text              = $Title
        FontSize          = 12
        VerticalAlignment = 'Center'
        Margin            = [System.Windows.Thickness]::new(8, 0, 0, 0)
        Tag               = 'HeaderText'
    }
    # Use DynamicResource for foreground so it updates with theme
    $titleText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'HeaderForegroundBrush')
    [System.Windows.Controls.Grid]::SetColumn($titleText, 1)
    [void]$titleBarGrid.Children.Add($titleText)

    $buttonPanel = [System.Windows.Controls.StackPanel]@{ Orientation = 'Horizontal' }
    [System.Windows.Controls.Grid]::SetColumn($buttonPanel, 2)

    $createWindowBtn = {
        param([string]$Glyph, [scriptblock]$OnClick, [bool]$IsClose = $false)
        
        $btn = [System.Windows.Controls.Button]@{
            Content         = $Glyph
            FontFamily      = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            FontSize        = 10
            Width           = 46
            Height          = 32
            BorderThickness = [System.Windows.Thickness]::new(0)
            Cursor          = [System.Windows.Input.Cursors]::Arrow
            Padding         = [System.Windows.Thickness]::new(0)
            Tag             = 'WindowControlButton'
        }
        $btn.OverridesDefaultStyle = $true
        
        # Foreground is set inside the template via TextElement.Foreground on ContentPresenter.
        # Do NOT use SetResourceReference on the button - it creates a local value that
        # overrides template trigger setters after theme changes.
        
        if ($IsClose) {
            # Close button: red hover with white X, darker red pressed
            $templateXaml = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="border" Background="Transparent">
        <ContentPresenter x:Name="content" HorizontalAlignment="Center" VerticalAlignment="Center"
                          TextElement.Foreground="{DynamicResource HeaderForegroundBrush}"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="border" Property="Background" Value="#E81123"/>
            <Setter TargetName="content" Property="TextElement.Foreground" Value="White"/>
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
            <Setter TargetName="border" Property="Background" Value="#C50F1F"/>
            <Setter TargetName="content" Property="TextElement.Foreground" Value="White"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
'@
        }
        else {
            # Min/Max buttons: use WindowControlHoverBrush, slightly darker on press
            $templateXaml = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="border" Background="Transparent">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                          TextElement.Foreground="{DynamicResource HeaderForegroundBrush}"/>
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
        }
        # Cache parsed templates per session — avoids re-parsing identical XAML for every window
        if ($IsClose) {
            if (!$script:_closeBtnTemplate) { $script:_closeBtnTemplate = [System.Windows.Markup.XamlReader]::Parse($templateXaml) }
            $btn.Template = $script:_closeBtnTemplate
        }
        else {
            if (!$script:_windowCtrlBtnTemplate) { $script:_windowCtrlBtnTemplate = [System.Windows.Markup.XamlReader]::Parse($templateXaml) }
            $btn.Template = $script:_windowCtrlBtnTemplate
        }
        $btn.Add_Click($OnClick)
        
        # Mark button as hit-testable within WindowChrome area (critical for maximized state)
        [System.Windows.Shell.WindowChrome]::SetIsHitTestVisibleInChrome($btn, $true)
        
        return $btn
    }

    $capturedWindow = $window
    $capturedShadow = $shadowBorder

    $minimizeBtn = & $createWindowBtn ([PsUi.ModuleContext]::GetIcon('ChromeMinimize')) { $capturedWindow.WindowState = 'Minimized' }.GetNewClosure() $false
    [void]$buttonPanel.Children.Add($minimizeBtn)

    $maximizeBtn = & $createWindowBtn ([PsUi.ModuleContext]::GetIcon('ChromeMaximize')) {
        if ($capturedWindow.WindowState -eq 'Maximized') {
            $capturedWindow.WindowState = 'Normal'
        }
        else {
            $capturedWindow.WindowState = 'Maximized'
        }
    }.GetNewClosure() $false
    [void]$buttonPanel.Children.Add($maximizeBtn)

    $closeBtn = & $createWindowBtn ([PsUi.ModuleContext]::GetIcon('ChromeClose')) { 
        # Just close the window - let the Closing event handler deal with confirmations
        # and closing the ReadKey dialog at the appropriate time
        $capturedWindow.Close() 
    }.GetNewClosure() $true
    [void]$buttonPanel.Children.Add($closeBtn)

    [void]$titleBarGrid.Children.Add($buttonPanel)
    [void]$mainGrid.Children.Add($titleBar)

    $capturedMaxBtn       = $maximizeBtn
    $capturedPadding      = $shadowPadding
    $capturedShadowEffect = $shadow
    $capturedChrome       = $windowChrome
    $window.Add_StateChanged({
        if ($capturedWindow.WindowState -eq 'Maximized') {
            $capturedMaxBtn.Content = [PsUi.ModuleContext]::GetIcon('ChromeRestore')
            $capturedShadow.Margin  = [System.Windows.Thickness]::new(0)
            $capturedShadow.Effect  = $null
            
            # Remove resize borders so titlebar and scrollbars remain clickable
            $capturedChrome.ResizeBorderThickness = [System.Windows.Thickness]::new(0)
        }
        else {
            $capturedMaxBtn.Content = [PsUi.ModuleContext]::GetIcon('ChromeMaximize')
            $capturedShadow.Margin  = [System.Windows.Thickness]::new($capturedPadding)
            $capturedShadow.Effect  = $capturedShadowEffect
            
            # Restore resize borders for normal window state
            $capturedChrome.ResizeBorderThickness = [System.Windows.Thickness]::new($capturedPadding + 4)
        }
    }.GetNewClosure())

    # Shared drag state for restore-on-drag
    $dragState = @{ StartPoint = $null }
    
    $titleBar.Add_MouseLeftButtonDown({
        param($sender, $eventArgs)
        if ($eventArgs.ClickCount -eq 2) {
            if ($capturedWindow.WindowState -eq 'Maximized') {
                $capturedWindow.WindowState = 'Normal'
            }
            else {
                $capturedWindow.WindowState = 'Maximized'
            }
        }
        elseif ($eventArgs.ClickCount -eq 1) {
            if ($capturedWindow.WindowState -eq 'Maximized') {
                # Capture start point for drag detection
                $dragState.StartPoint = $eventArgs.GetPosition($capturedWindow)
                $sender.CaptureMouse()
            }
            else {
                $capturedWindow.DragMove()
            }
        }
    }.GetNewClosure())
    
    $titleBar.Add_MouseMove({
        param($sender, $eventArgs)
        if ($dragState.StartPoint -eq $null) { return }
        if ($eventArgs.LeftButton -ne 'Pressed') { return }
        
        # Check if mouse moved enough to count as a drag (5px threshold)
        $currentPos = $eventArgs.GetPosition($capturedWindow)
        $deltaX = [Math]::Abs($currentPos.X - $dragState.StartPoint.X)
        $deltaY = [Math]::Abs($currentPos.Y - $dragState.StartPoint.Y)
        
        if ($deltaX -gt 5 -or $deltaY -gt 5) {
            $sender.ReleaseMouseCapture()
            
            # Capture screen position and relative X BEFORE restoring
            $screenPos = $capturedWindow.PointToScreen($dragState.StartPoint)
            $relativeX = $dragState.StartPoint.X / $capturedWindow.ActualWidth
            
            $capturedWindow.WindowState = 'Normal'
            
            # Position window so mouse stays on titlebar at same relative X
            $capturedWindow.Left = $screenPos.X - ($capturedWindow.ActualWidth * $relativeX)
            $capturedWindow.Top  = $screenPos.Y - ($capturedPadding + 16)
            
            $dragState.StartPoint = $null
            $capturedWindow.DragMove()
        }
    }.GetNewClosure())
    
    $titleBar.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        $dragState.StartPoint = $null
        $sender.ReleaseMouseCapture()
    }.GetNewClosure())

    $contentArea = [System.Windows.Controls.Border]@{ Name = 'ContentArea' }
    [System.Windows.Controls.Grid]::SetRow($contentArea, 1)
    [void]$mainGrid.Children.Add($contentArea)

    # Create window icon (use custom logo if provided)
    $iconForLoaded = $null
    try {
        if ($CustomLogo -and (Test-Path $CustomLogo)) {
            $iconForLoaded = Get-CustomLogoIcon -Path $CustomLogo
        }
        else {
            $iconForLoaded = New-WindowIcon -Colors $Colors
        }
        if ($iconForLoaded) {
            $window.Icon         = $iconForLoaded
            $titleBarIcon.Source = $iconForLoaded
        }
    }
    catch { Write-Verbose "Failed to create window icon: $_" }

    $capturedIcon   = $iconForLoaded
    $capturedColors = $Colors

    $window.Add_Loaded({
        $anim = [System.Windows.Media.Animation.DoubleAnimation]@{
            From     = 0
            To       = 1
            Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(150))
        }
        $capturedWindow.BeginAnimation([System.Windows.Window]::OpacityProperty, $anim)

        if ($capturedIcon) {
            [PsUi.WindowManager]::SetTaskbarIcon($capturedWindow, $capturedIcon)
        }

        try {
            $runningOverlay = New-TaskbarOverlayIcon -GlyphChar ([PsUi.ModuleContext]::GetIcon('Sync')) -Color $capturedColors.Accent -BackgroundColor '#FFFFFF'
            if ($runningOverlay) {
                [PsUi.WindowManager]::SetTaskbarOverlay($capturedWindow, $runningOverlay, 'Running...')
            }
        }
        catch { Write-Debug "Suppressed taskbar running overlay error: $_" }
    }.GetNewClosure())

    # Store references for caller
    $window.Tag = @{
        ShadowBorder = $shadowBorder
        MainGrid     = $mainGrid
        ContentArea  = $contentArea
        TitleText    = $titleText
        TitleBarIcon = $titleBarIcon
    }

    return $window
}
