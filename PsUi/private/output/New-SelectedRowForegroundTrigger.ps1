function New-SelectedRowForegroundTrigger {
    <#
    .SYNOPSIS
        DataTrigger swapping a cell TextBlock's foreground to SelectionTextBrush on the selected row.
    #>

    $binding = [System.Windows.Data.Binding]::new('IsSelected')
    $binding.RelativeSource = [System.Windows.Data.RelativeSource]::new(
        [System.Windows.Data.RelativeSourceMode]::FindAncestor,
        [System.Windows.Controls.DataGridRow], 1)
    $binding.FallbackValue = $false

    $trigger = [System.Windows.DataTrigger]::new()
    $trigger.Binding = $binding
    $trigger.Value   = $true
    [void]$trigger.Setters.Add([System.Windows.Setter]::new(
        [System.Windows.Controls.TextBlock]::ForegroundProperty,
        [System.Windows.DynamicResourceExtension]::new('SelectionTextBrush')))
    $trigger
}
