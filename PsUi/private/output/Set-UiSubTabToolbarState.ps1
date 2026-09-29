function Set-UiSubTabToolbarState {
    <#
    .SYNOPSIS
        Sets the filter box and column button for whichever sub-tab is showing.
    #>
    [CmdletBinding()]
    param(
        [object]$Tab,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox]$FilterBox
    )

    if (!$Tab) { return }

    # Until the index lands no row has _SearchText, so a search would empty the grid.
    $searchable          = $Tab.Tag -in @('Indexed', 'TextType', 'Dictionary')
    $FilterBox.IsEnabled = $searchable

    # Columns the index skipped are still on screen, so a search on one finds no rows and the tooltip lists them.
    # Tabs that never index have no entry here, and @($null).Count is 1, so the null goes before the count.
    $skipped = @($Tab.Resources['__SkippedColumns'] | Where-Object { $_ })
    $FilterBox.ToolTip = if (!$searchable) { 'Indexing...' }
                         elseif ($skipped.Count -gt 0) { "Filter results. Too slow to index, so a search will not match on them: $($skipped -join ', ')" }
                         else { 'Filter results' }
    if ($FilterBox.Tag.Watermark) {
        $FilterBox.Tag.Watermark.Text = if ($searchable) { 'Filter...' } else { 'Indexing...' }
    }

    # Dictionary grids have two fixed columns and no column set to pick from
    $colButton = $FilterBox.Tag.ColumnButton
    if ($colButton) {
        $showColumns          = ($null -ne (Get-UiSubTabGrid -Tab $Tab)) -and $Tab.Tag -ne 'Dictionary'
        $colButton.Visibility = if ($showColumns) { 'Visible' } else { 'Collapsed' }
    }
}
