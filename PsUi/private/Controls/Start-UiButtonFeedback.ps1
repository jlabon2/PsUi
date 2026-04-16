function Start-UiButtonFeedback {
    <#
    .SYNOPSIS
        Flashes accent color and swaps icon to provide visual click feedback.
        We use this for buttons like "Copy" to dislay that the action was performed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$Button,
        
        [Parameter(Mandatory)]
        [string]$OriginalIconChar,
        
        [string]$FeedbackIconChar = [PsUi.ModuleContext]::GetIcon('CheckMark'),
        
        [int]$DurationMs = 1500
    )
    
    $colors = Get-ThemeColors
    
    # Bail if button doesn't have an icon TextBlock
    $icon = $Button.Content
    if (!$icon -or $icon -isnot [System.Windows.Controls.TextBlock]) { return }
    
    # Apply feedback state
    $originalBg        = $Button.Background
    $Button.Background = ConvertTo-UiBrush $colors.Accent
    $icon.Text         = $FeedbackIconChar
    
    # Timer reverts to original state after delay
    $timer          = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds($DurationMs)
    $timer.Tag      = @{ Btn = $Button; Icon = $icon; Bg = $originalBg; Char = $OriginalIconChar }
    $timer.Add_Tick({
        $this.Tag.Btn.Background = $this.Tag.Bg
        $this.Tag.Icon.Text      = $this.Tag.Char
        $this.Stop()
    })
    $timer.Start()
}
