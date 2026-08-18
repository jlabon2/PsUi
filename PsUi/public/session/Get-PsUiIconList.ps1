function Get-PsUiIconList {
    <#
    .SYNOPSIS
        Lists all available icon names.
    .DESCRIPTION
        Every icon name in the module's glyph map, optionally narrowed by wildcard. The map
        isn't tied to a font - Test-PsUiIcon tells you whether a name renders in the active
        one. For the visual version, Show-UiGlyphBrowser draws them all as clickable tiles.
    .PARAMETER Filter
        Optional wildcard filter for icon names.
    .EXAMPLE
        Get-PsUiIconList
    .EXAMPLE
        Get-PsUiIconList -Filter '*Arrow*'
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*'
    )

    # Static C# dictionary works from any runspace
    [PsUi.ModuleContext]::Icons.Keys | Where-Object { $_ -like $Filter } | Sort-Object
}
