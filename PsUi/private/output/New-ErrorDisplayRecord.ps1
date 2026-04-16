function New-ErrorDisplayRecord {
    <#
    .SYNOPSIS
        Creates a PSCustomObject for displaying errors in the Errors DataGrid.
    #>
    param(
        [Parameter(Mandatory)]
        $ErrorRecord
    )

    # Detect if this is a raw System.Management.Automation.ErrorRecord vs PSErrorRecord wrapper
    $isRawErrorRecord = $ErrorRecord -is [System.Management.Automation.ErrorRecord]

    if ($isRawErrorRecord) {
        # Extract values from native ErrorRecord structure
        $message       = if ($ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { $ErrorRecord.ToString() }
        $lineNumber    = if ($ErrorRecord.InvocationInfo) { $ErrorRecord.InvocationInfo.ScriptLineNumber } else { 0 }
        $category      = if ($ErrorRecord.CategoryInfo) { $ErrorRecord.CategoryInfo.Category.ToString() } else { 'Error' }
        $scriptName    = if ($ErrorRecord.InvocationInfo) { $ErrorRecord.InvocationInfo.ScriptName } else { $null }
        $line          = if ($ErrorRecord.InvocationInfo) { $ErrorRecord.InvocationInfo.Line } else { $null }
        $stackTrace    = $ErrorRecord.ScriptStackTrace
        $errorId       = $ErrorRecord.FullyQualifiedErrorId
        $innerEx       = if ($ErrorRecord.Exception -and $ErrorRecord.Exception.InnerException) { $ErrorRecord.Exception.InnerException } else { $null }
    }
    else {
        # PSErrorRecord wrapper - use direct properties
        $message       = if ($ErrorRecord.Message) { $ErrorRecord.Message } else { $ErrorRecord.ToString() }
        $lineNumber    = if ($ErrorRecord.LineNumber -gt 0) { $ErrorRecord.LineNumber } else { 0 }
        $category      = if ($ErrorRecord.Category) { $ErrorRecord.Category } else { 'Error' }
        $scriptName    = $ErrorRecord.ScriptName
        $line          = $ErrorRecord.Line
        $stackTrace    = $ErrorRecord.ScriptStackTrace
        $errorId       = $ErrorRecord.FullyQualifiedErrorId
        $innerEx       = $ErrorRecord.InnerException
    }

    # Build searchable details combining all error info
    $detailParts = @(
        $message
        $category
        $scriptName
        $line
        $stackTrace
        $errorId
        if ($innerEx) { $innerEx.ToString() }
    ) | Where-Object { $_ }
    $errorDetails = $detailParts -join ' '

    return [PSCustomObject]@{
        Time                  = if ($ErrorRecord.Timestamp) { $ErrorRecord.Timestamp.ToString('HH:mm:ss') } else { (Get-Date).ToString('HH:mm:ss') }
        LineNumber            = if ($lineNumber -gt 0) { $lineNumber } else { '' }
        Category              = $category
        Message               = $message
        ScriptName            = $scriptName
        Line                  = $line
        ScriptStackTrace      = $stackTrace
        FullyQualifiedErrorId = $errorId
        InnerException        = $innerEx
        RawRecord             = $ErrorRecord
        _ErrorDetails         = $errorDetails
    }
}
