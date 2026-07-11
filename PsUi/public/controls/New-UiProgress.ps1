function New-UiProgress {
    <#
    .SYNOPSIS
        Creates a progress bar.
    .PARAMETER Variable
        Variable name to reference the bar later.
    .PARAMETER Label
        Optional text shown above the bar. Updateable via Set-UiProgress -Label.
    .PARAMETER Minimum
        Lower limit. Default 0.
    .PARAMETER Maximum
        Upper limit. Default 100.
    .PARAMETER Default
        Initial value. Default 0.
    .PARAMETER Height
        Bar height in pixels.
    .PARAMETER Indeterminate
        Animated bar instead of a fill.
    .PARAMETER ShowValue
        Render the current value as text beside the bar. Pointless with
        -Indeterminate (the bar has no real value to display), but allowed.
    .PARAMETER ValueFormat
        Format string for the value text. {0} is current, {1} is max.
        Defaults to '{0:N0}%'. '{0}/{1}' gives you the x/y look.
    .PARAMETER Severity
        Color tint: Info (default), Success, Warning, Error.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties.
    .EXAMPLE
        New-UiProgress -Variable 'progress'
    .EXAMPLE
        New-UiProgress -Variable 'loading' -Indeterminate -Label 'Connecting...'
    .EXAMPLE
        New-UiProgress -Variable 'files' -Maximum 250 -ShowValue -ValueFormat '{0}/{1} files'
    .EXAMPLE
        New-UiProgress -Variable 'disk' -Default 87 -ShowValue -Severity Warning -Label 'Disk usage'
    #>
    [CmdletBinding()]
    param(
        # Optional - a bare display bar needs no name. Omitted means "don't register for Set-UiProgress by name"; the body puts up a throwaway name for the registry.
        [string]$Variable,

        [string]$Label,

        [double]$Minimum = 0,

        [double]$Maximum = 100,

        [double]$Default = 0,

        [int]$Height = 6,

        [switch]$Indeterminate,

        [switch]$ShowValue,

        [string]$ValueFormat = '{0:N0}%',

        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Severity = 'Info',

        [Parameter()]
        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiProgress'
    $parent  = $session.CurrentParent
    Write-Debug "Variable='$Variable', Min=$Minimum Max=$Maximum Default=$Default Severity=$Severity"

    if ($Maximum -le $Minimum) {
        throw "New-UiProgress: -Maximum ($Maximum) must be greater than -Minimum ($Minimum)."
    }

    $progress = [System.Windows.Controls.ProgressBar]::new()
    $progress.Minimum         = $Minimum
    $progress.Maximum         = $Maximum
    $progress.Value           = [Math]::Max($Minimum, [Math]::Min($Maximum, $Default))
    $progress.IsIndeterminate = $Indeterminate.IsPresent
    $progress.Margin          = [System.Windows.Thickness]::new(4, 4, 4, 8)

    # ThemeEngine reads Tag.BrushTag and rebinds Foreground on theme switches.
    $brushKey = Get-SeverityBrushKey -Severity $Severity -UseAccentDefault

    # Tag goes on early so the first ApplyTheme pass picks up the right brush.
    # ValueBlock/LabelBlock get filled in below if the wrapper is built.
    $labelBlock = $null
    $valueBlock = $null
    $progress.Tag = @{
        LabelBlock  = $labelBlock
        ValueBlock  = $valueBlock
        ValueFormat = $ValueFormat
        Severity    = $Severity
        BrushTag    = $brushKey
    }

    # Tag is set above, so Set-ProgressBarStyle's RegisterElement picks up the right severity brush on the first paint.
    Set-ProgressBarStyle -ProgressBar $progress

    if ($PSBoundParameters.ContainsKey('Height')) { $progress.Height = $Height }

    if ($WPFProperties) {
        # Tag is reserved - it stores the metadata that makes -Label/-ShowValue/-Severity work. Letting the caller stomp it would silently break all three.
        if ($WPFProperties.ContainsKey('Tag')) {
            Write-Warning "New-UiProgress: -WPFProperties Tag is reserved (used for label/value/severity bookkeeping). Ignoring."
            $WPFProperties = @{} + $WPFProperties
            [void]$WPFProperties.Remove('Tag')
        }
        Set-UiProperties -Control $progress -Properties $WPFProperties
    }

    # Wrap in a stack only when there's a label or value text. Bare bars stay bare so existing layouts don't shift a pixel.
    $needsWrapper = $Label -or $ShowValue
    if ($needsWrapper) {
        $colors = Get-ThemeColors
        $stack = [System.Windows.Controls.StackPanel]::new()
        $stack.Margin = [System.Windows.Thickness]::new(4, 4, 4, 8)

        if ($Label) {
            $labelBlock = [System.Windows.Controls.TextBlock]@{
                Text       = $Label
                FontSize   = 12
                Foreground = ConvertTo-UiBrush $colors.ControlFg
                Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
                Tag        = 'ControlForegroundBrush'
            }
            [PsUi.ThemeEngine]::RegisterElement($labelBlock)
            [void]$stack.Children.Add($labelBlock)
        }

        # Bar + value text share a row so the percentage rides next to it
        if ($ShowValue) {
            $row = [System.Windows.Controls.Grid]::new()
            $col1 = [System.Windows.Controls.ColumnDefinition]::new()
            $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $col2 = [System.Windows.Controls.ColumnDefinition]::new()
            $col2.Width = [System.Windows.GridLength]::Auto
            $row.ColumnDefinitions.Add($col1)
            $row.ColumnDefinitions.Add($col2)

            $progress.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
            $progress.VerticalAlignment = 'Center'
            [System.Windows.Controls.Grid]::SetColumn($progress, 0)
            [void]$row.Children.Add($progress)

            $valueBlock = [System.Windows.Controls.TextBlock]@{
                Text              = ($ValueFormat -f $progress.Value, $Maximum)
                FontSize          = 12
                Foreground        = ConvertTo-UiBrush $colors.ControlFg
                VerticalAlignment = 'Center'
                MinWidth          = 48
                TextAlignment     = 'Right'
                Tag               = 'ControlForegroundBrush'
            }
            [PsUi.ThemeEngine]::RegisterElement($valueBlock)
            [System.Windows.Controls.Grid]::SetColumn($valueBlock, 1)
            [void]$row.Children.Add($valueBlock)

            # Update the text whenever the bar moves. Read Maximum from the sender so post-construction tweaks (yes, people do that) stay in sync.
            $capturedFormat = $ValueFormat
            $progress.Add_ValueChanged({
                param($sender, $e)
                $valueBlock.Text = $capturedFormat -f $e.NewValue, $sender.Maximum
            }.GetNewClosure())

            [void]$stack.Children.Add($row)
        }
        else {
            [void]$stack.Children.Add($progress)
        }

        [void]$parent.Children.Add($stack)
    }
    else {
        [void]$parent.Children.Add($progress)
    }

    # Patch the metadata with the actual wrapper blocks (if any).
    $progress.Tag.LabelBlock = $labelBlock
    $progress.Tag.ValueBlock = $valueBlock

    # A bare display bar has no -Variable, but Register-UiControlComplete's -Name is Mandatory - an empty string there makes PowerShell prompt for it and the whole window hangs. Hand it a throwaway name (same trick New-UiStatusBar uses for anonymous bars).
    $varName = if ($Variable) { $Variable  }
    else {  '_anonProgress_' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)  }

    Write-Debug "Registered progress bar '$varName' (wrapper=$needsWrapper)"
    Register-UiControlComplete -Name $varName -Control $progress -InitialValue $progress.Value
}

