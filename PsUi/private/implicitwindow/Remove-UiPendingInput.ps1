function Remove-UiPendingInput {
    <#
    .SYNOPSIS
        Takes the keys that became the joined text back out of PSReadLine's queue, so they do not
        run at the prompt after the window closes.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        $Pending,

        [Parameter(Mandatory)]
        [int]$Chars
    )

    if ($Chars -lt 1) { return $false }

    # This is the one call that destroys input, so the queue is read a second time and compared against what the prompt actually showed.
    # Anything that moved in between means the count is olld and nothing gets dequeued.
    $again = Get-UiPendingInput -Queue $Pending.Queue
    if (!$again -or $again.Text.Length -lt $Chars) { return $false }
    if ($again.Text.Substring(0, $Chars) -cne $Pending.Text.Substring(0, $Chars)) { return $false }

    $entries = $again.EntryEnds[$Chars - 1]
    for ($i = 0; $i -lt $entries; $i++) { [void]$Pending.Queue.Dequeue() }
    return $true
}
