<#
.SYNOPSIS
    Styles a ComboBox with theme-aware colors.
#>
function Set-ComboBoxStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ComboBox]$ComboBox
    )

    $styleApplied = $false
    if ($null -ne [System.Windows.Application]::Current) {
        try {
            $style = [System.Windows.Application]::Current.Resources['ModernComboBoxStyle']
            if ($null -ne $style) {
                $ComboBox.Style = $style
                $styleApplied = $true
            }
        }
        catch {
            Write-Verbose "Failed to apply ModernComboBoxStyle: $_"
        }
    }

    # Warn if XAML style not found (indicates ThemeEngine initialization issue)
    if (!$styleApplied) {
        Write-Warning "XAML style 'ModernComboBoxStyle' not found. Ensure ThemeEngine.LoadStyles() was called."
    }

    try {
        [PsUi.ThemeEngine]::RegisterElement($ComboBox)
    }
    catch {
        Write-Verbose "Failed to register ComboBox with ThemeEngine: $_"
    }
}
