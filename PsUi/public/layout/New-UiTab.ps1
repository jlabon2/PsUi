function New-UiTab {
    <#
    .SYNOPSIS
        Creates a tab with an optional header icon. Content scrolls if it overflows.
    .DESCRIPTION
        Tabs declared at the same level share one TabControl, so a window becomes tabbed just by
        listing New-UiTab blocks in its Content. -EnabledWhen gates a tab until another control
        or captured variable turns truthy (locking later tabs until a connection exists, say).
    .PARAMETER Header
        The text label displayed on the tab header.
    .PARAMETER Content
        ScriptBlock containing the tab's child controls.
    .PARAMETER EnabledWhen
        Control name, session variable name, or scriptblock. Truthy enables the tab, falsy
        disables it. Control references ('showAdvanced') and -Capture variables
        ('VCSAConnection') both work. A scriptblock re-evaluates whenever the controls it
        names change: { $serverName -and $environment } needs both. A scriptblock reads
        controls only, never -Capture variables.
    .PARAMETER Icon
        Optional icon name shown on the tab header. Use Show-UiGlyphBrowser to browse names.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
        Allows setting any valid WPF property not explicitly exposed as a parameter.
        Bad values warn and get skipped. A property name that does not exist on the control is
        skipped silently (-Verbose shows it). Nothing stops execution.
        Supports attached properties using dot notation (e.g., "Grid.Row").
    .EXAMPLE
        New-UiTab -Header "Settings" -EnabledWhen 'isConnected' -Content {
            New-UiInput -Label "Server" -Variable "server"
        }

        Creates a tab that is disabled until the 'isConnected' variable is truthy.
    .EXAMPLE
        # Tabs listed together share one TabControl. -Icon puts a glyph on the header
        New-UiTab -Header 'General' -Icon 'Settings' -Content {
            New-UiLabel -Text 'General settings'
        }
        New-UiTab -Header 'History' -Icon 'History' -Content {
            New-UiLabel -Text 'Run history'
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Header,

        [Parameter(Mandatory)]
        [scriptblock]$Content,

        [Parameter()]
        [object]$EnabledWhen,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    DynamicParam {
        Get-IconDynamicParameter -ParameterName 'Icon'
    }

    begin {
        $Icon = $PSBoundParameters['Icon']
    }

    process {

    $session = Assert-UiSession -CallerName 'New-UiTab'
    $parent  = $session.CurrentParent
    Write-Debug "Header: '$Header', Parent: $($parent.GetType().Name)"

    $targetTabControl = $null
    if ($parent -is [System.Windows.Controls.TabControl]) {
        $targetTabControl = $parent
    }
    elseif ($parent -is [System.Windows.Controls.Panel]) {
        foreach ($child in $parent.Children) {
            if ($child -is [System.Windows.Controls.TabControl]) {
                $targetTabControl = $child
                break
            }
        }
    }
    if (!$targetTabControl) {
        $colors = Get-ThemeColors
        $targetTabControl = [System.Windows.Controls.TabControl]@{
            Background      = [System.Windows.Media.Brushes]::Transparent
            BorderBrush     = ConvertTo-UiBrush $colors.Border
            BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
            Padding         = [System.Windows.Thickness]::new(0)
            Margin          = [System.Windows.Thickness]::new(0, 0, 0, 10)
            TabStripPlacement = 'Top'
        }

        # Use WrapPanel instead of TabPanel to fix multi-row selection behavior
        Set-TabControlStyle -TabControl $targetTabControl

        # Apply center alignment to tab headers if requested
        if ($session.TabAlignment -eq 'Center') {
            # Need to modify the WrapPanel (which holds the tab headers) to center them
            $targetTabControl.Add_Loaded({
                param($sender, $eventArgs)

                # Find the WrapPanel (HeaderPanel) in the visual tree
                $headerPanel = $null
                $queue = [System.Collections.Generic.Queue[System.Windows.Media.Visual]]::new()
                $queue.Enqueue($sender)

                while ($queue.Count -gt 0) {
                    $current = $queue.Dequeue()

                    # Look for the WrapPanel with IsItemsHost, which the custom template puts there
                    if ($current -is [System.Windows.Controls.WrapPanel]) {
                        $headerPanel = $current
                        break
                    }
                    # The default template has a TabPanel there instead
                    if ($current -is [System.Windows.Controls.Primitives.TabPanel]) {
                        $headerPanel = $current
                        break
                    }

                    $childCount = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($current)
                    for ($i = 0; $i -lt $childCount; $i++) {
                        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($current, $i)
                        $queue.Enqueue($child)
                    }
                }

                # Center the header panel if found
                if ($headerPanel) {
                    $headerPanel.HorizontalAlignment = 'Center'
                }
            })
        }

        Set-ResponsiveConstraints -Control $targetTabControl -FullWidth
        Add-UiControlToParent -Control $targetTabControl -Parent $parent
    }
    $tabItem = [System.Windows.Controls.TabItem]@{ Header = $Header }

    # HeaderTemplate, since a theme switch pins ControlForegroundBrush on any TextBlock without a TemplatedParent and the tab loses its selected colors
    $iconText = if ($Icon) { [PsUi.ModuleContext]::GetIcon($Icon) } else { $null }
    if ($iconText) {
        $textBlockType = [System.Windows.Controls.TextBlock]
        $centered      = [System.Windows.VerticalAlignment]::Center

        $iconFactory = [System.Windows.FrameworkElementFactory]::new($textBlockType)
        $iconFactory.SetValue($textBlockType::TextProperty, $iconText)
        $iconFactory.SetValue($textBlockType::FontFamilyProperty, [PsUi.ModuleContext]::ActiveIconFontFamily)
        $iconFactory.SetValue($textBlockType::FontSizeProperty, [double]12)
        $iconFactory.SetValue($textBlockType::VerticalAlignmentProperty, $centered)
        $iconFactory.SetValue($textBlockType::MarginProperty, [System.Windows.Thickness]::new(0, 0, 6, 0))

        $textFactory = [System.Windows.FrameworkElementFactory]::new($textBlockType)
        $textFactory.SetBinding($textBlockType::TextProperty, [System.Windows.Data.Binding]::new())
        $textFactory.SetValue($textBlockType::VerticalAlignmentProperty, $centered)

        $panelFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.StackPanel])
        $panelFactory.SetValue([System.Windows.Controls.StackPanel]::OrientationProperty, [System.Windows.Controls.Orientation]::Horizontal)
        $panelFactory.AppendChild($iconFactory)
        $panelFactory.AppendChild($textFactory)

        $headerTemplate            = [System.Windows.DataTemplate]::new()
        $headerTemplate.VisualTree = $panelFactory
        $tabItem.HeaderTemplate    = $headerTemplate
    }
    Set-TabItemStyle -TabItem $tabItem

    # Respect LayoutMode from session
    $layoutMode = if ($session.LayoutMode) { $session.LayoutMode } else { 'Responsive' }

    if ($layoutMode -eq 'Responsive') {
        # WrapPanel enables responsive horizontal wrapping based on available width
        $contentPanel = [System.Windows.Controls.WrapPanel]@{
            HorizontalAlignment = 'Stretch'
            Margin              = [System.Windows.Thickness]::new(10)
        }
    }
    else {
        # Use StackPanel for stack layout
        $contentPanel = [System.Windows.Controls.StackPanel]@{
            Orientation         = 'Vertical'
            HorizontalAlignment = 'Stretch'
            Margin              = [System.Windows.Thickness]::new(10)
        }
    }

    # Wrap tab content in ScrollViewer so overflow is scrollable.
    # In AutoSize mode the ScrollViewer reports its full content height (window grows), but if MaxHeight caps the window, the ScrollViewer constrains and scrolls.
    $tabScrollViewer = [System.Windows.Controls.ScrollViewer]@{
        VerticalScrollBarVisibility   = 'Auto'
        HorizontalScrollBarVisibility = 'Disabled'
        Focusable                     = $false
    }
    $tabScrollViewer.Content = $contentPanel

    # Once this one is at its end the wheel goes on to the outer ScrollViewer.
    $tabScrollViewer.Add_PreviewMouseWheel({
        param($sender, $eventArgs)
        trap { Write-Debug "Tab wheel routing: $_"; continue }

        $hit = $eventArgs.OriginalSource -as [System.Windows.DependencyObject]

        # A dropdown list or the column picker has in its own popup, but the preview wheel still comes through
        if ($hit -and ![object]::ReferenceEquals(
                [System.Windows.PresentationSource]::FromDependencyObject($hit),
                [System.Windows.PresentationSource]::FromDependencyObject($sender))) {
            return
        }

        # Set-UiWheelRouting leaves __WheelCapture on a control that keeps the wheel.
        while ($hit -and ![object]::ReferenceEquals($hit, $sender)) {
            if ($hit -is [System.Windows.FrameworkElement] -and $hit.Resources.Contains('__WheelCapture')) { return }
            # OriginalSource can be a ContentElement (WPF Run or a Hyperlink), VisualTreeHelper.GetParent throws on those, so hop to the tree until a Visual shows up
            $hit = if ($hit -is [System.Windows.Media.Visual] -or $hit -is [System.Windows.Media.Media3D.Visual3D]) {
                [System.Windows.Media.VisualTreeHelper]::GetParent($hit)
            }
            else { [System.Windows.LogicalTreeHelper]::GetParent($hit) }
        }

        $atTop    = ($eventArgs.Delta -gt 0) -and ($sender.VerticalOffset -eq 0)
        $atBottom = ($eventArgs.Delta -lt 0) -and ($sender.VerticalOffset -ge $sender.ScrollableHeight)
        $noScroll = $sender.ScrollableHeight -eq 0

        if ($atTop -or $atBottom -or $noScroll) {
            $eventArgs.Handled = $true
            $newArgs = [System.Windows.Input.MouseWheelEventArgs]::new(
                $eventArgs.MouseDevice, $eventArgs.Timestamp, $eventArgs.Delta)
            $newArgs.RoutedEvent = [System.Windows.UIElement]::MouseWheelEvent
            $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($sender)
            if ($parent) { $parent.RaiseEvent($newArgs) }
        }
    })

    $tabItem.Content = $tabScrollViewer
    $oldParent = $session.CurrentParent
    $session.CurrentParent = $contentPanel
    $script:TabOrExpanderDepth = [int]$script:TabOrExpanderDepth + 1
    Write-Debug "Entering content block"

    # Restores stay out of a finally for 5.1, and the one pass loop soaks up a break or continue from -Content
    try {
        do { Invoke-UiContent -Content $Content -CallerName 'New-UiTab' -ErrorAction Stop } while ($false)
    }
    catch {
        # Restore parent before re-throwing
        $session.CurrentParent = $oldParent
        $script:TabOrExpanderDepth--
        throw
    }

    # Restore parent after successful content execution
    $session.CurrentParent = $oldParent
    $script:TabOrExpanderDepth--
    Write-Debug "Content block complete"

    # Tab content only sits in rows under a Responsive layout, which New-UiWindow has to set (but New-UiChildWindow gets by default)
    Set-UiRowAlignment -Panel $contentPanel

    # Apply custom WPF properties if specified
    if ($WPFProperties) { Set-UiProperties -Control $tabItem -Properties $WPFProperties }

    if ($EnabledWhen) { Register-UiCondition -TargetControl $tabItem -Condition $EnabledWhen }

    [void]$targetTabControl.Items.Add($tabItem)
    Write-Debug "Tab added to TabControl"
    }
}