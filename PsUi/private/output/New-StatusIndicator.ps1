
function New-StatusIndicator {
    <#
    .SYNOPSIS
        Creates animated status indicator (spinner/checkmark/warning).
    #>
    [CmdletBinding()]
    param()

    # Status indicator - small spinner that shows running/complete/warning states
    $statusIndicator = [System.Windows.Controls.Grid]@{
        Width             = 20
        Height            = 20
        Margin            = [System.Windows.Thickness]::new(0, 0, 8, 0)
        VerticalAlignment = 'Center'
        ToolTip           = "Running..."
    }

    # Keyed rather than colored, since this one is built once with the window and outlives theme switches.
    $statusSpinner = New-UiLoadingSpinner -Size 16 -BrushKey 'AccentBrush'
    [void]$statusIndicator.Children.Add($statusSpinner)

    # Success checkmark icon (hidden initially)
    $statusSuccess = [System.Windows.Controls.TextBlock]@{
        Text                = [PsUi.ModuleContext]::GetIcon('Accept')
        FontFamily          = [PsUi.ModuleContext]::ActiveIconFontFamily
        FontSize            = 16
        Foreground          = ConvertTo-UiBrush '#107C10'
        HorizontalAlignment = 'Center'
        VerticalAlignment   = 'Center'
        Visibility          = 'Collapsed'
    }
    [void]$statusIndicator.Children.Add($statusSuccess)

    # Warning icon (hidden initially)
    $statusWarning = [System.Windows.Controls.TextBlock]@{
        Text                = [PsUi.ModuleContext]::GetIcon('Warning')
        FontFamily          = [PsUi.ModuleContext]::ActiveIconFontFamily
        FontSize            = 16
        Foreground          = ConvertTo-UiBrush '#FFA500'
        HorizontalAlignment = 'Center'
        VerticalAlignment   = 'Center'
        Visibility          = 'Collapsed'
    }
    [void]$statusIndicator.Children.Add($statusWarning)

    return @{
        Container = $statusIndicator
        Spinner   = $statusSpinner
        Success   = $statusSuccess
        Warning   = $statusWarning
    }
}
