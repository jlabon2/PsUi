function Get-UiPendingInput {
    <#
    .SYNOPSIS
        Turns the keys still sitting in PSReadLine's queue back into the text the user pasted,
        without taking any of them out of it. A no at the prompt leaves the queue as it was and
        those lines run afterwards the way they always did.
    #>
    [CmdletBinding()]
    param($Queue)

    if (!$Queue) { $Queue = Get-UiPromptKeyQueue }
    if (!$Queue -or !$Queue.Count) { return $null }

    # EntryEnds maps a length in the text back to how many queue entries produced it, which is the only way Remove-UiPendingInput can dequeue exactly the keys that went into the window.
    # The walk stops at the first control character that is not a newline or a tab, since an arrow key means what follows is no longer the paste.
    $text     = [System.Text.StringBuilder]::new()
    $ends     = [System.Collections.Generic.List[int]]::new()
    $count    = 0
    $previous = [char]0
    foreach ($entry in $Queue) {

        $char = [char]$entry.KeyChar
        $count++

        if ($char -eq [char]13) { [void]$text.Append([char]10); $ends.Add($count) }
        elseif ($char -eq [char]10) { if ($previous -eq [char]13) { $ends[$ends.Count - 1] = $count } else { [void]$text.Append([char]10); $ends.Add($count) } }
        elseif ($char -eq [char]9 -or ![char]::IsControl($char)) { [void]$text.Append($char); $ends.Add($count) }
        else { break }

        $previous = $char
    }
    if (!$text.Length) { return $null }
    return [pscustomobject]@{ Text = $text.ToString(); EntryEnds = $ends.ToArray(); Queue = $Queue }
}
