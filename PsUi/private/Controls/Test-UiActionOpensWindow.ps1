function Test-UiActionOpensWindow {
    <#
    .SYNOPSIS
        Does the action call something that opens a window? Tests for actual PsUi calls, not just comments or strings.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    # Out-Datagrid, Out-CSVDataGrid and Out-TextEditor stay off this list. Each runs its window on its own STA thread, so calling one from an async action is safe and the data fetch stays off the UI thread.
    $spawners = 'New-UiWindow', 'New-UiChildWindow', 'New-UiTool'

    # The same filter three session helpers keep, guarded on itself the way they guard it. A fresh block would make FindAll convert a new Func on every button.
    if (!$script:uiCommandAstFilter) {
        $script:uiCommandAstFilter = {
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }
    }

    # FindAll builds the whole list before the loop starts.
    foreach ($command in $Action.Ast.FindAll($script:uiCommandAstFilter, $true)) {
        $name = Get-UiPlainCommandName -Command $command
        if (!$name) { continue }
        if ($name -in $spawners) { return $true }

        # An alias is evaluated by what it points at. An aliased win spawner slipping through puts a window on the async thread, where it dies pathetically... 
        # A false positive results in a button running sync that could have run async, and that is the better way to be wrong.
        $alias = Get-Command -Name $name -CommandType Alias -ErrorAction SilentlyContinue
        if ($alias -and $alias.Definition -in $spawners) { return $true }
    }
    return $false
}
