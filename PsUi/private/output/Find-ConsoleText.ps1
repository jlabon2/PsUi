function Find-ConsoleText {
    <#
    .SYNOPSIS
        Performs text search with highlighting in a RichTextBox.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.RichTextBox]$RichTextBox,
        
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$SearchText,
        
        [int]$MaxMatches = 200
    )
    
    $state = $RichTextBox.Tag
    if (!$state) { return }
    
    # Clear previous highlights
    foreach ($prevRange in $state.Matches) {
        try { $prevRange.ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.ResetBrush) } catch { Write-Debug "Highlight reset failed: $_" }
    }
    $state.Matches.Clear()
    
    if ([string]::IsNullOrEmpty($SearchText)) { return }
    
    # Get document bounds
    $docStart = $RichTextBox.Document.ContentStart
    $docEnd = $RichTextBox.Document.ContentEnd
    
    # Get full text and find all match positions
    $fullRange = [System.Windows.Documents.TextRange]::new($docStart, $docEnd)
    $fullText = $fullRange.Text
    
    # Find all match indices
    $matchIndices = [System.Collections.Generic.List[int]]::new()
    $searchIdx = 0
    while ($matchIndices.Count -lt $MaxMatches) {
        $idx = $fullText.IndexOf($SearchText, $searchIdx, [StringComparison]::OrdinalIgnoreCase)
        if ($idx -lt 0) { break }
        [void]$matchIndices.Add($idx)
        $searchIdx = $idx + 1
    }
    
    # Convert text indices to TextPointers and highlight
    # $fullText includes \r\n for LineBreaks, but GetTextInRun doesn't see them.
    # We must count LineBreak elements as 2 characters (\r\n) to stay in sync.
    foreach ($textIdx in $matchIndices) {
        $ptr = $docStart
        $charCount = 0
        $startPtr = $null
        $endPtr = $null
        
        while ($null -ne $ptr -and $ptr.CompareTo($docEnd) -lt 0) {
            $ctx = $ptr.GetPointerContext([System.Windows.Documents.LogicalDirection]::Forward)
            
            if ($ctx -eq [System.Windows.Documents.TextPointerContext]::Text) {
                $runText = $ptr.GetTextInRun([System.Windows.Documents.LogicalDirection]::Forward)
                $runLen = $runText.Length
                
                # Match starts somewhere in this run
                if ($null -eq $startPtr -and $charCount + $runLen -gt $textIdx) {
                    $offsetInRun = $textIdx - $charCount
                    $startPtr = $ptr.GetPositionAtOffset($offsetInRun)
                }
                
                # Match ends somewhere in this run
                $matchEnd = $textIdx + $SearchText.Length
                if ($null -ne $startPtr -and $null -eq $endPtr -and $charCount + $runLen -ge $matchEnd) {
                    $offsetInRun = $matchEnd - $charCount
                    $endPtr = $ptr.GetPositionAtOffset($offsetInRun)
                    break
                }
                
                $charCount += $runLen
            }
            elseif ($ctx -eq [System.Windows.Documents.TextPointerContext]::ElementEnd) {
                # LineBreaks count as \r\n (2 chars) in TextRange.Text
                $adjacent = $ptr.GetAdjacentElement([System.Windows.Documents.LogicalDirection]::Forward)
                if ($adjacent -is [System.Windows.Documents.LineBreak]) {
                    $charCount += 2
                }
            }
            
            $ptr = $ptr.GetNextContextPosition([System.Windows.Documents.LogicalDirection]::Forward)
        }
        
        if ($startPtr -and $endPtr) {
            $range = [System.Windows.Documents.TextRange]::new($startPtr, $endPtr)
            $range.ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.HighlightBrush)
            [void]$state.Matches.Add($range)
        }
    }
    
    # Scroll to first match
    if ($state.Matches.Count -gt 0) {
        try {
            $rect = $state.Matches[0].Start.GetCharacterRect([System.Windows.Documents.LogicalDirection]::Forward)
            $RichTextBox.ScrollToVerticalOffset($RichTextBox.VerticalOffset + $rect.Top - 50)
        } catch { Write-Debug "Suppressed scroll to match error: $_" }
    }
}
