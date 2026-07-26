function ConvertTo-UiDataGridSnapshot {
    <#
    .SYNOPSIS
        Flattens .NET objects into PSCustomObjects so PS added properties bind. Drops nulls.
    #>
    [CmdletBinding()]
    param(
        # AllowNull: a Mandatory [object[]] rejects the whole array if ANY element is null (not just a null array), so an owned grid built from rows carrying a null would throw during parameter binding before the null skip below ever runs.
        # The body drops nulls. Let them bind.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Items,

        [switch]$BuildSearchIndex
    )

    # $null check, not truthiness: a lone falsy scalar (@(0)/@('')/@($false)) unwraps to a falsy value under !$Items, so the only row got dropped and the grid rendered blank.
    if ($null -eq $Items -or $Items.Count -eq 0) {
        return [System.Collections.Generic.List[object]]::new()
    }

    # First item that actually needs snapshotting hands over the DefaultDisplayPropertySet (uniform per collection, no point running a good ol probe on each row).
    # TypeNames are per item below so a mixed collection (Process + ServiceController in the same array) keeps row accurate types.
    $firstSnapshotItem = $null
    foreach ($probe in $Items) {
        if ($null -eq $probe) { continue }
        if ($probe -is [string] -or $probe -is [System.ValueType]) { continue }
        if ($probe -is [System.Collections.IDictionary]) { continue }
        if ($probe -is [System.Management.Automation.PSCustomObject]) { continue }

        $firstSnapshotItem = $probe
        break
    }

    $defaultPropertyNames = $null

    if ($firstSnapshotItem) {
        try {
            $stdMembers = $firstSnapshotItem.PSStandardMembers
            if ($stdMembers -and $stdMembers.DefaultDisplayPropertySet) {
                $defaultPropertyNames = [System.Collections.Generic.List[string]]::new()
                foreach ($propName in $stdMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) {
                    $defaultPropertyNames.Add([string]$propName)
                }
            }
        }
        catch { Write-Debug "DefaultDisplayPropertySet probe failed: $_" }
    }

    # Cast once so PSMemberSet construction below doesn't recast per row.
    $defaultPropNamesArr = if ($defaultPropertyNames -and $defaultPropertyNames.Count -gt 0) { [string[]]$defaultPropertyNames } else { $null }

    # PSPropertySet content is identical for every row in a homogeneous collection.
    # Build once outside the loop. Only the per row PSMemberSet has to stay inside - those can't be shared across objects.
    $sharedPropSet = $null
    $sharedMembers = $null
    if ($defaultPropNamesArr) {
        try {
            $sharedPropSet = [System.Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet', $defaultPropNamesArr)
            # PSMemberSet's constructor takes PSMemberInfo[]. A plain @($propSet) gives object[] and PowerShell picks the wrong constructor.
            [System.Management.Automation.PSMemberInfo[]]$sharedMembers = @($sharedPropSet)
        }
        catch {
            Write-Debug "Couldn't build shared PSPropertySet: $_"
            $sharedMembers = $null
        }
    }

    $result = [System.Collections.Generic.List[object]]::new($Items.Count)

    foreach ($item in $Items) {
        if ($null -eq $item) { continue }

        if ($item -is [string] -or $item -is [System.ValueType]) { [void]$result.Add($item); continue }
        if ($item -is [System.Collections.IDictionary]) {
            # WPF binding paths can't see IDictionary keys. A raw hashtable renders Count/Keys/Values columns and none of the user's data. Convert. _BaseObject keeps the user's original.
            try {
                $converted = [PSCustomObject]$item
                $converted.PSObject.Properties.Add(
                    [System.Management.Automation.PSNoteProperty]::new('_BaseObject', $item))
                if ($BuildSearchIndex) { Add-UiDataGridSearchText -PsObject $converted }
                [void]$result.Add($converted)
            }
            catch {
                Write-Debug "Hashtable conversion failed, keeping original: $_"
                [void]$result.Add($item)
            }
            continue
        }
        if ($item -is [System.Management.Automation.PSCustomObject]) {

            # Copy() gives an independent property bag over the same values - the NoteProperties below land on the DISPLAY row, never the user's object.
            # Mutating the original leaked _BaseObject/_SearchText into the user's own Export-Csv and ConvertTo-Json (the self referential _BaseObject recursed to the json depth cap), and -PassThru handed back rows wearing grid internals.
            $display = $item.PSObject.Copy()

            # Keep the _BaseObject contract consistent across input types. Downstream consumers (context menus, action handlers) reach for $row._BaseObject without caring how the row got into the grid.
            # A repassed display row already carries one pointing at the true original - keep that chain intact.
            if (!$display.PSObject.Properties['_BaseObject']) {
                try {
                    $display.PSObject.Properties.Add(
                        [System.Management.Automation.PSNoteProperty]::new('_BaseObject', $item))
                }
                catch { Write-Debug "Couldn't attach _BaseObject to PSCustomObject: $_" }
            }

            if ($BuildSearchIndex) { Add-UiDataGridSearchText -PsObject $display -Force }
            [void]$result.Add($display)
            continue
        }

        # Per item guard. Some objects throw beyond a single property access (services in restricted contexts).
        # Fall back to the original row so one bad object doesn't take the grid down.
        try {
            $snap         = [ordered]@{}
            # 256 char initial capacity covers a typical property heavy row (~10 props * ~25 chars) without reallocs.
            $searchBuffer = if ($BuildSearchIndex) { [System.Text.StringBuilder]::new(256) } else { $null }

            foreach ($prop in $item.PSObject.Properties) {

                $name = $prop.Name
                if ($name.StartsWith('_')) { continue }
                if ($prop -is [System.Management.Automation.PSMemberSet]) { continue }
                $val = $null
                try { $val = $prop.Value }
                catch {
                    # ScriptProperty throws on protected resources (Process.MainModule on elevated procs). Null is what the grid would render anyway.
                    $val = $null
                }

                $snap[$name] = $val
                if ($searchBuffer -and $null -ne $val) {
                    [void]$searchBuffer.Append([string]$val)
                    [void]$searchBuffer.Append(' ')
                }
            }

            # _BaseObject keeps the original .NET object one hop away - e.g. Stop-Process -InputObject $row._BaseObject.
            $snap['_BaseObject'] = $item
            if ($searchBuffer) { $snap['_SearchText'] = $searchBuffer.ToString() }
            $snapObj = [PSCustomObject]$snap

            # Reattach PSStandardMembers per snapshot - DefaultDisplayPropertySet won't fire without it, and PSObject members can't be shared between objects.
            if ($sharedMembers) {
                try {
                    $memberSet = [System.Management.Automation.PSMemberSet]::new('PSStandardMembers', $sharedMembers)
                    $snapObj.PSObject.Members.Add($memberSet)
                }
                catch { Write-Debug "Couldn't attach PSStandardMembers to snapshot: $_" }
            }

            # Carry only this row's TypeName, not a collection wide one... heterogeneous arrays (Process + Service in the same Out-Datagrid) otherwise stamp every row with the first item's type and the regex fallbacks misfire.
            try {
                $rowTypeName = if ($item.PSObject.TypeNames.Count -gt 0) { [string]$item.PSObject.TypeNames[0] } else { $null }
                if ($rowTypeName -and $snapObj.PSObject.TypeNames -notcontains $rowTypeName) { $snapObj.PSObject.TypeNames.Insert(0, $rowTypeName) }
            }
            catch { Write-Debug "Couldn't insert row type name: $_" }

            [void]$result.Add($snapObj)
        }
        catch {
            Write-Debug "Snapshot failed for item, falling back to original: $_"
            [void]$result.Add($item)
        }
    }

    return $result
}
