function New-UiDataGridToolbarIconButton {
    <#
    .SYNOPSIS
        Small themed icon only button used by the DataGrid toolbar (copy/export/etc).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Icon,

        [Parameter(Mandatory)]
        [string]$ToolTip
    )

    $btn = [System.Windows.Controls.Button]@{
        Width   = 32
        Height  = 28
        Margin  = [System.Windows.Thickness]::new(6, 0, 0, 0)
        Padding = [System.Windows.Thickness]::new(0)
        ToolTip = $ToolTip
    }

    $iconText = [System.Windows.Controls.TextBlock]@{
        Text                = [PsUi.ModuleContext]::GetIcon($Icon)
        FontFamily          = [PsUi.ModuleContext]::ActiveIconFontFamily
        FontSize            = 14
        HorizontalAlignment = 'Center'
        VerticalAlignment   = 'Center'
    }
    $btn.Content = $iconText

    Set-ButtonStyle -Button $btn -IconOnly
    return $btn
}
