function ConvertTo-NormalizedKeyCombo {
    <#
    .SYNOPSIS
        Normalizes a key combination string to a standard format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$KeyCombo
    )

    # Parse modifiers and key (seperate by +)
    $parts    = $KeyCombo.Trim() -split '\+'
    $hasCtrl  = $false
    $hasAlt   = $false
    $hasShift = $false
    $mainKey  = $null

    foreach ($part in $parts) {
        $cleaned = $part.Trim()
        switch -Regex ($cleaned) {
            '^(Ctrl|Control)$' { $hasCtrl = $true }
            '^Alt$'            { $hasAlt = $true }
            '^Shift$'          { $hasShift = $true }
            default {
                # This is the main key - validate it maps to a WPF key
                $wpfKey = ConvertTo-WpfKey -KeyName $cleaned
                if ($wpfKey) {
                    $mainKey = $wpfKey.ToString()
                }
                else {
                    Write-Warning "Unknown key: '$cleaned'"
                    return $null
                }
            }
        }
    }

    if (!$mainKey) {
        Write-Warning "No main key found in: '$KeyCombo'"
        return $null
    }

    # Build normalized string in consistent order: Ctrl+Alt+Shift+Key
    $result = [System.Collections.Generic.List[string]]::new()
    if ($hasCtrl)  { [void]$result.Add('Ctrl') }
    if ($hasAlt)   { [void]$result.Add('Alt') }
    if ($hasShift) { [void]$result.Add('Shift') }
    [void]$result.Add($mainKey)

    return ($result -join '+').ToUpperInvariant()
}

function ConvertTo-WpfKey {
    <#
    .SYNOPSIS
        Converts a key name string to a WPF Key enum value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$KeyName
    )

    # Handle common aliases
    $mapped = switch -Regex ($KeyName) {
        '^Esc(ape)?$' { 'Escape' }
        '^Enter$'     { 'Return' }
        '^Del(ete)?$' { 'Delete' }
        '^Ins(ert)?$' { 'Insert' }
        '^PgUp$'      { 'PageUp' }
        '^PgDown$'    { 'PageDown' }
        '^PgDn$'      { 'PageDown' }
        default       { $KeyName }
    }

    # Try to parse as WPF Key enum
    try {
        $key = [System.Windows.Input.Key]$mapped
        return $key
    }
    catch {
        return $null
    }
}
