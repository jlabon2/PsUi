function Add-ErrorDetailsPanel {
    <#
    .SYNOPSIS
        The collapsible details panel under the errors grid, and the handlers for its two toolbar buttons.
    #>
    [CmdletBinding()]
    param(
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

    # WPF's own Expander draws a circled arrow, so this is built the way New-UiExpander builds one.
    # It's up for as long as the window is so every brush here follows the theme.
    $errorDetailsPanel = [System.Windows.Controls.Border]@{
        Visibility      = 'Collapsed'
        Margin          = [System.Windows.Thickness]::new(4)
        BorderThickness = [System.Windows.Thickness]::new(1)
        CornerRadius    = [System.Windows.CornerRadius]::new(4)
    }
    $errorDetailsPanel.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'ControlBackgroundBrush')
    $errorDetailsPanel.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'BorderBrush')

    $detailsStack            = [System.Windows.Controls.StackPanel]::new()
    $errorDetailsPanel.Child = $detailsStack

    $expandIcon = [System.Windows.Controls.TextBlock]@{
        Text                  = [PsUi.ModuleContext]::GetIcon('ChevronRight')
        FontFamily            = [PsUi.ModuleContext]::ActiveIconFontFamily
        FontSize              = 12
        VerticalAlignment     = 'Center'
        Margin                = [System.Windows.Thickness]::new(0, 0, 8, 0)
        RenderTransformOrigin = '0.5,0.5'
    }
    # The glyph turns rather than swapping to a second one, so the two stay the same width and the label never shifts.
    $expandIcon.RenderTransform = [System.Windows.Media.RotateTransform]::new(0)
    $expandIcon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'SecondaryTextBrush')

    $headerText = [System.Windows.Controls.TextBlock]@{
        Text              = 'Error Details'
        FontFamily        = [System.Windows.Media.FontFamily]::new('Segoe UI Variable, Segoe UI')
        FontSize          = 13
        FontWeight        = 'SemiBold'
        VerticalAlignment = 'Center'
    }
    $headerText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'ControlForegroundBrush')

    $headerPanel = [System.Windows.Controls.StackPanel]@{
        Orientation = 'Horizontal'
        Cursor      = 'Hand'
        Background  = [System.Windows.Media.Brushes]::Transparent
        Margin      = [System.Windows.Thickness]::new(10, 8, 10, 8)
    }
    [void]$headerPanel.Children.Add($expandIcon)
    [void]$headerPanel.Children.Add($headerText)
    [void]$detailsStack.Children.Add($headerPanel)

    $errorDetailsText = [System.Windows.Controls.TextBox]@{
        IsReadOnly                  = $true
        FontFamily                  = [System.Windows.Media.FontFamily]::new('Cascadia Code, Cascadia Mono, Consolas, Courier New')
        FontSize                    = 11
        TextWrapping                = 'Wrap'
        AcceptsReturn               = $true
        VerticalScrollBarVisibility = 'Auto'
        MaxHeight                   = 200
        Visibility                  = 'Collapsed'
        Margin                      = [System.Windows.Thickness]::new(12, 0, 12, 10)
        Padding                     = [System.Windows.Thickness]::new(4)
    }
    Set-TextBoxStyle -TextBox $errorDetailsText

    # After Set-TextBoxStyle, which wipes any Foreground set before it, and keyed so a theme switch recolours the text.
    $errorDetailsText.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'ErrorBrush')
    [void]$detailsStack.Children.Add($errorDetailsText)

    $headerPanel.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        trap { Write-Debug "Error details toggle: $_"; continue }
        if ($errorDetailsText.Visibility -eq 'Collapsed') {
            $errorDetailsText.Visibility      = 'Visible'
            $expandIcon.RenderTransform.Angle = 90
        }
        else {
            $errorDetailsText.Visibility      = 'Collapsed'
            $expandIcon.RenderTransform.Angle = 0
        }
    }.GetNewClosure())
    [System.Windows.Controls.Grid]::SetRow($errorDetailsPanel, 2)
    [void]$Container.Children.Add($errorDetailsPanel)

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

    $DataGrid.add_SelectionChanged({
        param($sender, $eventArgs)
        $selected = $sender.SelectedItem
        if ($null -ne $selected) {
            $errorDetailsPanel.Visibility = 'Visible'
            $details = [System.Collections.Generic.List[string]]::new()

            # PSErrorRecord carries ToDetailedString, which beats assembling the fields by hand.
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
