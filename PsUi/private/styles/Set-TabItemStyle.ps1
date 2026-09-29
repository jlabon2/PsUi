function Set-TabItemStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.TabItem]$TabItem
    )

    # Try to use the ModernTabItemStyle from loaded XAML resources
    $styleApplied = $false
    try {
        $tabItemStyle = [PsUi.ThemeEngine]::FindStyleResource('ModernTabItemStyle')
        if ($null -ne $tabItemStyle) {
            $TabItem.Style = $tabItemStyle
            $styleApplied = $true
            Write-Verbose "Applied ModernTabItemStyle from XAML resources"
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