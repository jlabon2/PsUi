function Set-ListBoxStyle {
    <#
    .SYNOPSIS
        Applies theme styling to a ListBox control.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListBox]$ListBox
    )

    # Try to apply XAML style
    $styleApplied = $false
    try {
        $style = [PsUi.ThemeEngine]::FindStyleResource('ModernListBoxStyle')
        if ($null -ne $style) {
            $ListBox.Style = $style
            $styleApplied = $true
        }
    }
    catch { Write-Verbose "Failed to apply ModernListBoxStyle from resources: $_" }

    # Warn if XAML style not found (indicates ThemeEngine initialization issue)
    if (!$styleApplied) { Write-Warning "XAML style 'ModernListBoxStyle' not found. Ensure ThemeEngine.LoadStyles() was called." }

    try {
        [PsUi.ThemeEngine]::RegisterElement($ListBox)
    }
    catch {
        Write-Verbose "Failed to register ListBox with ThemeEngine: $_"
    }
}