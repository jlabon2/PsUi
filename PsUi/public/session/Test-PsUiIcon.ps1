function Test-PsUiIcon {
    <#
    .SYNOPSIS
        Tests whether an icon name will render under the current (or a specified) icon font.
    .DESCRIPTION
        Returns $true if the named glyph is present in the requested font. Use this in scripts
        to skip rendering an icon you can't trust, or to lint a list against a target font.

        -Font picks the check:
        - Active (default): checks the live active font. Strict: a failed glyph cache build
          returns $false instead of guessing (the glyph browser guesses on purpose so its
          tiles don't all dim). Honors the fallback chain unless Set-PsUiIconFont was called
          with -NoIconFontFallback.
        - Fluent: checks Segoe Fluent Icons explicitly.
        - MDL2: checks Segoe MDL2 Assets explicitly.
        - Either: returns true if either icon font has the glyph.
    .PARAMETER Name
        The icon name to test (key from CharList.json).
    .PARAMETER Font
        Which font to test against. Defaults to Active.
    .EXAMPLE
        Test-PsUiIcon -Name 'Calculator'
        # True if the active font has Calculator
    .EXAMPLE
        if (-not (Test-PsUiIcon 'WeirdNewGlyph' -Font MDL2)) { Write-Warning "WeirdNewGlyph won't render on Win10" }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [ValidateSet('Active', 'Fluent', 'MDL2', 'Either')]
        [string]$Font = 'Active'
    )

    # Active routes through IsGlyphAvailableInFont (strict) rather than IsGlyphAvailable. The
    # latter returns optimistic $true on a cache-build failure because the glyph browser's
    # dim-vs-bright UX is worse if every tile dims - that's the wrong contract for a linter.
    switch ($Font) {
        'Active' {
            $primary = [PsUi.ModuleContext]::ActiveIconFontName
            if ([PsUi.ModuleContext]::IsGlyphAvailableInFont($Name, $primary)) { return $true }
            if ([PsUi.ModuleContext]::IconFontNoFallback) { return $false }
            $secondary = if ($primary -eq [PsUi.ModuleContext]::FontNameFluent) {
                [PsUi.ModuleContext]::FontNameMDL2
            }
            else {
                [PsUi.ModuleContext]::FontNameFluent
            }
            [PsUi.ModuleContext]::IsGlyphAvailableInFont($Name, $secondary)
        }
        'Fluent' { [PsUi.ModuleContext]::IsGlyphAvailableInFont($Name, [PsUi.ModuleContext]::FontNameFluent) }
        'MDL2'   { [PsUi.ModuleContext]::IsGlyphAvailableInFont($Name, [PsUi.ModuleContext]::FontNameMDL2) }
        'Either' {
            [PsUi.ModuleContext]::IsGlyphAvailableInFont($Name, [PsUi.ModuleContext]::FontNameFluent) -or
            [PsUi.ModuleContext]::IsGlyphAvailableInFont($Name, [PsUi.ModuleContext]::FontNameMDL2)
        }
    }
}
