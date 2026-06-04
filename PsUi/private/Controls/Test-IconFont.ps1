function Test-IconFont {
    <#
    .SYNOPSIS
        Returns $true if the FontFamily references a known icon font. Matches both bare names ("Segoe MDL2 Assets") and the fallback chain ("Segoe Fluent Icons, Segoe MDL2 Assets").
    #>
    param([System.Windows.Media.FontFamily]$Font)

    if ($null -eq $Font -or [string]::IsNullOrEmpty($Font.Source)) { return $false }

    $source = $Font.Source
    $source.Contains([PsUi.ModuleContext]::FontNameMDL2) -or $source.Contains([PsUi.ModuleContext]::FontNameFluent)
}
