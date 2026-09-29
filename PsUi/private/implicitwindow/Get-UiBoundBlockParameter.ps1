function Get-UiBoundBlockParameter {
    <#
    .SYNOPSIS
        Works out which parameter a block binds to, by the name written in front of it when
        there is one and by position otherwise.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.CommandAst]$Command,

        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ScriptBlockExpressionAst]$Block
    )

    $name = Get-UiPlainCommandName -Command $Command
    if (!$name) { return $null }

    if (!$script:uiBlockParameterFacts) {
        $script:uiBlockParameterFacts = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    }

    $facts = $null
    if (!$script:uiBlockParameterFacts.TryGetValue($name, [ref]$facts)) {
        $facts    = @{ Positional = $null; Switches = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase) }
        $resolved = Get-Command -Name $name -Module 'PsUi' -ErrorAction SilentlyContinue

        if ($resolved) {
            $lowest = [int]::MaxValue
            foreach ($parameter in $resolved.Parameters.Values) {
                if ($parameter.SwitchParameter) { [void]$facts.Switches.Add($parameter.Name) }
                if ($parameter.ParameterType -ne [scriptblock]) { continue }
                foreach ($attribute in $parameter.Attributes) {
                    if ($attribute -isnot [System.Management.Automation.ParameterAttribute]) { continue }
                    if ($attribute.Position -lt 0 -or $attribute.Position -ge $lowest) { continue }
                    $lowest           = $attribute.Position
                    $facts.Positional = $parameter.Name
                }
            }
        }
        $script:uiBlockParameterFacts[$name] = $facts
    }

    # -Content { } arrives as the parameter element then the block, so the element in front is the parameter it binds to. A switch in front takes no value, and a block behind one is really binding by position.
    # Names are read as written, so an abbreviated -Cont or -Full misses both tests and the block falls through as deferred. The cost is a control left out, which is prolly on the safe side.
    $index = $Command.CommandElements.IndexOf($Block)
    if ($index -gt 0) {
        $previous = $Command.CommandElements[$index - 1] -as [System.Management.Automation.Language.CommandParameterAst]
        if ($previous -and !$previous.Argument -and !$facts.Switches.Contains($previous.ParameterName)) { return $previous.ParameterName }
    }

    # New-UiPanel { } binds by position, and no PsUi command takes two blocks that way.
    return $facts.Positional
}
