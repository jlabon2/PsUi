function Push-UiIconFontOverride {
    <#
    .SYNOPSIS
        Snapshots icon font state and applies a caller-supplied override. Returns the snapshot for
        the caller to restore on close via [PsUi.ModuleContext]::RestoreIconFontState. Returns $null
        when no override should apply - either because the caller didn't pass the param, or because
        the window is being hosted inside a parent (parent's font wins, mirror of how -Theme works).
    #>
    [CmdletBinding()]
    param(
        [bool]$IsStandalone,

        [System.Collections.IDictionary]$BoundParameters,

        [string]$IconFont,

        [bool]$NoIconFontFallback
    )

    # Non-standalone = inside a parent New-UiWindow context. Parent's icon font wins, same as theme.
    if (!$IsStandalone) { return $null }

    # Treat -IconFont 'Inherit' as not-bound. Out-* callers default to 'Inherit' so $IconFont
    # always satisfies their ValidateSet (avoiding a GetNewClosure crash on unbound ""). An
    # explicit 'Inherit' from a user means "no override", same as omitting the param entirely.
    $iconFontBound = $BoundParameters.ContainsKey('IconFont') -and $IconFont -ne 'Inherit'
    $fallbackBound = $BoundParameters.ContainsKey('NoIconFontFallback')
    if (!$iconFontBound -and !$fallbackBound) { return $null }

    $snap = [PsUi.ModuleContext]::SnapshotIconFontState()

    if ($iconFontBound) {
        # Resolve friendly token (Auto/SegoeMDL2/SegoeFluentIcons) to a real font family name
        $resolved = [PsUi.ModuleContext]::ResolveIconFontToken($IconFont)

        # Warn when the caller named a specific font that isn't installed - matches
        # Set-PsUiIconFont's behavior so per-window overrides aren't silent about fallback.
        # Auto is best-effort by design and stays silent.
        if ($IconFont -in @('SegoeMDL2', 'SegoeFluentIcons') -and ![PsUi.ModuleContext]::IsFontInstalled($resolved)) {
            Write-Warning "$resolved is not installed. Falling back to $([PsUi.ModuleContext]::FontNameMDL2)."
        }

        $effectiveNoFallback = if ($fallbackBound) { $NoIconFontFallback } else { [PsUi.ModuleContext]::IconFontNoFallback }
        [PsUi.ModuleContext]::SetIconFont($resolved, $effectiveNoFallback)
    }
    elseif ($fallbackBound) {
        [PsUi.ModuleContext]::SetIconFontNoFallback($NoIconFontFallback)
    }

    return $snap
}
