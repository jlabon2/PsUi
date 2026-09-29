function New-UiPopupCopyHeader {
    <#
    .SYNOPSIS
        Title row for an expand popup, copy button on the right.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Colors
    )

    $title = [System.Windows.Controls.TextBlock]@{
        FontWeight        = 'SemiBold'
        VerticalAlignment = 'Center'
        Foreground        = ConvertTo-UiBrush $Colors.ControlFg
    }

    # The body builder fills State.Text later, since a string captured here would copy empty forever.
    $panel = [System.Windows.Controls.DockPanel]@{ Margin = [System.Windows.Thickness]::new(0, 0, 0, 8) }
    $state = @{ Text = '' }

    $copyBtn        = New-UiDataGridToolbarIconButton -Icon 'Copy' -ToolTip 'Copy these values'
    $copyBtn.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($copyBtn, 'Right')
    [void]$panel.Children.Add($copyBtn)

    $buttonFeedback = ${function:Start-UiButtonFeedback}

    $copyBtn.Add_Click({
        trap { Write-Debug "Popup copy failed: $_"; continue }
        if ([string]::IsNullOrEmpty($state.Text)) { return }

        # SetText throws when another process has the clipboard open, and the trap resumes past the whole assignment with $copied still false.
        $copied = $false
        $copied = & { [System.Windows.Clipboard]::SetText($state.Text); $true }
        if ($copied) { & $buttonFeedback -Button $this -OriginalIconChar ([PsUi.ModuleContext]::GetIcon('Copy')) }
    }.GetNewClosure())

    # Title docks last so it fills what the button left
    [void]$panel.Children.Add($title)

    return @{ Panel = $panel; Title = $title; State = $state }
}
