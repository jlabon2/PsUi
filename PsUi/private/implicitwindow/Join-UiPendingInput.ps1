function Join-UiPendingInput {
    <#
    .SYNOPSIS
        Joins the text still sitting in PSReadLine's queue to the text already in the window,
        once the user has said yes to it. Without this, every pasted line that builds a control
        opens a window of its own and the user closes them one at a time.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Span
    )

    # Anything unexpected leaves what PsUi already had alone rather than turning a working window into a giant error.
    # A no does the same, and the lines it would have combined just run at the prompt after the window closes.
    $taken = $null
    try {
        $pending = Get-UiPendingInput
        if ($pending) {
            $candidate = Get-UiPendingSpan -Text $pending.Text -Span $Span
            if ($candidate -and (Confirm-UiPasteJoin -Text $candidate.Text)) {
                if (Remove-UiPendingInput -Pending $pending -Chars $candidate.Chars) { $taken = $candidate }
            }
        }
    }
    catch { return $Span }
    if (!$taken) { return $Span }

    Write-Debug "The paste behind the control joins the window, $($taken.Chars) characters of it."
    $joined      = $Span.PSObject.Copy()
    $joined.Text = $Span.Text + [char]10 + $taken.Text
    return $joined
}
