function ConvertTo-UiDataGridLength {
    <#
    .SYNOPSIS
        Column width grammar shared by every column builder: 'Star', '*', '2*', or a number.
    #>
    [CmdletBinding()]
    [OutputType([System.Windows.Controls.DataGridLength])]
    param(
        $Width
    )

    if ($Width -is [string]) {
        if ($Width -eq 'Auto') { return [System.Windows.Controls.DataGridLength]::Auto }
        if ($Width -eq 'Star' -or $Width -eq '*') {
            return [System.Windows.Controls.DataGridLength]::new(1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
        }
        if ($Width -match '^(\d+(?:\.\d+)?)\*$') {
            return [System.Windows.Controls.DataGridLength]::new([double]$matches[1], [System.Windows.Controls.DataGridLengthUnitType]::Star)
        }
        $parsed = 0.0
        if ([double]::TryParse($Width, [ref]$parsed)) { return [System.Windows.Controls.DataGridLength]::new($parsed) }
        Write-Warning "ConvertTo-UiDataGridLength: unrecognized width '$Width' - using Auto. Pass a number, 'Star', '*', or 'N*'."
        return [System.Windows.Controls.DataGridLength]::Auto
    }
    if ($Width -is [System.ValueType]) {
        $numeric = $Width -as [double]
        if ($null -ne $numeric) { return [System.Windows.Controls.DataGridLength]::new($numeric) }
    }
    return [System.Windows.Controls.DataGridLength]::Auto
}
