
function New-ProgressPanel {
    <#
    .SYNOPSIS
        Creates a progress panel with support for nested progress activities.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Colors
    )

    # Progress panel - supports multiple nested progress bars (keyed by ActivityId)
    $progressPanel = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Vertical'
        Margin      = [System.Windows.Thickness]::new(12, 0, 12, 8)
        Visibility  = 'Collapsed'
    }
    [System.Windows.Controls.DockPanel]::SetDock($progressPanel, 'Top')

    # Dictionary to track multiple progress activities (keyed by ActivityId)
    $progressActivities = @{}

    # Resolve brushes up front so GetNewClosure captures the values. Show-UiOutput invokes this per ActivityId after this function returns, and -NoWait leaves no dynamic scope to supply $Colors. Inline calls die regardless since closures carry values and not private functions.
    $secondaryBrush = ConvertTo-UiBrush $Colors.SecondaryText
    $barBgBrush     = ConvertTo-UiBrush $Colors.ControlBg
    $accentBrush    = ConvertTo-UiBrush $Colors.Accent
    $applyBarStyle  = ${function:Set-ProgressBarStyle}

    $createProgressUI = {
        param($activityId, $isChild)

        $stack = [System.Windows.Controls.StackPanel]@{
            Orientation = 'Vertical'
            Margin      = if ($isChild) { [System.Windows.Thickness]::new(24, 2, 12, 2) } else { [System.Windows.Thickness]::new(12, 4, 12, 4) }
        }

        $label = [System.Windows.Controls.TextBlock]@{
            FontSize   = if ($isChild) { 10 } else { 11 }
            Foreground = $secondaryBrush
            Margin     = [System.Windows.Thickness]::new(0, 0, 0, 2)
        }
        [void]$stack.Children.Add($label)

        $bar = [System.Windows.Controls.ProgressBar]@{
            IsIndeterminate = $true
            Height          = if ($isChild) { 3 } else { 4 }
            Background      = $barBgBrush
            Foreground      = if ($isChild) { $secondaryBrush } else { $accentBrush }
        }
        & $applyBarStyle -ProgressBar $bar
        [void]$stack.Children.Add($bar)

        return @{
            Container = $stack
            Label     = $label
            Bar       = $bar
            IsChild   = $isChild
        }
    }.GetNewClosure()

    # Create default progress bar (ActivityId = 0) but DON'T add to panel yet
    $defaultProgressUI             = & $createProgressUI 0 $false
    $defaultProgressUI.Label.Text  = "Processing..."

    # Alias for backward compatibility
    $progressBar = $defaultProgressUI.Bar

    return @{
        Panel               = $progressPanel
        Activities          = $progressActivities
        DefaultUI           = $defaultProgressUI
        ProgressBar         = $progressBar
        CreateProgressUI    = $createProgressUI
    }
}
