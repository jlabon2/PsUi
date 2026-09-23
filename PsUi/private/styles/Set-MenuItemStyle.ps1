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

    $styleApplied = $false
    try {
        $style = [PsUi.ThemeEngine]::FindStyleResource([System.Windows.Controls.MenuItem])
        if ($null -ne $style -and $style -is [System.Windows.Style]) {
            $MenuItem.Style = $style
            $styleApplied = $true
        }
    }
    catch { Write-Verbose "Failed to apply MenuItem style from resources: $_" }

    # If XAML style wasn't applied, set properties manually with hover handlers
    if (!$styleApplied) {
        $MenuItem.Background = [System.Windows.Media.Brushes]::Transparent
        $MenuItem.Foreground = ConvertTo-UiBrush $Colors.ControlFg
        $MenuItem.Padding    = [System.Windows.Thickness]::new(10, 6, 10, 6)
        $MenuItem.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
        $MenuItem.FontSize   = 12

        # Colors are read on hover, so a theme switch doesn't need a second pair of handlers to update the hover color
        Add-UiStyleHandler -Control $MenuItem -Key '__MenuHoverHooked' -Attach {
            param($item)
            $item.Add_MouseEnter({
                param($sender, $eventArgs)
                $currentColors = Get-ThemeColors
                $sender.Background = ConvertTo-UiBrush $currentColors.ItemHover
            })

            $item.Add_MouseLeave({
                param($sender, $eventArgs)
                $sender.Background = [System.Windows.Media.Brushes]::Transparent
            })
        }
    }

    foreach ($subItem in $MenuItem.Items) {
        if ($subItem -is [System.Windows.Controls.MenuItem]) { Set-MenuItemStyle -MenuItem $subItem -Colors $Colors }
    }

    try { [PsUi.ThemeEngine]::RegisterElement($MenuItem) }
    catch { Write-Verbose "Failed to register MenuItem with ThemeEngine: $_" }
}
