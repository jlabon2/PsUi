function Get-UiRepeatedCommand {
    <#
    .SYNOPSIS
        Walks the statements PsUi is about to rerun to build an implicit window, looking for a
        command that changes something and has already run once. A hit refuses the build, so a
        Remove-Item sharing a line with the control, or sitting in a loop that already reached
        it, gets an error rather than a second run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Chain,

        [Parameter(Mandatory)]
        [System.Management.Automation.Language.StatementAst]$Statement,

        [Parameter(Mandatory)]
        $Exempt,

        [Parameter(Mandatory)]
        $Deferrers,

        $BlockStorers
    )

    # A fresh block makes FindAll convert a new Func every call, and that costs more than the walk it drives.
    # One guard each. Get-UiStatementCommandList and Get-UiInvokedBlock write uiCommandAstFilter too, and keying the other three off that one name leaves them null whenever either of those ran first.
    if (!$script:uiCommandAstFilter) {
        $script:uiCommandAstFilter = {
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }
    }

    if (!$script:uiWriteAstFilter) {
        $script:uiWriteAstFilter = {
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -or
            $node -is [System.Management.Automation.Language.FileRedirectionAst]
        }
    }

    if (!$script:uiStatementAstFilter) {
        $script:uiStatementAstFilter = {
            param($node)
            $node -is [System.Management.Automation.Language.StatementAst]
        }
    }

    if (!$script:uiLoopCommandFilter) {
        $script:uiLoopCommandFilter = {
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and (Get-UiPlainCommandName -Command $node) -in 'ForEach-Object', '%', 'foreach'
        }
    }

    # A Get or a Test only reads, and so does the rest of those kind of commands. These verbs mess with something, and a second run does it again.
    $mutating = 'Remove', 'Set', 'New', 'Add', 'Clear', 'Move', 'Copy', 'Rename', 'Update', 'Install', 'Uninstall', 'Start', 'Stop', 'Restart',
                'Send', 'Invoke', 'Push', 'Register', 'Unregister', 'Enable', 'Disable', 'Grant', 'Revoke', 'Reset', 'Restore', 'Save', 'Submit',
                'Publish', 'Export', 'Import', 'Write'

    # These here carry one of those verbs and are harmless to run twice. Making an object or reading a file is not the kind of New or Import the list above is looking for.
    # A loop full of them is the ordinary way to build a row per item.
    # Add-Member misses the cut because it changes an object the statement did not make, and a second runthrough over the same one is a duplicate member error.
    $harmless = 'Start-Sleep', 'Import-Module', 'Write-Host', 'Write-Output', 'Write-Verbose', 'Write-Debug', 'Write-Warning', 'Write-Information',
                'Write-Progress', 'Write-Error', 'Set-StrictMode', 'New-Object', 'New-TimeSpan', 'New-Guid', 'Import-Csv', 'Import-Clixml',
                'Import-PowerShellDataFile', 'Import-LocalizedData'
    $loops    = @(
        [System.Management.Automation.Language.ForEachStatementAst], [System.Management.Automation.Language.ForStatementAst],
        [System.Management.Automation.Language.WhileStatementAst], [System.Management.Automation.Language.DoWhileStatementAst],
        [System.Management.Automation.Language.DoUntilStatementAst]
    )
    $labels   = @{
        ForEachStatementAst = 'a foreach'; ForStatementAst = 'a for'; WhileStatementAst = 'a while'; DoWhileStatementAst = 'a do loop'
        DoUntilStatementAst = 'a do loop'; IfStatementAst = 'an if'; SwitchStatementAst = 'a switch'; TryStatementAst = 'a try'; PipelineAst = 'the same pipeline'
    }

    # Innermost frame first. Each ran from the top of its body to the call, or through its whole loop when the call sits in one.
    for ($i = 0; $i -lt $Chain.Count; $i++) {
        $hop       = $Chain[$i]
        $outermost = $i -eq $Chain.Count - 1
        $container = if ($outermost) { $Statement } elseif ($hop.Ast -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $hop.Ast.Body } else { $hop.Ast }
        if (!$container) { continue }
        $offset    = $hop.Offset
        $end       = $offset
        $loopStart = $offset
        $innerLoop = $null

        # Earlier trips round a loop ran what comes after the call as well. A ForEach-Object block counts as a loop.
        foreach ($candidate in $container.FindAll($script:uiStatementAstFilter, $true)) {
            $isLoop = $false
            foreach ($type in $loops) { if ($candidate -is $type) { $isLoop = $true; break } }
            if (!$isLoop -and $candidate -is [System.Management.Automation.Language.PipelineAst]) {
                $isLoop = @($candidate.FindAll($script:uiLoopCommandFilter, $true)).Count -gt 0
            }
            if (!$isLoop -or $candidate.Extent.StartOffset -gt $offset -or $offset -ge $candidate.Extent.EndOffset) { continue }
            if ($candidate.Extent.EndOffset -gt $end) { $end = $candidate.Extent.EndOffset }
            if ($candidate.Extent.StartOffset -lt $loopStart) { $loopStart = $candidate.Extent.StartOffset }
            if (!$innerLoop -or $candidate.Extent.Text.Length -lt $innerLoop.Extent.Text.Length) { $innerLoop = $candidate }
        }

        foreach ($command in $container.FindAll($script:uiWriteAstFilter, $true)) {
            if ($command.Extent.EndOffset -gt $end) { continue }

            # A redirect writes a file and carries no command name, so the verb test below has nothing to read and the file path is all there is to go on.
            $redirect = $command -as [System.Management.Automation.Language.FileRedirectionAst]

            if ($redirect) {
                # 2>$null throws the stream away instead of writing anything, and it is the everyday way to quieten a command, so it is no write.
                $target = $redirect.Location -as [System.Management.Automation.Language.VariableExpressionAst]
                if ($target -and $target.VariablePath.UserPath -eq 'null') { continue }
                $name = "a redirect to $($redirect.Location.Extent.Text)"
            }

            else {
                $name = Get-UiPlainCommandName -Command $command
                if (!$name) { continue }
                if ($Exempt.Contains($name) -or $name -in $harmless) { continue }
            }

            # A block handed to a PsUi command is PsUi's to run later. The body of a function defined here never ran at all.
            $skip = $false
            $node = $command.Parent
            while ($node -and $node -ne $container) {
                if ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $skip = $true; break }
                if ($node -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                    # A block that has not run yet cannot have run a write twice. The deferrers are the PsUi command names, the same set the statement scan asks about.
                    # The exempt set would not do here, since it carries the script's own builders, and a block handed to one of those is judged by the storer set instead.
                    if (Test-UiDeferredBlock -Block $node -Deferrers $Deferrers -BlockStorers $BlockStorers) { $skip = $true; break }
                }

                # An if takes one leg of the journey. With the control in another arm of that same if, this one never ran, unless a loop around the pair could have sent an earlier trip down here.
                # Switch is left out because it runs every clause that matches, and over an array it runs several of them whatever the conditions say.
                # So the AST cannot show which clause the run skipped.
                if ($node -is [System.Management.Automation.Language.StatementBlockAst] -and $node.Parent -is [System.Management.Automation.Language.IfStatementAst]) {
                    $branch = $node.Parent
                    $holds  = $node.Extent.StartOffset -le $offset -and $offset -lt $node.Extent.EndOffset
                    if (!$holds -and $branch.Extent.StartOffset -lt $loopStart -and $offset -lt $branch.Extent.EndOffset) { $skip = $true; break }
                }
                $node = $node.Parent
            }
            if ($skip) { continue }

            # An alias is judged by what it points at, exempt list included. No dash in the name means a native program or a plain word, and those are left alone.
            if (!$redirect) {
                $alias = Get-Command -Name $name -CommandType Alias -ErrorAction SilentlyContinue
                if ($alias) { $name = $alias.Definition }
                if ($Exempt.Contains($name) -or $name -in $harmless -or $name -notmatch '^([A-Za-z]+)-') { continue }
                if ($Matches[1] -notin $mutating -and $name -ne 'Out-File') { continue }
            }

            # The error reads better with the loop the control sits in than with the statement around it.
            $where = if (!$outermost) { $hop.Name } elseif ($innerLoop) { $labels[$innerLoop.GetType().Name] } else { $labels[$Statement.GetType().Name] }
            if (!$where) { $where = 'the same statement' }
            return @{ Name = $name; Where = $where }
        }
    }
    return $null
}
