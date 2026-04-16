function Add-ErrorDetailsPanel {
    <#
    .SYNOPSIS
        Adds the error details expander panel and wires up event handlers for the errors tab.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Colors,

        [Parameter(Mandatory)]
        [System.Windows.Controls.Grid]$Container,

        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.ObjectModel.ObservableCollection[PSObject]]$ErrorsList,

        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$CopyButton,

        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$ExportButton
    )

    # Error details panel (shown when error selected)
    $errorDetailsPanel = [System.Windows.Controls.Expander]@{
        Header          = "Error Details (click to expand)"
        IsExpanded      = $false
        Visibility      = 'Collapsed'
        Margin          = [System.Windows.Thickness]::new(4)
        Background      = ConvertTo-UiBrush $Colors.ControlBg
        Foreground      = ConvertTo-UiBrush $Colors.ControlFg
        BorderBrush     = ConvertTo-UiBrush $Colors.Border
        BorderThickness = [System.Windows.Thickness]::new(1)
    }

    # Create header with chevron icon
    $headerPanel = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Horizontal'
    }
    $expandIcon = [System.Windows.Controls.TextBlock]@{
        Text              = [PsUi.ModuleContext]::GetIcon('ChevronRight')
        FontFamily        = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize          = 12
        VerticalAlignment = 'Center'
        Margin            = [System.Windows.Thickness]::new(0, 0, 6, 0)
        Foreground        = ConvertTo-UiBrush $Colors.ControlFg
    }
    $headerText = [System.Windows.Controls.TextBlock]@{
        Text              = "Error Details"
        FontWeight        = 'SemiBold'
        VerticalAlignment = 'Center'
        Foreground        = ConvertTo-UiBrush $Colors.ControlFg
    }
    [void]$headerPanel.Children.Add($expandIcon)
    [void]$headerPanel.Children.Add($headerText)
    $errorDetailsPanel.Header = $headerPanel

    # Rotate chevron on expand/collapse
    $errorDetailsPanel.add_Expanded({
        $expandIcon.Text = [PsUi.ModuleContext]::GetIcon('ChevronDown')
    }.GetNewClosure())
    $errorDetailsPanel.add_Collapsed({
        $expandIcon.Text = [PsUi.ModuleContext]::GetIcon('ChevronRight')
    }.GetNewClosure())

    $errorDetailsText = [System.Windows.Controls.TextBox]@{
        IsReadOnly                  = $true
        FontFamily                  = [System.Windows.Media.FontFamily]::new('Cascadia Code, Cascadia Mono, Consolas, Courier New')
        FontSize                    = 11
        TextWrapping                = 'Wrap'
        AcceptsReturn               = $true
        VerticalScrollBarVisibility = 'Auto'
        MaxHeight                   = 200
        Background                  = ConvertTo-UiBrush $Colors.ControlBg
        Foreground                  = ConvertTo-UiBrush $(if ($Colors.ErrorText) { $Colors.ErrorText } else { $Colors.ControlFg })
        BorderBrush                 = ConvertTo-UiBrush $Colors.Border
        Padding                     = [System.Windows.Thickness]::new(4)
    }
    Set-TextBoxStyle -TextBox $errorDetailsText
    $errorDetailsPanel.Content = $errorDetailsText
    [System.Windows.Controls.Grid]::SetRow($errorDetailsPanel, 2)
    [void]$Container.Children.Add($errorDetailsPanel)

    # Wire up copy all button
    $CopyButton.Add_Click({
        if ($ErrorsList.Count -gt 0) {
            $lines = $ErrorsList | ForEach-Object {
                "$($_.Time)`t$($_.LineNumber)`t$($_.Category)`t$($_.Message)"
            }
            $header = "Time`tLine`tCategory`tMessage"
            $allLines = @($header) + @($lines)
            [System.Windows.Clipboard]::SetText($allLines -join "`n")
            Start-UiButtonFeedback -Button $CopyButton -OriginalIconChar ([PsUi.ModuleContext]::GetIcon('Copy'))
        }
    }.GetNewClosure())

    # Wire up export CSV button
    $ExportButton.Add_Click({
        if ($ErrorsList.Count -gt 0) {
            $saveDialog = [Microsoft.Win32.SaveFileDialog]::new()
            $saveDialog.Filter     = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
            $saveDialog.DefaultExt = '.csv'
            $saveDialog.FileName   = "errors_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

            if ($saveDialog.ShowDialog()) {
                $ErrorsList | Select-Object Time, LineNumber, Category, Message, ScriptName, Line, FullyQualifiedErrorId |
                    Export-Csv -Path $saveDialog.FileName -NoTypeInformation
                Start-UiButtonFeedback -Button $ExportButton -OriginalIconChar ([PsUi.ModuleContext]::GetIcon('Export'))
            }
        }
    }.GetNewClosure())

    # Wire up selection changed to show error details
    $DataGrid.add_SelectionChanged({
        param($sender, $eventArgs)
        $selected = $sender.SelectedItem
        if ($null -ne $selected) {
            $errorDetailsPanel.Visibility = 'Visible'
            $details = [System.Collections.Generic.List[string]]::new()
            
            # Try ToDetailedString() for PSErrorRecord wrapper - its more detailed... fall back to manual construction if needed
            $rawRec = $selected.RawRecord
            if ($null -ne $rawRec -and $rawRec.PSObject.Methods['ToDetailedString']) {
                $errorDetailsText.Text = $rawRec.ToDetailedString()
            }
            else {
                # Check and add each property from the error record (if present - they're pretty hit or miss)
                if ($selected.Message) { $details.Add("Message: $($selected.Message)") }
                if ($selected.LineNumber -and $selected.LineNumber -ne '') { $details.Add("Line: $($selected.LineNumber)") }
                if ($selected.ScriptName) { $details.Add("Script: $($selected.ScriptName)") }
                if ($selected.Line) { $details.Add("Code: $($selected.Line)") }
                if ($selected.Category) { $details.Add("Category: $($selected.Category)") }
                if ($selected.FullyQualifiedErrorId) { $details.Add("ErrorId: $($selected.FullyQualifiedErrorId)") }
                if ($selected.ScriptStackTrace) { $details.Add("`nStack Trace:`n$($selected.ScriptStackTrace)") }
                if ($selected.InnerException) { $details.Add("`nInner Exception: $($selected.InnerException)") }
                $errorDetailsText.Text = $details -join "`n"
            }
        }
        else {
            $errorDetailsPanel.Visibility = 'Collapsed'
        }
    }.GetNewClosure())
}
