function Set-ContextMenuStyle {
    <#
    .SYNOPSIS
        Applies theme styling to a ContextMenu and its MenuItems.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ContextMenu]$ContextMenu
    )
    
    $colors = Get-ThemeColors
    
    # Try to apply the implicit style from Application resources first
    $styleApplied = $false
    try {
        if ($null -ne [System.Windows.Application]::Current) {
            # Look for implicit ContextMenu style (keyed by type)
            $style = [System.Windows.Application]::Current.TryFindResource([System.Windows.Controls.ContextMenu])
            if ($null -ne $style -and $style -is [System.Windows.Style]) {
                $ContextMenu.Style = $style
                $styleApplied = $true
            }
        }
    }
    catch {
        Write-Verbose "Failed to apply ContextMenu style from resources: $_"
    }
    
    # If XAML style wasn't applied, set properties manually
    if (!$styleApplied) {
        $ContextMenu.Background      = ConvertTo-UiBrush $colors.ControlBg
        $ContextMenu.Foreground      = ConvertTo-UiBrush $colors.ControlFg
        $ContextMenu.BorderBrush     = ConvertTo-UiBrush $colors.Border
        $ContextMenu.BorderThickness = [System.Windows.Thickness]::new(1)
        $ContextMenu.Padding         = [System.Windows.Thickness]::new(4)
        $ContextMenu.FontFamily      = [System.Windows.Media.FontFamily]::new('Segoe UI')
        $ContextMenu.FontSize        = 12
        
        # Add drop shadow effect
        $shadow             = [System.Windows.Media.Effects.DropShadowEffect]::new()
        $shadow.BlurRadius  = 8
        $shadow.ShadowDepth = 2
        $shadow.Opacity     = 0.2
        $ContextMenu.Effect = $shadow
    }

    foreach ($item in $ContextMenu.Items) {
        if ($item -is [System.Windows.Controls.MenuItem]) {
            Set-MenuItemStyle -MenuItem $item -Colors $colors
        }
    }
}
