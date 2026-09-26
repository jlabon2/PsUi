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
    # Typed on the variable, since an if expression hands back object[]
    [string[]]$defaultPropNamesArr = if ($defaultPropertyNames -and $defaultPropertyNames.Count -gt 0) { $defaultPropertyNames } else { $null }

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

    $result       = [System.Collections.Generic.List[object]]::new($Items.Count)
    $commandLines = $null
    $copyRefused  = @{}

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

        $display = $null
        if ($item -is [System.Management.Automation.PSCustomObject]) {
            # Copy() throws on a deserialized row from Import-Clixml or Invoke-Command
            $rowType = [string]$item.PSObject.TypeNames[0]
            if (!$copyRefused.ContainsKey($rowType)) {
                try { $display = $item.PSObject.Copy() }
                catch {
                    # One throw per type, at 300us a row on 5.1
                    $copyRefused[$rowType] = $true
                    Write-Debug "Copy() refused a $rowType row: $_"
                }
            }
        }

        if ($null -ne $display) {

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
            $isProcess    = $item -is [System.Diagnostics.Process]

            foreach ($prop in $item.PSObject.Properties) {

                $name = $prop.Name
                if ($name.StartsWith('_')) { continue }
                if ($prop -is [System.Management.Automation.PSMemberSet]) { continue }

                # Modules walks every loaded DLL, 10ms a process on either edition and 3.9s for 390. $row._BaseObject.Modules still has it in there
                if ($isProcess -and $name -eq 'Modules') { continue }

                $val = $null
                if ($isProcess -and $name -eq 'CommandLine') {
                    # On 7 this ScriptProperty runs a CIM query per process, 54s for 390, where one query for all of them takes 150-240ms.
                    # Leaving it off the row doesn't work, because the row carries the Process type name and the type data puts the ScriptProperty straight back
                    if ($null -eq $commandLines) {
                        $commandLines = @{}
                        try {
                            $cimProcesses = Get-CimInstance -ClassName Win32_Process -Property ProcessId, CommandLine -ErrorAction Stop

                            # ProcessId is UInt32 against Process.Id's Int32, so cast or miss
                            foreach ($cimProcess in $cimProcesses) {  $commandLines[[int]$cimProcess.ProcessId] = $cimProcess.CommandLine }
                        }
                        catch { Write-Debug "Bulk CommandLine query failed: $_" }
                    }

                    # If the Process never started its Id reads null, and a null key throws
                    if ($null -ne $item.Id) { $val = $commandLines[$item.Id] }
                }
                else {
                    try { $val = $prop.Value }
                    catch {
                        # Throws on protected ones, like MainModule on an elevated process
                        $val = $null
                    }
                }

                $snap[$name] = $val

                # Parent is a Process built from an Id, and its ToString rereads the process table, 1.6s over a full Get-Process on 7.
                if ($searchBuffer -and $null -ne $val -and !($isProcess -and $name -eq 'Parent')) {
                    # [string] read a hashtable as its type name
                    [void]$searchBuffer.Append([PsUi.ValueKind]::IndexText($val, 25, 512))
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
