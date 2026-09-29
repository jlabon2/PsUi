function New-UiImplicitContent {
    <#
    .SYNOPSIS
        Turns the statements PsUi took into the scriptblock it passes to New-UiWindow as -Content.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Span
    )

    # $PSScriptRoot and $PSCommandPath are both reserved, so the capture never has them and the new runspace gets them empty.
    $prefix = ''
    if ($Span.ScriptName) { $prefix = New-UiPathPrefix -ScriptName $Span.ScriptName }

    # The blank lines put the first statement back on the line number it has in the file.
    $text   = $Span.Text
    $blanks = $Span.StartLine - 1
    if ($blanks -gt 0) { $text = ("`n" * $blanks) + $text }

    # The read starts at the first PsUi control rather than at the top of the file, so a using statement never comes along and a script that leaned on one for a short type name breaks in the window.
    return [scriptblock]::Create($prefix + $text)
}
