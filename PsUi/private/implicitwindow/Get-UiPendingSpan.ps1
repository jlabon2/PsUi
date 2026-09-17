function Get-UiPendingSpan {
    <#
    .SYNOPSIS
        Decides how many of the queued paste lines belong in the window. Stricter than the scan
        used on a file, because a queued line has not been submitted yet, so the take ends at
        the first line that builds nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        $Span
    )

    # A parse error means a line is half typed or still arriving, so drop the last line and try again until what is left parses out.
    $tokens = $null
    $errors = $null
    $ast    = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)

    while ($errors) {

        $cut = $Text.TrimEnd([char]10).LastIndexOf([char]10)

        $start = $errors[0].Extent.StartOffset
        if ($start -lt 1) { return $null }
        $jump = $Text.LastIndexOf([char]10, [Math]::Min($start - 1, $Text.Length - 1))

        if ($jump -lt $cut) { $cut = $jump }
        if ($cut -lt 0) { return $null }


        if ($cut + 1 -ge $Text.Length) { return $null }

        $Text = $Text.Substring(0, $cut + 1)
        $ast  = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    }
    if (!$ast.EndBlock) { return $null }
    $statements = $ast.EndBlock.Statements

    # The same forward walk the file scan does. Nothing has run yet, so the repeat protection isn't needed here.
    $last = -1
    for ($i = 0; $i -lt $statements.Count; $i++) {
        $found = Get-UiStatementCommandList -Statement $statements[$i] -Deferrers $Span.Deferrers -BlockStorers $Span.Helpers.BlockStorers
        foreach ($invoked in (Get-UiInvokedBlock -Statement $statements[$i] -Statements $statements -Limit ($i - 1))) {
            foreach ($statement in (Get-UiBlockStatement -Block $invoked.Block)) {
                $found.AddRange((Get-UiStatementCommandList -Statement $statement -Deferrers $Span.Deferrers -BlockStorers $Span.Helpers.BlockStorers))
            }
        }
        $stops = $false
        foreach ($name in $found) {
            if ($Span.Stoppers.Contains($name) -or $Span.Helpers.Stoppers.Contains($name)) { $stops = $true; break }
        }
        if ($stops) { break }

        # Only lines that build controls are taken.
        $builds = $false
        foreach ($name in $found) {
            if ($Span.Commands.Contains($name) -or $Span.Helpers.Builders.Contains($name)) { $builds = $true; break }
        }
        if (!$builds) { break }
        $last = $i
    }
    if ($last -lt 0) { return $null }

    # The cut has to land on a line boundary, since PSReadLine submits whatever is left of a split line on its own.
    $chars = 0

    while ($last -ge 0) {
        $end   = $Text.IndexOf([char]10, $statements[$last].Extent.EndOffset)
        $chars = if ($end -lt 0) { $Text.Length } else { $end + 1 }
        if ($last + 1 -ge $statements.Count -or $statements[$last + 1].Extent.StartOffset -ge $chars) { break }
        $last--
    }
    if ($last -lt 0) { return $null }

    return [pscustomobject]@{ Text = $Text.Substring(0, $chars).TrimEnd([char]10); Chars = $chars }
}
