function Set-MenuItemStyle {
    <#
    .SYNOPSIS
        Applies theme styling to a MenuItem.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.MenuItem]$MenuItem,
        
        [hashtable]$Colors
    )
    
    if (!$Colors) { $Colors = Get-ThemeColors }
    
    # Try to apply the implicit style from Application resources first
    $styleApplied = $false
    try {
        if ($null -ne [System.Windows.Application]::Current) {
            $style = [System.Windows.Application]::Current.TryFindResource([System.Windows.Controls.MenuItem])
            if ($null -ne $style -and $style -is [System.Windows.Style]) {
                $MenuItem.Style = $style
                $styleApplied = $true
            }
        }
    }
    catch {
        Write-Verbose "Failed to apply MenuItem style from resources: $_"
    }
    
    # If XAML style wasn't applied, set properties manually with hover handlers
    if (!$styleApplied) {
        $MenuItem.Background = [System.Windows.Media.Brushes]::Transparent
        $MenuItem.Foreground = ConvertTo-UiBrush $Colors.ControlFg
        $MenuItem.Padding    = [System.Windows.Thickness]::new(10, 6, 10, 6)
        $MenuItem.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
        $MenuItem.FontSize   = 12
        
        # Add hover effect via event handlers - fetch colors dynamically for theme switching
        $MenuItem.Add_MouseEnter({
            param($sender, $eventArgs)
            $currentColors = Get-ThemeColors
            $sender.Background = ConvertTo-UiBrush $currentColors.ItemHover
        })
        
        $MenuItem.Add_MouseLeave({
            param($sender, $eventArgs)
            $sender.Background = [System.Windows.Media.Brushes]::Transparent
        })
    }

    foreach ($subItem in $MenuItem.Items) {
        if ($subItem -is [System.Windows.Controls.MenuItem]) {
            Set-MenuItemStyle -MenuItem $subItem -Colors $Colors
        }
    }

    try {
        [PsUi.ThemeEngine]::RegisterElement($MenuItem)
    }
    catch {
        Write-Verbose "Failed to register MenuItem with ThemeEngine: $_"
    }
}
