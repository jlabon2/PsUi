<#
.SYNOPSIS
    Converts markdown-formatted text to a WPF TextBlock with styled inlines.
#>
function ConvertTo-FormattedTextBlock {
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        
        [double]$FontSize = 12,
        
        [System.Windows.Media.Brush]$Foreground
    )
    
    $textBlock = [System.Windows.Controls.TextBlock]@{
        TextWrapping = [System.Windows.TextWrapping]::Wrap
        FontSize     = $FontSize
    }
    
    if ($Foreground) {
        $textBlock.Foreground = $Foreground
    }
    
    # Parse markdown and build inlines
    # Patterns: **bold**, *italic*, `code`
    # Italic pattern is restrictive to avoid matching PowerShell wildcards like *Property*
    # Requires space/start before opening * and space/end after closing *
    $remaining = $Text
    
    while ($remaining.Length -gt 0) {
        # Find the next markdown pattern
        $boldMatch   = [regex]::Match($remaining, '\*\*([^*]+)\*\*')
        $italicMatch = [regex]::Match($remaining, '(?<=^|[\s(])\*([^*\s][^*]*[^*\s])\*(?=[\s.,;:!?)]|$)')
        $codeMatch   = [regex]::Match($remaining, '`([^`]+)`')
        
        # Find which comes first
        $nextMatch = $null
        $matchType = $null
        
        $candidates = @()
        if ($boldMatch.Success) { $candidates += @{ Match = $boldMatch; Type = 'Bold' } }
        if ($italicMatch.Success) { $candidates += @{ Match = $italicMatch; Type = 'Italic' } }
        if ($codeMatch.Success) { $candidates += @{ Match = $codeMatch; Type = 'Code' } }
        
        if ($candidates.Count -gt 0) {
            $first = $candidates | Sort-Object { $_.Match.Index } | Select-Object -First 1
            $nextMatch = $first.Match
            $matchType = $first.Type
        }
        
        if (!$nextMatch) {
            # No more markdown - add remaining as plain text
            if ($remaining.Length -gt 0) {
                $run = [System.Windows.Documents.Run]::new($remaining)
                [void]$textBlock.Inlines.Add($run)
            }
            break
        }
        
        # Add text before the match
        if ($nextMatch.Index -gt 0) {
            $before = $remaining.Substring(0, $nextMatch.Index)
            $run = [System.Windows.Documents.Run]::new($before)
            [void]$textBlock.Inlines.Add($run)
        }
        
        $innerText = $nextMatch.Groups[1].Value
        
        switch ($matchType) {
            'Bold' {
                $bold = [System.Windows.Documents.Bold]::new()
                $bold.Inlines.Add([System.Windows.Documents.Run]::new($innerText))
                [void]$textBlock.Inlines.Add($bold)
            }
            'Italic' {
                $italic = [System.Windows.Documents.Italic]::new()
                $italic.Inlines.Add([System.Windows.Documents.Run]::new($innerText))
                [void]$textBlock.Inlines.Add($italic)
            }
            'Code' {
                # Style code with monospace font and subtle background
                $run = [System.Windows.Documents.Run]::new($innerText)
                $run.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
                
                # Use a border with the run for background effect (not directly supported)
                # For simplicity, just use monospace font
                [void]$textBlock.Inlines.Add($run)
            }
        }
        
        # Move past the match
        $remaining = $remaining.Substring($nextMatch.Index + $nextMatch.Length)
    }
    
    return $textBlock
}
