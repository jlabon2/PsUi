function New-UiWebView {
    <#
    .SYNOPSIS
        Creates an embedded WebView2 browser control.
    .DESCRIPTION
        Embeds a Chromium browser via Microsoft Edge WebView2, for OAuth sign-ins,
        HTML reports, vendor dashboards inside a PsUi window.

        Requires the WebView2 runtime to be installed on the system.
        If missing, displays an error message with installation instructions.

        The view sits in a slot of fixed height and is trimmed to whatever part of that slot
        is on screen, so scrolling past it never draws the browser over its neighbours.
        Window size is left to the calling script.
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
        Fixed height in pixels. Left out, the view pins to -MinHeight instead.
    .PARAMETER MinHeight
        Minimum height in pixels. Default is 200.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties. The keys that place the control in its parent
        (Margin, HorizontalAlignment, VerticalAlignment, Visibility, Width, MinWidth, MaxWidth,
        and attached values such as 'Grid.Row') apply to the element holding the view. Every
        other key, Tag and ZoomFactor alike, applies to the browser control. Height, MinHeight
        and MaxHeight are refused with a warning, because -Height and -MinHeight size the view.
    .EXAMPLE
        New-UiWebView -Uri "https://example.com" -Variable "browser"
    .EXAMPLE
        $stamp = Get-Date -Format 'HH:mm'
        New-UiWebView -Html ('<h1>Report</h1><p>Generated at ' + $stamp + '</p>')
    .EXAMPLE
        New-UiWebView -Uri $authUrl -OnNavigated {
            param($url)
            if ($url -match 'code=([^&]+)') {
                $session = Get-UiSession
                $session.Variables['authCode'] = $Matches[1]
                $session.Window.Close()
            }
        }
        # OAuth callback capture. The code lands in the session store
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
            FontFamily          = [PsUi.ModuleContext]::ActiveIconFontFamily
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

    # Apply sizing. Max, because WPF resolves MinHeight over MaxHeight and -Height 300 -MinHeight 400 used to land on 400.
    $slotHeight = if ($Height -gt 0) { [Math]::Max($Height, $MinHeight) } else { $MinHeight }

    $webView.Height            = $slotHeight
    $webView.MaxHeight         = $slotHeight
    $webView.VerticalAlignment = 'Top'

    # The slot owns the floor now, so the view is free to shrink below it. Leave MinHeight alone and the clip below can never trim the view down.
    $webView.MinHeight = 0

    # A fixed slot for the view to sit in. The clip further down trims the view to whatever part of this slot is on screen.
    # It can only do that while the slot holds still. Change the space the document occupies and the scroll offset moves, which moves the answer, which moves the offset again.
    $viewSlot = [System.Windows.Controls.Grid]@{
        Height            = $slotHeight
        VerticalAlignment = 'Top'
        ClipToBounds      = $true
    }
    [void]$viewSlot.Children.Add($webView)

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
        
        # Copy to locals before building the inner handlers. A nested GetNewClosure captures only the immediate scope, never this handler's own closure, so the captured* variables arrive as nulls when the event fires.
        $localOnNavigating = $capturedOnNavigating
        $localOnNavigated  = $capturedOnNavigated

        if ($localOnNavigating) {
            $wv.CoreWebView2.add_NavigationStarting({
                param($navSender, $navArgs)
                $navUrl = $navArgs.Uri
                $result = & $localOnNavigating $navUrl
                if ($result -eq $false) {
                    $navArgs.Cancel = $true
                }
            }.GetNewClosure())
        }

        if ($localOnNavigated) {
            $wv.CoreWebView2.add_NavigationCompleted({
                param($navSender, $navArgs)
                $navUrl = $navSender.Source
                & $localOnNavigated $navUrl
            }.GetNewClosure())
        }
        
        if ($capturedHtml) {
            [PsUi.WebViewHelper]::NavigateToHtml($wv, $capturedHtml)
        }
        elseif ($capturedUri) {
            $wv.Source = [uri]$capturedUri
        }
    }.GetNewClosure())

    # Only the keys that place the whole thing in its parent belong on the slot. Margin has to go there because the trim rewrites the view's own copy on every scroll, and Visibility because hiding the slot gives the space back instead of leaving a hole the height of the view.
    # Everything else stays on the view, where it went before the slot existed. Routing on "does a Grid have this property" instead would quietly strand Tag, Style and the rest on an element no script can reach.
    $slotOwned = @('Margin', 'HorizontalAlignment', 'VerticalAlignment', 'Visibility', 'Width', 'MinWidth', 'MaxWidth')

    if ($WPFProperties) {
        $slotProps = @{}
        $viewProps = @{}

        foreach ($key in $WPFProperties.Keys) {
            # -Height and -MinHeight own the slot. A second opinion here parts the trim's ceiling from the space the slot actually takes.
            if ($key -in 'Height', 'MinHeight', 'MaxHeight') {
                Write-Warning "New-UiWebView: -WPFProperties '$key' ignored. Use -Height or -MinHeight to size the view."
                continue
            }

            # Attached values ('Grid.Row') position the slot in its parent, so they go with the layout keys.
            if ($key -like '*.*' -or $key -in $slotOwned) { $slotProps[$key] = $WPFProperties[$key] }
            else { $viewProps[$key] = $WPFProperties[$key] }
        }

        if ($slotProps.Count) { Set-UiProperties -Control $viewSlot -Properties $slotProps }
        if ($viewProps.Count) { Set-UiProperties -Control $webView  -Properties $viewProps }
    }
    
    # Nothing here raises the window's MinHeight. That was the old airspace guard and it never held: WM_GETMINMAXINFO snapshots the minimum when the window is created, so a MinHeight set later leaves the frame free to drag smaller while WPF carries on laying out at the taller figure, with the bottom of the window off the screen for good.
    # The trim below covers the same ground without asking the window for anything. Give the view less room and it takes less.
    $webView.add_Loaded({
        param($sender, $eventArgs)
        $wv = $sender

        $window = [System.Windows.Window]::GetWindow($wv)
        if ($null -eq $window) { return }

        # Recaptured as locals. A nested GetNewClosure only reaches the scope it sits in, never what the closure around it captured.
        $slot     = $viewSlot
        $slotTall = [double]$slotHeight

        # Loaded fires again every time a tab shows the view, so the whole setup is built once and parked on the view itself. Rebuilding it per Loaded hangs another ScrollChanged handler off every ancestor each time.
        if ($wv.Resources.Contains('__PsUiWebViewClip')) {
            $clip = $wv.Resources['__PsUiWebViewClip']
            [void]$wv.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::Loaded,
                [Action]{ & $clip.Hook }.GetNewClosure())
            return
        }

        $clip = @{
            Scrollers  = [System.Collections.Generic.List[object]]::new()
            Handler    = $null
            Hook       = $null
            VisHandler = $null
        }
        $wv.Resources['__PsUiWebViewClip'] = $clip
        $clipScrollers = $clip.Scrollers

        # Trim the view to the slice of its slot that is on screen. The slot is measured, never the view: the view moves every time this runs, so its own position is no reference at all.
        # Runs on every scroll event. Each run resizes the browser and the browser lays its page out again, which is the judder on a fast scroll.
        # A settle timer drops that to one resize per gesture, at the cost of hiding the view until the gesture ends. The blink is worse than the judder.
        $updateClipVisibility = {
            $sliceTop    = 0.0
            $sliceBottom = $slotTall

            # Off tree there is no shared root, and TranslatePoint quietly answers 0 rather than throwing. Believing it reads as fully on screen, which leaves the wrong geometry to composite for a frame when the tab comes back.
            $onScreen = $slot.IsVisible

            if ($onScreen) {
                foreach ($clipper in $clipScrollers) {
                    if (!$clipper.IsVisible) { continue }
                    $slotTop = $slot.TranslatePoint([System.Windows.Point]::new(0, 0), $clipper).Y

                    $cutTop    = -$slotTop
                    $cutBottom = $clipper.ViewportHeight - $slotTop
                    if ($cutTop -gt $sliceTop)       { $sliceTop    = $cutTop }
                    if ($cutBottom -lt $sliceBottom) { $sliceBottom = $cutBottom }
                }
            }

            # An HwndHost draws its child window wherever it likes, so a slot scrolled right off has to lose its height, not merely be trimmed.
            # Height is what does the hiding here, never Visibility. Zero height takes the hosted window to zero on the same layout pass, Visibility waits a frame, and leaving Visibility alone means a script can hide the browser and have it stay hidden.
            $sliceHeight = $sliceBottom - $sliceTop
            if (!$onScreen -or $sliceHeight -lt 1) {
                $sliceTop    = 0.0
                $sliceHeight = 0.0
            }

            # Redundant assignments each cost a layout pass and a browser relayout.
            if ([double]::IsNaN($wv.Height) -or [Math]::Abs($wv.Height - $sliceHeight) -gt 0.5) { $wv.Height = $sliceHeight }
            if ([Math]::Abs($wv.Margin.Top - $sliceTop) -gt 0.5) { $wv.Margin = [System.Windows.Thickness]::new(0, $sliceTop, 0, 0) }
        }.GetNewClosure()

        # ScrollChanged also fires on viewport and extent changes, which is how a resize or a maximize gets here.
        $clip.Handler = [System.Windows.Controls.ScrollChangedEventHandler]{
            param($scrollSender, $scrollArgs)
            & $updateClipVisibility
        }.GetNewClosure()

        # The slot coming back into view has to re-trim, and Loaded is not guaranteed to fire for it.
        $clip.VisHandler = {
            param($visSender, $visArgs)
            & $updateClipVisibility
        }.GetNewClosure()
        $slot.add_IsVisibleChanged($clip.VisHandler)

        # Subscribe to any scrolling ancestor not already covered, then trim.
        # The logical parent, falling back to the visual one: on the first Loaded of a tab that did not start selected, the visual tree above the slot is not built yet and a visual walk reaches no ScrollViewer at all. The logical tree is there from the moment the content block runs, and a ScrollViewer is the logical parent of its own Content.
        # Rerun on every Loaded, because a tab realised later brings ancestors the first pass could not see.
        $clip.Hook = {
            $walker = $slot
            while ($walker) {
                if ($walker -is [System.Windows.Controls.ScrollViewer] -and !$clipScrollers.Contains($walker)) {
                    $walker.add_ScrollChanged($clip.Handler)
                    [void]$clipScrollers.Add($walker)
                }
                if ($walker -is [System.Windows.Window]) { break }

                $next = [System.Windows.LogicalTreeHelper]::GetParent($walker)
                if ($null -eq $next -and $walker -is [System.Windows.Media.Visual]) {
                    $next = [System.Windows.Media.VisualTreeHelper]::GetParent($walker)
                }
                $walker = $next
            }

            & $updateClipVisibility
        }.GetNewClosure()

        # Deferred one pass. The slot has no arranged position at Loaded, so the first trim has to wait for layout.
        [void]$wv.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Loaded,
            [Action]{ & $clip.Hook }.GetNewClosure())

        $window.add_Closed({
            try { $slot.remove_IsVisibleChanged($clip.VisHandler) }
            catch { Write-Debug "WebView2 visibility detach failed: $_" }
            foreach ($clipper in $clipScrollers) {
                try { $clipper.remove_ScrollChanged($clip.Handler) }
                catch { Write-Debug "WebView2 scroll detach failed: $_" }
            }
            try { $wv.Dispose() }
            catch { Write-Debug "WebView2 dispose failed: $_" }
        }.GetNewClosure())
    }.GetNewClosure())

    if ($Variable) {
        $session.AddControlSafe($Variable, $webView)
    }

    # The slot goes in the tree, the view goes in the slot. -Variable still registers the view itself, so every helper keeps addressing the browser.
    [void]$session.CurrentParent.Children.Add($viewSlot)

    return $webView
}
