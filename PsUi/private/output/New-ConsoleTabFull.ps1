function New-ConsoleTabFull {
    <#
    .SYNOPSIS
        Creates the full Console tab with RichTextBox, toolbar, and text search.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Colors
    )

    # Create Console tab (initially hidden until it has content)
    $consoleTab = [System.Windows.Controls.TabItem]@{
        Header     = "Console"
        Visibility = 'Collapsed'
    }
    Set-TabItemStyle -TabItem $consoleTab

    # Container for console toolbar and output
    $consoleContainer = [System.Windows.Controls.DockPanel]::new()

    # Console toolbar - use DockPanel for left/right alignment
    $consoleToolbar = [System.Windows.Controls.DockPanel]@{
        Margin = [System.Windows.Thickness]::new(4, 4, 4, 4)
        Height = 32
    }
    [System.Windows.Controls.DockPanel]::SetDock($consoleToolbar, [System.Windows.Controls.Dock]::Top)

    $leftToolbarPanel = [System.Windows.Controls.StackPanel]@{
        Orientation       = 'Horizontal'
        VerticalAlignment = 'Center'
    }
    [System.Windows.Controls.DockPanel]::SetDock($leftToolbarPanel, 'Left')

    $autoScrollCheckbox = [System.Windows.Controls.CheckBox]@{
        Content                  = 'Auto-scroll'
        IsChecked                = $true
        Margin                   = [System.Windows.Thickness]::new(0, 0, 10, 0)
        VerticalAlignment        = 'Center'
        VerticalContentAlignment = 'Center'
    }
    Set-CheckBoxStyle -CheckBox $autoScrollCheckbox
    [void]$leftToolbarPanel.Children.Add($autoScrollCheckbox)

    $wrapCheckbox = [System.Windows.Controls.CheckBox]@{
        Content                  = 'Wrap'
        IsChecked                = $true
        Margin                   = [System.Windows.Thickness]::new(0, 0, 10, 0)
        VerticalAlignment        = 'Center'
        VerticalContentAlignment = 'Center'
        ToolTip                  = 'Toggle word wrapping'
    }
    Set-CheckBoxStyle -CheckBox $wrapCheckbox
    [void]$leftToolbarPanel.Children.Add($wrapCheckbox)

    $pinToTopCheckbox = [System.Windows.Controls.CheckBox]@{
        Content                  = 'Pin'
        IsChecked                = $false
        Margin                   = [System.Windows.Thickness]::new(0, 0, 10, 0)
        VerticalAlignment        = 'Center'
        VerticalContentAlignment = 'Center'
        ToolTip                  = 'Keep window on top of other windows'
    }
    Set-CheckBoxStyle -CheckBox $pinToTopCheckbox
    [void]$leftToolbarPanel.Children.Add($pinToTopCheckbox)

    $timestampsCheckbox = [System.Windows.Controls.CheckBox]@{
        Content                  = 'Time'
        IsChecked                = $false
        Margin                   = [System.Windows.Thickness]::new(0, 0, 6, 0)
        VerticalAlignment        = 'Center'
        VerticalContentAlignment = 'Center'
        ToolTip                  = 'Show timestamps on console output'
    }
    Set-CheckBoxStyle -CheckBox $timestampsCheckbox
    [void]$leftToolbarPanel.Children.Add($timestampsCheckbox)

    # Vertical separator between toggles and action buttons
    $toolbarSeparator = [System.Windows.Controls.Border]@{
        Width             = 1
        Height            = 18
        Margin            = [System.Windows.Thickness]::new(4, 0, 10, 0)
        Background        = ConvertTo-UiBrush $Colors.Border
        VerticalAlignment = 'Center'
    }
    [void]$leftToolbarPanel.Children.Add($toolbarSeparator)

    # Action buttons
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

    $clearConsoleButton = [System.Windows.Controls.Button]@{
        Content           = 'Clear'
        Padding           = [System.Windows.Thickness]::new(8, 2, 8, 2)
        Margin            = [System.Windows.Thickness]::new(0, 0, 4, 0)
        VerticalAlignment = 'Center'
    }
    Set-ButtonStyle -Button $clearConsoleButton
    [void]$leftToolbarPanel.Children.Add($clearConsoleButton)

    # Vertical separator before font size control
    $fontSeparator = [System.Windows.Controls.Border]@{
        Width             = 1
        Height            = 18
        Margin            = [System.Windows.Thickness]::new(8, 0, 12, 4)
        Background        = ConvertTo-UiBrush $Colors.Border
        VerticalAlignment = 'Center'
    }
    [void]$leftToolbarPanel.Children.Add($fontSeparator)

    # Font size slider with label beneath
    $defaultFontSize = 12
    $fontSizePanel   = [System.Windows.Controls.StackPanel]@{
        Orientation       = 'Vertical'
        VerticalAlignment = 'Center'
    }

    $fontSizeSlider = [System.Windows.Controls.Slider]@{
        Minimum             = 8
        Maximum             = 24
        Value               = $defaultFontSize
        Width               = 70
        TickFrequency       = 1
        IsSnapToTickEnabled = $true
        ToolTip             = 'Adjust font size (8-24pt). Ctrl+Scroll to change. Double-click to reset.'
        Tag                 = $defaultFontSize
    }
    Set-SliderStyle -Slider $fontSizeSlider
    [void]$fontSizePanel.Children.Add($fontSizeSlider)

    $fontSizeLabel = [System.Windows.Controls.TextBlock]@{
        Text                = 'Font Size'
        HorizontalAlignment = 'Center'
        FontSize            = 8
        Margin              = [System.Windows.Thickness]::new(-15, -4.5, 0, 0)
        Foreground          = ConvertTo-UiBrush $Colors.SecondaryText
    }
    [void]$fontSizePanel.Children.Add($fontSizeLabel)
    [void]$leftToolbarPanel.Children.Add($fontSizePanel)

    [void]$consoleToolbar.Children.Add($leftToolbarPanel)

    $findPanel = [System.Windows.Controls.StackPanel]@{
        Orientation         = 'Horizontal'
        HorizontalAlignment = 'Right'
        VerticalAlignment   = 'Center'
    }
    [System.Windows.Controls.DockPanel]::SetDock($findPanel, 'Right')

    # Match count label (first, before icon)
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
    $consoleFindBox   = $findBoxResult.TextBox

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

    [void]$consoleToolbar.Children.Add($findPanel)
    [void]$consoleContainer.Children.Add($consoleToolbar)

    # Console RichTextBox for colored output
    $highlightColor = if ($Colors.TextHighlight) { $Colors.TextHighlight } else { $Colors.Selection }
    $consoleTextBox = [System.Windows.Controls.RichTextBox]@{
        IsReadOnly                    = $true
        FontFamily                    = [System.Windows.Media.FontFamily]::new('Cascadia Code, Cascadia Mono, Consolas, Courier New')
        VerticalScrollBarVisibility   = 'Auto'
        HorizontalScrollBarVisibility = 'Auto'
        Background                    = ConvertTo-UiBrush $Colors.ControlBg
        Foreground                    = ConvertTo-UiBrush $Colors.ControlFg
        BorderBrush                   = ConvertTo-UiBrush $Colors.Border
        BorderThickness               = [System.Windows.Thickness]::new(0)
        Padding                       = [System.Windows.Thickness]::new(8, 4, 8, 4)
        SelectionBrush                = ConvertTo-UiBrush $highlightColor
    }
    [void]$consoleContainer.Children.Add($consoleTextBox)

    # Create FlowDocument with matching style
    $consoleDocument = [System.Windows.Documents.FlowDocument]@{
        FontFamily  = [System.Windows.Media.FontFamily]::new('Cascadia Code, Cascadia Mono, Consolas, Courier New')
        FontSize    = 12
        Foreground  = ConvertTo-UiBrush $Colors.ControlFg
        Background  = ConvertTo-UiBrush $Colors.ControlBg
        PagePadding = [System.Windows.Thickness]::new(0)
    }

    # Track max content width for no-wrap mode
    $maxLineWidth = @{ Value = 0 }

    $consoleParagraph = [System.Windows.Documents.Paragraph]@{
        Margin               = [System.Windows.Thickness]::new(0)
        LineHeight           = 16
        LineStackingStrategy = [System.Windows.LineStackingStrategy]::BlockLineHeight
    }
    [void]$consoleDocument.Blocks.Add($consoleParagraph)
    $consoleTextBox.Document = $consoleDocument

    # Text search brushes and state
    $highlightBrush = if ($Colors.FindHighlight) { ConvertTo-UiBrush $Colors.FindHighlight } else { [System.Windows.Media.Brushes]::Gold }
    $currentBrush   = if ($Colors.Accent) { ConvertTo-UiBrush $Colors.Accent } else { [System.Windows.Media.Brushes]::Orange }

    # Create debounce timer
    $debounceTimer          = [System.Windows.Threading.DispatcherTimer]::new()
    $debounceTimer.Interval = [TimeSpan]::FromMilliseconds(300)

    # Merge clear button and watermark references into the Tag
    $originalTag = $consoleFindBox.Tag
    $findState = @{
        Paragraph          = $consoleParagraph
        TextBox            = $consoleTextBox
        Label              = $findMatchLabel
        HighlightBrush     = $highlightBrush
        CurrentBrush       = $currentBrush
        ResetBrush         = [System.Windows.Media.Brushes]::Transparent
        Matches            = [System.Collections.Generic.List[object]]::new()
        Index              = -1
        Timer              = $debounceTimer
        FindBox            = $consoleFindBox
        SearchTerm         = ''
        AutoScrollCheckbox = $autoScrollCheckbox
        ClearButton        = $originalTag.ClearButton
        Watermark          = $originalTag.Watermark
    }
    $consoleFindBox.Tag = $findState

    # Store references for nav buttons and timer
    $findPrevBtn.Tag   = $consoleFindBox
    $findNextBtn.Tag   = $consoleFindBox
    $debounceTimer.Tag = $consoleFindBox

    # Search function extracted for reuse
    $doSearch = {
        param($findBox)
        $state     = $findBox.Tag
        $paragraph = $state.Paragraph
        $term      = $findBox.Text

        # Store current search term for live highlighting
        $state.SearchTerm = $term

        # Clear previous highlights
        foreach ($prevRange in $state.Matches) {
            try { $prevRange.ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.ResetBrush) } catch { Write-Debug "Suppressed highlight reset error: $_" }
        }
        $state.Matches.Clear()
        $state.Index = -1

        if ([string]::IsNullOrEmpty($term)) {
            $state.Label.Text       = ''
            $state.Label.Visibility = 'Hidden'
            return
        }

        # Check document size and warn if too large
        $inlinesCopy = @($paragraph.Inlines)
        $tooLarge    = $inlinesCopy.Count -gt 2000

        # Buffer ranges to highlight
        $rangesToHighlight = [System.Collections.Generic.List[object]]::new()
        $termLen           = $term.Length
        $maxMatches        = if ($tooLarge) { 100 } else { 500 }
        $matchLimitReached = $false

        # Build concatenated text from all Runs with position mapping
        $textBuilder = [System.Text.StringBuilder]::new()
        $runMap      = [System.Collections.Generic.List[object]]::new()

        foreach ($inline in $inlinesCopy) {
            if ($inline -isnot [System.Windows.Documents.Run]) { continue }
            $runText = $inline.Text
            if ([string]::IsNullOrEmpty($runText)) { continue }

            $startPos = $textBuilder.Length
            [void]$textBuilder.Append($runText)
            [void]$runMap.Add(@{ Run = $inline; Start = $startPos; Length = $runText.Length })
        }

        $fullText = $textBuilder.ToString()

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

            if ($rangesToHighlight.Count -ge $maxMatches) {
                $matchLimitReached = $true
                break searchLoop
            }
            $offset = $ix + $termLen
        }

        # Apply highlights
        foreach ($range in $rangesToHighlight) {
            $range.ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.HighlightBrush)
        }

        # Store matches and update UI
        $state.Matches = $rangesToHighlight
        if ($rangesToHighlight.Count -gt 0) {
            $state.Index = 0
            $rangesToHighlight[0].ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.CurrentBrush)

            $state.Label.Visibility = 'Visible'
            if ($matchLimitReached) {
                $state.Label.Text = "1 of $maxMatches+ (limit)"
            }
            else {
                $state.Label.Text = "1 of $($rangesToHighlight.Count)"
            }

            try {
                $rect = $rangesToHighlight[0].Start.GetCharacterRect([System.Windows.Documents.LogicalDirection]::Forward)
                $state.TextBox.ScrollToVerticalOffset($state.TextBox.VerticalOffset + $rect.Top - 100)
            } catch { Write-Debug "Suppressed scroll to first match error: $_" }
        }
        else {
            $state.Label.Visibility = 'Visible'
            $state.Label.Text       = 'No matches'
        }
    }

    # Helper to highlight matches in a single Run (for live streaming)
    $highlightRunMatches = {
        param([System.Windows.Documents.Run]$Run, $FindState)
        if (!$FindState -or [string]::IsNullOrEmpty($FindState.SearchTerm)) { return }

        $term    = $FindState.SearchTerm
        $termLen = $term.Length
        $text    = $Run.Text
        if ([string]::IsNullOrEmpty($text)) { return }

        # Buffer ranges first
        $rangesToAdd = [System.Collections.Generic.List[object]]::new()

        $offset = 0
        while (($ix = $text.IndexOf($term, $offset, [StringComparison]::CurrentCultureIgnoreCase)) -ge 0) {
            $ptrStart = $Run.ContentStart.GetPositionAtOffset($ix, [System.Windows.Documents.LogicalDirection]::Forward)
            $ptrEnd   = $Run.ContentStart.GetPositionAtOffset($ix + $termLen, [System.Windows.Documents.LogicalDirection]::Backward)

            if ($ptrStart -and $ptrEnd) {
                $range = [System.Windows.Documents.TextRange]::new($ptrStart, $ptrEnd)
                [void]$rangesToAdd.Add($range)
            }
            $offset = $ix + $termLen
        }

        # Apply highlights
        foreach ($range in $rangesToAdd) {
            $range.ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $FindState.HighlightBrush)
            [void]$FindState.Matches.Add($range)
        }

        # Update match count label
        if ($FindState.Matches.Count -gt 0) {
            $FindState.Label.Text = "$($FindState.Index + 1) of $($FindState.Matches.Count)"
        }
    }

    # Store search function in Tag
    $findState.DoSearch = $doSearch

    # Timer tick handler
    $debounceTimer.Add_Tick({
        param($sender, $eventArgs)
        $sender.Stop()
        $fb    = $sender.Tag
        $state = $fb.Tag
        & $state.DoSearch $fb
    }.GetNewClosure())

    # Auto-search on text change with debounce
    $consoleFindBox.Add_TextChanged({
        param($sender, $eventArgs)
        $state = $sender.Tag
        $state.Timer.Stop()
        $state.Timer.Start()
    }.GetNewClosure())

    # Prev button
    $findPrevBtn.Add_Click({
        param($sender, $eventArgs)
        $fb    = $sender.Tag
        $state = $fb.Tag
        if ($state.Matches.Count -eq 0) { return }

        # Disable auto-scroll when navigating
        if ($state.AutoScrollCheckbox.IsChecked) {
            $state.AutoScrollCheckbox.IsChecked = $false
        }

        # Reset current highlight
        $state.Matches[$state.Index].ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.HighlightBrush)

        $state.Index = $state.Index - 1
        if ($state.Index -lt 0) { $state.Index = $state.Matches.Count - 1 }

        # Highlight new current
        $cur = $state.Matches[$state.Index]
        $cur.ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.CurrentBrush)
        $state.Label.Text = "$($state.Index + 1) of $($state.Matches.Count)"

        try {
            $rect = $cur.Start.GetCharacterRect([System.Windows.Documents.LogicalDirection]::Forward)
            $state.TextBox.ScrollToVerticalOffset($state.TextBox.VerticalOffset + $rect.Top - 100)
        } catch { Write-Debug "Suppressed scroll to prev match error: $_" }
    }.GetNewClosure())

    # Next button
    $findNextBtn.Add_Click({
        param($sender, $eventArgs)
        $fb    = $sender.Tag
        $state = $fb.Tag
        if ($state.Matches.Count -eq 0) { return }

        # Disable auto-scroll when navigating
        if ($state.AutoScrollCheckbox.IsChecked) {
            $state.AutoScrollCheckbox.IsChecked = $false
        }

        # Reset current highlight
        $state.Matches[$state.Index].ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.HighlightBrush)

        $state.Index = $state.Index + 1
        if ($state.Index -ge $state.Matches.Count) { $state.Index = 0 }

        # Highlight new current
        $cur = $state.Matches[$state.Index]
        $cur.ApplyPropertyValue([System.Windows.Documents.TextElement]::BackgroundProperty, $state.CurrentBrush)
        $state.Label.Text = "$($state.Index + 1) of $($state.Matches.Count)"

        try {
            $rect = $cur.Start.GetCharacterRect([System.Windows.Documents.LogicalDirection]::Forward)
            $state.TextBox.ScrollToVerticalOffset($state.TextBox.VerticalOffset + $rect.Top - 100)
        } catch { Write-Debug "Suppressed scroll to next match error: $_" }
    }.GetNewClosure())

    # Map console colors to WPF brushes (adjusted for dark bg readability)
    $consoleColorMap = Get-ConsoleColorBrushMap
    
    # Raw colors used when user explicitly sets -BackgroundColor (they've handled contrast)
    $rawColorMap = Get-RawConsoleColorBrushMap

    # Helper to append colored text
    $appendConsoleText = {
        param([string]$Text, [System.Windows.Media.Brush]$Color, [System.Windows.Media.Brush]$BackColor, [switch]$SkipScroll, [switch]$NoNewLine, $State)
        
        # Newline-only text (from WriteLine after colored Write)
        if ($Text -eq "`n" -or $Text -eq "`r`n") {
            [void]$State.Paragraph.Inlines.Add([System.Windows.Documents.LineBreak]::new())
            $State.AtLineStart.Value = $true
            if (!$SkipScroll -and $State.AutoScrollCheckbox.IsChecked) {
                $State.TextBox.ScrollToEnd()
            }
            return
        }
        
        if ([string]::IsNullOrEmpty($Text)) { return }

        $charWidth   = 7.2
        $paragraph   = $State.Paragraph
        $textBox     = $State.TextBox
        $document    = $State.Document
        $wrap        = $State.WrapCheckbox
        $autoScrl    = $State.AutoScrollCheckbox
        $tsCheckbox  = $State.TimestampsCheckbox
        $atLineStart = $State.AtLineStart
        $findState   = $State.FindState
        $maxWidth    = $State.MaxLineWidth
        $hlFunc      = $State.HighlightRunMatches
        
        # Capture current timestamp for this batch of output
        $currentTimestamp = Get-Date
        
        # Helper to prepend timestamp if enabled and at line start
        $prependTimestamp = {
            if ($tsCheckbox.IsChecked -and $atLineStart.Value) {
                $ts    = '[' + $currentTimestamp.ToString('HH:mm:ss') + '] '
                $tsRun = [System.Windows.Documents.Run]::new($ts)
                $tsRun.Foreground = [System.Windows.Media.Brushes]::Gray
                $tsRun.Tag        = 'TS'  # Mark as timestamp run for removal
                [void]$paragraph.Inlines.Add($tsRun)
            }
            $atLineStart.Value = $false
        }
        
        # Helper to store timestamp in a run's Tag
        $storeTimestamp = {
            param($targetRun)
            $targetRun.Tag = $currentTimestamp
        }

        # Backspace for spinner patterns (e.g., Write-Host "`b|" -NoNewline)
        # Only triggers when text literally starts with backspace character
        if ($Text[0] -eq [char]8) {
            $backspaceCount = 0
            $idx = 0
            while ($idx -lt $Text.Length -and $Text[$idx] -eq [char]8) {
                $backspaceCount++
                $idx++
            }
            $cleanText = $Text.Substring($backspaceCount)
            
            # Find the last Run, skipping trailing LineBreaks
            # (NoNewLine flag may not be preserved correctly through event chain)
            $lastRun = $null
            $current = $paragraph.Inlines.LastInline
            $skippedLineBreak = $false
            
            while ($null -ne $current) {
                if ($current -is [System.Windows.Documents.LineBreak]) {
                    # Skip LineBreak and keep looking for a Run
                    $skippedLineBreak = $true
                    $current = $current.PreviousInline
                    continue
                }
                if ($current -is [System.Windows.Documents.Run]) {
                    $lastRun = $current
                    break
                }
                $current = $current.PreviousInline
            }
            
            # Remove characters from the end of the last run
            if ($lastRun -and $lastRun.Text.Length -gt 0) {
                $removeCount = [Math]::Min($backspaceCount, $lastRun.Text.Length)
                $lastRun.Text = $lastRun.Text.Substring(0, $lastRun.Text.Length - $removeCount)
                
                # If we skipped a LineBreak, remove it so the new text continues on same line
                if ($skippedLineBreak) {
                    $lb = $paragraph.Inlines.LastInline
                    if ($lb -is [System.Windows.Documents.LineBreak]) {
                        $paragraph.Inlines.Remove($lb)
                    }
                }
            }
            
            # Append the new text if any
            if (![string]::IsNullOrEmpty($cleanText)) {
                & $prependTimestamp
                $run = [System.Windows.Documents.Run]::new($cleanText)
                if ($Color) { $run.Foreground = $Color }
                if ($BackColor) { $run.Background = $BackColor }
                & $storeTimestamp $run
                [void]$paragraph.Inlines.Add($run)
            }
            
            # Add LineBreak if NoNewLine is not set
            if (!$NoNewLine) {
                [void]$paragraph.Inlines.Add([System.Windows.Documents.LineBreak]::new())
                $atLineStart.Value = $true
            }
            
            if (!$SkipScroll -and $autoScrl.IsChecked) { $textBox.ScrollToEnd() }
            return
        }

        # Carriage return for line replacement (e.g., Write-Host "`rProgress: 50%" -NoNewline)
        if ($Text[0] -eq [char]13 -and ($Text.Length -eq 1 -or $Text[1] -ne [char]10)) {
            # Strip leading CR characters
            $idx = 0
            while ($idx -lt $Text.Length -and $Text[$idx] -eq [char]13) { $idx++ }
            $cleanText = if ($idx -lt $Text.Length) { $Text.Substring($idx) } else { '' }
            
            # Remove all inlines on the current line (after last LineBreak)
            $inlinesToRemove = [System.Collections.Generic.List[object]]::new()
            $current = $paragraph.Inlines.LastInline
            
            while ($null -ne $current) {
                if ($current -is [System.Windows.Documents.LineBreak]) { break }
                $inlinesToRemove.Add($current)
                $current = $current.PreviousInline
            }
            
            foreach ($inline in $inlinesToRemove) {
                $paragraph.Inlines.Remove($inline)
            }
            
            # We're now at the start of the line
            $atLineStart.Value = $true
            
            # Append the new text if any (recursively handle remaining text)
            if (![string]::IsNullOrEmpty($cleanText)) {
                & $appendConsoleText $cleanText $Color $BackColor -SkipScroll:$SkipScroll -NoNewLine:$NoNewLine -State $State
            }
            elseif (!$NoNewLine) {
                # Just CR with no text and no NoNewLine - add a line break
                [void]$paragraph.Inlines.Add([System.Windows.Documents.LineBreak]::new())
            }
            
            if (!$SkipScroll -and $autoScrl.IsChecked) { $textBox.ScrollToEnd() }
            return
        }

        # Split into lines
        $lines = $Text -split "`r?`n"
        $lineCount = $lines.Count
        $lineIndex = 0
        foreach ($lineText in $lines) {
            $lineIndex++
            if ([string]::IsNullOrEmpty($lineText)) { continue }

            # Prepend timestamp if at start of line and timestamps enabled
            & $prependTimestamp

            # Create Run with just the text (no embedded newline - those don't work in FlowDocument)
            $run = [System.Windows.Documents.Run]::new($lineText)
            if ($Color) { $run.Foreground = $Color }
            if ($BackColor) { $run.Background = $BackColor }
            & $storeTimestamp $run
            [void]$paragraph.Inlines.Add($run)

            # Add LineBreak element unless NoNewLine is set and this is the last line
            $needsNewLine = !($NoNewLine -and $lineIndex -eq $lineCount)
            if ($needsNewLine) {
                [void]$paragraph.Inlines.Add([System.Windows.Documents.LineBreak]::new())
                $atLineStart.Value = $true
            }

            # Track max width for no-wrap mode
            $estimatedWidth = $lineText.Length * $charWidth
            if ($estimatedWidth -gt $maxWidth.Value) {
                $maxWidth.Value = $estimatedWidth
                if (!$wrap.IsChecked) {
                    $minWidth         = [Math]::Max($maxWidth.Value + 50, $textBox.ActualWidth)
                    $document.PageWidth = $minWidth
                }
            }

            # Highlight matches in new runs if search is active
            if ($hlFunc -and $findState) {
                & $hlFunc $run $findState
            }
        }

        # Auto-scroll if enabled
        if (!$SkipScroll -and $autoScrl.IsChecked) {
            $textBox.ScrollToEnd()
        }
    }

    # Font size slider changes document and paragraph font sizes, plus line height
    $fontSizeSlider.Add_ValueChanged({
        $fontSize                    = $fontSizeSlider.Value
        $consoleDocument.FontSize    = $fontSize
        $consoleParagraph.FontSize   = $fontSize
        $consoleParagraph.LineHeight = [Math]::Round($fontSize * 1.33)
    }.GetNewClosure())

    # Double-click slider to reset to default (use Preview to catch before thumb handles it)
    $fontSizeSlider.Add_PreviewMouseDoubleClick({
        $fontSizeSlider.Value = $fontSizeSlider.Tag
    }.GetNewClosure())

    # Ctrl+scroll to change font size, regular scroll disables auto-scroll
    $consoleTextBox.Add_PreviewMouseWheel({
        param($sender, $wheelArgs)
        if ([System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
            # Ctrl held - adjust font size
            $wheelArgs.Handled = $true
            $delta             = if ($wheelArgs.Delta -gt 0) { 1 } else { -1 }
            $newValue          = $fontSizeSlider.Value + $delta

            # Clamp to slider bounds
            if ($newValue -ge $fontSizeSlider.Minimum -and $newValue -le $fontSizeSlider.Maximum) {
                $fontSizeSlider.Value = $newValue
            }
        }
        else {
            # Normal scroll - disable auto-scroll
            if ($autoScrollCheckbox.IsChecked) {
                $autoScrollCheckbox.IsChecked = $false
            }
        }
    }.GetNewClosure())

    # Wire up word wrap checkbox
    $wrapCheckbox.Add_Checked({
        $consoleDocument.PageWidth                    = [Double]::NaN
        $consoleTextBox.HorizontalScrollBarVisibility = 'Auto'
    }.GetNewClosure())

    $wrapCheckbox.Add_Unchecked({
        $minWidth                                     = [Math]::Max($maxLineWidth.Value + 50, $consoleTextBox.ActualWidth)
        $consoleDocument.PageWidth                    = $minWidth
        $consoleTextBox.HorizontalScrollBarVisibility = 'Auto'
    }.GetNewClosure())

    # Show timestamps retroactively when checkbox is checked
    $timestampsCheckbox.Add_Checked({
        $inlines  = $consoleParagraph.Inlines
        $toInsert = [System.Collections.Generic.List[object]]::new()
        $atStart  = $true
        
        foreach ($inline in $inlines) {
            if ($inline -is [System.Windows.Documents.LineBreak]) {
                $atStart = $true
                continue
            }
            if ($inline -is [System.Windows.Documents.Run] -and $inline.Tag -ne 'TS') {
                if ($atStart -and $inline.Tag -is [datetime]) {
                    $toInsert.Add(@{ Before = $inline; Timestamp = $inline.Tag.ToString('HH:mm:ss') })
                }
                $atStart = $false
            }
        }
        
        # Insert after iteration to avoid modifying collection during enumeration
        foreach ($item in $toInsert) {
            $tsRun            = [System.Windows.Documents.Run]::new('[' + $item.Timestamp + '] ')
            $tsRun.Foreground = [System.Windows.Media.Brushes]::Gray
            $tsRun.Tag        = 'TS'
            $inlines.InsertBefore($item.Before, $tsRun)
        }
    }.GetNewClosure())

    # Remove timestamps when checkbox is unchecked
    $timestampsCheckbox.Add_Unchecked({
        $inlines  = $consoleParagraph.Inlines
        $toRemove = [System.Collections.Generic.List[System.Windows.Documents.Run]]::new()
        
        foreach ($inline in $inlines) {
            if ($inline -is [System.Windows.Documents.Run] -and $inline.Tag -eq 'TS') {
                $toRemove.Add($inline)
            }
        }
        
        foreach ($tsRun in $toRemove) {
            $inlines.Remove($tsRun)
        }
    }.GetNewClosure())

    # Resize handler
    $consoleTextBox.Add_SizeChanged({
        param($sender, $eventArgs)
        if (!$wrapCheckbox.IsChecked) {
            $minWidth = [Math]::Max($maxLineWidth.Value + 50, $consoleTextBox.ActualWidth)
            if ($consoleDocument.PageWidth -lt $minWidth) {
                $consoleDocument.PageWidth = $minWidth
            }
        }
    }.GetNewClosure())

    # Create context menu
    $consoleContextMenu = [System.Windows.Controls.ContextMenu]::new()

    # Scoped Separator style
    $sepStyle = [System.Windows.Style]::new([System.Windows.Controls.Separator])
    $sepStyle.Setters.Add([System.Windows.Setter]::new(
        [System.Windows.FrameworkElement]::MarginProperty,
        [System.Windows.Thickness]::new(0, 4, 0, 4)
    ))
    $sepStyle.Setters.Add([System.Windows.Setter]::new(
        [System.Windows.FrameworkElement]::HorizontalAlignmentProperty,
        [System.Windows.HorizontalAlignment]::Stretch
    ))
    $sepTemplate   = [System.Windows.Controls.ControlTemplate]::new([System.Windows.Controls.Separator])
    $borderFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.Border])
    $borderFactory.SetValue([System.Windows.FrameworkElement]::HeightProperty, [double]1)
    $borderFactory.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)
    $borderFactory.SetValue([System.Windows.FrameworkElement]::SnapsToDevicePixelsProperty, $true)
    $borderFactory.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'BorderBrush')
    $sepTemplate.VisualTree = $borderFactory
    $sepStyle.Setters.Add([System.Windows.Setter]::new(
        [System.Windows.Controls.Control]::TemplateProperty,
        $sepTemplate
    ))
    $consoleContextMenu.Resources.Add([System.Windows.Controls.Separator], $sepStyle)

    # Menu items
    $copyMenuItem = [System.Windows.Controls.MenuItem]@{
        Header  = 'Copy'
        Command = [System.Windows.Input.ApplicationCommands]::Copy
    }
    $selectAllMenuItem = [System.Windows.Controls.MenuItem]@{
        Header  = 'Select All'
        Command = [System.Windows.Input.ApplicationCommands]::SelectAll
    }
    $menuSep       = [System.Windows.Controls.Separator]::new()
    $menuSep.Style = $sepStyle

    [void]$consoleContextMenu.Items.Add($copyMenuItem)
    [void]$consoleContextMenu.Items.Add($menuSep)
    [void]$consoleContextMenu.Items.Add($selectAllMenuItem)

    $consoleTextBox.ContextMenu = $consoleContextMenu

    # Wire up clear button
    $clearConsoleButton.Add_Click({
        $consoleParagraph.Inlines.Clear()
        $maxLineWidth.Value      = 0
        $consoleDocument.PageWidth = $consoleTextBox.ActualWidth

        if ($findState) {
            $findState.SearchTerm = ''
            $findState.Matches.Clear()
            $findState.Index            = -1
            $findState.Label.Text       = ''
            $findState.Label.Visibility = 'Hidden'
        }
    }.GetNewClosure())

    # Wire up copy all button
    $copyAllButton.Add_Click({
        $textRange = [System.Windows.Documents.TextRange]::new($consoleDocument.ContentStart, $consoleDocument.ContentEnd)
        $text      = $textRange.Text
        if (![string]::IsNullOrWhiteSpace($text)) {
            [System.Windows.Clipboard]::SetText($text)

            $copyAllButton.Content = 'Copied!'
            $originalBg            = $copyAllButton.Background
            $copyAllButton.Background = ConvertTo-UiBrush $Colors.Accent

            $timer          = [System.Windows.Threading.DispatcherTimer]::new()
            $timer.Interval = [TimeSpan]::FromMilliseconds(1500)
            $timer.Tag      = @{ Btn = $copyAllButton; Bg = $originalBg }
            $timer.Add_Tick({ $this.Tag.Btn.Background = $this.Tag.Bg; $this.Tag.Btn.Content = 'Copy All'; $this.Stop() })
            $timer.Start()
        }
    }.GetNewClosure())

    # Wire up save button
    $saveButton.Add_Click({
        $textRange = [System.Windows.Documents.TextRange]::new($consoleDocument.ContentStart, $consoleDocument.ContentEnd)
        $text      = $textRange.Text
        if (![string]::IsNullOrWhiteSpace($text)) {
            $dialog = [Microsoft.Win32.SaveFileDialog]@{
                Filter          = 'Text files (*.txt)|*.txt|Log files (*.log)|*.log|All files (*.*)|*.*'
                DefaultExt      = '.txt'
                FileName        = 'output.txt'
                Title           = 'Save Console Output'
                OverwritePrompt = $true
            }

            if ($dialog.ShowDialog()) {
                [System.IO.File]::WriteAllText($dialog.FileName, $text)

                $saveButton.Content = 'Saved!'
                $originalBg         = $saveButton.Background
                $saveButton.Background = ConvertTo-UiBrush $Colors.Accent

                $timer          = [System.Windows.Threading.DispatcherTimer]::new()
                $timer.Interval = [TimeSpan]::FromMilliseconds(1500)
                $timer.Tag      = @{ Btn = $saveButton; Bg = $originalBg }
                $timer.Add_Tick({ $this.Tag.Btn.Background = $this.Tag.Bg; $this.Tag.Btn.Content = 'Save'; $this.Stop() })
                $timer.Start()
            }
        }
    }.GetNewClosure())

    # Set tab content
    $consoleTab.Content = $consoleContainer

    # Track whether we're at the start of a line (for timestamp prefixing)
    $atLineStart = [ref]$true

    # Build state bag for appendConsoleText
    $appendState = @{
        Paragraph           = $consoleParagraph
        TextBox             = $consoleTextBox
        Document            = $consoleDocument
        WrapCheckbox        = $wrapCheckbox
        AutoScrollCheckbox  = $autoScrollCheckbox
        TimestampsCheckbox  = $timestampsCheckbox
        AtLineStart         = $atLineStart
        FindState           = $findState
        MaxLineWidth        = $maxLineWidth
        HighlightRunMatches = $highlightRunMatches
    }

    # Return all references needed by caller
    return @{
        Tab                 = $consoleTab
        Container           = $consoleContainer
        TextBox             = $consoleTextBox
        Document            = $consoleDocument
        Paragraph           = $consoleParagraph
        AutoScrollCheckbox  = $autoScrollCheckbox
        WrapCheckbox        = $wrapCheckbox
        PinToTopCheckbox    = $pinToTopCheckbox
        TimestampsCheckbox  = $timestampsCheckbox
        FontSizeSlider      = $fontSizeSlider
        ClearButton         = $clearConsoleButton
        CopyAllButton       = $copyAllButton
        SaveButton          = $saveButton
        FindState           = $findState
        ConsoleColorMap     = $consoleColorMap
        RawColorMap         = $rawColorMap
        AppendConsoleText   = $appendConsoleText
        AppendState         = $appendState
        HighlightRunMatches = $highlightRunMatches
    }
}
