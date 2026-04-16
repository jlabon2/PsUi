function Get-CleanTypeName {
    <#
    .SYNOPSIS
        Extracts a clean, user-friendly type name from an object for display purposes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Item
    )

    # Get the primary type name from PSObject metadata
    $typeName = $Item.PSObject.TypeNames[0]
    if (!$typeName) { $typeName = $Item.GetType().FullName }
    if (!$typeName) { $typeName = 'Unknown' }

    # Strip common prefixes for readability
    $displayName = $typeName -replace '^Deserialized\.', ''
    $displayName = $displayName -replace '^System\.Management\.Automation\.', ''

    # Extract just the class name if fully qualified
    if ($displayName -like '*.*') {
        $displayName = $displayName.Split('.')[-1]
    }

    # Strip ETS adapter suffix (e.g. ServiceController#StartupType -> ServiceController)
    # This appears on certain object types
    if ($displayName -like '*#*') {
        $displayName = $displayName.Split('#')[0]
    }

    return $displayName
}
