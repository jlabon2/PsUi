<#
.SYNOPSIS
    Styles a GroupBox with theme-aware border.
#>
function Set-GroupBoxStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.GroupBox]$GroupBox
    )

    # Try to apply Modern XAML style
    $styleApplied = $false
    try {
        if ($null -ne [System.Windows.Application]::Current) {
            $style = [System.Windows.Application]::Current.TryFindResource('ModernGroupBoxStyle')
            if ($null -ne $style) {
                $GroupBox.Style = $style
                $styleApplied = $true
            }
        }
    }
    catch {
        Write-Verbose "Failed to apply ModernGroupBoxStyle from resources: $_"
    }

    # Warn if XAML style not found (indicates ThemeEngine initialization issue)
    if (!$styleApplied) {
        Write-Warning "XAML style 'ModernGroupBoxStyle' not found. Ensure ThemeEngine.LoadStyles() was called."
    }

    try {
        [PsUi.ThemeEngine]::RegisterElement($GroupBox)
    }
    catch {
        Write-Verbose "Failed to register GroupBox with ThemeEngine: $_"
    }
}