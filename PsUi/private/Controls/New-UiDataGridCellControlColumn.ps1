function New-UiDataGridCellControlColumn {
    <#
    .SYNOPSIS
        Builds a DataGridTemplateColumn hosting a Button, Toggle (CheckBox), or Link per cell.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Column,

        [Parameter(Mandatory)]
        [ValidateSet('Button', 'Toggle', 'Link')]
        [string]$CellType
    )

    $col = [System.Windows.Controls.DataGridTemplateColumn]::new()
    $header = if ($Column.Header) { [string]$Column.Header } else { $CellType }
    $col.Header = $header
    $col.IsReadOnly = $true
    $col.CanUserSort = $false

    # Same width grammar as text columns - '*' and '2*' on a Button/Toggle/Link column used to silently fall to Auto.
    $col.Width = if ($Column.Width) { ConvertTo-UiDataGridLength $Column.Width } else { [System.Windows.Controls.DataGridLength]::Auto }

    # MinWidth floor. The DataGrid lets users drag column edges down to zero, which leaves the cell button / checkbox / link a 1px sliver - unclickable. Use the same header length floor as New-UiDataGridTextColumn / Add-DataGridColumns, raised by a per cell type content floor so an empty Header doesn't collapse a Toggle to less than a checkbox. $Column.MinWidth wins if the user cares.
    $contentFloor = switch ($CellType) {
        'Button' {
            if ($Column.Icon -and !$Column.Binding -and !$Column.Text) { 44 }
            elseif ($Column.Icon)                                      { 80 }
            else                                                        { 60 }
        }
        'Toggle' { 36 }
        'Link'   { 60 }
    }
    $headerFloor  = ($header.Length * 7) + 30
    $col.MinWidth = [Math]::Max($contentFloor, $headerFloor)
    if ($Column.MinWidth) { $col.MinWidth = [double]$Column.MinWidth }

    $tpl = [System.Windows.DataTemplate]::new()

    switch ($CellType) {

        'Button' {

            $factory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.Button])
            $factory.SetValue([System.Windows.Controls.Button]::MarginProperty, [System.Windows.Thickness]::new(2))
            $factory.SetValue([System.Windows.Controls.Button]::PaddingProperty, [System.Windows.Thickness]::new(8, 2, 8, 2))
            $factory.SetValue([System.Windows.Controls.Button]::CursorProperty, [System.Windows.Input.Cursors]::Hand)
            # Lock Height so the press animation (1px border shift) doesn't grow the row.
            $factory.SetValue([System.Windows.Controls.Button]::HeightProperty, [double]24)

            if ($Column.Icon) {

                # Icon and label need DIFFERENT fonts. Icon fonts are symbol only, so setting the icon font on the whole button renders the label as missing glyph boxes.
                $iconText = [PsUi.ModuleContext]::GetIcon([string]$Column.Icon)

                $stackFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.StackPanel])
                $stackFactory.SetValue([System.Windows.Controls.StackPanel]::OrientationProperty, [System.Windows.Controls.Orientation]::Horizontal)
                $stackFactory.SetValue([System.Windows.Controls.StackPanel]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)

                $iconTbFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.TextBlock])
                $iconTbFactory.SetValue([System.Windows.Controls.TextBlock]::TextProperty, $iconText)
                $iconTbFactory.SetValue([System.Windows.Controls.TextBlock]::FontFamilyProperty, [PsUi.ModuleContext]::ActiveIconFontFamily)
                $iconTbFactory.SetValue([System.Windows.Controls.TextBlock]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
                $iconTbFactory.SetValue([System.Windows.Controls.TextBlock]::MarginProperty, [System.Windows.Thickness]::new(0, 0, 6, 0))
                $stackFactory.AppendChild($iconTbFactory)

                # Binding wins for the label: row driven labels (e.g. row.Name) need a Binding, not a frozen string. Static Text stays the fallthrough for action labels like "Delete".
                if ($Column.Binding -or $Column.Text) {
                    $labelTbFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.TextBlock])
                    $labelTbFactory.SetValue([System.Windows.Controls.TextBlock]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
                    if ($Column.Binding) {
                        $labelBinding = [System.Windows.Data.Binding]::new([string]$Column.Binding)
                        $labelBinding.Mode = [System.Windows.Data.BindingMode]::OneWay
                        $labelTbFactory.SetBinding([System.Windows.Controls.TextBlock]::TextProperty, $labelBinding)
                    }
                    else {
                        $labelTbFactory.SetValue([System.Windows.Controls.TextBlock]::TextProperty, [string]$Column.Text)
                    }
                    $stackFactory.AppendChild($labelTbFactory)
                }

                $factory.SetValue([System.Windows.Controls.Button]::ContentProperty, $null)
                $factory.AppendChild($stackFactory)
            }
            elseif ($Column.Binding) {
                $contentBinding = [System.Windows.Data.Binding]::new([string]$Column.Binding)
                $contentBinding.Mode = [System.Windows.Data.BindingMode]::OneWay
                $factory.SetBinding([System.Windows.Controls.Button]::ContentProperty, $contentBinding)
            }
            else { $factory.SetValue([System.Windows.Controls.Button]::ContentProperty, [string]$Column.Text) }

            # Resource reference so the style follows theme switches at runtime.
            $factory.SetResourceReference([System.Windows.Controls.Button]::StyleProperty, 'ModernButtonStyle')

            # Invoke-UiAction handles execution semantics ($_ binding, refresh, host routing).
            $cellAction = $Column.Action
            $cellSync   = if ($Column.Contains('Sync')) { [bool]$Column['Sync'] } else { $false }
            $clickHandler = {
                param($sender, $eventArgs)
                $row = $sender.DataContext
                if (!$cellAction) { return }

                # Walk up to find the owning DataGrid so Invoke-UiAction can refresh it.
                $grid = $sender
                while ($grid -and $grid -isnot [System.Windows.Controls.DataGrid]) {
                    $grid = [System.Windows.Media.VisualTreeHelper]::GetParent($grid)
                }

                Invoke-UiAction -Action $cellAction -Item $row -RefreshTarget $grid -Sync:$cellSync
            }.GetNewClosure()

            $factory.AddHandler([System.Windows.Controls.Button]::ClickEvent, [System.Windows.RoutedEventHandler]$clickHandler)
            $tpl.VisualTree = $factory
            $col.CellTemplate = $tpl
        }

        'Toggle' {

            $factory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.CheckBox])
            $factory.SetValue([System.Windows.Controls.CheckBox]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
            $factory.SetValue([System.Windows.Controls.CheckBox]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
            $factory.SetValue([System.Windows.Controls.CheckBox]::CursorProperty, [System.Windows.Input.Cursors]::Hand)

            # Same template Set-CheckBoxStyle uses.
            $factory.SetValue([System.Windows.Controls.CheckBox]::StyleProperty, (Get-UiDataGridCheckBoxStyle))

            # Header defaults to the literal 'Toggle' string at the top when no header is set - binding to that silently misses the actual bool property. Require an explicit Binding instead of guessing from Header.
            if (!$Column.Binding) {
                throw "New-UiDataGrid: Toggle cell requires -Binding to specify the bool property to bind to. Add Binding = 'PropName' to the column hashtable."
            }
            $bindPath = [string]$Column.Binding
            $binding  = [System.Windows.Data.Binding]::new($bindPath)
            $binding.Mode = [System.Windows.Data.BindingMode]::TwoWay
            $binding.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::PropertyChanged
            $factory.SetBinding([System.Windows.Controls.CheckBox]::IsCheckedProperty, $binding)

            # Click, not Checked/Unchecked. Those also fire when the TwoWay binding writes the initial value at container realization and again on virtualization recycling, running user side effects for rows nobody touched. Click fires only on real input (mouse, spacebar), after IsChecked has already flipped. Attached even without OnChange: the binding wrote the row, but its baked _SearchText still holds the old value (no edit transaction runs for a template column checkbox, so RowEditEnding never rebuilds it).
            $onChange = $Column.OnChange
            $changeHandler = {
                param($sender, $eventArgs)
                $row = $sender.DataContext
                $newValue = $sender.IsChecked

                if ($null -ne $row -and $row.PSObject.Properties['_SearchText']) {
                    Add-UiDataGridSearchText -PsObject $row -Force
                }

                # Stale filter cache would keep matching the pre toggle text on not owned rows.
                try {
                    $grid = $sender
                    while ($grid -and $grid -isnot [System.Windows.Controls.DataGrid]) {
                        $grid = [System.Windows.Media.VisualTreeHelper]::GetParent($grid)
                    }
                    $gridTag = if ($grid) { $grid.Tag } else { $null }
                    $filterBox = if ($gridTag -is [hashtable] -and $gridTag.FilterBox) { $gridTag.FilterBox } else { $null }
                    if ($filterBox -and $filterBox.Tag -and $filterBox.Tag.ClearSearchCache) { & $filterBox.Tag.ClearSearchCache }
                }
                catch { Write-Debug "Toggle filter cache invalidation skipped: $_" }

                if (!$onChange) { return }

                # ForEach-Object binds $_ to the row. The .EXAMPLE in New-UiDataGrid uses $_.PropertyName form, so the natural scriptblock would silently see $null without this pipe.
                try { $row | ForEach-Object { & $onChange $_ $newValue } }
                catch { Write-Debug "Toggle OnChange failed: $($_.Exception.Message)" }
            }.GetNewClosure()

            $factory.AddHandler([System.Windows.Controls.CheckBox]::ClickEvent, [System.Windows.RoutedEventHandler]$changeHandler)

            # Template columns have no path of their own, and Get-UiDataGridVisibleColumnPaths skips pathless columns - without this, copy/export silently drop the toggle's bool.
            $col.ClipboardContentBinding = [System.Windows.Data.Binding]::new($bindPath)

            $tpl.VisualTree = $factory
            $col.CellTemplate = $tpl
        }

        'Link' {

            # WPF's Hyperlink ignores theme changes (hardcoded blue/purple since... 2004?). TextBlock/underline is the workaround. Selected row trigger swaps the color.

            $tbFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.TextBlock])
            
            # Binding wins for per row labels (row.Url, row.Name). Static Text is the fallthrough.
            if ($Column.Binding) {
                $linkBinding = [System.Windows.Data.Binding]::new([string]$Column.Binding)
                $linkBinding.Mode = [System.Windows.Data.BindingMode]::OneWay
                $tbFactory.SetBinding([System.Windows.Controls.TextBlock]::TextProperty, $linkBinding)
            }
            else {
                $linkText = if ($Column.Text) { [string]$Column.Text } else { 'Open' }
                $tbFactory.SetValue([System.Windows.Controls.TextBlock]::TextProperty, $linkText)
            }

            $tbFactory.SetValue([System.Windows.Controls.TextBlock]::FontFamilyProperty, [System.Windows.Media.FontFamily]::new('Segoe UI Variable, Segoe UI'))
            $tbFactory.SetValue([System.Windows.Controls.TextBlock]::FontSizeProperty, [double]13)
            $tbFactory.SetValue([System.Windows.Controls.TextBlock]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
            $tbFactory.SetValue([System.Windows.Controls.TextBlock]::MarginProperty, [System.Windows.Thickness]::new(4, 2, 4, 2))
            $tbFactory.SetValue([System.Windows.Controls.TextBlock]::CursorProperty, [System.Windows.Input.Cursors]::Hand)
            $tbFactory.SetValue([System.Windows.Controls.TextBlock]::TextDecorationsProperty, [System.Windows.TextDecorations]::Underline)

            $linkStyle = [System.Windows.Style]::new([System.Windows.Controls.TextBlock])

            [void]$linkStyle.Setters.Add([System.Windows.Setter]::new( [System.Windows.Controls.TextBlock]::ForegroundProperty, [System.Windows.DynamicResourceExtension]::new('AccentBrush')))

            $linkSelTrigger = [System.Windows.DataTrigger]::new()
            $linkSelBinding = [System.Windows.Data.Binding]::new('IsSelected')
            $linkSelBinding.RelativeSource = [System.Windows.Data.RelativeSource]::new(  [System.Windows.Data.RelativeSourceMode]::FindAncestor,   [System.Windows.Controls.DataGridRow], 1)

            $linkSelTrigger.Binding = $linkSelBinding
            $linkSelTrigger.Value   = $true
            [void]$linkSelTrigger.Setters.Add([System.Windows.Setter]::new(  [System.Windows.Controls.TextBlock]::ForegroundProperty,  [System.Windows.DynamicResourceExtension]::new('SelectionTextBrush')))

            [void]$linkStyle.Triggers.Add($linkSelTrigger)
            $tbFactory.SetValue([System.Windows.Controls.TextBlock]::StyleProperty, $linkStyle)

            $linkUrl    = if ($Column.Url) { [string]$Column.Url } else { $null }
            $linkAction = $Column.Action
            $allowFile  = [bool]$Column.AllowFileScheme
            $linkSync   = if ($Column.Contains('Sync')) { [bool]$Column['Sync'] } else { $false }

            $tbClick = {
                param($sender, $eventArgs)
                $row = $sender.DataContext

                if ($linkAction) {
                    # Walk up to the owning DataGrid so Invoke-UiAction can refresh after.
                    $grid = $sender

                    while ($grid -and $grid -isnot [System.Windows.Controls.DataGrid]) {
                        $grid = [System.Windows.Media.VisualTreeHelper]::GetParent($grid)
                    }

                    Invoke-UiAction -Action $linkAction -Item $row -RefreshTarget $grid -Sync:$linkSync
                    return
                }
                if (!$linkUrl) { return }

                # {Prop} placeholders get resolved against the row at click time.
                $resolved = [regex]::Replace($linkUrl, '\{(\w+)\}', {
                    param($match)
                    $propName = $match.Groups[1].Value
                    $val = $row.$propName
                    if ($null -eq $val) { '' } else { [string]$val }
                })

                # Scheme guard. file: is off by default - {Prop} substitutes literally, so untrusted row data in a Url template can otherwise launch e.g. 'C:\evil.exe'. Set AllowFileScheme = $true on the column hashtable to opt in.
                $schemePattern = if ($allowFile) { '^(https?|mailto|tel|file):' } else { '^(https?|mailto|tel):' }
                if ($resolved -notmatch $schemePattern) {
                    Write-Warning "Link Url '$resolved' blocked: scheme not allowed."
                    return
                }
                Start-Process $resolved
            }.GetNewClosure()

            $tbFactory.AddHandler([System.Windows.UIElement]::MouseLeftButtonUpEvent, [System.Windows.Input.MouseButtonEventHandler]$tbClick)

            $tpl.VisualTree = $tbFactory
            $col.CellTemplate = $tpl
        }
    }

    return $col
}
