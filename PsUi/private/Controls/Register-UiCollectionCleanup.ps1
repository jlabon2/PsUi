function Register-UiCollectionCleanup {
    <#
    .SYNOPSIS
        Unhooks a wrapped collection from the script's original when the owning window closes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Control,

        [Parameter(Mandatory)]
        [object]$Collection
    )

    # AttachMirror leaves the wrap subscribed to the script's collection. A collection that outlives the window (a $script: list, say) would keep the wrap and every item the window showed alive. Unhook when the window closes.
    # Window.Closed, not Unloaded. Unloaded fires on the first tab switch (the overfire New-UiDataGrid's detach hook dodges).
    $cleanup = @{ Done = $false; Collection = $Collection }

    $hookCleanup = {
        if ($cleanup.Done) { return }
        $window = [System.Windows.Window]::GetWindow($this)
        if (!$window) { return }
        # Rebind to a local first or the Closed handler captures an empty $cleanup.
        $localCleanup = $cleanup
        $window.Add_Closed({
            try { $localCleanup.Collection.DetachMirror() }
            catch { Write-Debug "Mirror detach failed: $_" }
        }.GetNewClosure())
        $cleanup.Done = $true
    }.GetNewClosure()

    # Loaded never fires for a control that gets built but never shown, so Initialized backs it up. $cleanup.Done keeps the pair from hooking Closed twice.
    $Control.Add_Loaded($hookCleanup)
    $Control.Add_Initialized($hookCleanup)
}
