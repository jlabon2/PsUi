function New-UiPanel {
    <#
    .SYNOPSIS
        Creates a panel container for organizing child controls.
    .PARAMETER Content
        ScriptBlock containing child controls to render inside the panel.
    .PARAMETER Header
        Optional header text. Wraps the panel in a themed GroupBox when set.
    .PARAMETER Type
        Container type: Stack (default), Tab, or Wrap.
    .PARAMETER LayoutStyle
        Child layout mode: Stack (default) or Wrap.
    .PARAMETER Orientation
        Stack direction when Type is Stack. Defaults to Vertical.
    .PARAMETER FullWidth
        Forces the panel to take full width in WrapPanel layouts.
    .PARAMETER MaxColumns
        Maximum responsive columns for Wrap layout (1-4). Children resize automatically.
    .PARAMETER HeaderAction
        Optional hashtable defining a custom action button in the panel header.
        Requires -Header parameter to be set.
        Hashtable should contain: Icon (string), Tooltip (string), Action (scriptblock).
    .PARAMETER ShowSourceButton
        When used with -Header, automatically adds a "View Source Code" button that displays
        the Content scriptblock in a PowerShell-styled dialog.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
        Allows setting any valid WPF property not explicitly exposed as a parameter.
        Invalid properties will generate warnings but not stop execution.
        Supports attached properties using dot notation (e.g., "Grid.Row").
    .EXAMPLE
        New-UiPanel -Header "Example Panel" -ShowSourceButton -Content {
            New-UiLabel -Text "This code can be viewed by clicking the button"
        }
    .EXAMPLE
        New-UiPanel -Header "Custom Action" -HeaderAction @{
            Icon = "Info"
            Tooltip = "Show Help"
            Action = { Show-UiMessageDialog -Title "Help" -Message "This is help text" }
        } -Content {
            New-UiLabel -Text "Panel content"
        }
    .EXAMPLE
        New-UiPanel -Content { } -WPFProperties @{
            ToolTip = "Custom tooltip"
            Cursor = "Hand"
            Opacity = 0.8
        }
    .EXAMPLE
        New-UiPanel -Content { } -WPFProperties @{
            "Grid.Row" = 1
            "Grid.Column" = 2
            Tag = "MyTag"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Content,

        [string]$Header,

        [ValidateSet('Stack', 'Tab', 'Wrap')]
        [string]$Type = 'Stack',

        [ValidateSet('Stack', 'Wrap')]
        [string]$LayoutStyle = 'Stack',

        [System.Windows.Controls.Orientation]$Orientation = 'Vertical',

        [switch]$FullWidth,

        [ValidateScript({ $_ -eq 0 -or ($_ -ge 1 -and $_ -le 4) })]
        [int]$MaxColumns = 0,

        [hashtable]$HeaderAction,

        [switch]$ShowSourceButton,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiPanel'
    Write-Debug "Header: '$Header', Type: $Type"
    $parent    = $session.CurrentParent
    $oldParent = $parent

    # Auto-generate HeaderAction for ShowSourceButton
    if ($ShowSourceButton -and $Header) {
        # Preserve indentation by using the ScriptBlock's AST extent
        # This captures the original formatting including indentation
        $sourceCode = $Content.Ast.Extent.Text

        # If AST is not available or doesn't preserve formatting, fall back to ToString()
        if (!$sourceCode) {
            $sourceCode = $Content.ToString()
        }

        # Strip outer braces and normalize indentation
        # Remove leading/trailing whitespace
        $sourceCode = $sourceCode.Trim()

        # If the code starts with { and ends with }, remove them
        if ($sourceCode -match '(?s)^\s*\{(.+)\}\s*$') {
            $sourceCode = $matches[1]
        }

        # Normalize indentation - find minimum indentation and remove it from all lines
        $lines = $sourceCode -split "`r?`n"
        $nonEmptyLines = $lines | Where-Object { $_ -match '\S' }
        if ($nonEmptyLines) {
            $minIndent = ($nonEmptyLines | ForEach-Object {
                if ($_ -match '^(\s*)') {
                    $matches[1].Length
                } else {
                    0
                }
            } | Measure-Object -Minimum).Minimum

            $normalizedLines = $lines | ForEach-Object {
                if ($_ -match '\S' -and $_.Length -ge $minIndent) {
                    $_.Substring($minIndent)
                } else {
                    $_
                }
            }
            $sourceCode = $normalizedLines -join "`n"
        }

        # Final trim to remove leading/trailing blank lines
        $sourceCode = $sourceCode.Trim()

        $HeaderAction = @{
            Icon = 'Code'
            Tooltip = 'View Source Code'
            Action = [scriptblock]::Create(@"
Show-UiMessageDialog -Title 'Source Code' -Message @'
$sourceCode
'@ -PowerShell
"@)
        }
    }

    # Create container based on Type and LayoutStyle
    if ($Type -eq 'Tab') {
        $innerContainer = [System.Windows.Controls.TabControl]@{
            Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
        }
        $fullWidthConstraint = $true
    }
    elseif ($Type -eq 'Wrap' -or $LayoutStyle -eq 'Wrap') {
        # Use WrapPanel for wrapping child controls
        $innerContainer = [System.Windows.Controls.WrapPanel]@{
            Orientation = 'Horizontal'
            HorizontalAlignment = 'Stretch'
        }
        # When MaxColumns is specified, panel should stretch but stay in column layout
        $fullWidthConstraint = $FullWidth

        # If MaxColumns specified, add responsive sizing for child controls inside this panel
        if ($MaxColumns -gt 0) {
            $panelMaxCols = $MaxColumns  # Capture for closure - completely independent from window
            $innerContainer.Add_SizeChanged({
                param($sender, $eventArgs)

                $paddingBuffer = 16
                $availableWidth = $sender.ActualWidth - $paddingBuffer
                if ($availableWidth -le 0) { return }

                # Calculate column width based on this panel's MaxColumns (NOT window's)
                $minColumnWidth = 150  # Minimum width per column in wrap panel
                $possibleCols = [Math]::Max(1, [Math]::Floor($availableWidth / $minColumnWidth))
                $actualCols = [Math]::Min($possibleCols, $panelMaxCols)
                $actualCols = [Math]::Max($actualCols, 1)

                $childWidth = [Math]::Floor(($availableWidth / $actualCols) - 8)

                # Apply width to all children that support it
                foreach ($child in $sender.Children) {
                    if ($child -is [System.Windows.FrameworkElement]) {
                        # Skip items that explicitly want full width (have Tag = 'FullWidth')
                        if ($child.Tag -eq 'FullWidth') { continue }
                        $child.Width = $childWidth
                    }
                }
            }.GetNewClosure())
        }
    }
    else {
        # Default Stack behavior
        $innerContainer = [System.Windows.Controls.StackPanel]@{
            Orientation = $Orientation
        }
        $fullWidthConstraint = $FullWidth
    }

    # Build display control (GroupBox wrapper if Header specified)
    if ($Header) {
        $displayControl = [System.Windows.Controls.GroupBox]@{
            Content = $innerContainer
        }

        # When using Wrap layout, panel should stretch to fill available space
        if ($Type -eq 'Wrap' -or $LayoutStyle -eq 'Wrap') {
            $displayControl.HorizontalAlignment = 'Stretch'
        }

        # Create header with icon button if HeaderAction is provided
        if ($HeaderAction) {
            $headerGrid = [System.Windows.Controls.Grid]::new()
            $col1 = [System.Windows.Controls.ColumnDefinition]::new()
            $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $col2 = [System.Windows.Controls.ColumnDefinition]::new()
            $col2.Width = [System.Windows.GridLength]::Auto
            [void]$headerGrid.ColumnDefinitions.Add($col1)
            [void]$headerGrid.ColumnDefinitions.Add($col2)

            $headerText = [System.Windows.Controls.TextBlock]::new()
            $headerText.Text = $Header
            $headerText.VerticalAlignment = 'Center'
            $headerText.FontWeight = 'SemiBold'
            $headerText.Tag = 'ControlFgBrush'
            [PsUi.ThemeEngine]::RegisterElement($headerText)
            [System.Windows.Controls.Grid]::SetColumn($headerText, 0)
            [void]$headerGrid.Children.Add($headerText)

            $iconButton = [System.Windows.Controls.Button]::new()
            $iconButton.Width = 24
            $iconButton.Height = 24
            $iconButton.Padding = [System.Windows.Thickness]::new(0)
            $iconButton.ToolTip = $HeaderAction.Tooltip
            $iconButton.VerticalAlignment = 'Center'
            $iconButton.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)

            $iconBlock = [System.Windows.Controls.TextBlock]::new()
            $iconBlock.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            $iconBlock.FontSize = 12
            $iconBlock.HorizontalAlignment = 'Center'
            $iconBlock.VerticalAlignment = 'Center'

            # Map icon name to character using ModuleContext if available
            $iconChar = $null
            if ($HeaderAction.Icon) {
                $iconText = [PsUi.ModuleContext]::GetIcon($HeaderAction.Icon)
                if ($iconText) {
                    $iconChar = $iconText
                }
                else {
                    # Fallback mapping (icons should already be in CharList but just in case)
                    $iconChar = switch ($HeaderAction.Icon) {
                        'Code' { [PsUi.ModuleContext]::GetIcon('Code') }
                        'Info' { [PsUi.ModuleContext]::GetIcon('Info') }
                        'Help' { [PsUi.ModuleContext]::GetIcon('Help') }
                        'View' { [PsUi.ModuleContext]::GetIcon('View') }
                        default { [PsUi.ModuleContext]::GetIcon('Info') }
                    }
                }
            }
            else {
                $iconChar = [PsUi.ModuleContext]::GetIcon('Info')
            }

            $iconBlock.Text = $iconChar
            $iconButton.Content = $iconBlock

            # Style and click handler
            Set-ButtonStyle -Button $iconButton -IconOnly
            $actionScript = $HeaderAction.Action
            $iconButton.Add_Click({ & $actionScript }.GetNewClosure())

            [System.Windows.Controls.Grid]::SetColumn($iconButton, 1)
            [void]$headerGrid.Children.Add($iconButton)

            # Use grid as header
            $displayControl.Header = $headerGrid
        }
        else {
            # Simple string header (existing behavior)
            $displayControl.Header = $Header
        }

        Set-GroupBoxStyle -GroupBox $displayControl
    }
    else {
        $displayControl = $innerContainer
    }

    # Apply layout constraints
    Set-FullWidthConstraint -Control $displayControl -Parent $parent -FullWidth:$fullWidthConstraint
    Set-ResponsiveConstraints -Control $displayControl -FullWidth:$fullWidthConstraint

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $displayControl -Properties $WPFProperties
    }

    if ($parent -is [System.Windows.Controls.Panel]) {
        [void]$parent.Children.Add($displayControl)
    }
    elseif ($parent -is [System.Windows.Controls.ItemsControl]) {
        [void]$parent.Items.Add($displayControl)
    }
    elseif ($parent -is [System.Windows.Controls.ContentControl]) {
        $parent.Content = $displayControl
    }

    # Execute content block with innerContainer as the new parent
    $session.CurrentParent = $innerContainer
    Write-Debug "Entering content block. Parent set to: $($innerContainer.GetType().Name)"
    
    # Execute content - restore parent outside try/finally for PS 5.1 closure compatibility
    try {
        Invoke-UiContent -Content $Content -CallerName 'New-UiPanel' -ErrorAction Stop
    }
    catch {
        # Restore parent before re-throwing
        $session.CurrentParent = $oldParent
        Write-Debug "Content execution failed: $($_.Exception.Message)"
        throw
    }
    
    # Restore parent after successful content execution
    $session.CurrentParent = $oldParent
    
    Write-Debug "Content block complete. Added to: $($oldParent.GetType().Name)"
}