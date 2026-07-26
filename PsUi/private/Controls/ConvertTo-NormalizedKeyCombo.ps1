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

    $parts = $KeyCombo.Trim() -split '\+'

    $parts = $parts | Where-Object { $_ -ne '' }
    if (!$parts -or @($parts).Count -eq 0) {
        Write-Warning "Cannot normalize '$KeyCombo'; the literal '+' key can't be expressed in this format."
        return $null
    }

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
                if ($wpfKey) { $mainKey = $wpfKey.ToString() }
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

    return $result -join '+'
}
