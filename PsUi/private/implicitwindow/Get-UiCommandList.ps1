function Get-UiCommandList {
    <#
    .SYNOPSIS
        Every PsUi command except the window openers. Seeing one of these in a statement means
        there is still window left to build.
    #>
    [CmdletBinding()]
    param()

    if ($script:uiCommandList) { return ,$script:uiCommandList }

    $commands = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $module   = $ExecutionContext.SessionState.Module
    if ($module) {
        $makers = Get-UiWindowMakerList
        foreach ($name in $module.ExportedCommands.Keys) {
            if (!$makers.Contains($name)) { [void]$commands.Add($name) }
        }
    }

    # A list built with no module behind it would persist for the session.
    if ($module) { $script:uiCommandList = $commands }
    return ,$commands
}
