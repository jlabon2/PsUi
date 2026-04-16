function New-UiIconButton {
    <#
    .SYNOPSIS
        Creates a themed button with an icon from Segoe MDL2 Assets font.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IconChar,
        
        [string]$ToolTip,
        
        [int]$Size = 32,
        
        [System.Windows.Thickness]$Margin,
        
        [switch]$ReturnIcon
    )
    
    $icon = [System.Windows.Controls.TextBlock]@{
        Text       = $IconChar
        FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    }
    
    $button = [System.Windows.Controls.Button]@{
        Content = $icon
        Padding = 0
        Width   = $Size
        Height  = $Size
    }
    
    if ($ToolTip) { $button.ToolTip = $ToolTip }
    if ($Margin) { $button.Margin = $Margin }
    
    Set-ButtonStyle -Button $button -IconOnly
    
    # Return both button and icon if requested (for feedback animations)
    if ($ReturnIcon) {
        return @{ Button = $button; Icon = $icon }
    }
    
    return $button
}
