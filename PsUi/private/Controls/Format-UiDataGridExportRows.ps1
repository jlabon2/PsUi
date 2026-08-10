function Format-UiDataGridExportRows {
    <#
    .SYNOPSIS
        Projects DataGrid rows to PSCustomObjects with the requested properties. With -Sanitize, prefixes formula prone leading chars with an apostrophe.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Items,

        [string[]]$Properties,

        [switch]$Sanitize
    )

    if (!$Properties -or $Properties.Count -eq 0) {
        $first = $null
        foreach ($candidate in $Items) { if ($null -ne $candidate) { $first = $candidate; break } }
        if ($null -eq $first) { return }
        $Properties = if ($first -is [string] -or $first -is [System.ValueType]) { @('.') }
                      else { @($first.PSObject.Properties.Name | Where-Object { !$_.StartsWith('_') }) }
    }

    foreach ($row in $Items) {
        $projected = [ordered]@{}
        foreach ($prop in $Properties) {

            $isSelf = $prop -eq '.'
            $val    = $null
            if ($isSelf) { $val = $row }
            else {
                try { $val = $row.$prop } catch { Write-Debug "Export read of '$prop' failed: $_" }
            }

            if ($val -is [System.Collections.ICollection] -and $val -isnot [string]) {
                $val = @(foreach ($element in $val) { [string]$element }) -join ', '
            }

            if ($Sanitize -and $null -ne $val) {
                $text = [string]$val
                if ($text.Length -gt 0) {
                    $head = $text[0]
                    # Excel runs formulas starting with =/+/-/@. Tab, CR, LF are Microsoft's documented "macro injection" prefixes. Maybe more?
                    if ($head -eq '=' -or $head -eq '+' -or $head -eq '-' -or $head -eq '@' -or $head -eq "`t" -or $head -eq "`r" -or $head -eq "`n") { $val = "'" + $text }
                }
            }

            $projected[$(if ($isSelf) { 'Value' } else { $prop })] = $val
        }
        [pscustomobject]$projected
    }
}
