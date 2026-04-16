function Add-MultiTypeFilterControls {
    <#
    .SYNOPSIS
        Adds filter box and column visibility button for multi-type result tabs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.TabControl]$SubTabControl,

        [Parameter(Mandatory)]
        [System.Windows.Controls.StackPanel]$RightToolbar,

        [Parameter(Mandatory)]
        [System.Windows.Controls.StackPanel]$FilterPanel,

        [Parameter(Mandatory)]
        [System.Windows.Controls.DockPanel]$Toolbar2
    )

    $colButton = [System.Windows.Controls.Button]@{
        Padding = 0
        Width   = 32
        Height  = 32
        ToolTip = 'Show/Hide Columns'
        Margin  = [System.Windows.Thickness]::new(0, 0, 4, 0)
        Tag     = $SubTabControl
        Content = [System.Windows.Controls.TextBlock]@{
            Text       = [PsUi.ModuleContext]::GetIcon('AllApps')
            FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        }
    }
    Set-ButtonStyle -Button $colButton -IconOnly

    $colButton.Add_Click({
        param($sender, $eventArgs)
        $tabCtrl = $sender.Tag
        $selectedTab = $tabCtrl.SelectedItem
        if (!$selectedTab) { return }

        $currentGrid = $selectedTab.Content
        if ($currentGrid -isnot [System.Windows.Controls.DataGrid]) { return }

        # Get property info from grid's tag
        $propInfo = $currentGrid.Tag
        if (!$propInfo -or !$propInfo.AllProperties) { return }

        $allProps = @($propInfo.AllProperties)
        $defaultProps = @($propInfo.DefaultProperties)
        $populatedProps = @($propInfo.PopulatedProperties)

        if ($allProps.Count -eq 0) { return }

        # Create and show popup for this grid
        $popup = New-ColumnVisibilityPopup -DataGrid $currentGrid -DefaultProperties $defaultProps -AllProperties $allProps -PopulatedProperties $populatedProps
        $popup.Popup.PlacementTarget = $sender
        $popup.Popup.IsOpen = $true
    }.GetNewClosure())

    $RightToolbar.Children.Insert(0, $colButton)

    $firstTab = $SubTabControl.Items[0]
    if ($firstTab -and $firstTab.Content -isnot [System.Windows.Controls.DataGrid]) {
        $colButton.Visibility = 'Collapsed'
    }

    $filterResult = New-FilterBoxWithClear -Width 200 -Height 28 -IncludeIcon -AdditionalTagData @{
        SubTabControl = $SubTabControl
        Timer         = $null
        Indexing      = $false
    }
    $filterBox = $filterResult.TextBox
    [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($filterBox, $true)

    # Start disabled with "Indexing..." placeholder until first tab is ready
    $filterBox.IsEnabled = $false
    $filterBox.ToolTip = 'Indexing...'
    $filterResult.Watermark.Text = 'Indexing...'

    $SubTabControl.Tag = $filterBox

    [void]$FilterPanel.Children.Add($filterResult.Icon)
    [void]$FilterPanel.Children.Add($filterResult.Container)
    [System.Windows.Controls.DockPanel]::SetDock($FilterPanel, 'Left')
    $Toolbar2.Children.Insert(0, $FilterPanel)

    $filterBox.Add_TextChanged({
        $tag = $this.Tag

        $tag.ClearButton.Visibility = if ([string]::IsNullOrEmpty($this.Text)) { 'Collapsed' } else { 'Visible' }

        if ($tag.Timer) {
            $tag.Timer.Stop()
            $tag.Timer = $null
        }

        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(300)
        $timer.Tag = $this
        $tag.Timer = $timer

        $timer.Add_Tick({
            try {
                $fb = $this.Tag
                $fbTag = $fb.Tag
                $subTabs = $fbTag.SubTabControl

                $selectedTab = $subTabs.SelectedItem
                if (!$selectedTab) { return }

                $searchText = $fb.Text.Trim()

                # TextType tabs (string output) - highlight matches
                if ($selectedTab.Tag -eq 'TextType') {
                    $rtb = $selectedTab.Content
                    if ($rtb -isnot [System.Windows.Controls.RichTextBox]) { return }
                    Find-ConsoleText -RichTextBox $rtb -SearchText $searchText
                    return
                }

                # DataGrid tabs - rebuild collection to filter (avoids delegate issues with sorting)
                $currentGrid = $selectedTab.Content
                if ($currentGrid -isnot [System.Windows.Controls.DataGrid]) { return }

                $gridTag = $currentGrid.Tag
                if (!$gridTag -or !$gridTag.UnfilteredItems -or !$gridTag.Observable) { return }

                $unfilteredItems = $gridTag.UnfilteredItems
                $observable = $gridTag.Observable

                # Save sort state
                $view = $currentGrid.ItemsSource
                $sortDescriptions = @()
                if ($view) {
                    foreach ($sd in $view.SortDescriptions) {
                        $sortDescriptions += $sd
                    }
                }

                # Filter by rebuilding collection
                $observable.Clear()

                foreach ($item in $unfilteredItems) {
                    if ([string]::IsNullOrEmpty($searchText)) {
                        [void]$observable.Add($item)
                    }
                    else {
                        $st = $item._SearchText
                        if ($st -and $st.IndexOf($searchText, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                            [void]$observable.Add($item)
                        }
                    }
                }

                # Put sort back
                if ($view -and $sortDescriptions.Count -gt 0) {
                    $view.SortDescriptions.Clear()
                    foreach ($sd in $sortDescriptions) {
                        $view.SortDescriptions.Add($sd)
                    }
                }
            }
            catch {
                Write-Debug "Filter failed: $_"
            }
            finally {
                $this.Stop()
                $fb = $this.Tag
                $fb.Tag.Timer = $null
            }
        })

        $timer.Start()
    })

    return @{
        FilterBox    = $filterBox
        ColumnButton = $colButton
    }
}
