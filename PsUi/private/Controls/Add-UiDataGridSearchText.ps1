function Add-UiDataGridSearchText {
    <#
    .SYNOPSIS
        Attaches _SearchText: every property value concatenated. Filter matches against it later.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $PsObject,

        # Rebuild in place after a row change (edit commit, cell toggle). Without it an existing _SearchText wins and the filter keeps matching values from before the mutation.
        [switch]$Force
    )

    try {
        $existing = $PsObject.PSObject.Properties['_SearchText']
        if ($existing -and !$Force) { return }

        # 256 char initial capacity covers a typical row without reallocs.
        $sb = [System.Text.StringBuilder]::new(256)
        foreach ($prop in $PsObject.PSObject.Properties) {
            if ($prop.Name.StartsWith('_')) { continue }
            try {
                $val = $prop.Value
                if ($null -ne $val) {
                    [void]$sb.Append([string]$val)
                    [void]$sb.Append(' ')
                }
            }
            catch { }
        }
        if ($existing) { $existing.Value = $sb.ToString() }
        else {  $PsObject.PSObject.Properties.Add( [System.Management.Automation.PSNoteProperty]::new('_SearchText', $sb.ToString())) }
    }
    catch { Write-Debug "Add-UiDataGridSearchText failed: $_" }
}
