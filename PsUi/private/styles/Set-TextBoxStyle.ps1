function Set-TextBoxStyle {
    <#
    .SYNOPSIS
        Applies modern styling to a TextBox or PasswordBox control.
    #>
    [CmdletBinding(DefaultParameterSetName = 'TextBox')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'TextBox')]
        [System.Windows.Controls.TextBox]$TextBox,

        [Parameter(Mandatory, ParameterSetName = 'PasswordBox')]
        [System.Windows.Controls.PasswordBox]$PasswordBox
    )

    $control       = if ($PSCmdlet.ParameterSetName -eq 'PasswordBox') { $PasswordBox } else { $TextBox }
    $isPasswordBox = ($PSCmdlet.ParameterSetName -eq 'PasswordBox')

    # Try to apply Modern XAML style
    $styleApplied = $false
    $styleName    = if ($isPasswordBox) { 'ModernPasswordBoxStyle' } else { 'ModernTextBoxStyle' }
    try {
        $style = [PsUi.ThemeEngine]::FindStyleResource($styleName)
        if ($null -ne $style) {
            $control.Style = $style
            $styleApplied = $true
        }
    }
    catch {
        Write-Verbose "Failed to apply Modern style from resources: $_"
    }

    # Warn if XAML style not found (indicates ThemeEngine initialization issue)
    if (!$styleApplied) {
        Write-Warning "XAML style '$styleName' not found. Ensure ThemeEngine.LoadStyles() was called."
    }

    # Without the capture flag New-UiTab takes the wheel on the way down and the TextArea never actually grabs it
    $hasOwnScrollbar = !$isPasswordBox -and $control.VerticalScrollBarVisibility -ne 'Disabled' -and $control.VerticalScrollBarVisibility -ne 'Hidden'
    if ($hasOwnScrollbar) { Set-UiWheelRouting -Control $control -Mode Capture }
    else { Set-UiWheelRouting -Control $control }

    # Create per-instance ContextMenu using shared helper
    $control.ContextMenu = New-TextBoxContextMenu

    try {
        [PsUi.ThemeEngine]::RegisterElement($control)
    }
    catch {
        Write-Verbose "Failed to register control with ThemeEngine: $_"
    }
}