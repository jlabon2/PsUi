function Add-UiListItem {
    <#
    .SYNOPSIS
        Adds an item to a UiList control.
    .DESCRIPTION
        Adds an item to a list. If the list has a -DisplayFormat and you pass a hashtable,
        the display text is automatically generated. No need to manually create PSCustomObjects.
    .PARAMETER Variable
        The variable name of the list control.
    .PARAMETER Item
        The item to add. Can be a string, hashtable, or PSCustomObject.
        Hashtables are converted to objects automatically.
    .EXAMPLE
        Add-UiListItem 'myList' 'Simple string item'
    .EXAMPLE
        # With a list that has -DisplayFormat "{Name} ({Role})"
        Add-UiListItem 'userQueue' @{ Name = 'John'; Role = 'Admin'; Email = 'john@example.com' }
        # Displays as "John (Admin)" but full object is available when selected
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Variable,

        [Parameter(Mandatory, Position = 1)]
        [object]$Item
    )

    $session = Get-UiSession
    Write-Debug "Adding item to list '$Variable'"
    Write-Debug "Session: $($session.GetType().Name), SessionId: $([PsUi.SessionManager]::CurrentSessionId)"
    
    $collection = $session.GetListCollection($Variable)
    Write-Debug "Collection found: $($null -ne $collection)"
    
    if ($null -eq $collection) {
        $keys = $session.GetAllListKeys() -join ', '
        Write-Error "List '$Variable' not found. Available: $keys"
        return
    }
    
    Write-Debug "Collection type: $($collection.GetType().FullName), Count before: $($collection.Count)"

    if ($Item -is [hashtable]) {
        Write-Debug "Converting hashtable to PSCustomObject"
        $Item = [PSCustomObject]$Item
    }

    $displayFormat = $session.GetListDisplayFormat($Variable)
    
    if ($displayFormat -and $Item -is [PSObject]) {
        # Generate display text by replacing {PropertyName} with actual values
        $displayText = $displayFormat

        foreach ($prop in $Item.PSObject.Properties) {
            $displayText = $displayText -replace "\{$($prop.Name)\}", $prop.Value
        }

        # Add the display text as a property (use NoteProperty so it's accessible)
        $Item | Add-Member -NotePropertyName '_DisplayText' -NotePropertyValue $displayText -Force
        Write-Debug "Generated display text: $displayText"
    }

    Write-Debug "Collection count after add: $($collection.Count + 1)"
    $collection.Add($Item)
}
