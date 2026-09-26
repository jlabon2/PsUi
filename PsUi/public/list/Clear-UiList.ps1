function Clear-UiList {
    <#
    .SYNOPSIS
        Clears all items from a list or dropdown.
    .DESCRIPTION
        On a list built with -ItemsSource this empties your own collection, not a copy of it.
        Rebuild with Add-UiListItem.
    .PARAMETER Variable
        The -Variable name of the list or dropdown.
    .EXAMPLE
        Clear-UiList 'myList'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Variable
    )

    $session = Get-UiSession
    Write-Debug "Clearing list '$Variable'"

    $collection = $session.GetListCollection($Variable)

    if ($null -eq $collection) {
        Write-Error "List '$Variable' not found."
        return
    }

    Write-Debug "Removing $($collection.Count) items"

    if ((Get-UiCollectionType -Obj $collection) -eq 'PsUiObservable') { $collection.Clear() }
    else { Invoke-OnUIThread -ArgumentList (, $collection) -ScriptBlock { param($list) $list.Clear() } }
}
