function Invoke-UiContent {
    <#
    .SYNOPSIS
        Dot sources the content block and puts the file and line on any error that comes back.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Content,

        [string]$CallerName = 'Content'
    )

    # A block built at runtime has no File on its extent, which is why the fallback below is needed
    $originalFile      = 'script'
    $originalStartLine = 1
    try {
        $extent = $Content.Ast.Extent
        if ($extent.File) { $originalFile = Split-Path -Leaf $extent.File }
        $originalStartLine = $extent.StartLineNumber
    }
    # A block built at runtime has no Extent, so the defaults above are used.
    catch { }

    # With the extent blank, the session record of the calling script is all that is left to id.
    if ($originalFile -eq 'script') {
        $session = [PsUi.SessionManager]::Current
        if ($session -and $session.CallerScriptName) {
            $originalFile      = Split-Path -Leaf $session.CallerScriptName
            $originalStartLine = $session.CallerScriptLine
        }
    }

    try { . $Content }
    catch {
        Write-Debug "Error: $($_.Exception.GetType().Name) - $($_.Exception.Message)"

        if ($_.FullyQualifiedErrorId -eq 'PsUiContentError') { throw $_ }

        $info    = $_.InvocationInfo
        $errMsg  = $_.Exception.Message

        $cmd = 'unknown'
        if ($info -and $info.MyCommand) { $cmd = $info.MyCommand.Name }

        $relLine    = if ($info) { $info.ScriptLineNumber } else { 0 }
        $actualLine = $originalStartLine + $relLine - 1

        $msg = "[$originalFile`:$actualLine] Error in '$cmd': $errMsg"

        # ErrorRecord instead of a plain throw, else a debugger only gets the string
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
