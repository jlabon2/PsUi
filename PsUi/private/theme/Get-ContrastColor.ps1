function Get-ContrastColor {
    <#
    .SYNOPSIS
        Calculates contrasting text color (black or white) for a given background color.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HexColor
    )
    
    # Handle both 6-char RGB (#78B802) and 8-char ARGB (#FF78B802) hex values
    $hex    = $HexColor.TrimStart('#')
    $offset = if ($hex.Length -eq 8) { 2 } else { 0 }
    $red    = [Convert]::ToInt32($hex.Substring($offset, 2), 16)
    $green  = [Convert]::ToInt32($hex.Substring($offset + 2, 2), 16)
    $blue   = [Convert]::ToInt32($hex.Substring($offset + 4, 2), 16)
    
    # Calculate relative luminance (ITU-R BT.709)
    $luminance = (0.299 * $red) + (0.587 * $green) + (0.114 * $blue)
    
    # Bright backgrounds get black text, dark backgrounds get white
    if ($luminance -gt 128) {
        return '#000000'
    }
    else {
        return '#FFFFFF'
    }
}
