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

    # If the block came from a file, its lines already number from the top of it
    $originalFile = 'script'
    $lineOffset   = 0
    try {
        $extent = $Content.Ast.Extent
        if ($extent.File) { $originalFile = Split-Path -Leaf $extent.File }
    }
    # It has no Extent either, so the defaults above work
    catch { }

    # With the extent blank, the session record of the calling script is all that is left to id.
    if ($originalFile -eq 'script') {
        $session = [PsUi.SessionManager]::Current
        if ($session -and $session.CallerScriptName) {
            $originalFile = Split-Path -Leaf $session.CallerScriptName
            $lineOffset   = $session.CallerScriptLine - 1
        }
    }

    # PsUi commands here follow the block's $ErrorActionPreference, with Continue read as Stop. If a control can't build it stops the window, unless SilentlyContinue leaves it out.
    # New-UiWindow sets a ContentErrorPreference in PsUi's script scope while its content builds
    $blockPreference = Get-Variable -Name ErrorActionPreference -Scope Script -ErrorAction Ignore
    if ($blockPreference -isnot [PsUi.ContentErrorPreference]) {
        $blockPreference = $null
        $containerCmdlet = (Get-Variable -Name PSCmdlet -Scope 1 -ErrorAction Ignore).Value

        # If PsUi built the block for itself, the plain Stop below will hold
        if ($containerCmdlet -and $containerCmdlet.SessionState.Module -ne $ExecutionContext.SessionState.Module) {
            $blockPreference = [PsUi.ContentErrorPreference]::new($containerCmdlet.SessionState, $false)
        }
    }

    # The containers' -ErrorAction Stop reaches this function too, and the catch below needs it or New-UiChildWindow -ErrorAction SilentlyContinue swallows a throw
    $ErrorActionPreference = 'Stop'

    # The block's controls look in here before they reach the Stop above
    try {
        & {
            if ($blockPreference) { $ExecutionContext.SessionState.PSVariable.Set($blockPreference) }
            . $Content
        }
    }
    catch {
        Write-Debug "Error: $($_.Exception.GetType().Name) - $($_.Exception.Message)"

        if ($_.FullyQualifiedErrorId -eq 'PsUiContentError') { throw $_ }

        $info     = $_.InvocationInfo
        $errMsg   = $_.Exception.Message
        $relLine  = if ($info) { $info.ScriptLineNumber } else { 0 }
        $fromFile = if ($info) { $info.ScriptName } else { $null }

        # The block's frame sits just past this function and the & block
        $cmd     = $null
        $frames  = @($_.ScriptStackTrace -split '\r?\n')
        $blockAt = $frames.Count - @(Get-PSCallStack).Count - 2
        if ($blockAt -ge 0 -and $frames[$blockAt] -match '^at .+?, (.+): line (\d+)$') {
            $relLine  = [int]$Matches[2]
            $fromFile = if ($Matches[1] -ne '<No file>') { $Matches[1] } else { $null }
        }
        for ($i = $blockAt - 1; $i -ge 0; $i--) {
            if ($frames[$i] -notmatch '^at (.+?), ') { continue }
            if (!(Get-Command -Name $Matches[1] -Module PsUi -ErrorAction Ignore)) { continue }
            $cmd = $Matches[1]
            break
        }
        if (!$cmd -and $info -and $info.MyCommand) { $cmd = $info.MyCommand.Name }

        $where = "$originalFile`:$($relLine + $lineOffset)"
        if ($fromFile) { $where = "$(Split-Path -Leaf $fromFile):$relLine" }

        $msg = "[$where] $errMsg"
        if ($cmd) { $msg = "[$where] Error in '$cmd': $errMsg" }

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
