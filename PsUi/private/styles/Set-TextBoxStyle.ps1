<#
.SYNOPSIS
    Applies modern Fluent styling to a TextBox or PasswordBox control.
.PARAMETER TextBox
    The TextBox control to style.
.PARAMETER PasswordBox
    The PasswordBox control to style.
#>

function Set-TextBoxStyle {
    [CmdletBinding(DefaultParameterSetName = 'TextBox')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'TextBox')]
        [System.Windows.Controls.TextBox]$TextBox,
        
        [Parameter(Mandatory, ParameterSetName = 'PasswordBox')]
        [System.Windows.Controls.PasswordBox]$PasswordBox
    )
    
    # Determine which control we're styling
    $control       = if ($PSCmdlet.ParameterSetName -eq 'PasswordBox') { $PasswordBox } else { $TextBox }
    $isPasswordBox = ($PSCmdlet.ParameterSetName -eq 'PasswordBox')

    # Try to apply Modern XAML style
    $styleApplied = $false
    $styleName    = if ($isPasswordBox) { 'ModernPasswordBoxStyle' } else { 'ModernTextBoxStyle' }
    try {
        if ($null -ne [System.Windows.Application]::Current) {
            $style = [System.Windows.Application]::Current.TryFindResource($styleName)
            if ($null -ne $style) {
                $control.Style = $style
                $styleApplied = $true
            }
        }
    }
    catch {
        Write-Verbose "Failed to apply Modern style from resources: $_"
    }

    # Warn if XAML style not found (indicates ThemeEngine initialization issue)
    if (!$styleApplied) {
        Write-Warning "XAML style '$styleName' not found. Ensure ThemeEngine.LoadStyles() was called."
    }

    # Bubble scroll events to parent ScrollViewer so single-line controls don't trap the wheel.
    # Skip for TextBoxes with their own scrollbars (multi-line TextAreas) - they handle scrolling internally.
    # Guard against stacking via Resources dictionary (avoids clobbering .Tag which ControlFactory
    # uses to store placeholder text for XAML watermark binding).
    $hasOwnScrollbar = !$isPasswordBox -and $control.VerticalScrollBarVisibility -ne 'Disabled' -and $control.VerticalScrollBarVisibility -ne 'Hidden'
    $alreadyHooked   = $control.Resources.Contains('_WheelHooked')

    if (!$hasOwnScrollbar -and !$alreadyHooked) {
        $control.Add_PreviewMouseWheel({
            param($sender, $wheelArgs)
            if ($wheelArgs.Handled) { return }
            
            $wheelArgs.Handled = $true
            $bubbleEvent = [System.Windows.Input.MouseWheelEventArgs]::new(
                $wheelArgs.MouseDevice, $wheelArgs.Timestamp, $wheelArgs.Delta)
            $bubbleEvent.RoutedEvent = [System.Windows.UIElement]::MouseWheelEvent
            $bubbleEvent.Source = $sender
            
            $parent = $sender.Parent -as [System.Windows.UIElement]
            if ($parent) { $parent.RaiseEvent($bubbleEvent) }
        })

        # Mark this control so we don't stack handlers on re-style
        $control.Resources['_WheelHooked'] = $true
    }

    # Create per-instance ContextMenu using shared helper
    $control.ContextMenu = New-TextBoxContextMenu

    try {
        [PsUi.ThemeEngine]::RegisterElement($control)
    }
    catch {
        Write-Verbose "Failed to register control with ThemeEngine: $_"
    }
}