function ConvertFrom-UiHelpMarkdown {
    <#
    .SYNOPSIS
        Takes the markdown out of Get-Help text so it reads as plain text on the form.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Text,

        # For captions. One line, with the emphasis and code bits removed since a caption is a plain TextBlock.
        [switch]$Inline,

        # For the Help button's console text, paragraphs kept, markup gone
        [switch]$Plain
    )

    $bullet     = [string][char]0x2022
    $paragraphs = [System.Collections.Generic.List[string]]::new()

    foreach ($chunk in $Text) {
        if ([string]::IsNullOrWhiteSpace($chunk)) { continue }

        foreach ($block in [regex]::Split($chunk.Replace("`r", ''), '\n[ \t]*\n')) {
            $lines = [System.Collections.Generic.List[string]]::new()
            foreach ($line in $block.Split("`n")) {
                $line = $line.Trim()
                if ($line) { $lines.Add($line) }
            }
            if ($lines.Count -eq 0) { continue }

            if ($lines[0].StartsWith('>')) {
                for ($i = 0; $i -lt $lines.Count; $i++) { $lines[$i] = $lines[$i] -replace '^>\s?', '' }

                # Get-Help joins wrapped lines with a space, leaving markers mid line
                if ($lines.Count -eq 1) { $lines[0] = $lines[0] -replace '\s>(?=\s|$)', '' }
            }

            # Get-Help's join flattens lists onto one line too.
            if ($lines.Count -eq 1) {
                if ($lines[0] -match '^-\s') { $lines = [regex]::Split($lines[0], '\s+(?=-\s)') }
                elseif ($lines[0] -match '^\d{1,3}[.)]\s') {
                    $lines = [regex]::Split($lines[0], '\s+(?=\d{1,3}[.)]\s)')
                }
            }

            $lead  = [System.Collections.Generic.List[string]]::new()
            $items = [System.Collections.Generic.List[string]]::new()
            foreach ($line in $lines) {
                $line = ($line -replace '\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]', '').Trim()
                if (!$line) { continue }

                if ($line -match '^(?:[-*+]|(\d{1,3}[.)]))\s+(.+)$') {
                    $marker = if ($Matches[1]) { $Matches[1] } else { $bullet }
                    $items.Add("$marker $($Matches[2])")
                }
                elseif ($items.Count -gt 0) { $items[$items.Count - 1] += " $line" }
                else { $lead.Add($line) }
            }

            $parts = [System.Collections.Generic.List[string]]::new()
            if ($lead.Count -gt 0) { $parts.Add($lead -join ' ') }
            $parts.AddRange($items)
            if ($parts.Count -gt 0) { $paragraphs.Add($parts -join $(if ($Inline) { ' ' } else { "`n" })) }
        }
    }

    if ($Inline) {
        # Joined onto one line, a list or code sample without a full stop runs straight into the next paragraph
        for ($i = 0; $i -lt $paragraphs.Count - 1; $i++) {
            if ($paragraphs[$i] -notmatch '[.!?:;]\W*$') { $paragraphs[$i] += '.' }
        }
    }
    $result = $paragraphs -join $(if ($Inline) { ' ' } else { "`n`n" })

    # Links keep their text and drop the target which is a relative docs path or an xref that only resolves on the docs site
    $result = $result -replace '!?\[([^\]]*)\]\((?:[^()]|\([^()]*\))*\)', '$1'
    $result = $result -replace '\[([^\]]+)\]\[[^\]]*\]', '$1'
    $result = $result -replace '<(https?://[^>\s]+)>', '$1'

    if ($Inline -or $Plain) {
        # Emphasis only comes off outside code spans
        $pieces = foreach ($piece in [regex]::Split($result, '(`[^`\n]+`)')) {
            if ($piece.Length -gt 1 -and $piece.StartsWith('`') -and $piece.EndsWith('`')) {
                $piece.Substring(1, $piece.Length - 2)
            }
            else {
                $piece = $piece -replace '\*\*(.+?)\*\*', '$1'
                $piece -replace '(?<![\w*])\*(?![\s*])(.+?)(?<![\s*])\*(?![\w*])', '$1'
            }
        }
        $result = -join $pieces
    }
    $result = if ($Inline) { $result -replace '\s+', ' ' } else { $result -replace '[ \t]+', ' ' }

    $result.Trim()
}
