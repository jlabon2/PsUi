function Invoke-UiImplicitWindow {
    <#
    .SYNOPSIS
        Called when a control finds no session. This decides whether building a window makes sense
        at all, and when it does, reads the calling script and builds one. Returns how the
        script should end, or $false when it leaves and allows the a no-window error to
        throw instead.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CallerName,

        [Parameter(Mandatory)]
        [System.Management.Automation.SessionState]$CallerState,

        [System.Management.Automation.PSCmdlet]$CallerCmdlet
    )

    # A PsUi background thread reports no session too, and a window holds a pool thread on Join.
    if ([PsUi.SessionManager]::CurrentSessionId -ne [Guid]::Empty) { return $false }
    if ($Global:__PsUiSessionId) { return $false }
    if ($Global:AsyncExecutor) { return $false }
    if ([PsUi.AsyncExecutor]::CurrentExecutor) { return $false }

    # No interactive desktop to show a window on, and New-UiWindow holds its thread until one closes.
    if (![Environment]::UserInteractive) { return $false }
    if ($Host.Name -eq 'ServerRemoteHost') { return $false }

    foreach ($argument in [Environment]::GetCommandLineArgs()) {
        if ($argument -notmatch '^(--?|/)(.+)$') { continue }
        $switch = $Matches[2]
        if ('file'.StartsWith($switch, [System.StringComparison]::OrdinalIgnoreCase)) { break }
        if ($switch.Length -ge 4 -and 'noninteractive'.StartsWith($switch, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    }

    # For a test run that would rather have the old error than a window.
    if ($env:PsUiNoImplicitWindow) { return $false }

    $span = Get-UiImplicitSpan -CallerName $CallerName
    if (!$span) { return $false }

    # A script file is a submission. At a cmd the read covers only the line that was typed. But pasting multiple lines?
    # A console without bracketed paste sends a paste's contents over one line at a time, so the rest of it is still in PSReadLine's queue while the first line runs, resulting in a window for each call.
    # Those lines join this window instead of each opening one of their own.
    if (!$span.ScriptName -and $span.Complete) { $span = Join-UiPendingInput -Span $span }

    # A window built from a file takes its title from the file. At a prompt there is no file to take one from, so the title says what built it rather than fall back on New-UiWindow's UI
    $title = 'PsUi'
    if ($span.ScriptName) { $title = [System.IO.Path]::GetFileNameWithoutExtension($span.ScriptName) }

    $where = "line $($span.StartLine)"
    if ($span.ScriptName) { $where = "$($span.ScriptName):$($span.StartLine)" }
    Write-Verbose "$CallerName has no window, so PsUi is building one around $where. The script stops when it closes."

    $content = New-UiImplicitContent -Span $span

    # A module literal block would capture PsUi's variables rather than the script's, so the block is built from parsed text instead.
    # Parsed rather than Created so the call carries the script's name. New-UiWindow reads MyInvocation for the file it puts in front of a content error.
    # A created block leaves that empty, and the error comes out saying script.
    $tokens = $null
    $errors = $null
    $call   = 'New-UiWindow -Title $args[0] -Content $args[1] 2>&1 | & $args[2]'
    $parsed = [System.Management.Automation.Language.Parser]::ParseInput($call, $span.ScriptName, [ref]$tokens, [ref]$errors)

    # InvokeScript drops New-UiWindow's error stream into $Error, ergo the 2>&1
    $writer = $PSCmdlet
    if ($CallerCmdlet) { $writer = $CallerCmdlet }
    $relay = {
        process {
            if ($_ -isnot [System.Management.Automation.ErrorRecord]) { return }

            # The redirect already put it in $Error once
            $global:Error.Remove($_)
            $writer.WriteError($_)
        }
    }.GetNewClosure()

    # InvokeScript hands a stopped window back as a MethodInvocationException
    try {
        $null = $ExecutionContext.InvokeCommand.InvokeScript($CallerState, $parsed.GetScriptBlock(), $title, $content, $relay)
    }
    catch [System.Management.Automation.MethodInvocationException] {
        $inner = $_.Exception.InnerException
        if ($inner -isnot [System.Management.Automation.IContainsErrorRecord]) { throw }

        # Every wrap on the way out left its own rec in $Error
        $source = $inner.ErrorRecord
        $chain  = [System.Collections.Generic.HashSet[object]]::new()
        for ($link = $_.Exception; $link; $link = $link.InnerException) { $null = $chain.Add($link) }
        if ($source.Exception) { $null = $chain.Add($source.Exception) }
        $stale = @($global:Error | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $chain.Contains($_.Exception) })
        foreach ($record in $stale) { $global:Error.Remove($record) }

        # New-UiWindow's name from the id, need to add the cotnrol name
        $errorId   = $source.FullyQualifiedErrorId.Split(',')[0]
        $exception = [System.Exception]::new($source.ToString(), $source.Exception)
        $failure   = [System.Management.Automation.ErrorRecord]::new($exception, $errorId, $source.CategoryInfo.Category, $source.TargetObject)

        $stamp = [System.Management.Automation.ErrorRecord].GetMethod('SetInvocationInfo', [System.Reflection.BindingFlags]'Instance, NonPublic')
        if ($stamp) { $null = $stamp.Invoke($failure, @($writer.MyInvocation)) }

        # The control's -ErrorAction SilentlyContinue gets this far and would silent the throw
        $ErrorActionPreference = 'Stop'
        throw $failure
    }

    # exit ends the nearest running script file with code 0 and leaves the console it ran from alone.
    # With no script file anywhere on the stack, a module function called at a prompt, exit would take the console with it, so that one gets its pipeline stopped instead.
    foreach ($frame in (Get-PSCallStack)) {
        if ($frame.InvocationInfo.MyCommand.CommandType -eq 'ExternalScript') { return 'Exit' }
    }
    return 'Stop'
}
