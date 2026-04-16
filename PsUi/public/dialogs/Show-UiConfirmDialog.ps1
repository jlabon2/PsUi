function Show-UiConfirmDialog {
    <#
    .SYNOPSIS
        Displays a simple themed confirmation dialog.
    .DESCRIPTION
        Shows a custom WPF confirmation dialog with customizable button text.
    .PARAMETER Title
        Dialog window title.
    .PARAMETER Message
        Message text to display.
    .PARAMETER ConfirmText
        Text for the confirmation button (default "Yes").
    .PARAMETER CancelText
        Text for the cancel button (default "No").
    .EXAMPLE
        if (Show-UiConfirmDialog -Title 'Delete File' -Message 'Are you sure you want to delete this file?') {
            Remove-Item $file
        }
    .EXAMPLE
        $proceed = Show-UiConfirmDialog -Title 'Continue' -Message 'Continue with operation?' -ConfirmText 'Continue' -CancelText 'Stop'
    #>
    [CmdletBinding()]
    param(
        [string]$Title = 'Confirm',

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$ConfirmText = 'Yes',

        [string]$CancelText = 'No'
    )

    Write-Debug "Title='$Title' ConfirmText='$ConfirmText' CancelText='$CancelText'"

    # Create dialog window using shared helper
    $dlg = New-DialogWindow -Title $Title -Width 400 -AppIdSuffix 'ConfirmDialog' -OverlayGlyph ([PsUi.ModuleContext]::GetIcon('Help'))

    $window       = $dlg.Window
    $contentPanel = $dlg.ContentPanel
    $colors       = $dlg.Colors

    # Button panel at bottom
    $buttonPanel = [System.Windows.Controls.StackPanel]@{
        Orientation         = 'Horizontal'
        HorizontalAlignment = 'Right'
        Margin              = [System.Windows.Thickness]::new(0, 12, 0, 0)
    }
    [System.Windows.Controls.DockPanel]::SetDock($buttonPanel, 'Bottom')
    [void]$contentPanel.Children.Add($buttonPanel)

    # Message text with scroll support
    $scrollViewer = [System.Windows.Controls.ScrollViewer]@{
        VerticalScrollBarVisibility   = 'Auto'
        HorizontalScrollBarVisibility = 'Disabled'
        Padding                       = [System.Windows.Thickness]::new(0, 0, 8, 0)
    }

    $messageText = [System.Windows.Controls.TextBlock]@{
        Text         = $Message
        FontSize     = 13
        TextWrapping = 'Wrap'
        Foreground   = ConvertTo-UiBrush $colors.ControlFg
        Margin       = [System.Windows.Thickness]::new(0, 4, 0, 0)
    }
    $scrollViewer.Content = $messageText
    [void]$contentPanel.Children.Add($scrollViewer)

    # Confirm button (accent)
    $confirmBtn = [System.Windows.Controls.Button]@{
        Content = $ConfirmText
        Width   = 80
        Height  = 28
        Margin  = [System.Windows.Thickness]::new(0, 0, 4, 0)
    }
    Set-ButtonStyle -Button $confirmBtn -Accent
    $confirmBtn.Add_Click({
        $window.Tag = $true
        $window.Close()
    })
    [void]$buttonPanel.Children.Add($confirmBtn)
    $confirmBtn.IsDefault = $true

    # Cancel button
    $cancelBtn = [System.Windows.Controls.Button]@{
        Content = $CancelText
        Width   = 80
        Height  = 28
        Margin  = [System.Windows.Thickness]::new(4, 0, 0, 0)
    }
    Set-ButtonStyle -Button $cancelBtn
    $cancelBtn.Add_Click({
        $window.Tag = $false
        $window.Close()
    })
    [void]$buttonPanel.Children.Add($cancelBtn)
    $cancelBtn.IsCancel = $true

    # Standard window behavior: fade-in, title bar theming
    Initialize-UiWindowLoaded -Window $window

    Set-UiDialogPosition -Dialog $window

    Write-Debug "Showing modal dialog"
    [void]$window.ShowDialog()

    $result = $window.Tag -eq $true
    Write-Debug "Result: $result"
    return $result
}
