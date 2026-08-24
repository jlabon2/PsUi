function Remove-UiListItem {
    <#
    .SYNOPSIS
        Removes an item from a UiList control.
    .DESCRIPTION
        Removes one item: a specific one when -Item is passed, otherwise whatever row
        is currently selected.
    .PARAMETER Variable
        The variable name of the list control.
    .PARAMETER Item
        The item to remove. If not specified, removes the currently selected item.
    .EXAMPLE
        Remove-UiListItem 'myList'  # Removes selected item
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Variable,

        [Parameter(Position = 1)]
        [object]$Item
    )

    $session = Get-UiSession
    Write-Debug "Removing item from list '$Variable'"
    if ($null -eq $Item) {
        # Read the selection off the proxy, never off session.Variables.
        # That one hands back the raw ListBox, and touching it from an async action throws "The calling thread cannot access this object because a different thread owns it" before any of the removal below runs.
        $proxy = if ($session) { $session.GetSafeVariable($Variable) } else { $null }
        if ($proxy) {
            $Item = $proxy.SelectedItem
            Write-Debug "Using selected item for removal"
        }
        elseif ($session -and $session.Variables.ContainsKey($Variable)) {
            # Fallback for anything registered without a proxy.
            $Item = $session.Variables[$Variable].SelectedItem
        }
        if ($null -eq $Item) {
            Write-Warning "No item selected to remove."
            return
        }
    }

    $collection = $session.GetListCollection($Variable)
    if ($null -ne $collection) {
        # IndexOf and RemoveAt go across together.
        # Split them over two hops and another thread can shift the list between the two, so the index points at the wrong row by the time it lands.
        $removeOne = {
            $index = $collection.IndexOf($Item)
            if ($index -ge 0) {
                Write-Debug "Removing item at index $index"
                $collection.RemoveAt($index)
            }
            else {
                Write-Warning "Item not found in list."
            }
        }.GetNewClosure()

        if ((Get-UiCollectionKind -Obj $collection) -eq 'PsUiObservable') { & $removeOne }
        else { Invoke-OnUIThread -ScriptBlock $removeOne }
    }
    else {
        Write-Error "List '$Variable' not found."
    }
}
