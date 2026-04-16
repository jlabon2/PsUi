function Remove-UiListItem {
    <#
    .SYNOPSIS
        Removes an item from a UiList control.
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
        if ($session -and $session.Variables.ContainsKey($Variable)) {
            $listBox = $session.Variables[$Variable]
            $Item = $listBox.SelectedItem
            Write-Debug "Using selected item for removal"
        }
        if ($null -eq $Item) {
            Write-Warning "No item selected to remove."
            return
        }
    }

    $collection = $session.GetListCollection($Variable)
    if ($null -ne $collection) {
        $index = $collection.IndexOf($Item)
        if ($index -ge 0) {
            Write-Debug "Removing item at index $index"
            $collection.RemoveAt($index)
        }
        else {
            Write-Warning "Item not found in list."
        }
    }
    else {
        Write-Error "List '$Variable' not found."
    }
}
