function Add-UiDataGridEmptyOverlay {
    <#
    .SYNOPSIS
        Centered 'no items' placeholder (icon + message) over the grid when it's empty.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$HostControl,

        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) { $Message = 'No items to display.' }

    # Pin to 32. Without a fixed height the header floats and the overlay row looks like straight garbo
    $headerBandHeight  = 32.0
    $DataGrid.ColumnHeaderHeight = $headerBandHeight

    $wrapper   = [System.Windows.Controls.Grid]::new()
    $headerRow = [System.Windows.Controls.RowDefinition]@{ Height = [System.Windows.GridLength]::new($headerBandHeight) }
    $bodyRow   = [System.Windows.Controls.RowDefinition]@{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }

    [void]$wrapper.RowDefinitions.Add($headerRow)
    [void]$wrapper.RowDefinitions.Add($bodyRow)

    [System.Windows.Controls.Grid]::SetRow($HostControl, 0)
    [System.Windows.Controls.Grid]::SetRowSpan($HostControl, 2)
    [void]$wrapper.Children.Add($HostControl)

    $iconBlock = $null
    $glyph = [PsUi.ModuleContext]::GetIcon('BulletedList')

    if ($glyph) {
        $iconBlock = [System.Windows.Controls.TextBlock]@{
            Text                = $glyph
            FontFamily          = [PsUi.ModuleContext]::ActiveIconFontFamily
            FontSize            = 22
            HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            VerticalAlignment   = [System.Windows.VerticalAlignment]::Center
            IsHitTestVisible    = $false
            Opacity             = 0.55
            Tag                 = 'SecondaryTextBrush'
        }

        [System.Windows.Controls.Grid]::SetRow($iconBlock, 0)
        $iconBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'SecondaryTextBrush')
        [PsUi.ThemeEngine]::RegisterElement($iconBlock)
        [void]$wrapper.Children.Add($iconBlock)
    }

    $messageBlock = [System.Windows.Controls.TextBlock]@{
        Text                = $Message
        FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe UI Variable, Segoe UI')
        FontSize            = 14
        FontWeight          = [System.Windows.FontWeights]::Regular
        FontStyle           = [System.Windows.FontStyles]::Normal
        HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        VerticalAlignment   = [System.Windows.VerticalAlignment]::Center
        TextAlignment       = [System.Windows.TextAlignment]::Center
        TextWrapping        = [System.Windows.TextWrapping]::Wrap
        MaxWidth            = 380
        IsHitTestVisible    = $false
        Tag                 = 'SecondaryTextBrush'
    }

    [System.Windows.Controls.Grid]::SetRow($messageBlock, 1)
    $messageBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'SecondaryTextBrush')
    [PsUi.ThemeEngine]::RegisterElement($messageBlock)
    [void]$wrapper.Children.Add($messageBlock)

    # Otherwise an auto generated column header peeks through behind the icon.
    $defaultHeadersVisibility = $DataGrid.HeadersVisibility
    $sync = {
        $isEmpty = ($DataGrid.Items.Count -eq 0)
        $vis = if ($isEmpty) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }

        if ($iconBlock) { $iconBlock.Visibility = $vis }

        $messageBlock.Visibility = $vis
        $DataGrid.IsEnabled = !$isEmpty

        $DataGrid.HeadersVisibility = if ($isEmpty) { [System.Windows.Controls.DataGridHeadersVisibility]::None } else { $defaultHeadersVisibility }
    }.GetNewClosure()

    & $sync

    # Explicit delegate cast so add_/remove_ are guaranteed to see the same instance. PS's implicit scriptblock to delegate conversion caches that delegate today, but the cache isn't a documented contract - cross runspace conversions and GC pressure have both broken it historically.
    $syncHandler = [System.Collections.Specialized.NotifyCollectionChangedEventHandler]{
        param($sender, $eventArgs)
        & $sync
    }.GetNewClosure()

    # Reattach inside Loaded so it survives tab switches. Reattach on ItemsSource swap too (e.g., $grid.ItemsSource = $new), since the prior view's subscription becomes stale.
    $subState = @{ View = $null }

    $attach = {
        if ($subState.View) {
            try { $subState.View.remove_CollectionChanged($syncHandler) } catch { }
            $subState.View = $null
        }
        $view = $DataGrid.ItemsSource -as [System.ComponentModel.ICollectionView]
        if (!$view) { return }
        try {
            $view.add_CollectionChanged($syncHandler)
            $subState.View = $view
        }
        catch { Write-Debug "EmptyOverlay view CollectionChanged subscription failed: $_" }
    }.GetNewClosure()

    $DataGrid.Add_Loaded({
        & $sync
        & $attach
    }.GetNewClosure())

    # ItemsSource swap at runtime: AddValueChanged hooks the DependencyProperty descriptor and fires whenever the property's value changes. Reeval visibility and rebind the collectionchanged sub to the new view
    #
    # DPD.AddValueChanged stores the handler in a static internal dictionary that strong refs the DataGrid- good ol classic WPF leak. Subscribe AND its matching RemoveValueChanged BOTH live inside Add_Loaded so a never realized grid (unrealized tab) doesn't subscribe in the first place. Per grid hashtable flag means a window wide guard can't shadow sibling grids.
    $itemsSourcePropDesc = [System.ComponentModel.DependencyPropertyDescriptor]::FromProperty(
        [System.Windows.Controls.ItemsControl]::ItemsSourceProperty,
        [System.Windows.Controls.DataGrid])
    $itemsSourceChangedHandler = [System.EventHandler]{
        param($sender, $eventArgs)
        & $sync
        & $attach
    }.GetNewClosure()

    # Set-DataGridStyle puts HeadersVisibility back to Column as a local value on every restyle, and no other event fires for it.
    # ThemeEngine raises ThemeChanged before it refreshes the elements.
    # At any priority below Render the headers get one frame on screen before the resync hides them again.
    $themeChangedHandler = [System.Action[string]]{
        param($themeName)
        # ThemeEngine calls every subscriber inside one try, so a throw here would stop the ones after it.
        trap { Write-Debug "Overlay theme resync failed: $_"; continue }
        $null = $DataGrid.Dispatcher.BeginInvoke([Action]$sync, [System.Windows.Threading.DispatcherPriority]::Render)
    }.GetNewClosure()

    # Closed handler defined at function body. PS nested .GetNewClosure() doesn't propagate vars that the parent scope only reached via its own outer capture... building this handler inside Add_Loaded would leave $DataGrid / $itemsSourcePropDesc / etc. null at Closed time, so the cleanup silently does nothing and the DPD strong ref leaks anyway (the exact bug the comment above tries to prevent). Lifted out so the function params get captured directly.
    $onWindowClosed = {
        try { $itemsSourcePropDesc.RemoveValueChanged($DataGrid, $itemsSourceChangedHandler) }
        catch { Write-Debug "EmptyOverlay DPD detach failed: $_" }
        try { [PsUi.ThemeEngine]::remove_ThemeChanged($themeChangedHandler) }
        catch { Write-Debug "EmptyOverlay theme detach failed: $_" }
        if ($subState.View) {
            try { $subState.View.remove_CollectionChanged($syncHandler) } catch { }
            $subState.View = $null
        }
    }.GetNewClosure()

    # Per grid flag (hashtable so the closure can mutate it. A window wide flag would only hook the FIRST grid's DPD cleanup and leak every subsequent grid's DPD on window close.
    $initHooked = @{ Value = $false }
    $DataGrid.Add_Loaded({
        if ($initHooked.Value) { return }
        $window = [System.Windows.Window]::GetWindow($DataGrid)
        if (!$window) { return }
        $initHooked.Value = $true

        $itemsSourcePropDesc.AddValueChanged($DataGrid, $itemsSourceChangedHandler)
        [PsUi.ThemeEngine]::add_ThemeChanged($themeChangedHandler)
        $window.Add_Closed($onWindowClosed)
    }.GetNewClosure())

    $DataGrid.Add_Unloaded({
        if ($subState.View) {
            try { $subState.View.remove_CollectionChanged($syncHandler) }
            catch { Write-Debug "EmptyOverlay unsubscribe failed: $_" }
            $subState.View = $null
        }
    }.GetNewClosure())

    # The results filter swaps this text when a search empties the grid.
    # Resources and not Tag, since Set-UiProperties refuses a Tag on a control that already has one.
    $wrapper.Resources['__EmptyOverlay'] = @{ MessageBlock = $messageBlock; DefaultMessage = $Message }

    return $wrapper
}
