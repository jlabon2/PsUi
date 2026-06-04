function New-UiStatusBar {
    <#
    .SYNOPSIS
        Creates a status bar docked to the bottom (or top) of the window.
    .DESCRIPTION
        Themed bar with freeform child controls. Drop New-UiSpacer between
        items to push everything after it to the right side. -AutoProgress
        embeds a progress bar that Write-Progress from button actions drives
        automatically.
    .PARAMETER Content
        Scriptblock defining the bar's child controls. Optional when -DefaultText
        is supplied.
    .PARAMETER Variable
        Session name for the bar. When omitted, a synthetic name is minted and
        the bar stays discoverable via the IsStatusBar tag fallback.
    .PARAMETER Location
        'Bottom' (default) or 'Top'.
    .PARAMETER DefaultText
        Initial status text. Prepends a TextBlock that becomes the canonical
        status label Set-UiStatusBar / Write-Status target.
    .PARAMETER AutoProgress
        Embeds a right-anchored progress bar that updates from Write-Progress
        emitted by button actions.
    .PARAMETER AutoCancel
        Embeds a Cancel button that becomes visible while an async action is
        running. Click calls Stop-UiAsync.
    .PARAMETER Intercept
        Intercepts Write-Warning and Write-Error from button actions, displaying
        them as clickable badge counters in the status bar. Click a badge to see
        a popup with timestamped message details. Badges reset on each new
        action unless -Persist is also specified.
    .PARAMETER CaptureHost
        Requires -Intercept. Also intercepts Write-Host from button actions and
        displays the latest message in the status text label. Only captures from
        -NoOutput buttons (architectural constraint of the queue-based routing).
    .PARAMETER NoOutputOnly
        Requires -Intercept. Only intercepts from buttons that do NOT have an
        output window. Prevents duplicate badge notifications when warnings and
        errors are already visible in Show-UiOutput.
    .PARAMETER Persist
        Requires -Intercept. Keeps badge counters and popup messages across
        button actions instead of resetting on each new click. Useful for
        cumulative tracking across a workflow.
    .PARAMETER MaxMessages
        Requires -Intercept. Maximum number of messages per badge popup before
        oldest entries are dropped. Defaults to 100.
    .PARAMETER Inline
        Force docking to the immediate parent instead of the window outer panel.
        Tab and Expander nesting are already auto-detected; this is the escape
        hatch for everything else.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the bar root.
    .EXAMPLE
        New-UiStatusBar -DefaultText 'Ready'
    .EXAMPLE
        New-UiStatusBar -Content {
            New-UiLabel -Text 'Working...'
            New-UiSpacer
            New-UiButton -Text 'Cancel' -NoOutput -Action { Stop-UiAsync }
        }
    .EXAMPLE
        New-UiStatusBar -DefaultText 'Ready' -AutoProgress -AutoCancel
    .EXAMPLE
        New-UiStatusBar -Intercept -CaptureHost -AutoProgress -DefaultText 'Ready'

        Intercepts warnings/errors as badge counters and routes Write-Host to
        the status text. Click a badge to see accumulated messages.
    #>
    [CmdletBinding()]
    param(
        [scriptblock]$Content,

        [Alias('Name')]
        [string]$Variable,

        [ValidateSet('Bottom', 'Top')]
        [string]$Location = 'Bottom',

        [string]$DefaultText,

        [switch]$AutoProgress,

        [switch]$AutoCancel,

        [switch]$Intercept,

        [switch]$CaptureHost,

        [switch]$NoOutputOnly,

        [switch]$Persist,

        [ValidateRange(1, 10000)]
        [int]$MaxMessages = 100,

        [switch]$Inline,

        [hashtable]$WPFProperties
    )

    if (!$Content -and !$PSBoundParameters.ContainsKey('DefaultText')) {
        throw "New-UiStatusBar: supply -Content, -DefaultText, or both."
    }

    # Warn on dependent parameters used without -Intercept
    if (!$Intercept) {
        if ($CaptureHost)  { Write-Warning 'New-UiStatusBar: -CaptureHost requires -Intercept and will be ignored.' }
        if ($NoOutputOnly) { Write-Warning 'New-UiStatusBar: -NoOutputOnly requires -Intercept and will be ignored.' }
        if ($Persist)      { Write-Warning 'New-UiStatusBar: -Persist requires -Intercept and will be ignored.' }
        if ($PSBoundParameters.ContainsKey('MaxMessages')) { Write-Warning 'New-UiStatusBar: -MaxMessages requires -Intercept and will be ignored.' }
    }

    $session = Assert-UiSession -CallerName 'New-UiStatusBar'

    # Border root, not the actual StatusBar control - its layout quirks ended up not being worth the fight
    $bar = [System.Windows.Controls.Border]::new()
    Set-StatusBarStyle -StatusBar $bar

    if ($WPFProperties) {
        if ($WPFProperties.ContainsKey('Tag')) {
            Write-Warning "New-UiStatusBar: -WPFProperties Tag is reserved and will be ignored."
            $WPFProperties.Remove('Tag')
        }
        if ($WPFProperties.Count) { Set-UiProperties -Control $bar -Properties $WPFProperties }
    }

    # Inner DockPanel: LastChildFill stretches the spacer to fill the gap
    $innerPanel               = [System.Windows.Controls.DockPanel]::new()
    $innerPanel.LastChildFill = $true
    $bar.Child                = $innerPanel

    # Yeah this hashtable grows into a bit of a beast by the time Intercept
    # is done with it (~20 keys). Would benefit from a proper class at some
    # point but it works fine as a bag of state for now.
    $meta = @{
        IsStatusBar = $true
        InnerPanel  = $innerPanel
    }

    # Severity-reset timer lives on the UI thread so its Tick outlives background-action teardown.
    # Set-UiStatusBar reuses it via Stop/Start rather than creating new timers.
    $severityTimer     = [System.Windows.Threading.DispatcherTimer]::new()
    $severityTimer.Tag = $bar
    $severityTimer.Add_Tick({
        param($sender, $eventArgs)
        $sender.Stop()
        $targetBar = $sender.Tag
        if (!$targetBar) { return }

        Set-StatusBarSeverityVisual -Bar $targetBar -Severity Info

        $barMeta          = if ($targetBar.Tag -is [hashtable]) { $targetBar.Tag } else { @{} }
        $barMeta.Severity = 'Info'

        if ($barMeta.ProgressBar) {
            $barMeta.ProgressBar.Visibility     = [System.Windows.Visibility]::Hidden
            $barMeta.ProgressBar.Value          = 0
            $barMeta.ProgressBar.IsIndeterminate = $false

            if ($barMeta.ProgressBar.Tag -is [hashtable]) {
                $barMeta.ProgressBar.Tag.Severity = 'Info'
                $barMeta.ProgressBar.Tag.BrushTag = 'AccentBrush'
                Set-ProgressBarStyle -ProgressBar $barMeta.ProgressBar
            }
        }

    })
    $meta.SeverityTimer = $severityTimer

    # Severity indicator glyph (checkmark, warning, error) shown during active tints
    $severityIcon = [System.Windows.Controls.TextBlock]@{
        FontFamily        = [PsUi.ModuleContext]::ActiveIconFontFamily
        FontSize          = 12
        VerticalAlignment = 'Center'
        Visibility        = 'Collapsed'
        Margin            = [System.Windows.Thickness]::new(0, 0, 4, 0)
    }
    [void]$innerPanel.Children.Add($severityIcon)
    $meta.SeverityIcon = $severityIcon

    # -DefaultText prepends the canonical status label so user -Content flows in after it
    if ($PSBoundParameters.ContainsKey('DefaultText')) {
        $defaultLabel = [System.Windows.Controls.TextBlock]@{
            Text              = $DefaultText
            VerticalAlignment = 'Center'
        }
        [void]$innerPanel.Children.Add($defaultLabel)
    }

    # Swap CurrentParent so -Content children populate the inner panel
    if ($Content) {
        $oldParent             = $session.CurrentParent
        $session.CurrentParent = $innerPanel

        try { Invoke-UiContent -Content $Content -CallerName 'New-UiStatusBar' }
        catch {
            $session.CurrentParent = $oldParent
            throw
        }

        $session.CurrentParent = $oldParent
    }

    # Locate the first spacer to split left vs right docked content
    $children    = @($innerPanel.Children)
    $spacerIndex = -1

    for ($idx = 0; $idx -lt $children.Count; $idx++) {
        $tag = if ($children[$idx] -is [System.Windows.FrameworkElement]) { $children[$idx].Tag } else { $null }
        if ($tag -is [hashtable] -and $tag.IsSpacer) {
            $spacerIndex = $idx
            break
        }
    }

    if ($spacerIndex -ge 0) {
        # Reorder: left items, right items (reversed), spacer last
        $innerPanel.Children.Clear()

        for ($idx = 0; $idx -lt $spacerIndex; $idx++) {
            [System.Windows.Controls.DockPanel]::SetDock($children[$idx], 'Left')
            [void]$innerPanel.Children.Add($children[$idx])
        }

        # DockPanel docks Right-to-left in z-order, so reverse to match user-written order
        for ($idx = $children.Count - 1; $idx -gt $spacerIndex; $idx--) {
            [System.Windows.Controls.DockPanel]::SetDock($children[$idx], 'Right')
            [void]$innerPanel.Children.Add($children[$idx])
        }

        [void]$innerPanel.Children.Add($children[$spacerIndex])
    }
    else {
        foreach ($child in $innerPanel.Children) {
            [System.Windows.Controls.DockPanel]::SetDock($child, 'Left')
        }
    }

    Set-StatusBarChildLayout -Panel $innerPanel

    # Cache the first non-icon TextBlock as the canonical status label. Glyphs use an icon
    # font (MDL2 or Fluent) and are also TextBlocks - writing status text into one produces
    # missing-glyph boxes. Test-IconFont covers bare names and the fallback-chain form.
    $firstText = $null
    foreach ($child in $innerPanel.Children) {
        if ($child -is [System.Windows.Controls.TextBlock]) {
            $isIconFont = $child.FontFamily -and (Test-IconFont $child.FontFamily)
            if (!$firstText -and !$isIconFont) { $firstText = $child }
            $child.TextTrimming       = 'CharacterEllipsis'
            $child.TextWrapping       = 'NoWrap'
            $child.HorizontalAlignment = 'Left'
            $child.Margin             = [System.Windows.Thickness]::new(4, 0, 4, 0)
        }
    }
    $meta.StatusText = $firstText

    # Wrap user content in a clipping border so overflow truncates instead of bleeding over badges
    $contentPanel               = [System.Windows.Controls.DockPanel]::new()
    $contentPanel.LastChildFill = $true
    $userChildren               = @($innerPanel.Children)
    $innerPanel.Children.Clear()
    foreach ($moved in $userChildren) { [void]$contentPanel.Children.Add($moved) }

    $contentClip = [System.Windows.Controls.Border]@{ ClipToBounds = $true  }
    $contentClip.Child = $contentPanel

    # Severity DFS walks this panel for contrast calculation, not the outer panel with system controls
    $meta.InnerPanel  = $contentPanel
    $meta.ContentClip = $contentClip

    if ($AutoProgress) {
        $autoBar = [System.Windows.Controls.ProgressBar]@{
            Width             = 140
            Height            = 12
            Minimum           = 0
            Maximum           = 100
            Value             = 0
            VerticalAlignment = 'Center'
            Visibility        = 'Hidden'
            Margin            = [System.Windows.Thickness]::new(0, 0, 0, 0)
        }

        # Tag must be a hashtable before styling - Set-UiStatusBar and the timer Tick handler
        # both reach into it to update fill color when severity changes
        $autoBar.Tag = @{ BrushTag = 'AccentBrush'; Severity = 'Info' }

        try { Set-ProgressBarStyle -ProgressBar $autoBar }
        catch { Write-Debug "AutoProgress: Set-ProgressBarStyle failed: $_" }

        # Small label above the progress bar showing Write-Progress text
        $progressLabel = [System.Windows.Controls.TextBlock]@{
            FontSize            = 9
            TextTrimming        = 'CharacterEllipsis'
            VerticalAlignment   = 'Bottom'
            HorizontalAlignment = 'Left'
            Visibility          = 'Collapsed'
            Margin              = [System.Windows.Thickness]::new(0, 0, 0, 1)
        }
        $progressLabel.SetResourceReference(
            [System.Windows.Controls.TextBlock]::ForegroundProperty, 'ControlForegroundBrush')

        # Wrap label + bar in a vertical stack so they dock as one unit
        $progressStack = [System.Windows.Controls.StackPanel]@{
            VerticalAlignment = 'Center'
            Margin            = [System.Windows.Thickness]::new(8, 0, 4, 0)
        }
        [void]$progressStack.Children.Add($progressLabel)
        [void]$progressStack.Children.Add($autoBar)

        [System.Windows.Controls.DockPanel]::SetDock($progressStack, 'Right')
        $innerPanel.Children.Insert(0, $progressStack)

        $meta.AutoProgress  = $true
        $meta.ProgressBar   = $autoBar
        $meta.ProgressLabel = $progressLabel
    }

    if ($AutoCancel) {
        $cancelButton = [System.Windows.Controls.Button]@{
            Content           = 'Cancel'
            Padding           = [System.Windows.Thickness]::new(10, 2, 10, 2)
            Margin            = [System.Windows.Thickness]::new(4, 0, 0, 0)
            VerticalAlignment = 'Center'
            Visibility        = [System.Windows.Visibility]::Hidden
        }
        $cancelButton.Add_Click({
            try { Stop-UiAsync } catch { Write-Debug "AutoCancel: Stop-UiAsync threw: $_" }
        })

        try { Set-ButtonStyle -Button $cancelButton }
        catch { Write-Debug "AutoCancel: Set-ButtonStyle failed: $_" }

        # Match the compact sizing that Set-StatusBarChildCompact gives user-placed buttons
        $cancelButton.Height         = 26
        $cancelButton.Padding        = [System.Windows.Thickness]::new(10, 0, 10, 0)
        $cancelButton.Margin         = [System.Windows.Thickness]::new(2, 0, 2, 0)
        $cancelButton.FocusVisualStyle = $null

        [System.Windows.Controls.DockPanel]::SetDock($cancelButton, 'Right')
        $innerPanel.Children.Insert(0, $cancelButton)

        $meta.AutoCancel   = $true
        $meta.CancelButton = $cancelButton
    }

    if ($Intercept) {
        $warnMessages  = [System.Collections.Generic.List[hashtable]]::new()
        $errorMessages = [System.Collections.Generic.List[hashtable]]::new()

        # Warning badge: clickable pill counter with a popup of timestamped messages
        $warnBadge      = New-StatusBarBadge -Severity Warning
        $warnPopupSplat = @{
            Severity        = 'Warning'
            PlacementTarget = $warnBadge.Badge
            BadgeInfo       = $warnBadge
            MessageList     = $warnMessages
            Bar             = $bar
        }
        $warnPopup = New-StatusBarMessagePopup @warnPopupSplat

        # Error badge: same structure, different severity color
        $errBadge      = New-StatusBarBadge -Severity Error
        $errPopupSplat = @{
            Severity        = 'Error'
            PlacementTarget = $errBadge.Badge
            BadgeInfo       = $errBadge
            MessageList     = $errorMessages
            Bar             = $bar
        }
        $errPopup = New-StatusBarMessagePopup @errPopupSplat

        # Wire badge click to toggle popup
        $capturedWarnPopup = $warnPopup.Popup
        $warnBadge.Badge.Add_MouseLeftButtonDown({
            $capturedWarnPopup.IsOpen = !$capturedWarnPopup.IsOpen
        }.GetNewClosure())

        $capturedErrPopup = $errPopup.Popup
        $errBadge.Badge.Add_MouseLeftButtonDown({
            $capturedErrPopup.IsOpen = !$capturedErrPopup.IsOpen
        }.GetNewClosure())

        # Badge is a safe zone for its popup - suppress auto-close while hovering
        $warnBadge.Badge.Add_MouseEnter({ $capturedWarnPopup.StaysOpen = $true }.GetNewClosure())
        $warnBadge.Badge.Add_MouseLeave({ $capturedWarnPopup.StaysOpen = $false }.GetNewClosure())
        $errBadge.Badge.Add_MouseEnter({ $capturedErrPopup.StaysOpen = $true }.GetNewClosure())
        $errBadge.Badge.Add_MouseLeave({ $capturedErrPopup.StaysOpen = $false }.GetNewClosure())

        # Insert badges right-docked, before AutoProgress/AutoCancel (insert at 0)
        [System.Windows.Controls.DockPanel]::SetDock($errBadge.Badge, 'Right')
        $innerPanel.Children.Insert(0, $errBadge.Badge)
        [System.Windows.Controls.DockPanel]::SetDock($warnBadge.Badge, 'Right')
        $innerPanel.Children.Insert(0, $warnBadge.Badge)

        # Build console output badge when CaptureHost is enabled
        if ($CaptureHost) {
            $hostMessages = [System.Collections.Generic.List[hashtable]]::new()

            $hostBadge      = New-StatusBarBadge -Severity Info
            $hostPopupSplat = @{
                Severity        = 'Info'
                PlacementTarget = $hostBadge.Badge
                BadgeInfo       = $hostBadge
                MessageList     = $hostMessages
                Bar             = $bar
            }
            $hostPopup = New-StatusBarMessagePopup @hostPopupSplat

            $capturedHostPopup = $hostPopup.Popup
            $hostBadge.Badge.Add_MouseLeftButtonDown({
                $capturedHostPopup.IsOpen = !$capturedHostPopup.IsOpen
            }.GetNewClosure())
            $hostBadge.Badge.Add_MouseEnter({ $capturedHostPopup.StaysOpen = $true }.GetNewClosure())
            $hostBadge.Badge.Add_MouseLeave({ $capturedHostPopup.StaysOpen = $false }.GetNewClosure())

            # Console badge goes left of the warning badge
            [System.Windows.Controls.DockPanel]::SetDock($hostBadge.Badge, 'Right')
            $innerPanel.Children.Insert(0, $hostBadge.Badge)
        }

        $meta.Intercept       = $true
        $meta.CaptureHost     = $CaptureHost.IsPresent
        $meta.NoOutputOnly    = $NoOutputOnly.IsPresent
        $meta.Persist         = $Persist.IsPresent
        $meta.MaxMessages     = $MaxMessages
        $meta.WarningBadge    = $warnBadge
        $meta.ErrorBadge      = $errBadge
        $meta.WarningPopup    = $warnPopup
        $meta.ErrorPopup      = $errPopup
        $meta.WarningMessages = $warnMessages
        $meta.ErrorMessages   = $errorMessages

        if ($CaptureHost) {
            $meta.HostBadge    = $hostBadge
            $meta.HostPopup    = $hostPopup
            $meta.HostMessages = $hostMessages
        }
    }

    # Content clip fills remaining space after right-docked system controls
    [void]$innerPanel.Children.Add($contentClip)

    $bar.Tag = $meta

    # Identify the window's outer DockPanel so we can dock the bar there when at root
    $window     = $session.Window
    $chromeInfo = $window.Tag
    $outerPanel = $null
    if ($chromeInfo -is [hashtable] -and $chromeInfo.ContainsKey('ContentArea')) {
        $contentArea = $chromeInfo['ContentArea']
        if ($contentArea.Child -is [System.Windows.Controls.DockPanel]) {
            $outerPanel = $contentArea.Child
        }
    }

    # Walk up the parent chain to decide where to dock. Tabs and expanders get a local bar;
    # everything else docks to the window unless -Inline says otherwise.
    $dockToWindow = !$Inline.IsPresent
    if ($dockToWindow) {
        $walker = $session.CurrentParent
        while ($walker) {
            if ($walker -is [System.Windows.Controls.TabItem] -or $walker -is [System.Windows.Controls.Expander]) {
                $dockToWindow = $false
                break
            }
            if ($walker -eq $outerPanel) { break }
            $walker = $walker.Parent
        }
    }

    $docked = $false
    if ($dockToWindow -and $outerPanel) {
        # Insert at 0 so the content clip remains the last child (LastChildFill gives it the gap)
        [System.Windows.Controls.DockPanel]::SetDock($bar, $Location)
        [void]$outerPanel.Children.Insert(0, $bar)
        $docked            = $true
        $meta.IsWindowBar  = $true
    }

    # Fallback: dock to the immediate parent, adapting to whatever container type it is
    if (!$docked) {
        $parent = $session.CurrentParent
        if ($parent -is [System.Windows.Controls.DockPanel]) {
            [System.Windows.Controls.DockPanel]::SetDock($bar, $Location)
            [void]$parent.Children.Add($bar)
        }
        elseif ($parent -is [System.Windows.Controls.Panel]) {
            if ($Location -eq 'Top') { [void]$parent.Children.Insert(0, $bar) }
            else                     { [void]$parent.Children.Add($bar) }
        }
        elseif ($parent -is [System.Windows.Controls.ItemsControl])   { [void]$parent.Items.Add($bar) }
        elseif ($parent -is [System.Windows.Controls.ContentControl]) { $parent.Content = $bar }
    }

    # Anonymous bars still need a name for Register-UiControlComplete; the IsStatusBar
    # tag keeps them findable via Resolve-UiStatusBar's fallback
    $varName = if ($Variable) {
        $Variable
    }
    else {
        '_anonStatusBar_' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    }
    Register-UiControlComplete -Name $varName -Control $bar -RegisterTheme
}
