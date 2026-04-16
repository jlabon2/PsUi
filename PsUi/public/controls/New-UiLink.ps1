function New-UiLink {
    <#
    .SYNOPSIS
        Creates a clickable hyperlink that opens a URL or runs a custom action.
    .DESCRIPTION
        Creates a TextBlock styled as a hyperlink with underline and accent color.
        By default opens the URL in the system browser. Use -Action for custom behavior.
    .PARAMETER Text
        The display text for the link. Defaults to the URL if not specified.
    .PARAMETER Url
        The URL to open when clicked. Opens in default browser.
    .PARAMETER Action
        Custom scriptblock to run instead of opening a URL. Overrides -Url behavior.
    .PARAMETER NoUnderline
        Removes the underline decoration from the link text.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
    .EXAMPLE
        New-UiLink -Url 'https://github.com' -Text 'Visit GitHub'
    .EXAMPLE
        New-UiLink -Text 'Open Settings' -Action { Show-SettingsDialog }
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Text,

        [Parameter()]
        [string]$Url,

        [Parameter()]
        [scriptblock]$Action,

        [switch]$NoUnderline,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    # Grab session and theme context
    $session     = Assert-UiSession -CallerName 'New-UiLink'
    $colors      = Get-ThemeColors
    $parent      = $session.CurrentParent
    $displayText = if ($Text) { $Text } else { $Url }

    # Can't create a link with nothing to show
    if (!$displayText) {
        throw "New-UiLink: Either -Text or -Url must be specified."
    }

    # Build the link with accent color and hand cursor
    $link = [System.Windows.Controls.TextBlock]@{
        Text         = $displayText
        FontFamily   = [System.Windows.Media.FontFamily]::new('Segoe UI Variable, Segoe UI')
        FontSize     = 13
        Foreground   = ConvertTo-UiBrush $colors.Accent
        Cursor       = 'Hand'
        Margin       = [System.Windows.Thickness]::new(4, 2, 4, 2)
    }

    # Apply underline unless explicitly disabled
    if (!$NoUnderline) {
        $link.TextDecorations = [System.Windows.TextDecorations]::Underline
    }

    # Capture action context at creation time (like New-UiButton does)
    $capturedVars    = $null
    $capturedFuncs   = $null
    $resolvedModules = $null
    
    if ($Action) {
        $ctxParams = @{
            Action          = $Action
            LinkedVariables = @()
            LinkedFunctions = @()
            LinkedModules   = @()
        }
        $actionContext   = Get-UiActionContext @ctxParams
        $capturedVars    = $actionContext.CapturedVars
        $capturedFuncs   = $actionContext.CapturedFuncs
        $resolvedModules = $actionContext.LinkedModules
    }

    # Store action data in Tag (same structure as New-UiButton)
    $link.Tag = @{
        BrushTag      = 'AccentBrush'
        Url           = $Url
        Action        = $Action
        CapturedVars  = $capturedVars
        CapturedFuncs = $capturedFuncs
        LinkedModules = $resolvedModules
    }

    # Wire up click handler - runs action async or opens URL in browser
    $link.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        $data = $sender.Tag
        Write-Debug "New-UiLink: Click detected. Action=$($null -ne $data.Action), Url=$($data.Url)"
        
        if ($data.Action) {
            Write-Debug "New-UiLink: Executing custom action via AsyncExecutor"
            $executor = [PsUi.AsyncExecutor]::new()
            $executor.UiDispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
            
            # Route async output so Write-Host/Write-Warning/errors are visible
            $executor.add_OnHost({ param($hostRecord) Write-Host $hostRecord.Message })
            $executor.add_OnWarning({ param($warningMsg) Write-Warning $warningMsg })
            $executor.add_OnError({ param($errorRecord) Write-Warning "Link action error: $($errorRecord.Message)" })
            $executor.add_OnComplete({
                Write-Debug "New-UiLink: Action completed"
                $executor.Dispose()
            }.GetNewClosure())
            
            # Store executor in session for Stop-UiAsync cancellation
            $linkSession = [PsUi.SessionManager]::Current
            if ($linkSession) {
                $linkSession.ActiveExecutor = $executor
                Write-Debug "New-UiLink: Executor stored in session $($linkSession.SessionId)"
            }
            
            # Build variables dict with theme colors (same as New-UiButton)
            $currentThemeColors = Get-ThemeColors
            $varsWithTheme = if ($data.CapturedVars) { $data.CapturedVars.Clone() } else { @{} }
            if ($currentThemeColors) {
                $varsWithTheme['__WPFThemeColors'] = $currentThemeColors
            }
            
            $executor.ExecuteAsync(
                $data.Action,
                $null,
                $varsWithTheme,
                $data.CapturedFuncs,
                [string[]]@($data.LinkedModules | Where-Object { $_ })
            )
            Write-Debug "New-UiLink: ExecuteAsync called"
        }
        elseif ($data.Url) {
            # Only allow http/https schemes
            $urlToOpen = $data.Url
            Write-Debug "New-UiLink: Opening URL $urlToOpen"
            if ($urlToOpen -match '^https?://[^\s]+$') {
                Start-Process $urlToOpen
            }
            else {
                Write-Warning "New-UiLink: Blocked opening URL with invalid scheme. Only http/https URLs are allowed: $urlToOpen"
            }
        }
    }.GetNewClosure())

    # Subtle opacity change on hover for visual feeback
    $link.Add_MouseEnter({ param($sender, $eventArgs) $sender.Opacity = 0.7 })
    $link.Add_MouseLeave({ param($sender, $eventArgs) $sender.Opacity = 1.0 })

    # Register for dynamic theme switching
    [PsUi.ThemeEngine]::RegisterElement($link)

    if ($WPFProperties) {
        Set-UiProperties -Control $link -Properties $WPFProperties
    }

    # Attach to parent container
    if ($parent -is [System.Windows.Controls.Panel]) {
        [void]$parent.Children.Add($link)
    }
    elseif ($parent -is [System.Windows.Controls.ItemsControl]) {
        [void]$parent.Items.Add($link)
    }
    elseif ($parent -is [System.Windows.Controls.ContentControl]) {
        $parent.Content = $link
    }
}
