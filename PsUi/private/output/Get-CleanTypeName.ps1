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

    # Clean up generic type names (like System.Collections.Generic.List`1[System.String] to List<String>)
    $tick = $displayName.IndexOf('`')
    if ($tick -gt 0) {
        $tail  = $displayName.Substring($tick)
        $arity = [int]([regex]::Match($tail, '^`(\d+)')).Groups[1].Value

        $shortArgs = [System.Collections.Generic.List[string]]::new()
        foreach ($argMatch in [regex]::Matches($tail, '\[([\w.+]+)')) {
            if ($shortArgs.Count -ge $arity) { break }
            [void]$shortArgs.Add((($argMatch.Groups[1].Value -split '\.')[-1]))
        }

        $displayName = $displayName.Substring(0, $tick)
        if ($shortArgs.Count -gt 0) { $displayName += "<$($shortArgs -join ',')>" }
    }

    # Extract just the class name if fully qualified
    if ($displayName -like '*.*') { $displayName = $displayName.Split('.')[-1] }

    # Strip ETS adapter suffix (like ServiceController#StartupType to ServiceController)
    # This appears on certain object types
    if ($displayName -like '*#*') { $displayName = $displayName.Split('#')[0] }

    return $displayName
}
