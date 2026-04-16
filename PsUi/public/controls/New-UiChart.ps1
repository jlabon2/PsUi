function New-UiChart {
    <#
    .SYNOPSIS
        Creates a chart visualization that dynamically fills available space.
    .DESCRIPTION
        Renders bar, line, or pie charts using native WPF canvas drawing.
        By default, charts stretch to fill the width of their parent container
        and resize dynamically when the window is resized. When placed in a
        constrained parent (e.g. a Grid cell with star sizing), the chart
        scales to fit both width and height proportionally.

        Charts registered with -Variable can be updated from button actions
        using Update-UiChart, or by assigning new data to the variable directly
        (the hydration engine redraws automatically on dehydration).

        Omit -Data to create an empty chart with a placeholder, ready to be
        filled by a button action later.

        Specify -Width and -Height to opt into fixed display size instead.
        Colors are derived from the active theme's accent and semantic colors.
    .PARAMETER Type
        Chart type: Bar, Line, or Pie.
    .PARAMETER Data
        Chart data. Omit for an empty placeholder chart. Supported formats:
        - Ordered hashtable: [ordered]@{ "Label" = Value; ... }
        - Array of hashtables: @(@{Label="x"; Value=1}, ...)
        - Pipeline objects with configurable property names
    .PARAMETER LabelProperty
        Property name to use as labels when Data contains objects. Default "Label" or "Name".
    .PARAMETER ValueProperty
        Property name to use as values when Data contains objects. Default "Value" or "Count".
    .PARAMETER Title
        Optional chart title displayed above the chart.
    .PARAMETER XAxisLabel
        Label for the X-axis (bar and line charts only).
    .PARAMETER YAxisLabel
        Label for the Y-axis (bar and line charts only).
    .PARAMETER Width
        Fixed display width in pixels. When set, disables auto-stretch.
    .PARAMETER Height
        Fixed display height in pixels. When set, disables auto-stretch.
    .PARAMETER ShowLegend
        Show legend for pie charts. Default true for pie, ignored for others.
    .PARAMETER ShowValues
        Display values on bars or pie slices.
    .PARAMETER Variable
        Variable name to register the chart for later access.
    .EXAMPLE
        # Auto-sized chart - stretches to fill available width
        New-UiChart -Type Bar -Data ([ordered]@{ "C:" = 120; "D:" = 450; "E:" = 80 }) -Title "Disk Space"
    .EXAMPLE
        # Fixed size - explicit dimensions
        New-UiChart -Type Pie -Data ([ordered]@{ "A" = 60; "B" = 40 }) -Width 300 -Height 250
    .EXAMPLE
        # Pipeline data with custom properties
        Get-Process | Group-Object Company | Select-Object -First 5 |
            New-UiChart -Type Pie -LabelProperty Name -ValueProperty Count
    .EXAMPLE
        # Empty chart updated by a button action
        New-UiChart -Type Bar -Variable 'diskChart' -Title 'Disk Usage'
        New-UiButton -Text 'Scan' -Action {
            $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
                Select-Object @{N='Label';E={$_.DeviceID}}, @{N='Value';E={[math]::Round($_.FreeSpace/1GB)}}
            Update-UiChart -Variable 'diskChart' -Data $disks
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Bar', 'Line', 'Pie')]
        [string]$Type,

        [Parameter(ValueFromPipeline)]
        $Data,

        [string]$LabelProperty,

        [string]$ValueProperty,

        [string]$Title,

        [string]$XAxisLabel,

        [string]$YAxisLabel,

        [int]$Width,

        [int]$Height,

        [switch]$ShowLegend,

        [switch]$ShowValues,

        [string]$Variable
    )

    begin {
        $collectedData = [System.Collections.Generic.List[object]]::new()
    }

    process {
        if ($null -eq $Data) { return }

        # Collect pipeline input
        if ($Data -is [System.Collections.IDictionary]) {
            foreach ($key in $Data.Keys) {
                $collectedData.Add(@{ Label = $key; Value = $Data[$key] })
            }
        }
        elseif ($Data -is [array]) {
            foreach ($item in $Data) { $collectedData.Add($item) }
        }
        else {
            $collectedData.Add($Data)
        }
    }

    end {
        $session = Get-UiSession
        $parent  = $session.CurrentParent

        # Fixed mode: user explicitly set dimensions. Auto mode: stretch to fill parent.
        $fixedSize = $PSBoundParameters.ContainsKey('Width') -or $PSBoundParameters.ContainsKey('Height')

        # Detect whether we're inside a Grid with star rows (e.g., FillParent dashboard).
        # Star grids constrain cell height, so a squarer canvas fills cells better.
        # Standalone charts use a wider canvas to prevent excessive vertical growth
        # when the Viewbox scales uniformly to fill parent width.
        $inStarGrid = $false
        if (!$fixedSize -and $parent -is [System.Windows.Controls.Grid]) {
            foreach ($rowDef in $parent.RowDefinitions) {
                if ($rowDef.Height.IsStar) { $inStarGrid = $true; break }
            }
        }

        # Canvas internal resolution (Viewbox scales this to the display size).
        # Wider canvases = shorter charts at full width, better for scrollable content.
        # Squarer canvases = fill dashboard cells more evenly.
        if ($PSBoundParameters.ContainsKey('Width')) {
            $canvasWidth = $Width
        }
        elseif ($inStarGrid) {
            $canvasWidth = 600
        }
        else {
            $canvasWidth = if ($Type -eq 'Pie') { 700 } else { 900 }
        }

        if ($PSBoundParameters.ContainsKey('Height')) {
            $canvasHeight = $Height
        }
        elseif ($inStarGrid) {
            $canvasHeight = 400
        }
        else {
            $canvasHeight = if ($Type -eq 'Pie') { 420 } else { 360 }
        }

        # When only one dimension given, derive the other from canvas aspect ratio
        if ($PSBoundParameters.ContainsKey('Width') -and !$PSBoundParameters.ContainsKey('Height')) {
            $canvasHeight = [int]($Width * ($canvasHeight / $canvasWidth))
        }
        if ($PSBoundParameters.ContainsKey('Height') -and !$PSBoundParameters.ContainsKey('Width')) {
            $canvasWidth = [int]($Height * ($canvasWidth / $canvasHeight))
        }

        # Determine legend visibility (Pie charts show legend by default)
        $showLegend = $Type -eq 'Pie' -and ($ShowLegend -or !$PSBoundParameters.ContainsKey('ShowLegend'))

        # DockPanel passes finite height to the Viewbox when available from the parent.
        # StackPanel throws away height constraints - DockPanel preserves them.
        # Title docks Top, legend docks Bottom, Viewbox fills remaining space.
        # Dashboard grids (star rows) constrain cell height, so Stretch fills cells.
        # Everything else uses Top to prevent infinite vertical expansion.
        $vertAlign = if ($inStarGrid) { 'Stretch' } else { 'Top' }

        $container = [System.Windows.Controls.DockPanel]@{
            LastChildFill       = $true
            HorizontalAlignment = 'Stretch'
            VerticalAlignment   = $vertAlign
            Margin              = [System.Windows.Thickness]::new(8)
        }

        # Store chart config so Invoke-ChartRedraw knows how to re-render
        $container.Tag = @{
            ControlType   = 'Chart'
            ChartType     = $Type
            ShowValues    = $ShowValues.IsPresent
            ShowLegend    = $showLegend
            XAxisLabel    = $XAxisLabel
            YAxisLabel    = $YAxisLabel
            LabelProperty = $LabelProperty
            ValueProperty = $ValueProperty
        }

        # Title docked to top
        if ($Title) {
            $titleBlock = [System.Windows.Controls.TextBlock]@{
                Text                = $Title
                FontSize            = 16
                FontWeight          = 'SemiBold'
                HorizontalAlignment = 'Center'
                Margin              = [System.Windows.Thickness]::new(0, 0, 0, 8)
            }
            $titleBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'ControlForegroundBrush')
            [System.Windows.Controls.DockPanel]::SetDock($titleBlock, [System.Windows.Controls.Dock]::Top)
            [void]$container.Children.Add($titleBlock)
        }

        # Canvas draws at internal resolution, Viewbox scales to display size
        $canvas = [System.Windows.Controls.Canvas]@{
            Width      = $canvasWidth
            Height     = $canvasHeight
            Background = [System.Windows.Media.Brushes]::Transparent
        }

        $viewbox = [System.Windows.Controls.Viewbox]@{
            Stretch = 'Uniform'
            Child   = $canvas
        }

        # Viewbox must be last child - DockPanel gives the last child all remaining space
        [void]$container.Children.Add($viewbox)

        # Normalize collected data and render (or show placeholder if empty)
        $chartData = $null
        if ($collectedData.Count -gt 0) {
            $chartData = ConvertTo-ChartData -RawData $collectedData -LabelProperty $LabelProperty -ValueProperty $ValueProperty
        }

        # Invoke-ChartRedraw handles both data rendering and empty placeholder
        Invoke-ChartRedraw -Container $container -NewData $chartData

        # Register hydration callback - dehydration triggers this when $chartVar
        # is reassigned in a button action. Reads data from DataProperty.
        $containerRef = $container
        $redrawCallback = [Action]{
            $storedData = [PsUi.UiHydration]::GetData($containerRef)
            Invoke-ChartRedraw -Container $containerRef -NewData $storedData
        }.GetNewClosure()
        [PsUi.UiHydration]::SetOnDataChanged($container, $redrawCallback)

        # Register with session for variable access and hydration
        if ($Variable) { $session.AddControlSafe($Variable, $container) }

        # Add to current parent
        if ($parent -is [System.Windows.Controls.Panel]) {
            [void]$parent.Children.Add($container)
        }
        elseif ($parent -is [System.Windows.Controls.ItemsControl]) {
            [void]$parent.Items.Add($container)
        }
        elseif ($parent -is [System.Windows.Controls.ContentControl] -and $null -eq $parent.Content) {
            $parent.Content = $container
        }

        # WrapPanel parents size children to their content width, so charts need
        # explicit Width to fill the available space and track parent resizes.
        # Other parents (StackPanel vertical, Grid with star columns) constrain
        # width naturally - the Viewbox Uniform stretch fits within those bounds.
        # Note: horizontal StackPanels give children their desired width, so charts
        # in side-by-side layouts should use New-UiGrid -Columns 2 instead.
        if (!$fixedSize -and $parent -is [System.Windows.Controls.WrapPanel]) {
            $chartRef  = $container
            $parentRef = $parent

            $parentRef.Add_SizeChanged({
                param($sender, $sizeArgs)
                $available = $sender.ActualWidth - 20
                if ($available -gt 50) { $chartRef.Width = $available }
            }.GetNewClosure())

            if ($parentRef.ActualWidth -gt 0) {
                $container.Width = $parentRef.ActualWidth - 20
            }
        }

        return $container
    }
}
