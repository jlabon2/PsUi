function Show-UiHelperError {
    <#
    .SYNOPSIS
        Reports a HelperOptions click failure - transcript warning plus a themed error dialog.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory)]
        [string]$Mode
    )

    $msg   = "$ErrorRecord"
    # Strip the ", <No file>:" filler PS sticks into ScriptStackTrace - useless noise in a dialog.
    $trace = ($ErrorRecord.ScriptStackTrace -split "`r?`n" | ForEach-Object {
        ($_ -replace ', <No file>:', '').Trim()
    }) -join "`r`n"

    Write-Warning "HelperOptions on $Mode invalid: $msg`r`n$trace"

    $dlg = @{
        Title   = "$Mode error"
        Icon    = 'Error'
        Message = "$msg`r`n`r`n$trace"
    }
    Show-UiMessageDialog @dlg
}
