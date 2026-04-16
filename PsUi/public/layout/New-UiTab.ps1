function New-UiTab {
    <#
    .SYNOPSIS
        Creates a tab item within a TabControl, enabling responsive child layouts.
    .PARAMETER Header
        The text label displayed on the tab header.
    .PARAMETER Content
        ScriptBlock containing the tab's child controls.
    .PARAMETER EnabledWhen
        Control name or session variable name that determines when this tab is enabled.
        When the referenced value is truthy, the tab is enabled; when falsy, disabled.
        Supports both control references (e.g., 'showAdvanced') and -Capture variables
        (e.g., 'VCSAConnection') for gated workflows.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
        Allows setting any valid WPF property not explicitly exposed as a parameter.
        Invalid properties will generate warnings but not stop execution.
        Supports attached properties using dot notation (e.g., "Grid.Row").
    .EXAMPLE
        New-UiTab -Header "Settings" -EnabledWhen 'isConnected' -Content {
            New-UiInput -Label "Server" -Variable "server"
        }
        
        Creates a tab that is disabled until the 'isConnected' variable is truthy.
    .EXAMPLE
        New-UiTab -Header "Tab" -Content { } -WPFProperties @{
            ToolTip = "Custom tooltip"
            Cursor = "Hand"
            Opacity = 0.8
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

    # logic to find or create TabControl with null safety
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

                    # Look for WrapPanel with IsItemsHost (our custom template)
                    if ($current -is [System.Windows.Controls.WrapPanel]) {
                        $headerPanel = $current
                        break
                    }
                    # Fallback: also check for TabPanel (default template)
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
        if ($parent -is [System.Windows.Controls.Panel]) { [void]$parent.Children.Add($targetTabControl) }
        elseif ($parent -is [System.Windows.Controls.ItemsControl]) { [void]$parent.Items.Add($targetTabControl) }
        elseif ($parent -is [System.Windows.Controls.ContentControl]) { $parent.Content = $targetTabControl }
    }
    $tabItem = [System.Windows.Controls.TabItem]@{ Header = $Header }
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

    $tabItem.Content = $contentPanel
    $oldParent = $session.CurrentParent
    $session.CurrentParent = $contentPanel
    Write-Debug "Entering content block"

    # Execute content - restore parent outside try/finally for PS 5.1 closure compatibility
    try {
        Invoke-UiContent -Content $Content -CallerName 'New-UiTab' -ErrorAction Stop
    }
    catch {
        # Restore parent before re-throwing
        $session.CurrentParent = $oldParent
        throw
    }
    
    # Restore parent after successful content execution
    $session.CurrentParent = $oldParent
    Write-Debug "Content block complete"

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $tabItem -Properties $WPFProperties
    }

    # Wire up conditional enabling if specified
    if ($EnabledWhen) {
        Register-UiCondition -TargetControl $tabItem -Condition $EnabledWhen
    }

    [void]$targetTabControl.Items.Add($tabItem)
    Write-Debug "Tab added to TabControl"
    }
}