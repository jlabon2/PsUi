
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

    # Helper function to create a progress bar UI element for an activity
    $createProgressUI = {
        param($activityId, $isChild)

        $stack = [System.Windows.Controls.StackPanel]@{
            Orientation = 'Vertical'
            Margin      = if ($isChild) { [System.Windows.Thickness]::new(24, 2, 12, 2) } else { [System.Windows.Thickness]::new(12, 4, 12, 4) }
        }

        $label = [System.Windows.Controls.TextBlock]@{
            FontSize   = if ($isChild) { 10 } else { 11 }
            Foreground = ConvertTo-UiBrush $Colors.SecondaryText
            Margin     = [System.Windows.Thickness]::new(0, 0, 0, 2)
        }
        [void]$stack.Children.Add($label)

        $bar = [System.Windows.Controls.ProgressBar]@{
            IsIndeterminate = $true
            Height          = if ($isChild) { 3 } else { 4 }
            Background      = ConvertTo-UiBrush $Colors.ControlBg
            Foreground      = if ($isChild) { ConvertTo-UiBrush $Colors.SecondaryText } else { ConvertTo-UiBrush $Colors.Accent }
        }
        Set-ProgressBarStyle -ProgressBar $bar
        [void]$stack.Children.Add($bar)

        return @{
            Container = $stack
            Label     = $label
            Bar       = $bar
            IsChild   = $isChild
        }
    }

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
