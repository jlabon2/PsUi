function ConvertTo-UiDefinitionArray {
    <#
    .SYNOPSIS
        Normalizes standin scriptblock, array, or hashtable input into a plain hashtable array.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [Parameter(Mandatory)]
        [string]$CallerName,

        [switch]$PassThruDictionary,

        [switch]$AllowString
    )

    if ($null -eq $InputObject) { return $null }

    # Legacy dictionary form (RowContextMenu's [ordered]@{} keyed by label) passes through whole, order and identity intact. A bare standin item is also a dictionary, but a string Text plus a scriptblock Action can't be the legacy form (legacy values are scriptblocks or nested dicts), so that one falls through to normalization instead of rendering as two bogus menu entries.
    if ($PassThruDictionary -and $InputObject -is [System.Collections.IDictionary]) {
        if (!($InputObject['Text'] -is [string] -and $InputObject['Action'] -is [scriptblock])) { return $InputObject }
    }

    if ($InputObject -is [scriptblock]) {
        # Definition blocks emit data, nothing else. CurrentParent goes null for the duration so a stray New-UiLabel in there throws via Assert-UiSession instead of quietly landing in the enclosing panel.
        $session = $null
        try { $session = Get-UiSession } catch { }
        $oldParent = if ($session) { $session.CurrentParent } else { $null }
        if ($session) { $session.CurrentParent = $null }

        # Restore outside try/finally for PS 5.1 closure compatibility - same dance as the layout containers.
        try { $definitions = @(& $InputObject) }
        catch {
            if ($session) { $session.CurrentParent = $oldParent }
            throw
        }
        if ($session) { $session.CurrentParent = $oldParent }
    }
    else {
        # Covers the legacy hashtable[] form, a mixed array, and a single bare hashtable (hashtables don't unroll).
        $definitions = @($InputObject)
    }

    $normalized = [System.Collections.Generic.List[object]]::new()
    foreach ($definition in $definitions) {
        if ($null -eq $definition) { continue }
        if ($AllowString -and $definition -is [string]) { $normalized.Add($definition); continue }
        if ($definition -is [hashtable]) { $normalized.Add($definition); continue }

        # An [ordered]@{} emitted out of legacy habit still works. Copied into a plain table so the downstream [hashtable[]] casts and -is [hashtable] gates hold.
        if ($definition -is [System.Collections.IDictionary]) {
            $copy = @{}
            foreach ($key in $definition.Keys) { $copy[$key] = $definition[$key] }
            $normalized.Add($copy)
            continue
        }

        throw "$CallerName`: $ParameterName entries must be hashtables (from the New-Ui standin functions or written by hand). Got [$($definition.GetType().Name)]."
    }

    # Comma here so a one-item result survives the return as an array. A bare hashtable's .Count is its key count, which silently missizes anything counting entries.
    return , $normalized.ToArray()
}
