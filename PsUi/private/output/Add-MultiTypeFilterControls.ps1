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
            FontFamily = [PsUi.ModuleContext]::ActiveIconFontFamily
        }
    }
    Set-ButtonStyle -Button $colButton -IconOnly

    $colButton.Add_Click({
        param($sender, $eventArgs)
        $tabCtrl = $sender.Tag
        $selectedTab = $tabCtrl.SelectedItem
        if (!$selectedTab) { return }

        $currentGrid = Get-UiSubTabGrid -Tab $selectedTab
        if (!$currentGrid) { return }

        # Get property info from grid's tag
        $propInfo = $currentGrid.Tag
        if ($null -eq $propInfo -or $null -eq $propInfo.AllProperties) { return }

        $allProps = @($propInfo.AllProperties)
        if ($allProps.Count -eq 0) { return }

        # One popup per grid, on the Tag, else a fresh one per click throws away its signature caching and rebuilds a ton of checkboxes every open.
        $popup = $currentGrid.Tag.ColumnPopup
        if (!$popup) {
            # Read each open, or a cached popup misses a column set that changed after it was built.
            $gridForProvider = $currentGrid
            $popupArgs       = @{
                DataGrid           = $currentGrid
                PropertiesProvider = {
                    @{
                        All       = @($gridForProvider.Tag.AllProperties)
                        Default   = @($gridForProvider.Tag.DefaultProperties)
                        Populated = @($gridForProvider.Tag.PopulatedProperties)
                    }
                }.GetNewClosure()
                ItemsProvider      = { $gridForProvider.Tag.UnfilteredItems }.GetNewClosure()
            }
            $popup = New-ColumnVisibilityPopup @popupArgs
            $currentGrid.Tag.ColumnPopup = $popup
        }
        $popup.Popup.PlacementTarget = $sender

        # The popup's opened handler runs the lazy count walk, which can trip a CheckActionPreference NRE, and the popup still shows. The throw just escapes IsOpen.
        try { $popup.Popup.IsOpen = $true }
        catch { Write-Verbose "Failed to open column popup: $_" }
    }.GetNewClosure())

    $RightToolbar.Children.Insert(0, $colButton)

    $filterResult = New-FilterBoxWithClear -Width 200 -Height 28 -IncludeIcon -AdditionalTagData @{
        SubTabControl = $SubTabControl
        ColumnButton  = $colButton
        Timer         = $null
    }
    $filterBox = $filterResult.TextBox
    [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($filterBox, $true)

    # The tab switch runs this too, since a tab left mid search keeps its emptied rows and an already empty box raises no TextChanged to put them back.
    $filterBox.Tag.RunFilter = {
        param($fb)
        $subTabs     = $fb.Tag.SubTabControl
        $selectedTab = $subTabs.SelectedItem
        if (!$selectedTab) { return }

        $searchText = $fb.Text.Trim()

        # Text tabs highlight their matches in place.
        if ($selectedTab.Tag -eq 'TextType') {
            $rtb = $selectedTab.Content
            if ($rtb -isnot [System.Windows.Controls.RichTextBox]) { return }
            Find-ConsoleText -RichTextBox $rtb -SearchText $searchText
            return
        }

        # Grid tabs rebuild the collection instead of filtering the view, which dodges the sorting trouble a filter delegate brings.
        $currentGrid = Get-UiSubTabGrid -Tab $selectedTab
        if (!$currentGrid) { return }

        $gridTag = $currentGrid.Tag
        # An empty ObservableCollection is falsy, so a truthiness check here kills the filter after the first search that matches no rows.
        if ($null -eq $gridTag -or $null -eq $gridTag.UnfilteredItems -or $null -eq $gridTag.Observable) { return }

        $unfilteredItems = $gridTag.UnfilteredItems
        $observable = $gridTag.Observable

        # Save sort state
        $view = $currentGrid.ItemsSource
        $sortDescriptions = [System.Collections.Generic.List[System.ComponentModel.SortDescription]]::new()
        if ($view) {
            foreach ($sd in $view.SortDescriptions) {
                $sortDescriptions.Add($sd)
            }
        }

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

        # Emptying the grid with a search reads differently from a tab that never had rows. Only while the grid is actually empty, or the term outlives the search that produced it.
        $overlay      = $selectedTab.Content
        $overlayState = if ($overlay -is [System.Windows.FrameworkElement]) { $overlay.Resources['__EmptyOverlay'] } else { $null }
        if ($overlayState) {
            $overlayState.MessageBlock.Text = if ([string]::IsNullOrEmpty($searchText) -or $observable.Count -gt 0) { $overlayState.DefaultMessage }
                                              else { "No items matched '$searchText'" }
        }

        # Put sort back
        if ($view -and $sortDescriptions.Count -gt 0) {
            $view.SortDescriptions.Clear()
            foreach ($sd in $sortDescriptions) {
                $view.SortDescriptions.Add($sd)
            }
        }
    }

    $SubTabControl.Tag = $filterBox

    # The tab switch handler never fires for the tab the results open on.
    $openingTab = $SubTabControl.SelectedItem
    if (!$openingTab -and $SubTabControl.Items.Count -gt 0) { $openingTab = $SubTabControl.Items[0] }
    Set-UiSubTabToolbarState -Tab $openingTab -FilterBox $filterBox

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
            try { & $this.Tag.Tag.RunFilter $this.Tag }
            catch { Write-Debug "Filter failed: $_" }
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
