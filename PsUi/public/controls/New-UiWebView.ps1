function New-UiWebView {
    <#
    .SYNOPSIS
        Creates an embedded WebView2 browser control.
    .DESCRIPTION
        Embeds a Chromium-based browser using Microsoft Edge WebView2.
        Essential for modern OAuth/SAML authentication flows, displaying HTML reports,
        or embedding vendor web dashboards within a PsUi window.
        
        Requires the WebView2 runtime to be installed on the system.
        If missing, displays an error message with installation instructions.
        
        The control automatically resizes to fit available space when the window is
        smaller than the requested height, preventing overflow issues.
    .PARAMETER Uri
        URL to load in the browser. Mutually exclusive with -Html.
    .PARAMETER Html
        Raw HTML content to render. Mutually exclusive with -Uri.
    .PARAMETER Variable
        Variable name to register the control for later access.
    .PARAMETER OnNavigated
        ScriptBlock to execute when navigation completes. Receives the URL as $args[0].
        Useful for OAuth callback detection.
    .PARAMETER OnNavigating
        ScriptBlock to execute before navigation starts. Receives the URL as $args[0].
        Return $false to cancel navigation.
    .PARAMETER EnableScripts
        Enable JavaScript execution. Disabled by default for security.
    .PARAMETER EnableDevTools
        Allow F12 developer tools. Disabled by default.
    .PARAMETER EnableDownloads
        Allow file downloads. Disabled by default.
    .PARAMETER Height
        Fixed height in pixels. If not specified, uses default or fills available space.
    .PARAMETER MinHeight
        Minimum height in pixels. Default is 200.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control wrapper.
        These affect layout (Margin, Opacity, etc.) not the browser engine itself.
    .EXAMPLE
        New-UiWebView -Uri "https://example.com" -Variable "browser"
        # Simple URL loading
    .EXAMPLE
        New-UiWebView -Html "<h1>Report</h1><p>Generated at $(Get-Date)</p>"
        # Render HTML content
    .EXAMPLE
        New-UiWebView -Uri $authUrl -OnNavigated {
            param($url)
            if ($url -match 'callback.*code=([^&]+)') {
                $script:authCode = $matches[1]
                Close-UiParentWindow
            }
        }
        # OAuth flow with callback capture
    #>
    [CmdletBinding(DefaultParameterSetName = 'Uri')]
    param(
        [Parameter(ParameterSetName = 'Uri', Position = 0)]
        [string]$Uri,

        [Parameter(ParameterSetName = 'Html', Mandatory)]
        [string]$Html,

        [string]$Variable,

        [scriptblock]$OnNavigated,

        [scriptblock]$OnNavigating,

        [switch]$EnableScripts,

        [switch]$EnableDevTools,

        [switch]$EnableDownloads,

        [int]$Height,

        [int]$MinHeight = 200,

        [hashtable]$WPFProperties
    )

    $session = Get-UiSession

    # Check runtime availability
    if (![PsUi.WebViewHelper]::IsRuntimeAvailable) {
        $errorMsg = [PsUi.WebViewHelper]::GetMissingRuntimeMessage()
        Write-Warning $errorMsg
        
        # Build a themed placeholder for the missing runtime
        $colors = Get-ThemeColors
        
        $placeholder = [System.Windows.Controls.Border]@{
            Background      = $colors.ControlBg
            BorderBrush     = $colors.Error
            BorderThickness = [System.Windows.Thickness]::new(2)
            MinHeight       = $MinHeight
            Padding         = [System.Windows.Thickness]::new(16)
        }
        
        $errorPanel = [System.Windows.Controls.StackPanel]@{
            VerticalAlignment = 'Center'
        }
        
        $iconText = [System.Windows.Controls.TextBlock]@{
            Text                = [char]0xE783
            FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            FontSize            = 32
            Foreground          = $colors.Error
            HorizontalAlignment = 'Center'
            Margin              = [System.Windows.Thickness]::new(0, 0, 0, 8)
        }
        
        $msgText = [System.Windows.Controls.TextBlock]@{
            Text         = $errorMsg
            TextWrapping = 'Wrap'
            FontSize     = 12
            Foreground   = $colors.ControlFg
        }
        
        [void]$errorPanel.Children.Add($iconText)
        [void]$errorPanel.Children.Add($msgText)
        $placeholder.Child = $errorPanel
        
        [void]$session.CurrentParent.Children.Add($placeholder)
        return $null
    }

    $webView = [PsUi.WebViewHelper]::Create()
    
    if ($null -eq $webView) {
        Write-Warning "Failed to create WebView2 control."
        return
    }

    # Apply sizing
    if ($Height -gt 0) {
        $webView.Height    = $Height
        $webView.MaxHeight = $Height
    }
    else {
        $webView.Height    = $MinHeight
        $webView.MaxHeight = $MinHeight
    }
    $webView.MinHeight         = $MinHeight
    $webView.VerticalAlignment = 'Top'

    # Capture for closure
    [bool]$capturedEnableScripts   = $EnableScripts.IsPresent
    [bool]$capturedEnableDevTools  = $EnableDevTools.IsPresent
    [bool]$capturedEnableDownloads = $EnableDownloads.IsPresent
    [string]$capturedUri           = $Uri
    [string]$capturedHtml          = $Html
    $capturedOnNavigating          = $OnNavigating
    $capturedOnNavigated           = $OnNavigated

    # Defer settings and navigation until CoreWebView2 is ready
    $webView.add_CoreWebView2InitializationCompleted({
        param($sender, $eventArgs)
        
        if (!$eventArgs.IsSuccess) {
            Write-Warning "WebView2 initialization failed: $($eventArgs.InitializationException.Message)"
            return
        }
        
        $wv = $sender
        
        [PsUi.WebViewHelper]::ApplySecuritySettings($wv, $capturedEnableScripts, $capturedEnableDevTools, $capturedEnableDownloads)
        
        if ($capturedOnNavigating) {
            $wv.CoreWebView2.add_NavigationStarting({
                param($navSender, $navArgs)
                $navUrl = $navArgs.Uri
                $result = & $capturedOnNavigating $navUrl
                if ($result -eq $false) {
                    $navArgs.Cancel = $true
                }
            }.GetNewClosure())
        }
        
        if ($capturedOnNavigated) {
            $wv.CoreWebView2.add_NavigationCompleted({
                param($navSender, $navArgs)
                $navUrl = $navSender.Source
                & $capturedOnNavigated $navUrl
            }.GetNewClosure())
        }
        
        if ($capturedHtml) {
            [PsUi.WebViewHelper]::NavigateToHtml($wv, $capturedHtml)
        }
        elseif ($capturedUri) {
            $wv.Source = [uri]$capturedUri
        }
    }.GetNewClosure())

    if ($WPFProperties) {
        Set-UiProperties -Control $webView -Properties $WPFProperties
    }
    
    # Enforce minimum window height to prevent WebView overflow (airspace workaround)
    $webView.add_Loaded({
        param($sender, $eventArgs)
        $wv = $sender
        
        $window = [System.Windows.Window]::GetWindow($wv)
        if ($null -eq $window) { return }
        
        # Dispose WebView2 when window closes
        $window.add_Closed({
            try { $wv.Dispose() }
            catch { Write-Debug "WebView2 dispose failed: $_" }
        }.GetNewClosure())
        
        # Calculate required minimum height after layout settles
        $wv.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Loaded, [Action]{
            try {
                $point = $wv.TransformToAncestor($window).Transform([System.Windows.Point]::new(0, 0))
                $webViewTop = $point.Y
                $requiredMinHeight = $webViewTop + $wv.Height + 40
                
                if ($window.MinHeight -lt $requiredMinHeight) {
                    $window.MinHeight = $requiredMinHeight
                }
            }
            catch {
                Write-Debug "WebView2 MinHeight calculation failed: $_"
            }
        }.GetNewClosure())
    }.GetNewClosure())

    if ($Variable) {
        $session.AddControlSafe($Variable, $webView)
    }

    [void]$session.CurrentParent.Children.Add($webView)

    return $webView
}
