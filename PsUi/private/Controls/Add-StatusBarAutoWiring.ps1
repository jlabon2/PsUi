$script:StatusBarDefaults = @{
    MaxMessageChars = 120
    SuccessTimeout  = 2
    WarningTimeout  = 5
    ErrorTimeout    = 8
    CancelTimeout   = 3
}

function Add-StatusBarAutoWiring {
    <#
    .SYNOPSIS
        Routes executor lifecycle events to any registered status bar that opted in.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Executor,

        [Parameter(Mandatory)]
        $Session,

        [string]$ActionName
    )

    if (!$Executor -or !$Session) { return }

    # Collect every bar that opted in to auto-routing
    $targets = [System.Collections.Generic.List[object]]::new()
    foreach ($key in @($Session.SafeVariables.Keys)) {
        $candidate = $Session.GetControl($key)
        if (!$candidate -or $candidate.Tag -isnot [hashtable]) { continue }
        if (!$candidate.Tag['IsStatusBar']) { continue }
        if (!$candidate.Tag['AutoProgress'] -and !$candidate.Tag['AutoCancel'] -and !$candidate.Tag['Intercept']) { continue }
        $targets.Add($candidate)
    }
    if ($targets.Count -eq 0) { return }

    # Reset severity synchronously before the executor starts. OnStarted fires from a ThreadPool
    # via BeginInvoke, and the dispatch gap is long enough for WPF to paint one frame of stale
    # tint (e.g. leftover green from a prior Success).
    foreach ($bar in $targets) {
        $barMeta = if ($bar.Tag -is [hashtable]) { $bar.Tag } else { @{} }
        if ($barMeta.SeverityTimer) { $barMeta.SeverityTimer.Stop() }
        if ($barMeta.Severity -and $barMeta.Severity -ne 'Info') {
            $barMeta.Severity = 'Info'
            Set-StatusBarSeverityVisual -Bar $bar -Severity Info
        }
    }

    # Snapshot defaults so closures inside the handlers don't chase $script: at invoke time
    $successTimeout = $script:StatusBarDefaults.SuccessTimeout
    $warningTimeout = $script:StatusBarDefaults.WarningTimeout
    $errorTimeout   = $script:StatusBarDefaults.ErrorTimeout
    $cancelTimeout  = $script:StatusBarDefaults.CancelTimeout
    $maxChars       = $script:StatusBarDefaults.MaxMessageChars

    foreach ($bar in $targets) {
        $capturedBar      = $bar
        $capturedProgress = $bar.Tag['ProgressBar']
        $capturedText     = $bar.Tag['StatusText']
        $capturedCancel   = $bar.Tag['CancelButton']

        # Small label above the progress bar
        $capturedProgressLabel = $bar.Tag['ProgressLabel']

        # Intercept state for badge tracking
        $capturedIntercept    = [bool]$bar.Tag['Intercept']
        $capturedCaptureHost  = [bool]$bar.Tag['CaptureHost']
        $capturedNoOutputOnly = [bool]$bar.Tag['NoOutputOnly']
        $capturedPersist      = [bool]$bar.Tag['Persist']
        $capturedMaxMessages  = if ($bar.Tag['MaxMessages']) { $bar.Tag['MaxMessages'] } else { 100 }
        $capturedExecutor     = $Executor

        # The $meta guard repeats in every handler. Tag is always the New-UiStatusBar hashtable
        # (if it ever isn't, something larger is broken). Same reference, mutations write through.

        # OnStarted: reveal Cancel button and progress bar (severity already reset above)
        $Executor.add_OnStarted({
            Invoke-OnUIThread {
                if ($capturedCancel) {
                    $capturedCancel.Visibility = [System.Windows.Visibility]::Visible
                    $capturedCancel.IsEnabled  = $true
                }
                # Reset progress label
                if ($capturedProgressLabel) {
                    $capturedProgressLabel.Text       = ''
                    $capturedProgressLabel.Visibility = [System.Windows.Visibility]::Collapsed
                }
                # Reset progress bar state but keep it hidden until Write-Progress fires
                if ($capturedProgress) {
                    $capturedProgress.Value           = 0
                    $capturedProgress.IsIndeterminate = $false
                    $capturedProgress.Visibility      = [System.Windows.Visibility]::Hidden
                }

                # Reset intercept badges for the new action (unless -Persist keeps them)
                if ($capturedIntercept -and !$capturedPersist) {
                    $meta = if ($capturedBar.Tag -is [hashtable]) { $capturedBar.Tag } else { @{} }
                    Reset-StatusBarBadges -Meta $meta
                }
            }
        }.GetNewClosure())

        # OnProgress: drive embedded bar text + fill from Write-Progress
        $Executor.add_OnProgress({
            param($record)
            Invoke-OnUIThread {
                $meta = if ($capturedBar.Tag -is [hashtable]) { $capturedBar.Tag } else { @{} }

                if ($record.RecordType -eq 'Completed') {
                    if ($capturedText) { $capturedText.Text = ''; $capturedText.ToolTip = $null }
                    if ($capturedProgress) {
                        $capturedProgress.IsIndeterminate = $false
                        $capturedProgress.Value           = 0
                        $capturedProgress.Visibility      = [System.Windows.Visibility]::Hidden
                    }
                    if ($capturedProgressLabel) {
                        $capturedProgressLabel.Text       = ''
                        $capturedProgressLabel.Visibility = [System.Windows.Visibility]::Collapsed
                    }

                    Set-StatusBarSeverityVisual -Bar $capturedBar -Severity Success
                    $meta.Severity = 'Success'
                    if ($meta.SeverityTimer) {
                        $meta.SeverityTimer.Stop()
                        $meta.SeverityTimer.Interval = [TimeSpan]::FromSeconds($successTimeout)
                        $meta.SeverityTimer.Start()
                    }
                    return
                }

                # In-progress record: pick the most descriptive text and update fill
                $progressText = if ($record.StatusDescription) { $record.StatusDescription }
                                elseif ($record.Activity)      { $record.Activity }
                                else                            { $null }

                if ($capturedText -and $progressText) { $capturedText.Text = $progressText }

                # Update the small label above the progress bar
                if ($capturedProgressLabel -and $progressText) {
                    $capturedProgressLabel.Text       = $progressText
                    $capturedProgressLabel.Visibility = [System.Windows.Visibility]::Visible
                }

                if ($capturedProgress) {
                    # Reveal the bar on first real progress record
                    $capturedProgress.Visibility = [System.Windows.Visibility]::Visible
                    if ($record.PercentComplete -ge 0) {
                        $capturedProgress.IsIndeterminate = $false
                        $pct = $record.PercentComplete
                        if ($pct -gt 100) { $pct = 100 }
                        $capturedProgress.Value = $pct
                    }
                    else {
                        # Activity-only progress: marquee mode
                        $capturedProgress.IsIndeterminate = $true
                    }
                }
            }
        }.GetNewClosure())

        # OnHostBatch: route Write-Host to status text and console badge
        if ($capturedCaptureHost) {
            $Executor.add_OnHostBatch({
                param($batch)
                Invoke-OnUIThread {
                    if ($batch.Count -eq 0 -or !$capturedText) { return }
                    $meta = if ($capturedBar.Tag -is [hashtable]) { $capturedBar.Tag } else { @{} }

                    # Update the status text with the latest message in the batch
                    $lastRecord            = $batch[$batch.Count - 1]
                    $capturedText.Text     = $lastRecord.Message
                    $capturedText.ToolTip  = if ($lastRecord.Message.Length -gt 60) { $lastRecord.Message } else { $null }
                    try { Add-StatusBarHistoryEntry -Bar $capturedBar -Message $lastRecord.Message -Kind 'Info' }
                    catch { Write-Debug "OnHostBatch ledger entry failed: $_" }

                    # Accumulate every record in the console badge popup
                    if ($null -ne $meta.HostMessages) {
                        foreach ($record in $batch) {
                            if (!$record.Message) { continue }
                            $entry = @{ Time = [DateTime]::Now; Message = $record.Message }
                            if ($meta.HostMessages.Count -ge $capturedMaxMessages) {
                                $meta.HostMessages.RemoveAt(0)
                            }
                            $meta.HostMessages.Add($entry)

                            # Foreground inherited from popup container's TextElement.Foreground
                            $msgBlock = [System.Windows.Controls.TextBlock]@{
                                Text         = "[$($entry.Time.ToString('HH:mm:ss'))] $($record.Message)"
                                TextWrapping = 'Wrap'
                                Margin       = [System.Windows.Thickness]::new(4, 1, 4, 1)
                                FontSize     = 11
                                FontFamily   = [System.Windows.Media.FontFamily]::new('Consolas')
                            }
                            [void]$meta.HostPopup.MessagePanel.Children.Add($msgBlock)

                            # Trim popup panel if over limit
                            if ($meta.HostPopup.MessagePanel.Children.Count -gt $capturedMaxMessages) {
                                $meta.HostPopup.MessagePanel.Children.RemoveAt(0)
                            }
                        }

                        $count = $meta.HostMessages.Count
                        $meta.HostBadge.CountText.Text   = "$count"
                        $meta.HostBadge.Badge.Visibility = [System.Windows.Visibility]::Visible
                        $meta.HostBadge.Badge.Opacity    = 1.0
                        $meta.HostBadge.Badge.ToolTip    = "$count console message$(if ($count -ne 1) { 's' })"
                        $meta.HostPopup.HeaderText.Text  = "$count Message$(if ($count -ne 1) { 's' })"
                    }
                }
            }.GetNewClosure())
        }

        # OnError: the heavyweight. Tints severity, truncates the message for the status text,
        # extracts every diagnostic field PSErrorRecord offers, and builds a popup entry.
        $Executor.add_OnError({
            param($errorRecord)
            $fullErrorMsg = if ($errorRecord -and $errorRecord.Message) { $errorRecord.Message }
                            elseif ($errorRecord) { $errorRecord.ToString() }
                            else { 'Unknown error' }
            $errorMessage = $fullErrorMsg
            if ($null -ne $errorMessage -and $errorMessage.Length -gt $maxChars) {
                $errorMessage = $errorMessage.Substring(0, $maxChars - 3) + '...'
            }

            # Extract every diagnostic field PSErrorRecord has to offer. "Unknown error" is never
            # helpful, so go a little overboard here. Exception type first.
            $exceptionType = $null
            if ($errorRecord.RawRecord -and $errorRecord.RawRecord.Exception) {
                $exceptionType = $errorRecord.RawRecord.Exception.GetType().Name
            }

            # Location: file:line, category, FQEID - whatever the record actually populated
            $locationParts = [System.Collections.Generic.List[string]]::new()
            if ($exceptionType) { $locationParts.Add($exceptionType) }
            if ($errorRecord.ScriptName) {
                $fileName = [System.IO.Path]::GetFileName($errorRecord.ScriptName)
                if ($errorRecord.LineNumber -gt 0) { $locationParts.Add("${fileName}:$($errorRecord.LineNumber)") }
                else { $locationParts.Add($fileName) }
            }
            elseif ($errorRecord.LineNumber -gt 0) {
                $locationParts.Add("line $($errorRecord.LineNumber)")
            }
            if ($errorRecord.Category -and $errorRecord.Category -ne 'NotSpecified') {
                $locationParts.Add($errorRecord.Category)
            }
            if ($errorRecord.FullyQualifiedErrorId) {
                $locationParts.Add($errorRecord.FullyQualifiedErrorId)
            }
            $detailLine = if ($locationParts.Count -gt 0) { $locationParts -join ' | ' } else { $null }
            $codeLine   = if ($errorRecord.Line) { $errorRecord.Line.Trim() } else { $null }

            # First line of ScriptStackTrace gives the call site without the full trace noise
            $stackLine = $null
            if ($errorRecord.ScriptStackTrace) {
                $stackLine = ($errorRecord.ScriptStackTrace -split "`n")[0].Trim()
            }

            # TargetObject reveals what the cmdlet was actually operating on when it blew up
            $targetLine = $null
            if ($errorRecord.TargetObject) {
                $targetStr = $errorRecord.TargetObject.ToString()
                if ($targetStr -and $targetStr -ne $errorRecord.Message -and $targetStr.Length -le $maxChars) {
                    $targetLine = $targetStr
                }
            }

            # Inner exception is often the actual root cause hiding behind the wrapper
            $innerLine = $null
            if ($errorRecord.InnerException) {
                $innerType = $null
                if ($errorRecord.RawRecord -and $errorRecord.RawRecord.Exception -and $errorRecord.RawRecord.Exception.InnerException) {
                    $innerType = $errorRecord.RawRecord.Exception.InnerException.GetType().Name
                }
                $innerLine = if ($innerType) { "${innerType}: $($errorRecord.InnerException)" }
                            else { $errorRecord.InnerException }
            }

            Invoke-OnUIThread {
                if ($capturedText) {
                    $capturedText.Text    = $errorMessage
                    $capturedText.ToolTip = if ($fullErrorMsg.Length -gt 60) { $fullErrorMsg } else { $null }
                }
                try { Add-StatusBarHistoryEntry -Bar $capturedBar -Message $errorMessage -Kind 'Error' }
                catch { Write-Debug "OnError ledger entry failed: $_" }
                if ($capturedProgress) {
                    $capturedProgress.IsIndeterminate = $false
                    if ($capturedProgress.Value -le 0) {
                        $capturedProgress.Visibility = [System.Windows.Visibility]::Hidden
                    }
                }
                if ($capturedCancel) { $capturedCancel.Visibility = [System.Windows.Visibility]::Hidden }

                Set-StatusBarSeverityVisual -Bar $capturedBar -Severity Error
                $meta          = if ($capturedBar.Tag -is [hashtable]) { $capturedBar.Tag } else { @{} }
                $meta.Severity = 'Error'
                if ($meta.SeverityTimer) {
                    $meta.SeverityTimer.Stop()
                    $meta.SeverityTimer.Interval = [TimeSpan]::FromSeconds($errorTimeout)
                    $meta.SeverityTimer.Start()
                }

                # Accumulate in error badge when Intercept is active
                if ($capturedIntercept -and $null -ne $meta.ErrorMessages) {
                    if ($capturedNoOutputOnly -and $capturedExecutor.UseQueueMode) { return }
                    $entry = @{
                        Time    = [DateTime]::Now
                        Message = $fullErrorMsg
                        Detail  = $detailLine
                        Code    = $codeLine
                        Stack   = $stackLine
                        Target  = $targetLine
                        Inner   = $innerLine
                    }
                    if ($meta.ErrorMessages.Count -ge $capturedMaxMessages) { $meta.ErrorMessages.RemoveAt(0) }
                    $meta.ErrorMessages.Add($entry)

                    $count = $meta.ErrorMessages.Count
                    $meta.ErrorBadge.CountText.Text = "$count"
                    $meta.ErrorBadge.Badge.Opacity  = 1.0
                    $meta.ErrorBadge.Badge.ToolTip  = "$count Error$(if ($count -ne 1) { 's' }) - click to view"

                    # Build popup entry: message, location, offending code, stack, target, inner exception.
                    # Text foreground inherits from the popup's outerBorder, so entries track theme automatically.
                    $entryPanel = [System.Windows.Controls.StackPanel]::new()
                    $summaryBlock = [System.Windows.Controls.TextBlock]@{
                        Text         = "[$($entry.Time.ToString('HH:mm:ss'))] $fullErrorMsg"
                        TextWrapping = 'Wrap'
                        Margin       = [System.Windows.Thickness]::new(4, 2, 4, 0)
                        FontSize     = 12
                    }
                    [void]$entryPanel.Children.Add($summaryBlock)

                    if ($detailLine) {
                        $detailBlock = [System.Windows.Controls.TextBlock]@{
                            Text         = "  $detailLine"
                            TextWrapping = 'Wrap'
                            Margin       = [System.Windows.Thickness]::new(4, 0, 4, 0)
                            FontSize     = 10
                            Opacity      = 0.65
                        }
                        [void]$entryPanel.Children.Add($detailBlock)
                    }

                    # Show the offending code line when available
                    if ($codeLine) {
                        $codeBlock = [System.Windows.Controls.TextBlock]@{
                            Text         = "  > $codeLine"
                            TextWrapping = 'Wrap'
                            Margin       = [System.Windows.Thickness]::new(4, 0, 4, 0)
                            FontSize     = 10
                            FontFamily   = [System.Windows.Media.FontFamily]::new('Consolas')
                            Opacity      = 0.5
                        }
                        [void]$entryPanel.Children.Add($codeBlock)
                    }

                    # Show first line of stack trace for call-site context
                    if ($stackLine) {
                        $stackBlock = [System.Windows.Controls.TextBlock]@{
                            Text         = "  $stackLine"
                            TextWrapping = 'Wrap'
                            Margin       = [System.Windows.Thickness]::new(4, 0, 4, 0)
                            FontSize     = 9.5
                            FontFamily   = [System.Windows.Media.FontFamily]::new('Consolas')
                            Opacity      = 0.4
                        }
                        [void]$entryPanel.Children.Add($stackBlock)
                    }

                    # Show what the cmdlet was operating on
                    if ($targetLine) {
                        $targetBlock = [System.Windows.Controls.TextBlock]@{
                            Text         = "  Target: $targetLine"
                            TextWrapping = 'Wrap'
                            Margin       = [System.Windows.Thickness]::new(4, 0, 4, 0)
                            FontSize     = 10
                            FontFamily   = [System.Windows.Media.FontFamily]::new('Consolas')
                            Opacity      = 0.45
                        }
                        [void]$entryPanel.Children.Add($targetBlock)
                    }

                    # Show root cause when the exception wraps another
                    if ($innerLine) {
                        $innerBlock = [System.Windows.Controls.TextBlock]@{
                            Text         = "  Inner: $innerLine"
                            TextWrapping = 'Wrap'
                            Margin       = [System.Windows.Thickness]::new(4, 0, 4, 2)
                            FontSize     = 10
                            FontFamily   = [System.Windows.Media.FontFamily]::new('Consolas')
                            Opacity      = 0.45
                        }
                        [void]$entryPanel.Children.Add($innerBlock)
                    }

                    [void]$meta.ErrorPopup.MessagePanel.Children.Add($entryPanel)
                    $meta.ErrorPopup.HeaderText.Text = "$count Error$(if ($count -ne 1) { 's' })"

                    # Trim popup panel if over limit
                    if ($meta.ErrorPopup.MessagePanel.Children.Count -gt $capturedMaxMessages) {
                        $meta.ErrorPopup.MessagePanel.Children.RemoveAt(0)
                    }
                }
            }
        }.GetNewClosure())

        # OnWarning: tint Warning with truncated message and accumulate badge
        $Executor.add_OnWarning({
            param($warningMessage)
            $fullWarnMsg = $warningMessage
            $shown       = $warningMessage
            if ($null -ne $shown -and $shown.Length -gt $maxChars) {
                $shown = $shown.Substring(0, $maxChars - 3) + '...'
            }

            Invoke-OnUIThread {
                if ($capturedText -and $shown) {
                    $capturedText.Text    = $shown
                    $capturedText.ToolTip = if ($fullWarnMsg.Length -gt 60) { $fullWarnMsg } else { $null }
                    try { Add-StatusBarHistoryEntry -Bar $capturedBar -Message $shown -Kind 'Warning' }
                    catch { Write-Debug "OnWarning ledger entry failed: $_" }
                }
                Set-StatusBarSeverityVisual -Bar $capturedBar -Severity Warning
                $meta          = if ($capturedBar.Tag -is [hashtable]) { $capturedBar.Tag } else { @{} }
                $meta.Severity = 'Warning'
                if ($meta.SeverityTimer) {
                    $meta.SeverityTimer.Stop()
                    $meta.SeverityTimer.Interval = [TimeSpan]::FromSeconds($warningTimeout)
                    $meta.SeverityTimer.Start()
                }

                # Accumulate in warning badge when Intercept is active
                if ($capturedIntercept -and $null -ne $meta.WarningMessages) {
                    if ($capturedNoOutputOnly -and $capturedExecutor.UseQueueMode) { return }
                    $entry = @{ Time = [DateTime]::Now; Message = $fullWarnMsg }
                    if ($meta.WarningMessages.Count -ge $capturedMaxMessages) { $meta.WarningMessages.RemoveAt(0) }
                    $meta.WarningMessages.Add($entry)

                    $count = $meta.WarningMessages.Count
                    $meta.WarningBadge.CountText.Text = "$count"
                    $meta.WarningBadge.Badge.Opacity  = 1.0
                    $meta.WarningBadge.Badge.ToolTip  = "$count Warning$(if ($count -ne 1) { 's' }) - click to view"

                    # Foreground inherited from popup container's TextElement.Foreground
                    $msgBlock = [System.Windows.Controls.TextBlock]@{
                        Text         = "[$($entry.Time.ToString('HH:mm:ss'))] $fullWarnMsg"
                        TextWrapping = 'Wrap'
                        Margin       = [System.Windows.Thickness]::new(4, 2, 4, 2)
                        FontSize     = 12
                    }
                    [void]$meta.WarningPopup.MessagePanel.Children.Add($msgBlock)
                    $meta.WarningPopup.HeaderText.Text = "$count Warning$(if ($count -ne 1) { 's' })"

                    # Trim popup panel if over limit
                    if ($meta.WarningPopup.MessagePanel.Children.Count -gt $capturedMaxMessages) {
                        $meta.WarningPopup.MessagePanel.Children.RemoveAt(0)
                    }
                }
            }
        }.GetNewClosure())

        # OnCancelled: tint Warning briefly and reset the running visuals
        $Executor.add_OnCancelled({
            Invoke-OnUIThread {
                if ($capturedText) { $capturedText.Text = 'Cancelled'; $capturedText.ToolTip = $null }
                try { Add-StatusBarHistoryEntry -Bar $capturedBar -Message 'Cancelled' -Kind 'Warning' }
                catch { Write-Debug "OnCancelled ledger entry failed: $_" }
                if ($capturedProgress) {
                    $capturedProgress.IsIndeterminate = $false
                    if ($capturedProgress.Value -le 0) {
                        $capturedProgress.Visibility = [System.Windows.Visibility]::Hidden
                    }
                }
                if ($capturedCancel) { $capturedCancel.Visibility = [System.Windows.Visibility]::Hidden }
                if ($capturedProgressLabel) {
                    $capturedProgressLabel.Text       = ''
                    $capturedProgressLabel.Visibility = [System.Windows.Visibility]::Collapsed
                }

                Set-StatusBarSeverityVisual -Bar $capturedBar -Severity Warning
                $meta          = if ($capturedBar.Tag -is [hashtable]) { $capturedBar.Tag } else { @{} }
                $meta.Severity = 'Warning'
                if ($meta.SeverityTimer) {
                    $meta.SeverityTimer.Stop()
                    $meta.SeverityTimer.Interval = [TimeSpan]::FromSeconds($cancelTimeout)
                    $meta.SeverityTimer.Start()
                }
            }
        }.GetNewClosure())

        # OnComplete: hide Cancel and progress bar, drop indeterminate. Leave text
        # and severity alone so the user's last Write-Status / Set-UiStatusBar wins.
        $Executor.add_OnComplete({
            Invoke-OnUIThread {
                if ($capturedCancel) { $capturedCancel.Visibility = [System.Windows.Visibility]::Hidden }
                if ($capturedProgressLabel) {
                    $capturedProgressLabel.Text       = ''
                    $capturedProgressLabel.Visibility = [System.Windows.Visibility]::Collapsed
                }
                if ($capturedProgress) {
                    $capturedProgress.IsIndeterminate = $false
                    if ($capturedProgress.Value -le 0) {
                        $capturedProgress.Visibility = [System.Windows.Visibility]::Hidden
                    }
                }
            }
        }.GetNewClosure())
    }
}
