function Set-DataGridStyle {
    <#
    .SYNOPSIS
        Applies theme-aware styling to a DataGrid control.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid,
        
        [ValidateSet('Single', 'Extended')]
        [string]$SelectionMode = 'Extended'
    )

    # Try to apply the Modern XAML style
    $styleApplied = $false
    try {
        if ($null -ne [System.Windows.Application]::Current) {
            $style = [System.Windows.Application]::Current.TryFindResource('ModernDataGridStyle')
            if ($null -ne $style) {
                $Grid.Style = $style
                $styleApplied = $true
            }
        }
    }
    catch {
        Write-Verbose "Failed to apply ModernDataGridStyle from resources: $_"
    }

    # Always apply non-style configuration
    $Grid.GridLinesVisibility = [System.Windows.Controls.DataGridGridLinesVisibility]::Horizontal
    $Grid.HeadersVisibility = [System.Windows.Controls.DataGridHeadersVisibility]::Column
    $Grid.RowHeaderWidth = 0
    $Grid.AutoGenerateColumns = $false
    $Grid.CanUserAddRows = $false
    $Grid.CanUserResizeRows = $false
    $Grid.CanUserResizeColumns = $true
    $Grid.CanUserSortColumns = $true
    $Grid.CanUserReorderColumns = $true
    $Grid.SelectionMode = [System.Windows.Controls.DataGridSelectionMode]::$SelectionMode
    $Grid.SelectionUnit = [System.Windows.Controls.DataGridSelectionUnit]::FullRow
    $Grid.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
    $Grid.FontSize = 12
    $Grid.Margin = [System.Windows.Thickness]::new(0)
    $Grid.AlternationCount = 2
    $Grid.BorderThickness = [System.Windows.Thickness]::new(1)
    
    # Row virtualization - without this, large datasets murder the UI
    $Grid.EnableRowVirtualization = $true
    $Grid.EnableColumnVirtualization = $true
    [System.Windows.Controls.VirtualizingPanel]::SetIsVirtualizing($Grid, $true)
    [System.Windows.Controls.VirtualizingPanel]::SetVirtualizationMode($Grid, [System.Windows.Controls.VirtualizationMode]::Recycling)
    [System.Windows.Controls.VirtualizingPanel]::SetScrollUnit($Grid, [System.Windows.Controls.ScrollUnit]::Pixel)
}
