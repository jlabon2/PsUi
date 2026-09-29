function Get-UiListItems {
    <#
    .SYNOPSIS
        Gets all items from a list or dropdown.
    .DESCRIPTION
        Returns a snapshot of the list's current contents as a plain array. Items hidden
        by an active filter are still included.
    .PARAMETER Variable
        The -Variable name of the list or dropdown.
    .EXAMPLE
        $items = Get-UiListItems 'myList'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Variable
    )

    $session = Get-UiSession
    Write-Debug "Retrieving items from list '$Variable'"

    $collection = $session.GetListCollection($Variable)

    if ($null -eq $collection) {
        Write-Error "List '$Variable' not found."
        return @()
    }

    Write-Debug "Returning $($collection.Count) items"
    return @($collection)
}
