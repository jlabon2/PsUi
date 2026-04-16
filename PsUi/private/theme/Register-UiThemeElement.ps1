<#
.SYNOPSIS
    Registers a control with the ThemeEngine for dynamic theme updates.
#>
function Register-UiThemeElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Control
    )

    try {
        [PsUi.ThemeEngine]::RegisterElement($Control)
    }
    catch {
        Write-Verbose "Failed to register control with ThemeEngine: $_"
    }
}
