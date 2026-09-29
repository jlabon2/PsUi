function Set-ProgressBarStyle {
    <#
    .SYNOPSIS
        Applies theme styling to a progress bar control.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ProgressBar]$ProgressBar
    )

    # Indeterminate skips the custom template. WPF's native indeterminate animation is fine and honestly nicer than anything built by hand here.
    # DynamicResource so a theme switch still reaches it, and Tag carries the severity brush.
    if ($ProgressBar.IsIndeterminate) {
        $fgKey = 'AccentBrush'
        if ($ProgressBar.Tag -is [hashtable] -and $ProgressBar.Tag.BrushTag) {
            $fgKey = [string]$ProgressBar.Tag.BrushTag
        }

        $ProgressBar.SetResourceReference(
            [System.Windows.Controls.Control]::ForegroundProperty, $fgKey)

        # BorderBrush mirrors what ThemeEngine.ApplyTheme does on switches, keep them in lockstep.
        $ProgressBar.SetResourceReference(
            [System.Windows.Controls.Control]::BackgroundProperty, 'BorderBrush')
        $ProgressBar.Height = 6
        try { [PsUi.ThemeEngine]::RegisterElement($ProgressBar) }
        catch { Write-Verbose "Failed to register indeterminate ProgressBar: $_" }
        return
    }

    # Determinate: apply the modern template
    $styleApplied = $false
    try {
        $style = [PsUi.ThemeEngine]::FindStyleResource('ModernProgressBarStyle')
        if ($null -ne $style) {
            $ProgressBar.Style = $style
            $styleApplied = $true
        }
    }
    catch {  Write-Verbose "Failed to apply ModernProgressBarStyle: $_"
    }

    if (!$styleApplied) {
        Write-Warning "XAML style 'ModernProgressBarStyle' not found. Ensure ThemeEngine.LoadStyles() was called."
    }

    $ProgressBar.Height = 6

    # Register so theme switches refresh us via the Tag-aware ProgressBar branch
    try { [PsUi.ThemeEngine]::RegisterElement($ProgressBar) }
    catch { Write-Verbose "Failed to register ProgressBar with ThemeEngine: $_" }
}
