function Show-UiGlyphBrowser {
    <#
    .SYNOPSIS
        Opens a child window displaying all available glyphs.
    .DESCRIPTION
        Shows a searchable grid of all glyphs defined in CharList.json.
        Click a glyph to copy its name to the clipboard.
    .PARAMETER Parent
        The parent window. If not specified, uses the current session's window.
    .EXAMPLE
        Show-UiGlyphBrowser
    .EXAMPLE
        $parentSession = Get-UiSession
        Show-UiGlyphBrowser -Parent $parentSession.Window
    #>
    [CmdletBinding()]
    param(
        [System.Windows.Window]$Parent
    )

    if (!$Parent) {
        $session = Get-UiSession
        if ($session -and $session.Window) {
            $Parent = $session.Window
        }
    }

    $iconDict = [PsUi.ModuleContext]::Icons

    # Deduplicate (keep first occurrence of each glyph character)
    $seenChars = @{}
    $glyphList = [System.Collections.Generic.List[object]]::new()
    foreach ($kvp in $iconDict.GetEnumerator()) {
        $char = $kvp.Value
        if (!$seenChars.ContainsKey($char)) {
            $seenChars[$char] = $kvp.Key
            $glyphList.Add([PSCustomObject]@{ Name = $kvp.Key; Char = $char })
        }
    }
    $glyphList = $glyphList | Sort-Object Name

    # Pre-count renderable glyphs under the active font so the title reflects what's actually on
    # screen. Iterates IsGlyphAvailable once (cache-hits after the first lookup) - cheaper than
    # any other way of plumbing the count out of the per-tile loop below. Flipping the fallback
    # via Set-PsUiIconFont and reopening the browser changes this number, which is the whole point.
    $renderable = 0
    foreach ($g in $glyphList) {
        if ([PsUi.ModuleContext]::IsGlyphAvailable($g.Name)) { $renderable++ }
    }

    # Pre-create brushes BEFORE the content block since private functions aren't accessible inside
    $colors = Get-ThemeColors
    $tileBgBrush        = ConvertTo-UiBrush $colors.ControlBg
    $borderBrush        = ConvertTo-UiBrush $colors.Border
    $fgBrush            = ConvertTo-UiBrush $colors.ControlFg
    $secondaryTextBrush = ConvertTo-UiBrush $colors.SecondaryText

    $childParams = @{
        Title   = "Glyph Browser - $(Get-PsUiIconFont) ($renderable of $($glyphList.Count) renderable)"
        Width   = 867.5
        Height  = 600
        Content = {
            New-UiLabel -Text "$(Get-PsUiIconFont) Icon Browser" -Style Title
            New-UiLabel -Text "Click any icon to copy its name to clipboard. Dimmed icons are missing from the active font; hover any tile to see which font(s) carry it. Use -Icon 'Name' with buttons, cards, and panels." -Style Note
            New-UiInput -Label 'Search' -Variable 'glyphSearch' -Placeholder 'Type to filter glyphs...'

            $session = Get-UiSession

            # WrapPanel for glyph tiles - child window already has a ScrollViewer
            $wrapPanel = [System.Windows.Controls.WrapPanel]@{
                Orientation = 'Horizontal'
                Margin      = [System.Windows.Thickness]::new(0, 8, 0, 0)
            }

            # Pre-resolve the active font name once to avoid extra lookups per tile
            $activeName = [PsUi.ModuleContext]::ActiveIconFontName

            # Tooltip badge enumerates the fonts each glyph is carried by.
            # Add a new entry here when MS ships another icon font - the rest stays as-is.
            $fontSpecs = @(
                @{ Short = 'MDL2'   ; Name = [PsUi.ModuleContext]::FontNameMDL2   }
                @{ Short = 'Fluent' ; Name = [PsUi.ModuleContext]::FontNameFluent }
            )

            # Create glyph tiles using pre-created brushes (captured via AST)
            foreach ($glyph in $glyphList) {
                # Per-glyph availability in each font drives the tooltip badge
                $inActive  = [PsUi.ModuleContext]::IsGlyphAvailable($glyph.Name)
                $carriedBy = foreach ($spec in $fontSpecs) {
                    if ([PsUi.ModuleContext]::IsGlyphAvailableInFont($glyph.Name, $spec.Name)) { $spec.Short }
                }
                $badge   = if ($carriedBy) { $carriedBy -join ', ' } else { 'not available' }
                $tipText = if ($inActive) { "$($glyph.Name) ($badge)" } else { "$($glyph.Name) (not in $activeName - $badge)" }

                $tile = [System.Windows.Controls.Border]@{
                    Width           = 75
                    Height          = 75
                    Margin          = [System.Windows.Thickness]::new(3)
                    Background      = $tileBgBrush
                    BorderBrush     = $borderBrush
                    BorderThickness = [System.Windows.Thickness]::new(1)
                    CornerRadius    = [System.Windows.CornerRadius]::new(4)
                    Cursor          = 'Hand'
                    ToolTip         = $tipText
                    Tag             = @{ Name = $glyph.Name }
                }

                $stack = [System.Windows.Controls.StackPanel]@{
                    Orientation         = 'Vertical'
                    HorizontalAlignment = 'Center'
                    VerticalAlignment   = 'Center'
                    IsHitTestVisible    = $false
                }

                # Dim glyphs missing from the active font
                $tileOpacity = if ($inActive) { 1.0 } else { 0.3 }

                $icon = [System.Windows.Controls.TextBlock]@{
                    Text                = $glyph.Char
                    FontFamily          = [PsUi.ModuleContext]::ActiveIconFontFamily
                    FontSize            = 24
                    Foreground          = $fgBrush
                    HorizontalAlignment = 'Center'
                    Margin              = [System.Windows.Thickness]::new(0, 6, 0, 2)
                    Opacity             = $tileOpacity
                }

                $labelText = if ($glyph.Name.Length -gt 9) { $glyph.Name.Substring(0, 7) + '..' } else { $glyph.Name }
                $label = [System.Windows.Controls.TextBlock]@{
                    Text                = $labelText
                    FontSize            = 9
                    Foreground          = $secondaryTextBrush
                    HorizontalAlignment = 'Center'
                    TextTrimming        = 'CharacterEllipsis'
                    Opacity             = $tileOpacity
                }

                $stack.Children.Add($icon) | Out-Null
                $stack.Children.Add($label) | Out-Null
                $tile.Child = $stack

                # Register for theme updates (ThemeEngine is a static class, always available)
                try {
                    [PsUi.ThemeEngine]::RegisterElement($tile)
                    [PsUi.ThemeEngine]::RegisterElement($icon)
                    [PsUi.ThemeEngine]::RegisterElement($label)
                }
                catch { Write-Debug "ThemeEngine registration failed: $_" }

                # Click to copy name to clipboard
                $tile.Add_MouseLeftButtonUp({
                    param($sender, $eventArgs)
                    $data = $sender.Tag
                    [System.Windows.Clipboard]::SetText($data.Name)

                    # Flash accent color then restore - fetch fresh colors for theme support
                    $flashColors = Get-ThemeColors
                    $sender.Background = ConvertTo-UiBrush $flashColors.Accent
                    $timer = [System.Windows.Threading.DispatcherTimer]::new()
                    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
                    $ref = $sender
                    $timer.Add_Tick({
                        $restoreColors = Get-ThemeColors
                        $ref.Background = ConvertTo-UiBrush $restoreColors.ControlBg
                        $this.Stop()
                    }.GetNewClosure())
                    $timer.Start()
                }.GetNewClosure())

                $wrapPanel.Children.Add($tile) | Out-Null
            }

            # Add wrap panel directly to parent - child window already provides ScrollViewer
            $session.CurrentParent.Children.Add($wrapPanel) | Out-Null

            # Store reference for filtering
            $session.Variables['_glyphWrapPanel'] = $wrapPanel

            $searchBox = $session.GetControl('glyphSearch')
            if ($searchBox) {
                $searchBox.Add_TextChanged({
                    $sess = Get-UiSession
                    $panel = $sess.Variables['_glyphWrapPanel']
                    $filter = $this.Text.ToLower()

                    foreach ($child in $panel.Children) {
                        $name = $child.Tag.Name
                        if ([string]::IsNullOrEmpty($filter) -or $name.ToLower().Contains($filter)) {
                            $child.Visibility = 'Visible'
                        }
                        else {
                            $child.Visibility = 'Collapsed'
                        }
                    }
                }.GetNewClosure())
            }
        }
    }

    if ($Parent) {
        $childParams['Parent'] = $Parent
    }

    New-UiChildWindow @childParams
}
