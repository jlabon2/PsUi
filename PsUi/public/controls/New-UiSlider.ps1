function New-UiSlider {
    <#
    .SYNOPSIS
        Creates a slider control for numeric value selection.
    .DESCRIPTION
        Renders a horizontal or vertical slider with optional tick marks, snap-to-tick
        behavior, and a live value label. Supports format strings for the label
        (e.g. percentage, decimal) and can be bound to EnabledWhen for conditional state.
    .PARAMETER Variable
        Variable name to store the slider value.
    .PARAMETER Label
        Label text displayed above the slider.
    .PARAMETER Minimum
        Minimum value (default: 0).
    .PARAMETER Maximum
        Maximum value (default: 100).
    .PARAMETER Default
        Initial value (default: 50).
    .PARAMETER TickFrequency
        Interval between tick marks. Set to 0 to hide ticks.
    .PARAMETER IsSnapToTick
        If true, slider snaps to tick values.
    .PARAMETER ShowValueLabel
        If true, displays the current value next to the slider.
    .PARAMETER ValueLabelFormat
        Format string for the value label (e.g., "{0:N0}" for integers, "{0:P0}" for percentage).
    .PARAMETER Vertical
        If true, creates a vertical slider instead of horizontal.
    .PARAMETER Height
        Height of vertical slider (default: 100). Only valid with -Vertical.
    .PARAMETER MaxHeight
        Maximum height for vertical slider. Only valid with -Vertical.
    .PARAMETER MaxWidth
        Maximum width for horizontal slider. Only valid without -Vertical.
    .PARAMETER FullWidth
        If true, expands to fill available width.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
    .EXAMPLE
        New-UiSlider -Variable "volume" -Label "Volume" -Minimum 0 -Maximum 100 -Default 50
    .EXAMPLE
        New-UiSlider -Variable "opacity" -Label "Opacity" -Minimum 0 -Maximum 1 -Default 1 -TickFrequency 0.1 -ValueLabelFormat "{0:P0}"
    .EXAMPLE
        New-UiSlider -Variable "level" -Vertical -Height 150 -Minimum 0 -Maximum 10 -Default 5
    #>
    [CmdletBinding(DefaultParameterSetName = 'Horizontal')]
    param(
        [Parameter(Mandatory)]
        [string]$Variable,
        
        [string]$Label,
        
        [double]$Minimum = 0,
        
        [double]$Maximum = 100,
        
        [double]$Default = 50,
        
        [double]$TickFrequency = 0,
        
        [switch]$IsSnapToTick,
        
        [switch]$ShowValueLabel,
        
        [string]$ValueLabelFormat = "{0:N0}",
        
        [Parameter(ParameterSetName = 'Vertical', Mandatory)]
        [switch]$Vertical,
        
        [Parameter(ParameterSetName = 'Vertical')]
        [int]$Height = 100,
        
        [Parameter(ParameterSetName = 'Vertical')]
        [int]$MaxHeight,
        
        [Parameter(ParameterSetName = 'Horizontal')]
        [int]$MaxWidth,
        
        [switch]$FullWidth,
        
        [Parameter()]
        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiSlider'
    Write-Debug "Variable='$Variable', Min=$Minimum, Max=$Maximum, Default=$Default"

    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent
    Write-Debug "Parent: $($parent.GetType().Name)"

    $stack = [System.Windows.Controls.StackPanel]::new()
    $stack.Margin = [System.Windows.Thickness]::new(4, 4, 4, 8)
    
    # Apply MaxWidth/MaxHeight constraints based on orientation
    if ($Vertical -and $MaxHeight -gt 0) {
        $stack.MaxHeight = $MaxHeight
    }
    elseif (!$Vertical) {
        # Horizontal sliders should stretch to fill available width
        $stack.HorizontalAlignment = 'Stretch'
        if ($MaxWidth -gt 0) {
            $stack.MaxWidth = $MaxWidth
        }
    }

    if ($Label) {
        $labelBlock = [System.Windows.Controls.TextBlock]@{
            Text       = $Label
            FontSize   = 12
            Foreground = ConvertTo-UiBrush $colors.ControlFg
            Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
            Tag        = 'ControlFgBrush'
        }
        [PsUi.ThemeEngine]::RegisterElement($labelBlock)
        [void]$stack.Children.Add($labelBlock)
    }

    # Slider with optional value display
    if ($ShowValueLabel) {
        if ($Vertical) {
            # For vertical sliders, put value label below the slider
            $sliderPanel = [System.Windows.Controls.StackPanel]::new()
            $sliderPanel.Orientation = 'Vertical'
            $sliderPanel.HorizontalAlignment = 'Center'
            
            $slider = [System.Windows.Controls.Slider]::new()
            $slider.Minimum = $Minimum
            $slider.Maximum = $Maximum
            $slider.Value = $Default
            $slider.Orientation = 'Vertical'
            $slider.HorizontalAlignment = 'Center'
            
            if ($TickFrequency -gt 0) {
                $slider.TickFrequency = $TickFrequency
                $slider.TickPlacement = 'TopLeft'
                $slider.IsSnapToTickEnabled = $IsSnapToTick
            }
            
            Set-SliderStyle -Slider $slider
            
            # Override: Explicit height for vertical slider sizing
            $slider.Height = $Height
            [void]$sliderPanel.Children.Add($slider)
            
            $valueLabel = [System.Windows.Controls.TextBlock]::new()
            $valueLabel.Text = $ValueLabelFormat -f $Default
            $valueLabel.FontSize = 11
            $valueLabel.Foreground = ConvertTo-UiBrush $colors.ControlFg
            $valueLabel.HorizontalAlignment = 'Center'
            $valueLabel.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
            $valueLabel.Tag = 'ControlFgBrush'
            [PsUi.ThemeEngine]::RegisterElement($valueLabel)
            [void]$sliderPanel.Children.Add($valueLabel)
            
            # Update value label when slider changes
            $slider.Add_ValueChanged({
                param($sender, $eventArgs)
                $valueLabel.Text = $ValueLabelFormat -f $eventArgs.NewValue
            }.GetNewClosure())
            
            [void]$stack.Children.Add($sliderPanel)
        }
        else {
            # For horizontal sliders, put value label to the right
            $sliderPanel = [System.Windows.Controls.Grid]::new()
            $sliderPanel.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
            $sliderPanel.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $sliderPanel.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
            $sliderPanel.ColumnDefinitions[1].Width = [System.Windows.GridLength]::Auto

            $slider = [System.Windows.Controls.Slider]::new()
            $slider.Minimum = $Minimum
            $slider.Maximum = $Maximum
            $slider.Value = $Default
            $slider.VerticalAlignment = 'Center'
            
            if ($TickFrequency -gt 0) {
                $slider.TickFrequency = $TickFrequency
                $slider.TickPlacement = 'BottomRight'
                $slider.IsSnapToTickEnabled = $IsSnapToTick
            }
            
            Set-SliderStyle -Slider $slider
            [System.Windows.Controls.Grid]::SetColumn($slider, 0)
            [void]$sliderPanel.Children.Add($slider)

            $valueLabel = [System.Windows.Controls.TextBlock]::new()
            $valueLabel.Text = $ValueLabelFormat -f $Default
            $valueLabel.FontSize = 12
            $valueLabel.Foreground = ConvertTo-UiBrush $colors.ControlFg
            $valueLabel.VerticalAlignment = 'Center'
            $valueLabel.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
            $valueLabel.MinWidth = 40
            $valueLabel.TextAlignment = 'Right'
            $valueLabel.Tag = 'ControlFgBrush'
            [PsUi.ThemeEngine]::RegisterElement($valueLabel)
            [System.Windows.Controls.Grid]::SetColumn($valueLabel, 1)
            [void]$sliderPanel.Children.Add($valueLabel)

            # Update value label when slider changes
            $slider.Add_ValueChanged({
                param($sender, $eventArgs)
                $valueLabel.Text = $ValueLabelFormat -f $eventArgs.NewValue
            }.GetNewClosure())

            [void]$stack.Children.Add($sliderPanel)
        }
    }
    else {
        $slider = [System.Windows.Controls.Slider]::new()
        $slider.Minimum = $Minimum
        $slider.Maximum = $Maximum
        $slider.Value = $Default
        
        if ($Vertical) {
            $slider.Orientation = 'Vertical'
            $slider.HorizontalAlignment = 'Center'
        }
        
        if ($TickFrequency -gt 0) {
            $slider.TickFrequency = $TickFrequency
            $slider.TickPlacement = if ($Vertical) { 'TopLeft' } else { 'BottomRight' }
            $slider.IsSnapToTickEnabled = $IsSnapToTick
        }
        
        Set-SliderStyle -Slider $slider
        
        # Override: Explicit height for vertical slider sizing
        if ($Vertical) {
            $slider.Height = $Height
        }
        
        [void]$stack.Children.Add($slider)
    }

    # Tag wrapper for FormLayout unwrapping (when label exists)
    if ($Label) {
        $controlElement = if ($ShowValueLabel) { $sliderPanel } else { $slider }
        Set-UiFormControlTag -Wrapper $stack -Label $labelBlock -Control $controlElement
    }

    # FullWidth in WrapPanel contexts
    Set-FullWidthConstraint -Control $stack -Parent $parent -FullWidth:$FullWidth
    
    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $stack -Properties $WPFProperties
    }
    
    Write-Debug "Adding to $($parent.GetType().Name)"
    [void]$parent.Children.Add($stack)

    # Register control in all session registries
    Register-UiControlComplete -Name $Variable -Control $slider -InitialValue $slider.Value
}
