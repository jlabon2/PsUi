function New-UiTimePicker {
    <#
    .SYNOPSIS
        Creates a time picker control for selecting hours and minutes.
    .DESCRIPTION
        Creates a labeled time picker with a dropdown popup containing scrollable hour/minute/AM-PM columns.
        Styled to match the DatePicker control with theme support.
    .PARAMETER Label
        Label text displayed above the time picker.
    .PARAMETER Variable
        Variable name to store the selected time value.
    .PARAMETER Default
        Initial time value. Can be a TimeSpan, DateTime, or string like "14:30" or "2:30 PM".
    .PARAMETER Use24Hour
        Use 24-hour format instead of 12-hour with AM/PM.
    .PARAMETER MinuteInterval
        Interval for minute selection (1, 5, 10, 15, 30). Default is 5.
    .PARAMETER FullWidth
        Stretches the control to fill available width instead of fixed sizing.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
    .EXAMPLE
        New-UiTimePicker -Label "Start Time" -Variable "startTime" -Default "09:00"
    .EXAMPLE
        New-UiTimePicker -Label "Meeting Time" -Variable "meetingTime" -Use24Hour -MinuteInterval 15
    .EXAMPLE
        New-UiTimePicker -Label "Reminder" -Variable "reminder" -Default (Get-Date).TimeOfDay
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$Variable,

        [object]$Default,

        [switch]$Use24Hour,

        [ValidateSet(1, 5, 10, 15, 30)]
        [int]$MinuteInterval = 5,

        [switch]$FullWidth,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiTimePicker'
    Write-Debug "Label='$Label', Variable='$Variable', Use24Hour=$Use24Hour"

    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent
    Write-Debug "Parent: $($parent.GetType().Name)"

    # Parse default time
    $defaultHour = 9
    $defaultMinute = 0
    $defaultAmPm = 'AM'

    if ($Default) {
        if ($Default -is [TimeSpan]) {
            $defaultHour = $Default.Hours
            $defaultMinute = $Default.Minutes
        }
        elseif ($Default -is [DateTime]) {
            $defaultHour = $Default.Hour
            $defaultMinute = $Default.Minute
        }
        elseif ($Default -is [string]) {
            try {
                $parsedTime = [DateTime]::Parse($Default)
                $defaultHour = $parsedTime.Hour
                $defaultMinute = $parsedTime.Minute
            }
            catch {
                Write-Verbose "Failed to parse time string '$Default': $_"
            }
        }

        # Round minute to nearest interval
        $defaultMinute = [Math]::Round($defaultMinute / $MinuteInterval) * $MinuteInterval
        if ($defaultMinute -ge 60) { $defaultMinute = 0 }
    }

    # Convert to 12-hour format for display if needed
    $display24Hour = $defaultHour
    if (!$Use24Hour) {
        if ($defaultHour -ge 12) {
            $defaultAmPm = 'PM'
            if ($defaultHour -gt 12) { $defaultHour -= 12 }
        }
        else {
            $defaultAmPm = 'AM'
            if ($defaultHour -eq 0) { $defaultHour = 12 }
        }
    }

    $outerStack = [System.Windows.Controls.StackPanel]@{
        Margin = [System.Windows.Thickness]::new(4, 4, 4, 8)
    }

    $labelBlock = [System.Windows.Controls.TextBlock]@{
        Text       = $Label
        FontSize   = 12
        Foreground = ConvertTo-UiBrush $colors.ControlFg
        Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
        Tag        = 'ControlFgBrush'
    }
    [PsUi.ThemeEngine]::RegisterElement($labelBlock)
    [void]$outerStack.Children.Add($labelBlock)

    # Create the main button container (mimics DatePicker appearance)
    $pickerBorder = [System.Windows.Controls.Border]@{
        Background      = ConvertTo-UiBrush $colors.ControlBg
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
        CornerRadius    = [System.Windows.CornerRadius]::new(3)
        Height          = 30
        MinWidth        = 140
        Cursor          = [System.Windows.Input.Cursors]::Hand
        Tag             = 'TimePickerBorder'
    }
    [PsUi.ThemeEngine]::RegisterElement($pickerBorder)

    $pickerGrid = [System.Windows.Controls.Grid]::new()
    
    # Define columns: time text and dropdown arrow
    $col1 = [System.Windows.Controls.ColumnDefinition]::new()
    $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col2 = [System.Windows.Controls.ColumnDefinition]::new()
    $col2.Width = [System.Windows.GridLength]::new(28, [System.Windows.GridUnitType]::Pixel)
    [void]$pickerGrid.ColumnDefinitions.Add($col1)
    [void]$pickerGrid.ColumnDefinitions.Add($col2)

    # Time display text
    $timeDisplayFormat = if ($Use24Hour) { "{0:00}:{1:00}" } else { "{0}:{1:00} {2}" }
    $initialDisplayText = if ($Use24Hour) { 
        [string]::Format("{0:00}:{1:00}", $display24Hour, $defaultMinute) 
    } else { 
        [string]::Format("{0}:{1:00} {2}", $defaultHour, $defaultMinute, $defaultAmPm) 
    }

    $timeText = [System.Windows.Controls.TextBlock]@{
        Text                = $initialDisplayText
        FontSize            = 12
        FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe UI')
        Foreground          = ConvertTo-UiBrush $colors.ControlFg
        VerticalAlignment   = [System.Windows.VerticalAlignment]::Center
        Margin              = [System.Windows.Thickness]::new(8, 0, 0, 0)
        Tag                 = 'ControlFgBrush'
    }
    [PsUi.ThemeEngine]::RegisterElement($timeText)
    [System.Windows.Controls.Grid]::SetColumn($timeText, 0)
    [void]$pickerGrid.Children.Add($timeText)

    # Dropdown arrow button
    $arrowBorder = [System.Windows.Controls.Border]@{
        Background = ConvertTo-UiBrush $colors.ControlBg
        Width      = 28
        Tag        = 'TimePickerArrowBorder'
    }
    [PsUi.ThemeEngine]::RegisterElement($arrowBorder)
    $arrowText = [System.Windows.Controls.TextBlock]@{
        Text                = [PsUi.ModuleContext]::GetIcon('ChevronDown')
        FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize            = 10
        Foreground          = ConvertTo-UiBrush $colors.ControlFg
        HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        VerticalAlignment   = [System.Windows.VerticalAlignment]::Center
        Tag                 = 'ControlFgBrush'
    }
    [PsUi.ThemeEngine]::RegisterElement($arrowText)
    $arrowBorder.Child = $arrowText
    [System.Windows.Controls.Grid]::SetColumn($arrowBorder, 1)
    [void]$pickerGrid.Children.Add($arrowBorder)

    $pickerBorder.Child = $pickerGrid

    $popup = [System.Windows.Controls.Primitives.Popup]@{
        PlacementTarget = $pickerBorder
        Placement       = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
        StaysOpen       = $false
        AllowsTransparency = $true
    }

    # Popup content container
    $popupBorder = [System.Windows.Controls.Border]@{
        Background      = ConvertTo-UiBrush $colors.ControlBg
        BorderBrush     = ConvertTo-UiBrush $colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
        CornerRadius    = [System.Windows.CornerRadius]::new(4)
        Padding         = [System.Windows.Thickness]::new(8)
        MinWidth        = 180
        Tag             = 'TimePickerPopupBorder'
    }

    # Add shadow effect
    try {
        $shadow = [System.Windows.Media.Effects.DropShadowEffect]@{
            BlurRadius  = 10
            ShadowDepth = 3
            Opacity     = 0.3
            Color       = [System.Windows.Media.Colors]::Black
        }
        $popupBorder.Effect = $shadow
    }
    catch { Write-Debug "Drop shadow failed: $_" }

    $popupStack = [System.Windows.Controls.StackPanel]::new()

    # Columns container
    $columnsPanel = [System.Windows.Controls.StackPanel]@{
        Orientation = [System.Windows.Controls.Orientation]::Horizontal
        HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    }

    # Helper to create a scrollable column
    $createColumn = {
        param($items, $selectedValue, $width)
        
        $listBox = [System.Windows.Controls.ListBox]@{
            Width      = $width
            Height     = 120
            Margin     = [System.Windows.Thickness]::new(2)
            Background = ConvertTo-UiBrush $colors.ControlBg
            BorderThickness = [System.Windows.Thickness]::new(0)
            HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Center
        }
        Set-ListBoxStyle -ListBox $listBox

        foreach ($item in $items) {
            $listItem = [System.Windows.Controls.ListBoxItem]@{
                Content             = $item
                HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Center
                FontSize            = 14
                Padding             = [System.Windows.Thickness]::new(8, 4, 8, 4)
            }
            [void]$listBox.Items.Add($listItem)
            if ($item -eq $selectedValue) {
                $listBox.SelectedItem = $listItem
            }
        }
        
        return $listBox
    }

    # Hour column
    $hourItems = if ($Use24Hour) {
        0..23 | ForEach-Object { $_.ToString('00') }
    } else {
        1..12 | ForEach-Object { $_.ToString() }
    }
    $selectedHourStr = if ($Use24Hour) { $display24Hour.ToString('00') } else { $defaultHour.ToString() }
    $hourList = & $createColumn $hourItems $selectedHourStr 50

    # Colon separator
    $colonLabel = [System.Windows.Controls.TextBlock]@{
        Text              = ':'
        FontSize          = 18
        FontWeight        = [System.Windows.FontWeights]::Bold
        Foreground        = ConvertTo-UiBrush $colors.ControlFg
        VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        Margin            = [System.Windows.Thickness]::new(4, 0, 4, 0)
        Tag               = 'TimePickerColon'
    }

    # Minute column
    $minuteItems = for ($m = 0; $m -lt 60; $m += $MinuteInterval) { $m.ToString('00') }
    $minuteList = & $createColumn $minuteItems $defaultMinute.ToString('00') 50

    [void]$columnsPanel.Children.Add($hourList)
    [void]$columnsPanel.Children.Add($colonLabel)
    [void]$columnsPanel.Children.Add($minuteList)

    # AM/PM column (only for 12-hour)
    $ampmList = $null
    if (!$Use24Hour) {
        $ampmList = & $createColumn @('AM', 'PM') $defaultAmPm 50
        [void]$columnsPanel.Children.Add($ampmList)
    }

    [void]$popupStack.Children.Add($columnsPanel)

    # Separator
    $separator = [System.Windows.Controls.Border]@{
        Height     = 1
        Background = ConvertTo-UiBrush $colors.Border
        Margin     = [System.Windows.Thickness]::new(0, 8, 0, 8)
        Tag        = 'TimePickerSeparator'
    }
    [void]$popupStack.Children.Add($separator)

    # OK button
    $okButton = [System.Windows.Controls.Button]@{
        Content             = 'OK'
        Width               = 70
        Height              = 28
        HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        Cursor              = [System.Windows.Input.Cursors]::Hand
        Padding             = [System.Windows.Thickness]::new(16, 4, 16, 4)
    }
    Set-ButtonStyle -Button $okButton
    [void]$popupStack.Children.Add($okButton)

    $popupBorder.Child = $popupStack
    $popup.Child = $popupBorder

    # Store references for event handlers
    $state = @{
        TimeText     = $timeText
        HourList     = $hourList
        MinuteList   = $minuteList
        AmPmList     = $ampmList
        Popup        = $popup
        Use24Hour    = $Use24Hour.IsPresent
        PickerBorder = $pickerBorder
        PopupBorder  = $popupBorder
        ArrowBorder  = $arrowBorder
        ArrowText    = $arrowText
        ColonLabel   = $colonLabel
        Separator    = $separator
        LabelBlock   = $labelBlock
    }

    # Click handler to open popup
    $pickerBorder.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        $state.Popup.IsOpen = $true
        
        # Scroll selected items into view
        if ($state.HourList.SelectedItem) {
            $state.HourList.ScrollIntoView($state.HourList.SelectedItem)
        }
        if ($state.MinuteList.SelectedItem) {
            $state.MinuteList.ScrollIntoView($state.MinuteList.SelectedItem)
        }
        if ($state.AmPmList -and $state.AmPmList.SelectedItem) {
            $state.AmPmList.ScrollIntoView($state.AmPmList.SelectedItem)
        }
    }.GetNewClosure())

    # Hover effects - get colors dynamically for theme support
    $pickerBorder.Add_MouseEnter({
        param($sender, $eventArgs)
        $currentColors = Get-ThemeColors
        $sender.BorderBrush = ConvertTo-UiBrush $currentColors.Accent
    }.GetNewClosure())

    $pickerBorder.Add_MouseLeave({
        param($sender, $eventArgs)
        $currentColors = Get-ThemeColors
        $sender.BorderBrush = ConvertTo-UiBrush $currentColors.Border
    }.GetNewClosure())

    # OK button click - update display and close
    $okButton.Add_Click({
        param($sender, $eventArgs)
        
        $hour = if ($state.HourList.SelectedItem) { 
            $state.HourList.SelectedItem.Content 
        } else { 
            if ($state.Use24Hour) { '00' } else { '12' }
        }
        $minute = if ($state.MinuteList.SelectedItem) { 
            $state.MinuteList.SelectedItem.Content 
        } else { 
            '00' 
        }
        
        if ($state.Use24Hour) {
            $state.TimeText.Text = "${hour}:${minute}"
        }
        else {
            $ampm = if ($state.AmPmList -and $state.AmPmList.SelectedItem) { 
                $state.AmPmList.SelectedItem.Content 
            } else { 
                'AM' 
            }
            $state.TimeText.Text = "${hour}:${minute} ${ampm}"
        }
        
        $state.Popup.IsOpen = $false
    }.GetNewClosure())

    [void]$outerStack.Children.Add($pickerBorder)
    [void]$outerStack.Children.Add($popup)

    # Tag wrapper for FormLayout unwrapping in New-UiGrid
    Set-UiFormControlTag -Wrapper $outerStack -Label $labelBlock -Control $pickerBorder

    # FullWidth mode
    Set-FullWidthConstraint -Control $outerStack -Parent $parent -FullWidth:$FullWidth

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $outerStack -Properties $WPFProperties
    }

    Write-Debug "Adding to $($parent.GetType().Name)"
    [void]$parent.Children.Add($outerStack)

    # Create a container object to hold references to all components
    $timePickerContainer = [System.Windows.Controls.Grid]::new()
    $timePickerContainer.Tag = @{
        ControlType  = 'TimePicker'
        HourList     = $hourList
        MinuteList   = $minuteList
        AmPmList     = $ampmList
        Use24Hour    = $Use24Hour.IsPresent
        TimeText     = $timeText
    }

    $session.AddControlSafe($Variable, $timePickerContainer)

    # Register elements with ThemeEngine
    try {
        [PsUi.ThemeEngine]::RegisterElement($pickerBorder)
        [PsUi.ThemeEngine]::RegisterElement($popupBorder)
    }
    catch {
        Write-Verbose "Failed to register TimePicker with ThemeEngine: $_"
    }
}

