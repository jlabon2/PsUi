function Get-UiPlainCommandName {
    <#
    .SYNOPSIS
        Strips the module prefix off a full command name, so PsUi\New-UiLabel and New-UiLabel
        are the same.
    #>
    [OutputType([string])]
    param([System.Management.Automation.Language.CommandAst]$Command)

    $name = $Command.GetCommandName()
    if (!$name) { return $null }

    $slash = $name.LastIndexOf('\')

    if ($slash -lt 0) { return $name }
    return $name.Substring($slash + 1)
}
