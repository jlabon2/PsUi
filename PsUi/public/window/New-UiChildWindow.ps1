function New-UiChildWindow {
    <#
    .SYNOPSIS
        Creates a child window that automatically inherits the parent's theme.
    .DESCRIPTION
        Creates a child/nested window that uses the active theme.
        Supports modal and non-modal display, and allows data passing between parent and child.

        Windows are shown automatically:
        - Modal windows:  Shown with ShowDialog() and return DialogResult (bool?)
        - Non-modal windows: Shown with Show() and return nothing
        - PassThru: Returns window object for manual control

        Child windows called from buttons run synchronously on the UI thread.
        No threading gymnastics required.
    .PARAMETER Parent
        Parent window object.Can be omitted to create an independent window.
    .PARAMETER Title
        Window title bar text.
    .PARAMETER Content
        ScriptBlock containing child controls.
    .PARAMETER Width
        Window width in pixels (150-2000).
    .PARAMETER Height
        Window height in pixels (100-1500).
    .PARAMETER Modal
        Display as modal dialog (blocks parent until closed).
    .PARAMETER Position
        Window position:  CenterOnParent, CenterOnScreen, or Manual.
    .PARAMETER Left
        Left position (for Manual positioning).
    .PARAMETER Top
        Top position (for Manual positioning).
    .PARAMETER NoResize
        Prevent user from resizing the window. Windows are resizable by default.
    .PARAMETER OnClosed
        ScriptBlock to execute when window closes.
    .PARAMETER PassThru
        Return the window object instead of displaying it automatically.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
        Allows setting any valid WPF property not explicitly exposed as a parameter.
        Invalid properties will generate warnings but not stop execution.
        Supports attached properties using dot notation (e.g., "Grid.Row").
    .EXAMPLE
        # Modal dialog - parent is auto-detected from session
        New-UiButton -Text "Open Settings" -NoAsync -Action {
            $result = New-UiChildWindow -Title 'Settings' -Modal -Content {
                New-UiLabel -Text 'Configure settings'
                New-UiButton -Text 'Save' -Action {
                    $session = Get-UiSession
                    $session.Window.DialogResult = $true
                    $session.Window.Close()
                }
            }
            if ($result) { Write-Host "User clicked Save" }
        }
    .EXAMPLE
        # Non-modal window - parent auto-detected
        New-UiButton -Text "Show Monitor" -NoAsync -Action {
            New-UiChildWindow -Title 'Status Monitor' -Width 300 -Height 200 -Content {
                New-UiLabel -Text 'Monitoring...' -Variable statusLabel
                New-UiButton -Text "Close" -Action {
                    (Get-UiSession).Window.Close()
                }
            }
        }
    .EXAMPLE
        # Shared data between windows via reference type
        $counter = @{ Value = 0 }
        New-UiButton -Text "Open Counter" -LinkedVariables 'counter' -NoAsync -Action {
            New-UiChildWindow -Title "Counter" -Content {
                $label = New-UiLabel -Text "Count: 0" -Style SubHeader
                New-UiButton -Text "Increment" -Action {
                    $counter.Value++
                    $label.Text = "Count: $($counter.Value)"
                }
            }
        }
    #>
    [CmdletBinding()]
    param(
        [System.Windows.Window]$Parent,

        [string]$Title = 'Child Window',

        [Parameter(Mandatory)]
        [scriptblock]$Content,

        [ValidateRange(150, 2000)]
        [int]$Width = 400,

        [ValidateRange(100, 1500)]
        [int]$Height = 300,

        [switch]$Modal,

        [ValidateSet('CenterOnParent', 'CenterOnScreen', 'Manual')]
        [string]$Position = 'CenterOnParent',

        [System.Nullable[int]]$Left,

        [System.Nullable[int]]$Top,

        [switch]$NoResize,

        [scriptblock]$OnClosed,

        [switch]$PassThru,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    # Reject empty content scriptblock early
    if ([string]::IsNullOrWhiteSpace($Content.ToString())) {
        throw "New-UiChildWindow: The -Content scriptblock is empty. Add UI controls inside the block."
    }

    # Capture caller's session state for variable resolution
    $callerSessionState = $PSCmdlet.SessionState

    # Auto-detect parent window if not provided
    if (!$Parent) {
        $session = Get-UiSession
        if ($session -and $session.Window) {
            $Parent = $session.Window
            Write-Verbose "[New-UiChildWindow] Auto-detected parent window from session"
        }
    }

    $colors = if (Test-Path variable:__WPFThemeColors) {
        Get-Variable -Name __WPFThemeColors -ValueOnly -ErrorAction SilentlyContinue
    } else { $null }

    if (!$colors) {
        $colors = Get-ThemeColors
    }

    if (!$colors) {
        $colors = @{
            WindowBg = '#FFFFFF'
            WindowFg = '#1A1A1A'
            ControlBg = '#F0F0F0'
            ControlFg = '#000000'
        }
    }

    # Save parent session ID so we can restore it after child window closes
    $parentSessionId = [PsUi.SessionManager]::CurrentSessionId

    $session = Initialize-UiSession
    if (!$session) {
        Write-Error "Failed to initialize WPF session for child window"
        return
    }
    
    # Capture child session ID for cleanup
    $childSessionId = [PsUi.SessionManager]::CurrentSessionId

    $startupLocation = switch ($Position) {
        'CenterOnParent' { if ($Parent) { 'CenterOwner' } else { 'CenterScreen' } }
        'CenterOnScreen' { 'CenterScreen' }
        'Manual' { 'Manual' }
        default { 'CenterScreen' }
    }

    # Create the window with custom chrome for shadow support
    # Add padding to dimensions to accommodate shadow margin
    $shadowPadding = 16
    $window = [System.Windows.Window]@{
        Title                 = $Title
        Width                 = $Width + ($shadowPadding * 2)
        Height                = $Height + ($shadowPadding * 2)
        MinWidth              = 200 + ($shadowPadding * 2)
        MinHeight             = 150 + ($shadowPadding * 2)
        WindowStartupLocation = $startupLocation
        FontFamily            = [System.Windows.Media.FontFamily]::new('Segoe UI')
        Background            = [System.Windows.Media.Brushes]::Transparent
        Foreground            = ConvertTo-UiBrush $colors.WindowFg
        ResizeMode            = if ($NoResize) { 'NoResize' } else { 'CanResize' }
        WindowStyle           = 'None'
        AllowsTransparency    = $true
        Opacity               = 0
    }

    # Set unique AppUserModelID to separate from PowerShell in taskbar
    $appId = "PsUi.ChildWindow." + [Guid]::NewGuid().ToString("N").Substring(0, 8)
    [PsUi.WindowManager]::SetWindowAppId($window, $appId)

    # Create custom window icon (inherit parent's custom logo if set)
    $childWindowIcon = $null
    try {
        $parentSession = Get-UiSession
        if ($parentSession.CustomLogo -and (Test-Path $parentSession.CustomLogo)) {
            $childWindowIcon = Get-CustomLogoIcon -Path $parentSession.CustomLogo
        }
        else {
            $childWindowIcon = New-WindowIcon -Colors $colors
        }
        if ($childWindowIcon) {
            $window.Icon = $childWindowIcon
        }
    }
    catch {
        Write-Verbose "Failed to create window icon:  $_"
    }

    if ($Parent) {
        try {
            $window.Owner = $Parent
        }
        catch {
            Write-Verbose "[New-UiChildWindow] Could not set Owner: $_"
            # Adjust startup location if we couldn't set owner
            if ($startupLocation -eq 'CenterOwner') {
                $window.WindowStartupLocation = 'CenterScreen'
            }
        }
    }

    $shadowBorder = [System.Windows.Controls.Border]@{
        Margin     = [System.Windows.Thickness]::new($shadowPadding)
        Background = ConvertTo-UiBrush $colors.WindowBg
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
    }

    $shadow = [System.Windows.Media.Effects.DropShadowEffect]@{
        BlurRadius  = 16
        ShadowDepth = 4
        Opacity     = 0.35
        Color       = [System.Windows.Media.Colors]::Black
        Direction   = 270
    }
    $shadowBorder.Effect = $shadow
    $window.Content = $shadowBorder

    # Use a Grid as container so we can overlay a resize grip
    $containerGrid = [System.Windows.Controls.Grid]::new()
    $shadowBorder.Child = $containerGrid

    # Main layout DockPanel inside the shadow border
    $outerPanel = [System.Windows.Controls.DockPanel]@{
        LastChildFill = $true
    }
    [void]$containerGrid.Children.Add($outerPanel)

    # Add resize grip for borderless window (only if resizable)
    if (!$NoResize) {
        $resizeGrip = [System.Windows.Controls.Primitives.ResizeGrip]@{
            HorizontalAlignment = 'Right'
            VerticalAlignment   = 'Bottom'
            Cursor              = [System.Windows.Input.Cursors]::SizeNWSE
        }
        [void]$containerGrid.Children.Add($resizeGrip)

        # Calculate minimum dimensions (must match window's MinWidth/MinHeight)
        $minResizeWidth  = 200 + ($shadowPadding * 2)
        $minResizeHeight = 150 + ($shadowPadding * 2)

        $resizeGrip.Add_MouseLeftButtonDown({
            param($sender, $eventArgs)
            $sender.CaptureMouse()
            $eventArgs.Handled = $true
        })

        $capturedWindowForResize = $window
        $resizeGrip.Add_MouseMove({
            param($sender, $eventArgs)
            if ($sender.IsMouseCaptured) {
                $mousePos = [System.Windows.Input.Mouse]::GetPosition($capturedWindowForResize)
                $newWidth  = [Math]::Max($minResizeWidth, $mousePos.X)
                $newHeight = [Math]::Max($minResizeHeight, $mousePos.Y)
                $capturedWindowForResize.Width  = $newWidth
                $capturedWindowForResize.Height = $newHeight
                $eventArgs.Handled = $true
            }
        }.GetNewClosure())

        $resizeGrip.Add_MouseLeftButtonUp({
            param($sender, $eventArgs)
            $sender.ReleaseMouseCapture()
            $eventArgs.Handled = $true
        })
    }

    # Custom title bar for drag support and close button
    $titleBar = [System.Windows.Controls.Border]@{
        Background = ConvertTo-UiBrush $colors.HeaderBackground
        Height     = 36
        Padding    = [System.Windows.Thickness]::new(12, 0, 4, 0)
    }
    [System.Windows.Controls.DockPanel]::SetDock($titleBar, 'Top')

    $titleGrid = [System.Windows.Controls.Grid]::new()
    $titleBar.Child = $titleGrid

    $titleText = [System.Windows.Controls.TextBlock]@{
        Text              = $Title
        FontSize          = 13
        FontWeight        = 'SemiBold'
        Foreground        = ConvertTo-UiBrush $colors.HeaderForeground
        VerticalAlignment = 'Center'
    }
    [void]$titleGrid.Children.Add($titleText)

    # Close button with red hover effect
    # Foreground is set inside the template - do NOT use a property setter on the button,
    # it creates a local value that overrides template trigger setters after theme changes.
    $closeBtn = [System.Windows.Controls.Button]@{
        Content             = [PsUi.ModuleContext]::GetIcon('Close')
        FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize            = 10
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

    $capturedWindow = $window
    $capturedModal  = $Modal
    $closeBtn.Add_Click({
        if ($capturedModal) {
            $capturedWindow.DialogResult = $false
        }
        $capturedWindow.Close()
    }.GetNewClosure())
    [void]$titleGrid.Children.Add($closeBtn)

    $titleBar.Add_MouseLeftButtonDown({ $capturedWindow.DragMove() }.GetNewClosure())
    [void]$outerPanel.Children.Add($titleBar)

    $dockPanel = [System.Windows.Controls.DockPanel]::new()
    $scrollViewer = [System.Windows.Controls.ScrollViewer]::new()
    $scrollViewer.VerticalScrollBarVisibility = 'Auto'
    $scrollViewer.HorizontalScrollBarVisibility = 'Disabled'
    $contentStack = [System.Windows.Controls.StackPanel]::new()
    $contentStack.Margin = [System.Windows.Thickness]::new(16, 12, 16, 12)

    $scrollViewer.Content = $contentStack
    [void]$dockPanel.Children.Add($scrollViewer)
    [void]$outerPanel.Children.Add($dockPanel)

    $session.Window = $window
    $session.CurrentParent = $contentStack

    $controlName = "ChildWindow_$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    Register-UiControl -Name $controlName -Control $window
    Register-UiControl -Name "${controlName}_ContentStack" -Control $contentStack

# Build the content using dot-sourcing to run in current scope
# Capture variables from caller's scope that are referenced in Content
try {
    $capturedVars = @{}
    $ast = $Content.Ast

    # Find all variable references in the Content scriptblock
    $varExpressions = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.VariableExpressionAst]
    }, $true)

    # Variables to exclude (built-ins, scope-qualified, etc.)
    $excludeVars = @(
        '_', 'args', 'Error', 'false', 'Host', 'input', 'null', 'PSBoundParameters',
        'PSCmdlet', 'PSScriptRoot', 'PSVersionTable', 'true', 'env', 'this',
        'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
        'session', 'parent', 'parentSession', 'callerSessionState', 'colors'
    )

    foreach ($varExpr in $varExpressions) {
        $varName = $varExpr.VariablePath.UserPath

        if ($excludeVars -contains $varName) { continue }
        if ($capturedVars.ContainsKey($varName)) { continue }

        # Skip scope-qualified variables
        if ($varExpr.VariablePath.IsScript -or
            $varExpr.VariablePath.IsGlobal -or
            $varExpr.VariablePath.IsLocal -or
            $varExpr.VariablePath.IsPrivate) { continue }

        # Try to get the variable from caller's scope
        try {
            $var = $callerSessionState.PSVariable.Get($varName)
            if ($null -ne $var) {
                $capturedVars[$varName] = $var.Value
            }
        }
        catch { Write-Debug "Variable capture failed for '$varName': $_" }
    }

    # Inject captured variables into current scope before running Content
    foreach ($key in $capturedVars.Keys) {
        Set-Variable -Name $key -Value $capturedVars[$key] -Scope Local
    }

    Write-Verbose "[New-UiChildWindow] Captured $($capturedVars.Count) variables from caller scope"
}
catch {
    Write-Verbose "[New-UiChildWindow] Variable capture failed: $_"
}

try {
    Write-Debug "Executing content block"
    Invoke-UiContent -Content $Content -CallerName 'New-UiChildWindow'
}
catch {
    Write-Error $_
    Clear-UiSession
    return $null
}

# Set up window load event for fade-in and theming
$window.Add_Loaded({
    # Apply manual positioning if specified
    if ($Position -eq 'Manual') {
        if ($null -ne $Left) { $this.Left = $Left }
        if ($null -ne $Top) { $this.Top = $Top }
    }

    # Apply title bar theming using Set-UIResources (same as main window)
    Set-UIResources -Window $this -Colors $colors -IconPath $null

    # Force taskbar to use our themed icon (requires window handle)
    if ($childWindowIcon) {
        [PsUi.WindowManager]::SetTaskbarIcon($this, $childWindowIcon)
    }

    # Fade-in animation with easing
    $fadeIn = [System.Windows.Media.Animation.DoubleAnimation]@{
        From     = 0
        To       = 1
        Duration = [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds(350))
    }
    $fadeIn.EasingFunction = [System.Windows.Media.Animation.QuadraticEase]@{
        EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    }
    $this.BeginAnimation([System.Windows.Window]::OpacityProperty, $fadeIn)
}.GetNewClosure())

    if ($OnClosed) {
        $window.Add_Closed({
            & $OnClosed
        }.GetNewClosure())
    }

    # Cleanup child session and restore parent session when window closes
    $capturedParent = $Parent
    $window.Add_Closed({
        # Dispose the child window's session
        if ($childSessionId -ne [Guid]::Empty) {
            [PsUi.SessionManager]::DisposeSession($childSessionId)
        }
        
        # Restore the parent window's session as current (both ThreadStatic and global variable)
        if ($parentSessionId -ne [Guid]::Empty) {
            [PsUi.SessionManager]::SetCurrentSession($parentSessionId)
            $Global:__PsUiSessionId = $parentSessionId.ToString()
        }
        
        # Activate the parent window so it comes back to the foreground
        if ($capturedParent) {
            $capturedParent.Activate()
        }
    }.GetNewClosure())

    if ($WPFProperties) {
        Set-UiProperties -Control $window -Properties $WPFProperties
    }

    if ($PassThru) {
        return $window
    }
    elseif ($Modal) {
        return $window.ShowDialog()
    }
    else {
        [void]$window.Show()
    }
}