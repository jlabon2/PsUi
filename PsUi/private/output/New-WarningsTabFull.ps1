function New-WarningsTabFull {
    <#
    .SYNOPSIS
        Creates the Warnings tab with toolbar and text search.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Colors
    )

    $warningsTab = [System.Windows.Controls.TabItem]@{
        Header     = "Warnings"
        Visibility = 'Collapsed'
    }
    Set-TabItemStyle -TabItem $warningsTab

    $warningsContainer = [System.Windows.Controls.DockPanel]::new()

    $warningsToolbar = [System.Windows.Controls.DockPanel]@{
        Margin = [System.Windows.Thickness]::new(4, 4, 4, 4)
        Height = 32
    }
    [System.Windows.Controls.DockPanel]::SetDock($warningsToolbar, [System.Windows.Controls.Dock]::Top)

    $leftToolbarPanel = [System.Windows.Controls.StackPanel]@{
        Orientation       = 'Horizontal'
        VerticalAlignment = 'Center'
    }
    [System.Windows.Controls.DockPanel]::SetDock($leftToolbarPanel, 'Left')

    $copyAllButton = [System.Windows.Controls.Button]@{
        Content           = 'Copy All'
        Padding           = [System.Windows.Thickness]::new(8, 2, 8, 2)
        Margin            = [System.Windows.Thickness]::new(0, 0, 4, 0)
        VerticalAlignment = 'Center'
    }
    Set-ButtonStyle -Button $copyAllButton
    [void]$leftToolbarPanel.Children.Add($copyAllButton)

    $saveButton = [System.Windows.Controls.Button]@{
        Content           = 'Save'
        Padding           = [System.Windows.Thickness]::new(8, 2, 8, 2)
        Margin            = [System.Windows.Thickness]::new(0, 0, 4, 0)
        VerticalAlignment = 'Center'
    }
    Set-ButtonStyle -Button $saveButton
    [void]$leftToolbarPanel.Children.Add($saveButton)

    $clearButton = [System.Windows.Controls.Button]@{
        Content           = 'Clear'
        Padding           = [System.Windows.Thickness]::new(8, 2, 8, 2)
        Margin            = [System.Windows.Thickness]::new(0, 0, 8, 0)
        VerticalAlignment = 'Center'
    }
    Set-ButtonStyle -Button $clearButton
    [void]$leftToolbarPanel.Children.Add($clearButton)

    $wrapCheckbox = [System.Windows.Controls.CheckBox]@{
        Content                  = 'Wrap'
        IsChecked                = $true
        Margin                   = [System.Windows.Thickness]::new(0, 0, 0, 0)
        VerticalAlignment        = 'Center'
        VerticalContentAlignment = 'Center'
        ToolTip                  = 'Toggle word wrapping'
    }
    Set-CheckBoxStyle -CheckBox $wrapCheckbox
    [void]$leftToolbarPanel.Children.Add($wrapCheckbox)

    [void]$warningsToolbar.Children.Add($leftToolbarPanel)

    $findPanel = [System.Windows.Controls.StackPanel]@{
        Orientation         = 'Horizontal'
        HorizontalAlignment = 'Right'
        VerticalAlignment   = 'Center'
    }
    [System.Windows.Controls.DockPanel]::SetDock($findPanel, 'Right')

    $findMatchLabel = [System.Windows.Controls.TextBlock]@{
        Text              = ''
        FontSize          = 11
        VerticalAlignment = 'Center'
        Foreground        = ConvertTo-UiBrush $Colors.SecondaryText
        Margin            = [System.Windows.Thickness]::new(0, 0, 10, 0)
        MinWidth          = 50
        TextAlignment     = 'Right'
        Visibility        = 'Collapsed'
    }
    [void]$findPanel.Children.Add($findMatchLabel)

    $findIcon = [System.Windows.Controls.TextBlock]@{
        Text              = [PsUi.ModuleContext]::GetIcon('Search')
        FontFamily        = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize          = 14
        VerticalAlignment = 'Center'
        Foreground        = ConvertTo-UiBrush $Colors.ControlFg
        Margin            = [System.Windows.Thickness]::new(0, 0, 6, 0)
    }
    [void]$findPanel.Children.Add($findIcon)

    # Create filter box with clear button
    $findBoxResult    = New-FilterBoxWithClear -Width 150 -Height 24
    $findBoxContainer = $findBoxResult.Container
    $warningsFindBox  = $findBoxResult.TextBox

    [void]$findPanel.Children.Add($findBoxContainer)

    $findPrevBtn = [System.Windows.Controls.Button]@{
        Content           = [PsUi.ModuleContext]::GetIcon('ChevronUp')
        FontFamily        = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        Width             = 24
        Height            = 24
        Padding           = [System.Windows.Thickness]::new(0)
        Margin            = [System.Windows.Thickness]::new(4, 0, 0, 0)
        ToolTip           = 'Previous match'
        VerticalAlignment = 'Center'
    }
    Set-ButtonStyle -Button $findPrevBtn
    [void]$findPanel.Children.Add($findPrevBtn)

    $findNextBtn = [System.Windows.Controls.Button]@{
        Content           = [PsUi.ModuleContext]::GetIcon('ChevronDown')
        FontFamily        = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        Width             = 24
        Height            = 24
        Padding           = [System.Windows.Thickness]::new(0)
        Margin            = [System.Windows.Thickness]::new(2, 0, 0, 0)
        ToolTip           = 'Next match'
        VerticalAlignment = 'Center'
    }
    Set-ButtonStyle -Button $findNextBtn
    [void]$findPanel.Children.Add($findNextBtn)

    [void]$warningsToolbar.Children.Add($findPanel)
    [void]$warningsContainer.Children.Add($warningsToolbar)

    $warningColor   = if ($Colors.WarningText) { $Colors.WarningText } else { '#FFC107' }
    $highlightColor = if ($Colors.TextHighlight) { $Colors.TextHighlight } else { $Colors.Selection }
    $highlightBrush = if ($Colors.FindHighlight) { ConvertTo-UiBrush $Colors.FindHighlight } else { [System.Windows.Media.Brushes]::Gold }
    $currentBrush   = if ($Colors.Accent) { ConvertTo-UiBrush $Colors.Accent } else { [System.Windows.Media.Brushes]::Orange }

    # Warnings RichTextBox - styled like Console tab for multi-match highlighting
    $warningsTextBox = [System.Windows.Controls.RichTextBox]@{
        IsReadOnly                    = $true
        FontFamily                    = [System.Windows.Media.FontFamily]::new('Cascadia Code, Cascadia Mono, Consolas, Courier New')
        VerticalScrollBarVisibility   = 'Auto'
        HorizontalScrollBarVisibility = 'Disabled'
        Background                    = ConvertTo-UiBrush $Colors.ControlBg
        Foreground                    = ConvertTo-UiBrush $warningColor
        BorderBrush                   = ConvertTo-UiBrush $Colors.Border
        BorderThickness               = [System.Windows.Thickness]::new(0)
        Padding                       = [System.Windows.Thickness]::new(8, 4, 8, 4)
        SelectionBrush                = ConvertTo-UiBrush $highlightColor
    }
    [void]$warningsContainer.Children.Add($warningsTextBox)

    # Create FlowDocument with matching style
    $warningsDocument = [System.Windows.Documents.FlowDocument]@{
        FontFamily  = [System.Windows.Media.FontFamily]::new('Cascadia Code, Cascadia Mono, Consolas, Courier New')
        FontSize    = 12
        Foreground  = ConvertTo-UiBrush $warningColor
        Background  = ConvertTo-UiBrush $Colors.ControlBg
        PagePadding = [System.Windows.Thickness]::new(0)
    }

    $warningsParagraph = [System.Windows.Documents.Paragraph]@{
        Margin               = [System.Windows.Thickness]::new(0)
        LineHeight           = 16
        LineStackingStrategy = [System.Windows.LineStackingStrategy]::BlockLineHeight
    }
    [void]$warningsDocument.Blocks.Add($warningsParagraph)
    $warningsTextBox.Document = $warningsDocument

    $warningsTab.Content = $warningsContainer

    $wrapCheckbox.Tag = $warningsTextBox
    $wrapCheckbox.Add_Checked({
        $this.Tag.Document.PageWidth = [double]::NaN
        $this.Tag.HorizontalScrollBarVisibility = 'Disabled'
    }.GetNewClosure())
    $wrapCheckbox.Add_Unchecked({
        $this.Tag.Document.PageWidth = 10000
        $this.Tag.HorizontalScrollBarVisibility = 'Auto'
    }.GetNewClosure())

    $debounceTimer          = [System.Windows.Threading.DispatcherTimer]::new()
    $debounceTimer.Interval = [TimeSpan]::FromMilliseconds(300)

    # Merge clear button and watermark references into the Tag
    $originalTag = $warningsFindBox.Tag
    $findState = @{
        Paragraph      = $warningsParagraph
        TextBox        = $warningsTextBox
        Label          = $findMatchLabel
        HighlightBrush = $highlightBrush
        CurrentBrush   = $currentBrush
        ResetBrush     = [System.Windows.Media.Brushes]::Transparent
        Matches        = [System.Collections.Generic.List[object]]::new()
        Index          = -1
        Timer          = $debounceTimer
        FindBox        = $warningsFindBox
        ClearButton    = $originalTag.ClearButton
        Watermark      = $originalTag.Watermark
    }
    $warningsFindBox.Tag = $findState

    $findPrevBtn.Tag   = $warningsFindBox
    $findNextBtn.Tag   = $warningsFindBox
    $debounceTimer.Tag = $warningsFindBox

    $doSearch = {
        param($findBox)
        $state     = $findBox.Tag
        $paragraph = $state.Paragraph
        $term      = $findBox.Text

        foreach ($prevRange in $state.Matches) {
            try { $prevRange.ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.ResetBrush) } catch { Write-Debug "Suppressed highlight reset error: $_" }
        }
        $state.Matches.Clear()
        $state.Index = -1

        if ([string]::IsNullOrEmpty($term)) {
            $state.Label.Text       = ''
            $state.Label.Visibility = 'Collapsed'
            return
        }

        # Build concatenated text from all Runs with position mapping
        $textBuilder = [System.Text.StringBuilder]::new()
        $runMap      = [System.Collections.Generic.List[object]]::new()
        $inlinesCopy = @($paragraph.Inlines)

        foreach ($inline in $inlinesCopy) {
            if ($inline -isnot [System.Windows.Documents.Run]) { continue }
            $runText = $inline.Text
            if ([string]::IsNullOrEmpty($runText)) { continue }

            $startPos = $textBuilder.Length
            [void]$textBuilder.Append($runText)
            [void]$runMap.Add(@{ Run = $inline; Start = $startPos; Length = $runText.Length })
        }

        $fullText = $textBuilder.ToString()
        $termLen  = $term.Length

        # Buffer ranges to highlight
        $rangesToHighlight = [System.Collections.Generic.List[object]]::new()
        $maxMatches        = 500

        # Search in full text
        $offset = 0
        :searchLoop while (($ix = $fullText.IndexOf($term, $offset, [StringComparison]::OrdinalIgnoreCase)) -ge 0) {
            $matchEnd = $ix + $termLen

            # Find which Run(s) this match spans
            foreach ($entry in $runMap) {
                $runStart = $entry.Start
                $runEnd   = $runStart + $entry.Length
                $run      = $entry.Run

                if ($matchEnd -le $runStart) { continue }
                if ($ix -ge $runEnd) { continue }

                $localStart = [Math]::Max(0, $ix - $runStart)
                $localEnd   = [Math]::Min($entry.Length, $matchEnd - $runStart)

                $ptrStart = $run.ContentStart.GetPositionAtOffset($localStart, [System.Windows.Documents.LogicalDirection]::Forward)
                $ptrEnd   = $run.ContentStart.GetPositionAtOffset($localEnd, [System.Windows.Documents.LogicalDirection]::Forward)

                if ($ptrStart -and $ptrEnd) {
                    $range = [System.Windows.Documents.TextRange]::new($ptrStart, $ptrEnd)
                    [void]$rangesToHighlight.Add($range)
                }
            }

            if ($rangesToHighlight.Count -ge $maxMatches) { break searchLoop }
            $offset = $ix + $termLen
        }

        # Apply highlights to all matches
        foreach ($range in $rangesToHighlight) {
            $range.ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.HighlightBrush)
        }

        # Store matches and update UI
        $state.Matches = $rangesToHighlight
        if ($rangesToHighlight.Count -gt 0) {
            $state.Index = 0

            # Highlight current match with different color
            $rangesToHighlight[0].ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.CurrentBrush)

            $state.Label.Visibility = 'Visible'
            $state.Label.Text = "1 of $($rangesToHighlight.Count)"

            # Scroll to first match
            try {
                $rect = $rangesToHighlight[0].Start.GetCharacterRect([System.Windows.Documents.LogicalDirection]::Forward)
                $state.TextBox.ScrollToVerticalOffset($state.TextBox.VerticalOffset + $rect.Top - 100)
            } catch { Write-Debug "Suppressed scroll to match error: $_" }
        }
        else {
            $state.Label.Visibility = 'Visible'
            $state.Label.Text       = 'No matches'
        }
    }

    # Timer tick handler
    $debounceTimer.Add_Tick({
        $this.Stop()
        $findBox = $this.Tag
        & $doSearch $findBox
    }.GetNewClosure())

    # Text changed handler with debounce
    $warningsFindBox.Add_TextChanged({
        $state = $this.Tag

        # Show/hide clear button and watermark
        $isEmpty = [string]::IsNullOrEmpty($this.Text)
        if ($state.ClearButton) {
            $state.ClearButton.Visibility = if ($isEmpty) { 'Collapsed' } else { 'Visible' }
        }
        if ($state.Watermark) {
            $state.Watermark.Visibility = if ($isEmpty) { 'Visible' } else { 'Collapsed' }
        }

        # Restart debounce timer
        $state.Timer.Stop()
        $state.Timer.Start()
    }.GetNewClosure())

    # Navigation handlers with proper highlight swapping
    $navigateMatch = {
        param($direction, $findBox)
        $state = $findBox.Tag
        if ($state.Matches.Count -eq 0) { return }

        # Reset current match to normal highlight
        $state.Matches[$state.Index].ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.HighlightBrush)

        $newIndex = $state.Index + $direction
        if ($newIndex -lt 0) { $newIndex = $state.Matches.Count - 1 }
        if ($newIndex -ge $state.Matches.Count) { $newIndex = 0 }

        $state.Index = $newIndex
        $state.Label.Text = "$($newIndex + 1) of $($state.Matches.Count)"

        # Highlight new current match
        $state.Matches[$newIndex].ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.CurrentBrush)

        # Scroll to match
        try {
            $rect = $state.Matches[$newIndex].Start.GetCharacterRect([System.Windows.Documents.LogicalDirection]::Forward)
            $state.TextBox.ScrollToVerticalOffset($state.TextBox.VerticalOffset + $rect.Top - 100)
        } catch { Write-Debug "Suppressed scroll to match navigation error: $_" }
    }

    $findPrevBtn.Add_Click({
        & $navigateMatch -1 $this.Tag
    }.GetNewClosure())

    $findNextBtn.Add_Click({
        & $navigateMatch 1 $this.Tag
    }.GetNewClosure())

    # Copy All handler with "Copied!" feedback
    $copyAllButton.Tag = @{ TextBox = $warningsTextBox; Document = $warningsDocument; Colors = $Colors }
    $copyAllButton.Add_Click({
        $textRange = [System.Windows.Documents.TextRange]::new($this.Tag.Document.ContentStart, $this.Tag.Document.ContentEnd)
        $text      = $textRange.Text
        if (![string]::IsNullOrWhiteSpace($text)) {
            [System.Windows.Clipboard]::SetText($text)

            $this.Content = 'Copied!'
            $originalBg   = $this.Background
            $this.Background = ConvertTo-UiBrush $this.Tag.Colors.Accent

            $timer          = [System.Windows.Threading.DispatcherTimer]::new()
            $timer.Interval = [TimeSpan]::FromMilliseconds(1500)
            $timer.Tag      = @{ Btn = $this; Bg = $originalBg }
            $timer.Add_Tick({ $this.Tag.Btn.Background = $this.Tag.Bg; $this.Tag.Btn.Content = 'Copy All'; $this.Stop() })
            $timer.Start()
        }
    }.GetNewClosure())

    # Save handler
    $saveButton.Tag = $warningsDocument
    $saveButton.Add_Click({
        $textRange = [System.Windows.Documents.TextRange]::new($this.Tag.ContentStart, $this.Tag.ContentEnd)
        $text      = $textRange.Text
        if (![string]::IsNullOrWhiteSpace($text)) {
            $dialog = [Microsoft.Win32.SaveFileDialog]@{
                Filter   = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
                FileName = 'warnings.txt'
            }
            if ($dialog.ShowDialog()) {
                [System.IO.File]::WriteAllText($dialog.FileName, $text)
            }
        }
    }.GetNewClosure())

    # Clear handler
    $clearButton.Tag = $warningsParagraph
    $clearButton.Add_Click({
        $this.Tag.Inlines.Clear()
    }.GetNewClosure())

    return @{
        Tab           = $warningsTab
        TextBox       = $warningsTextBox
        Document      = $warningsDocument
        Paragraph     = $warningsParagraph
        CopyButton    = $copyAllButton
        SaveButton    = $saveButton
        ClearButton   = $clearButton
        WrapCheckbox  = $wrapCheckbox
        FindBox       = $warningsFindBox
        FindState     = $findState
    }
}
