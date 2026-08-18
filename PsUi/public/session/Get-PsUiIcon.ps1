function Get-PsUiIcon {
    <#
    .SYNOPSIS
        Gets an icon glyph by name.
    .DESCRIPTION
        Resolves an icon name to its glyph character from the shared icon map. Both icon
        fonts (Segoe MDL2 Assets and Segoe Fluent Icons) read the same map, so a name can
        resolve to a glyph the active font doesn't carry - Test-PsUiIcon says which ones.
        Warns and returns nothing for unknown names.
    .PARAMETER Name
        The icon name (e.g., 'Save', 'Delete', 'Check').
    .EXAMPLE
        Get-PsUiIcon -Name 'Save'
    .EXAMPLE
        New-UiLabel -Text ((Get-PsUiIcon Check) + ' Done')
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
