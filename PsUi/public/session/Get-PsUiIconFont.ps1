function Get-PsUiIconFont {
    <#
    .SYNOPSIS
        Returns the currently active icon font name.
    .DESCRIPTION
        Returns the name of the icon font PsUi is currently using for glyph rendering
        (e.g. "Segoe MDL2 Assets" or "Segoe Fluent Icons").
    .EXAMPLE
        Get-PsUiIconFont
        # Segoe Fluent Icons
    #>
    [CmdletBinding()]
    param()

    [PsUi.ModuleContext]::ActiveIconFontName
}
