function Clear-UiList {
    <#
    .SYNOPSIS
        Clears all items from a UiList control.
    .DESCRIPTION
        On a list built with -ItemsSource this empties your own collection, not a copy of it.
        Rebuild with Add-UiListItem.
    .PARAMETER Variable
        The variable name of the list control.
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

    if ((Get-UiCollectionKind -Obj $collection) -eq 'PsUiObservable') { $collection.Clear() }
    else { Invoke-OnUIThread -ScriptBlock { $collection.Clear() }.GetNewClosure() }
}
