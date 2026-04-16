function Invoke-UiContent {
    <#
    .SYNOPSIS
        Executes a content scriptblock with enhanced error reporting.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Content,

        [string]$CallerName = 'Content'
    )

    # Extract original file and line from the scriptblock's AST for accurate error reporting
    $originalFile = 'script'
    $originalStartLine = 1
    try {
        $extent = $Content.Ast.Extent
        if ($extent.File) {
            $originalFile = Split-Path -Leaf $extent.File
        }
        $originalStartLine = $extent.StartLineNumber
    }
    catch { <# AST extent may not be available for dynamic scriptblocks #> }
    
    # Fall back to session's caller script info if AST didn't have file info
    if ($originalFile -eq 'script') {
        $session = [PsUi.SessionManager]::Current
        if ($session -and $session.CallerScriptName) {
            $originalFile = Split-Path -Leaf $session.CallerScriptName
            $originalStartLine = $session.CallerScriptLine
        }
    }

    try {
        . $Content
    }
    catch {
        Write-Debug "Error: $($_.Exception.GetType().Name) - $($_.Exception.Message)"
        
        # If already an ErrorRecord from nested Invoke-UiContent, just rethrow it
        if ($_.FullyQualifiedErrorId -eq 'PsUiContentError') {
            throw $_
        }
        
        $info    = $_.InvocationInfo
        $errMsg  = $_.Exception.Message
        
        # Extract the actual command that failed
        $cmd = 'unknown'
        if ($info -and $info.MyCommand) { $cmd = $info.MyCommand.Name }
        
        # Calculate actual line in original file
        $relLine    = if ($info) { $info.ScriptLineNumber } else { 0 }
        $actualLine = $originalStartLine + $relLine - 1
        
        # Build a helpful message but preserve the full error chain
        $msg = "[$originalFile`:$actualLine] Error in '$cmd': $errMsg"
        
        # Wrap in a proper ErrorRecord so debuggers can inspect the original exception
        $wrappedException = [System.Exception]::new($msg, $_.Exception)
        $errorRecord      = [System.Management.Automation.ErrorRecord]::new(
            $wrappedException,
            'PsUiContentError',
            [System.Management.Automation.ErrorCategory]::NotSpecified,
            $null
        )
        
        throw $errorRecord
    }
}
