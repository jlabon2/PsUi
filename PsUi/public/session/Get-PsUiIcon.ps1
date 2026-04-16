function Get-PsUiIcon {
    <#
    .SYNOPSIS
        Gets an icon glyph by name.
    .PARAMETER Name
        The icon name (e.g., 'Save', 'Delete', 'Check').
    .EXAMPLE
        Get-PsUiIcon -Name 'Save'
    .EXAMPLE
        New-UiGlyph -Icon (Get-PsUiIcon Check)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    # Static C# dictionary works from any runspace (unlike $script: vars)
    $glyph = [PsUi.ModuleContext]::GetIcon($Name)
    if ($glyph) { return $glyph }
    
    Write-Warning "Icon '$Name' not found. Use Get-PsUiIconList to see available icons."
    return $null
}
