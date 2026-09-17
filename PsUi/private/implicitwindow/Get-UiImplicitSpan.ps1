function Get-UiImplicitSpan {
    <#
    .SYNOPSIS
        Reads the calling script's own text and works out which of its statements belong inside
        the window. Throws instead of returning when taking them would rerun a write or open a
        second window.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CallerName
    )

    $owner     = $null
    $ownerText = $null
    $ownerType = $null
    $chain     = [System.Collections.Generic.List[object]]::new()

    # Walk Get-PSCallStack out of PsUi's own frames, then keep walking while the frame above is still script the window would be able to run.
    # The outermost frame is the one that knows a helper was called in a loop. Every frame on the way is kept, since each of them ran code before the control did
    foreach ($frame in (Get-PSCallStack)) {
        $command = $frame.InvocationInfo.MyCommand
        if (!$command) { continue }

        $module = $command.Module
        if ($module -and $module.Name -eq 'PsUi') { continue }

        if (!$command.ScriptBlock) { break }
        $text = $frame.Position.StartScriptPosition.GetFullScript()

        if (!$owner) {
            $owner     = $frame
            $ownerText = $text
            $ownerType = $command.CommandType
            $chain.Add(@{ Name = $command.Name; Ast = $command.ScriptBlock.Ast; Offset = $frame.Position.StartOffset })

            # A user module function owns its body, and past it is a script that never mentions the control.
            if ($module) { break }
            continue
        }

        if ($module) { break }

        # A dot sourced file is its own owner
        # A frame with no file behind it was built at runtime, and that is as far out as this'll go.
        if ($text -ne $ownerText) {
            if (!$owner.ScriptName -or !$frame.ScriptName) { break }

            # Whatever launched this script carries on after it, so all that sits up there is the one line that ran it, and taking that would put the whole file in the window.
            if ($ownerType -eq 'ExternalScript') { break }
            $ownerText = $text
        }
        $owner     = $frame
        $ownerType = $command.CommandType

        # A ForEach-Object block reports the script around it as its command, so it and the statement holding it arrive as two frames over one Ast. The outer statement wraps the inner offset, and that containment is what tells the pair apart from a function calling itself.
        $ast      = $command.ScriptBlock.Ast
        $previous = $chain[$chain.Count - 1]
        if ($ast -eq $previous.Ast -and $previous.Offset -ge $frame.Position.StartOffset -and $previous.Offset -lt $frame.Position.EndOffset) { continue }

        # Recursion hands back the same AST at every depth, so the offset is the only way to tell if this frame has already been seen.
        $seen = $false
        foreach ($hop in $chain) {
            if ($hop.Ast -eq $ast -and $hop.Offset -eq $frame.Position.StartOffset) { $seen = $true; break }
        }
        if ($seen) { continue }

        $chain.Add(@{ Name = $command.Name; Ast = $ast; Offset = $frame.Position.StartOffset })
    }

    if (!$owner) { return $null }

    $root = $owner.InvocationInfo.MyCommand.ScriptBlock.Ast
    if ($root -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $root = $root.Body }
    if (!$root) { return $null }

    $full = $root.Extent.StartScriptPosition.GetFullScript()
    if (!$full) { return $null }

    # Every offset below indexes into this one string, so a mismatch here would cut the content out of the wrong file.
    if ($ownerText -ne $full) { return $null }

    $offset = $owner.Position.StartOffset

    # An advanced function called in the pipeline puts the control in begin or process rather than end, so find the block the offset actually lands in.
    $block = $null
    foreach ($candidate in @($root.BeginBlock, $root.ProcessBlock, $root.EndBlock)) {
        if (!$candidate) { continue }
        if ($offset -ge $candidate.Extent.StartOffset -and $offset -lt $candidate.Extent.EndOffset) {
            $block = $candidate
            break
        }
    }

    if (!$block) { return $null }

    $statements = $block.Statements
    if (!$statements -or $statements.Count -eq 0) { return $null }

    $mine = -1
    for ($i = 0; $i -lt $statements.Count; $i++) {
        $extent = $statements[$i].Extent
        if ($offset -ge $extent.StartOffset -and $offset -lt $extent.EndOffset) {
            $mine = $i
            break
        }
    }

    if ($mine -lt 0) { return $null }

    $commands = Get-UiCommandList
    $stoppers = Get-UiWindowMakerList

    # A block handed to a PsUi command is PsUi's to run on a click, so nothing written inside it runs while the statement does.
    $deferrers = [System.Collections.Generic.HashSet[string]]::new([string[]]@($commands), [StringComparer]::OrdinalIgnoreCase)
    $deferrers.UnionWith($stoppers)

    # Scanning the whole psm1 would reach a module function's siblings, and the window only copies over functions no module owns, so a sibling call in there dies on a missing command.
    $helpers = Get-UiScriptHelperName -Root $root -Commands $commands -Stoppers $stoppers -Deferrers $deferrers -ScriptName $owner.ScriptName

    # A helper the run came through built the control by definition. The scan above reads files, and a helper reached some other way is not in any of them.
    foreach ($hop in $chain) {
        if ($hop.Name -and $hop.Ast -is [System.Management.Automation.Language.FunctionDefinitionAst]) { [void]$helpers.Builders.Add($hop.Name) }
    }

    # Forward to the last statement that still builds. Plain script in between comes along too.
    $last = $mine
    for ($i = $mine + 1; $i -lt $statements.Count; $i++) {
        $found = Get-UiStatementCommandList -Statement $statements[$i] -Deferrers $deferrers -BlockStorers $helpers.BlockStorers

        # A call through a variable carries no name of its own, so read the block it points at. A control in there builds the same as one written out in full.
        foreach ($invoked in (Get-UiInvokedBlock -Statement $statements[$i] -Statements $statements -Limit ($i - 1))) {
            foreach ($statement in (Get-UiBlockStatement -Block $invoked.Block)) {
                $found.AddRange((Get-UiStatementCommandList -Statement $statement -Deferrers $deferrers -BlockStorers $helpers.BlockStorers))
            }
        }

        $stops = $false
        foreach ($name in $found) {
            if ($stoppers.Contains($name) -or $helpers.Stoppers.Contains($name)) { $stops = $true; break }
        }

        # A window of its own would open while the implicit one is still being built.
        if ($stops) { break }

        foreach ($name in $found) {
            if ($commands.Contains($name) -or $helpers.Builders.Contains($name)) { $last = $i; break }
        }
    }

    # A block invoked through a variable was written somewhere above, and starting at the call alone would leave the window running & $null. Reach back for the assignment that made it, across everything taken so far.
    # A block can call another block, so each pass reads only what the last one pulled in, and it stops once a pass finds nothing below it.
    $first = $mine
    $low   = $mine
    $high  = $last
    while ($true) {
        $found = $first
        for ($i = $low; $i -le $high; $i++) {
            foreach ($invoked in (Get-UiInvokedBlock -Statement $statements[$i] -Statements $statements -Limit ($i - 1))) {
                if ($invoked.Index -lt $found) { $found = $invoked.Index }
            }
        }
        if ($found -ge $first) { break }
        $low   = $found
        $high  = $first - 1
        $first = $found
    }

    # The window runs the control's statement again. The PsUi commands and the script's own builders are exempt, since rerunning those is the point.
    # What is left to check is whatever else rode along in that statement.
    $exempt = [System.Collections.Generic.HashSet[string]]::new([string[]]@($commands), [StringComparer]::OrdinalIgnoreCase)
    $exempt.UnionWith($helpers.Builders)
    $repeat = Get-UiRepeatedCommand -Chain $chain -Statement $statements[$mine] -Exempt $exempt -Deferrers $deferrers -BlockStorers $helpers.BlockStorers
    if ($repeat) {
        throw "$CallerName sits inside $($repeat.Where), which already ran $($repeat.Name). PsUi would run that again to build the window, so it did not. Wrap the block in New-UiWindow -Content { } or move the control to its own statement."
    }

    # Everything the reach swept in ran once already, and so did every block those lines call through a variable.
    $inside = $chain[0].Offset
    $swept  = [System.Collections.Generic.List[object]]::new()
    for ($i = $first; $i -le $mine; $i++) {
        if ($i -lt $mine -and $statements[$i] -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $swept.Add(@{ Statement = $statements[$i]; Ran = $true; Live = $false }) }
        foreach ($invoked in (Get-UiInvokedBlock -Statement $statements[$i] -Statements $statements -Limit ($i - 1))) {
            $live = $invoked.Block.Extent.StartOffset -le $inside -and $inside -lt $invoked.Block.Extent.EndOffset
            foreach ($statement in (Get-UiBlockStatement -Block $invoked.Block)) { $swept.Add(@{ Statement = $statement; Ran = !$live; Live = $live }) }
        }
    }

    # One made up hop per statement, its offset parked at the end, so the whole statement reads as having run. Check again for repeated blocks.
    foreach ($entry in $swept) {
        if ($entry.Ran) {
            $ran    = @([pscustomobject]@{ Ast = $entry.Statement; Offset = $entry.Statement.Extent.EndOffset; Name = $null })
            $repeat = Get-UiRepeatedCommand -Chain $ran -Statement $entry.Statement -Exempt $exempt -Deferrers $deferrers -BlockStorers $helpers.BlockStorers
            if ($repeat) {
                throw "$CallerName is built from a block written further up, so the window would carry the lines in between and run $($repeat.Name) a second time. It did not. Move the assignment next to $CallerName, or wrap the block in New-UiWindow -Content { }."
            }
        }

        # A block that opens a window of its own would run while this one is still being built.
        foreach ($name in (Get-UiStatementCommandList -Statement $entry.Statement -Deferrers $deferrers -BlockStorers $helpers.BlockStorers)) {
            if (!$stoppers.Contains($name) -and !$helpers.Stoppers.Contains($name)) { continue }
            if ($entry.Live) { throw "$CallerName shares a block with $name, which opens a window of its own. The whole block goes in the window, so it did not build one. Move $name out of the block, or wrap the block in New-UiWindow -Content { }." }
            throw "$CallerName is built from a block written further up, and $name sits between the two. PsUi would open that window again to build this one, so it did not. Move the assignment next to $CallerName, or wrap the block in New-UiWindow -Content { }."
        }
    }

    # The statement the control sits in always goes in whole, so a window maker sharing it cannot be left out, and its window would open while this one is still being built.
    foreach ($name in (Get-UiStatementCommandList -Statement $statements[$mine] -Deferrers $deferrers -BlockStorers $helpers.BlockStorers)) {
        if (!$stoppers.Contains($name) -and !$helpers.Stoppers.Contains($name)) { continue }
        throw "$CallerName sits in the same statement as $name, which opens a window of its own. PsUi cuts that whole statement into the content, so it did not build one. Wrap the block in New-UiWindow -Content { } or move $name to its own statement."
    }

    $start = $statements[$first].Extent.StartOffset
    $end   = $statements[$last].Extent.EndOffset
    if ($end -gt $full.Length -or $start -ge $end) { return $null }

    [pscustomobject]@{
        Text       = $full.Substring($start, $end - $start)
        StartLine  = $statements[$first].Extent.StartLineNumber
        ScriptName = $owner.ScriptName
        # Complete says the read had one frame and reached the end of it, which is what lets the paste join look for more lines.
        Complete   = $chain.Count -eq 1 -and $last -eq $statements.Count - 1
        Commands   = $commands
        Stoppers   = $stoppers
        Deferrers  = $deferrers
        Helpers    = $helpers
    }
}
