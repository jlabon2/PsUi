function Get-UiListItems {
    <#
    .SYNOPSIS
        Gets all items from a UiList control.
    .PARAMETER Variable
        The variable name of the list control.
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
