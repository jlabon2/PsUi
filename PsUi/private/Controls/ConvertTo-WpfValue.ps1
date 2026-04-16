function ConvertTo-WpfValue {
    <#
    .SYNOPSIS
        Converts a value to a WPF-compatible type. Covers most common scenarios but may
        need expansion for edge cases.
    #>
    param(
        [object]$Value,
        [Type]$TargetType,
        [string]$PropertyName
    )
    
    $bindingFlags = [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static -bor [System.Reflection.BindingFlags]::IgnoreCase
    
    # Brush from string
    if ($TargetType -eq [System.Windows.Media.Brush] -and $Value -is [string]) {
        try { return ConvertTo-UiBrush $Value }
        catch {
            Write-Warning "[Set-UiProperties] Could not convert '$Value' to Brush for '$PropertyName'. Skipping."
            return $null
        }
    }
    
    # Cursor from string
    if ($TargetType -eq [System.Windows.Input.Cursor] -and $Value -is [string]) {
        $cursorProp = [System.Windows.Input.Cursors].GetProperty($Value, $bindingFlags)
        if ($cursorProp) { return $cursorProp.GetValue($null) }
        Write-Warning "[Set-UiProperties] Cursor '$Value' not found. Skipping."
        return $null
    }
    
    # FontStyle from string
    if ($TargetType -eq [System.Windows.FontStyle] -and $Value -is [string]) {
        $styleProp = [System.Windows.FontStyles].GetProperty($Value, $bindingFlags)
        if ($styleProp) { return $styleProp.GetValue($null) }
        Write-Warning "[Set-UiProperties] FontStyle '$Value' not found. Skipping."
        return $null
    }
    
    # FontWeight from string
    if ($TargetType -eq [System.Windows.FontWeight] -and $Value -is [string]) {
        $weightProp = [System.Windows.FontWeights].GetProperty($Value, $bindingFlags)
        if ($weightProp) { return $weightProp.GetValue($null) }
        Write-Warning "[Set-UiProperties] FontWeight '$Value' not found. Skipping."
        return $null
    }
    
    # Thickness from number or CSV string
    if ($TargetType -eq [System.Windows.Thickness]) {
        if ($Value -is [int] -or $Value -is [double]) { return [System.Windows.Thickness]::new($Value) }
        if ($Value -is [string]) {
            try {
                $parts = $Value -split ','
                switch ($parts.Count) {
                    1 { return [System.Windows.Thickness]::new([double]$parts[0]) }
                    2 { return [System.Windows.Thickness]::new([double]$parts[0], [double]$parts[1], [double]$parts[0], [double]$parts[1]) }
                    4 { return [System.Windows.Thickness]::new([double]$parts[0], [double]$parts[1], [double]$parts[2], [double]$parts[3]) }
                    default {
                        Write-Warning "[Set-UiProperties] Thickness expects 1, 2, or 4 values, got $($parts.Count) in '$Value'. Skipping."
                        return $null
                    }
                }
            }
            catch {
                Write-Warning "[Set-UiProperties] Could not parse Thickness '$Value'. Skipping."
                return $null
            }
        }
    }
    
    # GridLength from number or star notation
    if ($TargetType -eq [System.Windows.GridLength]) {
        if ($Value -is [int] -or $Value -is [double]) { return [System.Windows.GridLength]::new($Value) }
        if ($Value -is [string]) {
            if ($Value -eq 'Auto') { return [System.Windows.GridLength]::Auto }
            if ($Value -match '^\*$') { return [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
            if ($Value -match '^(\d+(?:\.\d+)?)\*$') { return [System.Windows.GridLength]::new([double]$matches[1], [System.Windows.GridUnitType]::Star) }
            try { return [System.Windows.GridLength]::new([double]$Value) }
            catch { return $null }
        }
    }
    
    # Enum from string
    if ($TargetType.IsEnum -and $Value -is [string]) {
        try { return [Enum]::Parse($TargetType, $Value, $true) }
        catch {
            Write-Warning "[Set-UiProperties] Could not parse '$Value' as $($TargetType.Name). Skipping."
            return $null
        }
    }
    
    # Generic fallback
    try { return [System.Convert]::ChangeType($Value, $TargetType) }
    catch {
        Write-Warning "[Set-UiProperties] Could not convert '$Value' to $($TargetType.Name) for '$PropertyName'. Skipping."
        return $null
    }
}
