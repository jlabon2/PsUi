function Set-PsUiIconFont {
    <#
    .SYNOPSIS
        Sets the icon font used by PsUi controls.
    .DESCRIPTION
        Switches the icon font between Segoe MDL2 Assets (Windows 10) and Segoe Fluent Icons
        (Windows 11). Use 'Auto' to let PsUi detect the appropriate font for the current system.
        If the requested font is not installed, falls back to Segoe MDL2 Assets and writes a
        warning.

        By default the chosen font is paired with the other as a WPF font-fallback chain - any
        glyph missing from the primary still renders via the secondary. -NoIconFontFallback pins
        to the primary only (missing glyphs render as tofu).

        Affects newly-created controls only. Existing controls keep the font they were
        built with - reload the window to apply a font change to UI that's already on screen.
    .PARAMETER FontName
        The icon font to use: Auto, SegoeMDL2, or SegoeFluentIcons.
    .PARAMETER NoIconFontFallback
        Pin to the chosen font only. Disables the WPF fallback chain. Glyphs missing from the
        chosen font render as tofu.

        On a Win10 box with only MDL2 installed there's no secondary font to fall back to, so
        this is a rendering no-op. Its remaining effect there: tighter IntelliSense for -Icon
        parameters via Get-IconDynamicParameter - tofu names get filtered out of the dropdown.
        Also forward-looking - matters if CharList.json ever picks up single-font-exclusive
        entries, or if MS ships a third icon font.
    .EXAMPLE
        Set-PsUiIconFont -FontName 'SegoeFluentIcons'
    .EXAMPLE
        Set-PsUiIconFont -FontName 'SegoeMDL2' -NoIconFontFallback
        # Strict MDL2 - won't borrow Fluent glyphs as fallback.
    .NOTES
        Mixed-vintage rendering caveat: 125 names in CharList.json (Blocked, Effects,
        PhotoCollection, ...) only live in Fluent. With MDL2 active and fallback on they
        still render - WPF substitutes from Fluent - which means a Fluent-vintage glyph
        sneaks into an otherwise MDL2-styled app. Use -NoIconFontFallback for strict
        consistency; the Fluent-only names will tofu instead, telling you which ones
        to swap.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Auto', 'SegoeMDL2', 'SegoeFluentIcons')]
        [string]$FontName,

        [switch]$NoIconFontFallback
    )

    # Map friendly name to actual font family
    switch ($FontName) {
        'Auto'              { $resolved = [PsUi.ModuleContext]::DetectDefaultIconFont() }
        'SegoeMDL2'         { $resolved = [PsUi.ModuleContext]::FontNameMDL2 }
        'SegoeFluentIcons'  { $resolved = [PsUi.ModuleContext]::FontNameFluent }
    }

    # Warn before SetIconFont silently substitutes - the user picked something specific.
    if ($FontName -ne 'Auto' -and ![PsUi.ModuleContext]::IsFontInstalled($resolved)) {
        Write-Warning "$resolved is not installed. Falling back to $([PsUi.ModuleContext]::FontNameMDL2)."
    }

    # Only touch the fallback setting when the caller actually supplied -NoIconFontFallback.
    # Changing fonts shouldn't silently flip a previously-set fallback preference.
    if ($PSBoundParameters.ContainsKey('NoIconFontFallback')) {
        [PsUi.ModuleContext]::SetIconFont($resolved, [bool]$NoIconFontFallback)
    }
    else {
        [PsUi.ModuleContext]::SetIconFont($resolved)
    }

    $mode = if ([PsUi.ModuleContext]::IconFontNoFallback) { 'no-fallback' } else { 'with-fallback' }
    Write-Debug "Icon font set to: $([PsUi.ModuleContext]::ActiveIconFontName) ($mode)"
}
