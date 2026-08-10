function Add-UiDataGridAlternatingBrush {
    <#
    .SYNOPSIS
        Alternating, theme aware row stripes that reapply after theme switch.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid
    )

    # Theme changes wipe the stripe. Low priority so the theme finishes first.
    $gridRef = $DataGrid
    $applyAlt = {
        try {  $gridRef.SetResourceReference( [System.Windows.Controls.DataGrid]::AlternatingRowBackgroundProperty, 'ButtonHoverBackgroundBrush') }
        catch { Write-Debug "AlternatingRowBrush apply failed: $_" }
    }.GetNewClosure()

    # Explicit Action[string] cast so add_/remove_ThemeChanged both get the identical delegate.
    # A raw scriptblock rides PS's implicit conversion cache, which drops that delegate under GC pressure... then the unsubscribe does absolutely nothing and the static event traps every closed grid.
    $themeHandler = [System.Action[string]]{
        param($themeName)
        try {
            $gridRef.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::Background,
                [Action]$applyAlt) | Out-Null
        }
        catch { Write-Debug "AlternatingRowBrush re-apply failed: $_" }
    }.GetNewClosure()

    # Detach on Window.Closed, never Unloaded. Tab virtualization fires Unloaded on every tab switch, so a hidden then shown grid would miss the theme swap that happened while it was off.
    $subState = @{ Subscribed = $false }

    $gridRef.Add_Loaded({
        & $applyAlt
        if (!$subState.Subscribed) {
            [PsUi.ThemeEngine]::add_ThemeChanged($themeHandler)
            $subState.Subscribed = $true
        }
    }.GetNewClosure())

    $detachState = @{ Done = $false }
    $hookWindow = {
        if ($detachState.Done) { return }
        $window = [System.Windows.Window]::GetWindow($gridRef)
        if (!$window) { return }
        $detachState.Done = $true

        # Rebind to locals, nested GetNewClosure only captures the immediate scope, so the closed handler needs $subState/$themeHandler as its own locals or the ThemeChanged unsubscribe gets $null and the static event roots every closed grid.
        $stateRef   = $subState
        $handlerRef = $themeHandler
        $window.Add_Closed({
            if ($stateRef.Subscribed) {
                try { [PsUi.ThemeEngine]::remove_ThemeChanged($handlerRef) }
                catch { Write-Debug "AlternatingRowBrush unsubscribe failed: $_" }
                $stateRef.Subscribed = $false
            }
        }.GetNewClosure())
    }.GetNewClosure()

    # Initialized for grids constructed and torn down without ever loading. Loaded for the standard parent then show path.
    $gridRef.Add_Initialized({ & $hookWindow }.GetNewClosure())
    $gridRef.Add_Loaded({ & $hookWindow }.GetNewClosure())
}
