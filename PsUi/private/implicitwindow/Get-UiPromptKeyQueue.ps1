function Get-UiPromptKeyQueue {
    <#
    .SYNOPSIS
        Uses reflection to read the private, internal queue PSReadLine keeps pasted keys in.
        (If you're actually reading this, this was a nightmare to figure out.)
    #>
    [CmdletBinding()]
    param()

    # PSReadLine reads every key the console has ready in 2 ms batches and adds them here. So while the first line of a paste runs, the rest of it sits in this queue.
    $type = 'Microsoft.PowerShell.PSConsoleReadLine' -as [type]
    if (!$type) { return $null }

    $singleton = $type.GetField('_singleton', [System.Reflection.BindingFlags]'NonPublic,Static')
    if (!$singleton) { return $null }
    $instance = $singleton.GetValue($null)
    if (!$instance) { return $null }

    $queue = $type.GetField('_queuedKeys', [System.Reflection.BindingFlags]'NonPublic,Instance')
    if (!$queue) { return $null }

    # Without the comma the queue unrolls into an array on the way out, and then Clear quietly empties a copy while dequeue is not there at all.
    return ,$queue.GetValue($instance)
}
