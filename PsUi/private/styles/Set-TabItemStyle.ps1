function Set-TabItemStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.TabItem]$TabItem
    )

    # Try to use the ModernTabItemStyle from loaded XAML resources
    $styleApplied = $false
    try {
        if ([System.Windows.Application]::Current -and [System.Windows.Application]::Current.Resources) {
            if ([System.Windows.Application]::Current.Resources.Contains("ModernTabItemStyle")) {
                $TabItem.Style = [System.Windows.Application]::Current.Resources["ModernTabItemStyle"]
                $styleApplied = $true
                Write-Verbose "Applied ModernTabItemStyle from XAML resources"
            }
        }
    }
    catch {
        Write-Verbose "Failed to apply ModernTabItemStyle from resources: $_"
    }

    # Warn if XAML style not found (indicates ThemeEngine initialization issue)
    if (!$styleApplied) {
        Write-Warning "XAML style 'ModernTabItemStyle' not found. Ensure ThemeEngine.LoadStyles() was called."
    }
}