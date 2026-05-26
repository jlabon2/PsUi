function Set-StatusBarChildCompact {
    <#
    .SYNOPSIS
        Applies bar-friendly compact sizing to a single control based on its type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Control
    )

    if (!($Control -is [System.Windows.FrameworkElement])) { return }

    $Control.VerticalAlignment = 'Center'
    $Control.FocusVisualStyle  = $null

    # Buttons (incl. dropdown buttons) - compact height and padding so they fit the bar
    if ($Control -is [System.Windows.Controls.Primitives.ButtonBase] -and
        !($Control -is [System.Windows.Controls.CheckBox]) -and
        !($Control -is [System.Windows.Controls.RadioButton])) {
        $Control.Height  = 26
        $Control.Padding = [System.Windows.Thickness]::new(10, 0, 10, 0)
        $Control.Margin  = [System.Windows.Thickness]::new(2, 0, 2, 0)
        return
    }

    if ($Control -is [System.Windows.Controls.TextBox] -or
        $Control -is [System.Windows.Controls.PasswordBox]) {
        $Control.Height = 24
        $Control.Margin = [System.Windows.Thickness]::new(2, 0, 2, 0)
        if ($Control.MinWidth -lt 80) { $Control.MinWidth = 80 }
        return
    }

    if ($Control -is [System.Windows.Controls.CheckBox] -or
        $Control -is [System.Windows.Controls.RadioButton]) {
        $Control.Margin = [System.Windows.Thickness]::new(4, 0, 4, 0)
        return
    }

    if ($Control -is [System.Windows.Controls.ComboBox]) {
        $Control.Height  = 26
        $Control.Margin  = [System.Windows.Thickness]::new(2, 0, 2, 0)
        $Control.Padding = [System.Windows.Thickness]::new(5, 1, 5, 1)

        # Only enforce MinWidth when the wrapper has room; -WPFProperties sets
        # Width on the wrapper, and MinWidth + Margin can overflow it causing
        # a LayoutClip that hides the right border accent
        $wrapperW = if ($Control.Parent -is [System.Windows.FrameworkElement]) { $Control.Parent.Width } else { [double]::NaN }
        $available = if ([double]::IsNaN($wrapperW)) { [double]::MaxValue } else { $wrapperW - $Control.Margin.Left - $Control.Margin.Right }
        if ($available -ge 100 -and $Control.MinWidth -lt 100) { $Control.MinWidth = 100 }
        return
    }

    if ($Control -is [System.Windows.Controls.Slider]) {
        # Slider has thumb + track; 22px keeps both visible without overflow
        $Control.Height = 22
        $Control.Margin = [System.Windows.Thickness]::new(4, 0, 4, 0)
        if ($Control.MinWidth -lt 100) { $Control.MinWidth = 100 }
        return
    }

    if ($Control -is [System.Windows.Controls.DatePicker]) {
        $Control.Height = 26
        $Control.Margin = [System.Windows.Thickness]::new(2, 0, 2, 0)
        return
    }

    if ($Control -is [System.Windows.Controls.ProgressBar]) {
        $Control.Height = 12
        $Control.Margin = [System.Windows.Thickness]::new(4, 0, 4, 0)
        if ($Control.MinWidth -lt 80) { $Control.MinWidth = 80 }
        return
    }

    # Structural and display elements used internally by PsUi (labels,
    # wrappers, severity icons, badge pills, spacers, images, separators)
    if ($Control -is [System.Windows.Controls.TextBlock] -or
        $Control -is [System.Windows.Controls.Label] -or
        $Control -is [System.Windows.Controls.Image] -or
        $Control -is [System.Windows.Controls.Separator] -or
        $Control -is [System.Windows.Controls.Panel] -or
        $Control -is [System.Windows.Controls.Border] -or
        $Control -is [System.Windows.Controls.ContentControl]) {
        return
    }

    # Truly unsupported control type - collapse it and warn
    $typeName = $Control.GetType().Name
    Write-Warning "Status bar: unsupported control type [$typeName]. Use a recognized control (Button, TextBox, ComboBox, CheckBox, Slider, DatePicker, ProgressBar)."
    $Control.Visibility = [System.Windows.Visibility]::Collapsed
}
