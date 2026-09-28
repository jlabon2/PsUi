function New-UiList {
    <#
    .SYNOPSIS
        Themed listbox. Optional filter box and select-all/none buttons.
    .DESCRIPTION
        Builds a themed ListBox with opt-in toolbar controls: a real-time filter box,
        select-all/none buttons, a manual add button. Supports both static arrays and
        dynamic ObservableCollection binding. Use -DisplayFormat for object lists where
        each item is a hashtable with named properties.
    .PARAMETER Variable
        Variable name for the list.
    .PARAMETER Items
        Array of static items to display. Mutually exclusive with ItemsSource.
    .PARAMETER ItemsSource
        A collection to bind as the list's data source, for lists that change at runtime.
        Anything that isn't already a PsUi threadsafe collection gets wrapped in one, and the
        variable is repointed at the wrap so $list.Add() from a background action keeps working.
        The wrap is no longer the type passed in, so .AddRange(), .Sort() and -is [ArrayList]
        stop working. A [ref] has its .Value repointed instead. -NoBind skips the repoint.
    .PARAMETER NoBind
        Skip the repoint. The list still binds the wrap, the original keeps its own identity,
        and the two only stay in step while the mirror holds.
    .PARAMETER DisplayFormat
        Format string for displaying objects. Use property names in braces.
        Example: "{Username} ({AccountType})" shows "wesley (Admin)".
        When specified, Add-UiListItem automatically generates display text from hashtables.
    .PARAMETER MultiSelect
        Allow multiple selection.
    .PARAMETER Filterable
        Adds a filter textbox above the list. As the user types, items are filtered
        in real time. Includes a clear button (X) that appears when text is entered.
    .PARAMETER SelectionControls
        Adds "All" and "None" buttons for quick select/deselect operations.
        Most useful with -MultiSelect. Buttons appear in the filter toolbar.
    .PARAMETER AllowAdd
        Adds a "+" button to the toolbar that opens an input dialog for manually
        adding items to the list. Useful when items can't be auto-discovered.
        The new item comes up selected. With -MultiSelect it joins the current selection.
    .PARAMETER AddPrompt
        Custom prompt text for the add item dialog. Defaults to "Enter item to add:".
    .PARAMETER Height
        Fixed height in pixels. Defaults to 150. Ignored when -Fill is set.
    .PARAMETER Fill
        Grow to the rest of the window's vertical viewport instead of the fixed -Height.
        List resizes with the window. Use when the list is the dominant content in the view.
    .PARAMETER CaptureScrollWheel
        Keep every mouse-wheel event inside the list, ends included. Same as -ScrollWheel Capture.
    .PARAMETER ScrollWheel
        Says who gets the wheel while the cursor is over the list. Page, the default, hands every
        wheel event to the page, so a window full of them still scrolls. Edge scrolls the list's
        own rows until it reaches the top or bottom and gives the page the wheel from there.
        Capture holds on at the ends as well, so the page stays put while the cursor is here.
        A -Fill list starts on Edge instead, since it holds the viewport and the page behind it
        has almost no scroll of its own left. Pass -ScrollWheel to override that.
    .PARAMETER FullWidth
        Stretches the list to fill available width.
    .PARAMETER EnabledWhen
        Variable name that controls whether the list is enabled. Truthy value = enabled.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
    .EXAMPLE
        New-UiList -Variable "list" -Items @('A','B','C')
    .EXAMPLE
        # Filterable multi-select list with selection controls
        New-UiList -Variable "servers" -MultiSelect -Filterable -SelectionControls
    .EXAMPLE
        # List with manual add button for items that can't be auto-discovered
        New-UiList -Variable "uags" -MultiSelect -AllowAdd -AddPrompt "Enter UAG hostname:"
    .EXAMPLE
        # Object list with auto-formatted display
        New-UiList -Variable "queue" -DisplayFormat "{Username} ({AccountType})"
        # Then just pass hashtables - display text is automatic:
        Add-UiListItem 'queue' @{ Username = 'wesley'; FullName = 'Wesley'; AccountType = 'Admin' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Variable,

        [Parameter()]
        [string[]]$Items,

        # Untyped so the [ref] reaches Resolve-UiListSource whole.
        [Parameter()]
        $ItemsSource,

        [switch]$NoBind,

        [Parameter()]
        [string]$DisplayFormat,

        [switch]$MultiSelect,

        [switch]$Filterable,

        [switch]$SelectionControls,

        [switch]$AllowAdd,

        [string]$AddPrompt = 'Enter item to add:',

        [int]$Height = 150,

        [switch]$Fill,

        [switch]$CaptureScrollWheel,

        [switch]$FullWidth,

        [Parameter()]
        [object]$EnabledWhen,

        [Parameter()]
        [hashtable]$WPFProperties,

        [ValidateSet('Page', 'Edge', 'Capture')]
        [string]$ScrollWheel = 'Page'
    )

    # An empty -ItemsSource collection evaluates as false and still means "bind to this one".
    if ($Items.Count -gt 0 -and $PSBoundParameters.ContainsKey('ItemsSource')) {
        throw "New-UiList cannot use both -Items and -ItemsSource. Choose one."
    }

    $session = Assert-UiSession -CallerName 'New-UiList'
    Write-Debug "Creating list '$Variable' (MultiSelect=$MultiSelect, Height=$Height, Filterable=$Filterable)"
    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent

    $needsToolbar = $Filterable -or $SelectionControls -or $AllowAdd

    $listBox = [System.Windows.Controls.ListBox]::new()
    $listBox.Margin = [System.Windows.Thickness]::new(0)
    $listBox.SelectionMode = if ($MultiSelect) { 'Extended' } else { 'Single' }

    $wheelMode = if ($CaptureScrollWheel) { 'Capture' } else { $ScrollWheel }

    if ($Fill -and $wheelMode -eq 'Page' -and !$PSBoundParameters.ContainsKey('ScrollWheel')) {
        $wheelMode = 'Edge'
    }
    Set-UiWheelRouting -Control $listBox -Mode $wheelMode

    if ($DisplayFormat) {
        Write-Debug "Registering DisplayFormat: $DisplayFormat"
        $listBox.DisplayMemberPath = '_DisplayText'
        $session.RegisterListDisplayFormat($Variable, $DisplayFormat)
    }

    Set-ListBoxStyle -ListBox $listBox

    # Build the data source before filter setup - filtering needs a collection behind a CollectionView.
    # Also before the toolbar, since the filter box and + button close over $sourceCollection by value.
    $sourceCollection = $null
    $mirrorAttached   = $false
    if ($PSBoundParameters.ContainsKey('ItemsSource')) {
        Write-Debug "Binding external ItemsSource collection"
        $resolved         = Resolve-UiListSource -Source $ItemsSource -NoBind:$NoBind
        $sourceCollection = $resolved.Collection
        $mirrorAttached   = $resolved.MirrorAttached

        if ($resolved.NeedsBind -and !$NoBind -and $resolved.Repointed.Count -eq 0 -and $resolved.Converted.Count -eq 0) {
            Write-Warning 'New-UiList -ItemsSource: could not repoint any script variable to the autowrapped collection. Use a variable declared before New-UiWindow (or inside -Content) so $list.Add() and Add-UiListItem stay connected to the list.'
        }

        if ($resolved.RefWriteMissed) {
            Write-Warning 'New-UiList -ItemsSource: only a [ref] to a variable can be repointed, so a [ref] built from a property still holds the original list. Add through the [ref] .Value, or pass an ObservableCollection, which the list tracks wherever it lives.'
        }

        if ($resolved.Converted.Count -gt 0) {
            Write-Warning "New-UiList -ItemsSource: a type constrained target converted the threadsafe collection on assignment, and the copy never reaches the list ($($resolved.Converted -join ', ')). Drop the type, or use -NoBind and drive the list with Add-UiListItem."
        }

        $session.RegisterListCollection($Variable, $sourceCollection)
    }
    elseif ($Items.Count -gt 0) {
        # Seeded straight into the threadsafe collection. A plain ObservableCollection here made background Add-UiListItem throw the cross thread CollectionView error. The view attaches below and pins the whole thing to this thread.
        Write-Debug "Seeding $($Items.Count) static items into an AsyncObservableCollection"
        $sourceCollection = [PsUi.AsyncObservableCollection[object]]::new($Items)

        # Register for Add-UiListItem access
        $session.RegisterListCollection($Variable, $sourceCollection)
    }
    else {
        # Auto-create collection for dynamic use
        Write-Debug "Creating auto AsyncObservableCollection"
        $sourceCollection = [PsUi.AsyncObservableCollection[object]]::new()
        $session.RegisterListCollection($Variable, $sourceCollection)
    }

    # Set up ItemsSource with CollectionView for filtering
    if ($null -ne $sourceCollection) {
        $collectionView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($sourceCollection)
        $listBox.ItemsSource = $collectionView
    }

    # With a toolbar the whole thing goes in a DockPanel, and without one the ListBox goes in on its own.
    if ($needsToolbar) {
        $container = [System.Windows.Controls.DockPanel]@{
            Margin = [System.Windows.Thickness]::new(4, 4, 4, 8)
        }

        # Create toolbar row: [Icon] [Filter textbox*] [All btn?] [None btn?]
        $toolbar = [System.Windows.Controls.Grid]@{
            Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        }
        [System.Windows.Controls.DockPanel]::SetDock($toolbar, 'Top')

        $colIndex = 0

        # Icon column (auto) - only if filterable
        if ($Filterable) {
            $iconCol = [System.Windows.Controls.ColumnDefinition]::new()
            $iconCol.Width = [System.Windows.GridLength]::Auto
            [void]$toolbar.ColumnDefinitions.Add($iconCol)
            $colIndex++
        }

        # Filter textbox column (stretch)
        $filterCol = [System.Windows.Controls.ColumnDefinition]::new()
        $filterCol.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        [void]$toolbar.ColumnDefinitions.Add($filterCol)
        $filterColIndex = $colIndex; $colIndex++

        if ($SelectionControls) {
            # Selection count column (auto) - only if MultiSelect too
            if ($MultiSelect) {
                $countCol = [System.Windows.Controls.ColumnDefinition]::new()
                $countCol.Width = [System.Windows.GridLength]::Auto
                [void]$toolbar.ColumnDefinitions.Add($countCol)
                $countColIndex = $colIndex; $colIndex++
            }

            # All button column
            $allCol = [System.Windows.Controls.ColumnDefinition]::new()
            $allCol.Width = [System.Windows.GridLength]::Auto
            [void]$toolbar.ColumnDefinitions.Add($allCol)
            $allColIndex = $colIndex; $colIndex++

            # None button column
            $noneCol = [System.Windows.Controls.ColumnDefinition]::new()
            $noneCol.Width = [System.Windows.GridLength]::Auto
            [void]$toolbar.ColumnDefinitions.Add($noneCol)
            $noneColIndex = $colIndex; $colIndex++
        }

        # Add button column (auto) - if AllowAdd
        if ($AllowAdd) {
            $addCol = [System.Windows.Controls.ColumnDefinition]::new()
            $addCol.Width = [System.Windows.GridLength]::Auto
            [void]$toolbar.ColumnDefinitions.Add($addCol)
            $addColIndex = $colIndex; $colIndex++
        }

        # Create filter textbox in its own container (or placeholder if only selection controls)
        $filterBox = $null
        if ($Filterable) {
            # Search icon OUTSIDE the textbox (to the left)
            $searchIcon = [System.Windows.Controls.TextBlock]@{
                Text                = [PsUi.ModuleContext]::GetIcon('Search')
                FontFamily          = [PsUi.ModuleContext]::ActiveIconFontFamily
                FontSize            = 14
                Foreground          = ConvertTo-UiBrush $colors.SecondaryText
                VerticalAlignment   = 'Center'
                Margin              = [System.Windows.Thickness]::new(0, 0, 6, 0)
                Tag                 = 'SecondaryTextBrush'
            }
            [PsUi.ThemeEngine]::RegisterElement($searchIcon)
            [System.Windows.Controls.Grid]::SetColumn($searchIcon, 0)
            [void]$toolbar.Children.Add($searchIcon)

            $filterContainer = [System.Windows.Controls.Grid]@{
                VerticalAlignment = 'Center'
            }
            [System.Windows.Controls.Grid]::SetColumn($filterContainer, $filterColIndex)

            $filterBox = [System.Windows.Controls.TextBox]@{
                Height   = 26
                Padding  = [System.Windows.Thickness]::new(4, 0, 20, 0)
                FontSize = 13
                ToolTip  = 'Type to filter items'
            }
            Set-TextBoxStyle -TextBox $filterBox
            [void]$filterContainer.Children.Add($filterBox)

            # Clear button overlay (right side) - uses $this.Tag pattern like datagrid
            $clearBtn = [System.Windows.Controls.Button]@{
                Content             = [PsUi.ModuleContext]::GetIcon('Cancel')
                FontFamily          = [PsUi.ModuleContext]::ActiveIconFontFamily
                FontSize            = 10
                Width               = 16
                Height              = 16
                Padding             = [System.Windows.Thickness]::new(0)
                Margin              = [System.Windows.Thickness]::new(0, 0, 5, 0)
                HorizontalAlignment = 'Right'
                VerticalAlignment   = 'Center'
                Background          = [System.Windows.Media.Brushes]::Transparent
                BorderThickness     = [System.Windows.Thickness]::new(0)
                Cursor              = [System.Windows.Input.Cursors]::Hand
                Visibility          = 'Collapsed'
                ToolTip             = 'Clear filter'
                Tag                 = $filterBox
            }
            $clearBtn.SetResourceReference([System.Windows.Controls.Button]::ForegroundProperty, 'SecondaryTextBrush')
            $clearBtn.Add_Click({ $this.Tag.Text = ''; $this.Tag.Focus() }.GetNewClosure())
            [void]$filterContainer.Children.Add($clearBtn)

            # Refs for the TextChanged handler, including the Timer key. The filter drives View, SourceCollection keeps the unfiltered items.
            $filterBox.Tag = @{
                ClearButton      = $clearBtn
                ListView         = $listBox
                Timer            = $null
                SourceCollection = $sourceCollection
                View             = $collectionView
            }

            [void]$toolbar.Children.Add($filterContainer)
        }
        else {
            # No filter - just an empty space to push buttons right
            $spacer = [System.Windows.Controls.Border]::new()
            [System.Windows.Controls.Grid]::SetColumn($spacer, $filterColIndex)
            [void]$toolbar.Children.Add($spacer)
        }

        $countLabel = $null
        if ($SelectionControls) {
            # Selection count label (only for MultiSelect)
            if ($MultiSelect) {
                $countLabel = [System.Windows.Controls.TextBlock]@{
                    Text                = '(0/0)'
                    FontSize            = 11
                    Foreground          = ConvertTo-UiBrush $colors.SecondaryText
                    VerticalAlignment   = 'Center'
                    TextAlignment       = 'Right'
                    Margin              = [System.Windows.Thickness]::new(8, 0, 4, 0)
                    MinWidth            = 55
                    Tag                 = 'SecondaryTextBrush'
                }
                [PsUi.ThemeEngine]::RegisterElement($countLabel)
                [System.Windows.Controls.Grid]::SetColumn($countLabel, $countColIndex)
                [void]$toolbar.Children.Add($countLabel)
            }

            # "All" button
            $allBtn = [System.Windows.Controls.Button]@{
                Content = 'All'
                Width   = 36
                Height  = 24
                Margin  = [System.Windows.Thickness]::new(4, 0, 0, 0)
                Padding = [System.Windows.Thickness]::new(6, 2, 6, 2)
                ToolTip = 'Select all items'
                Cursor  = [System.Windows.Input.Cursors]::Hand
            }
            Set-ButtonStyle -Button $allBtn
            [System.Windows.Controls.Grid]::SetColumn($allBtn, $allColIndex)
            [void]$toolbar.Children.Add($allBtn)

            # "None" button
            $noneBtn = [System.Windows.Controls.Button]@{
                Content = 'None'
                Width   = 44
                Height  = 24
                Margin  = [System.Windows.Thickness]::new(4, 0, 0, 0)
                Padding = [System.Windows.Thickness]::new(6, 2, 6, 2)
                ToolTip = 'Clear selection'
                Cursor  = [System.Windows.Input.Cursors]::Hand
            }
            Set-ButtonStyle -Button $noneBtn
            [System.Windows.Controls.Grid]::SetColumn($noneBtn, $noneColIndex)
            [void]$toolbar.Children.Add($noneBtn)

            $selState = @{ ListView = $listBox }
            $allBtn.Add_Click({
                $selState.ListView.SelectAll()
            }.GetNewClosure())
            $noneBtn.Add_Click({
                $selState.ListView.UnselectAll()
            }.GetNewClosure())
        }

        if ($AllowAdd) {
            $addBtn = [System.Windows.Controls.Button]@{
                Content    = [PsUi.ModuleContext]::GetIcon('Add')
                FontFamily = [PsUi.ModuleContext]::ActiveIconFontFamily
                FontSize   = 12
                Width      = 24
                Height     = 24
                Margin     = [System.Windows.Thickness]::new(4, 0, 0, 0)
                Padding    = [System.Windows.Thickness]::new(0)
                ToolTip    = 'Add item'
                Cursor     = [System.Windows.Input.Cursors]::Hand
            }
            Set-ButtonStyle -Button $addBtn
            [System.Windows.Controls.Grid]::SetColumn($addBtn, $addColIndex)
            [void]$toolbar.Children.Add($addBtn)

            # Hook the add button, it shows input dialog and pushes into the collection
            $addState = @{
                Collection  = $sourceCollection
                PromptText  = $AddPrompt
                CountLabel  = $countLabel
                ListView    = $listBox
                SessionId   = $session.SessionId
                PushSession = ${function:Push-UiSession}
                PopSession  = ${function:Pop-UiSession}
            }
            $addBtn.Add_Click({
                trap { Write-Debug "New-UiList add button: $_"; continue }

                # Still $null if the dialog throws, which skips the add below
                $result       = $null
                $sessionToken = & $addState.PushSession -SessionId $addState.SessionId
                $result       = Show-UiInputDialog -Title 'Add Item' -Prompt $addState.PromptText
                & $addState.PopSession -Token $sessionToken
                if ([string]::IsNullOrWhiteSpace($result)) { return }

                # Top level because an ObservableCollection[int] source throws after the row is in and the trap's continue would skip the rest of an if
                [void]$addState.Collection.Add($result)

                # SelectedItem picks the first equal item, the older copy of a repeated name, and the index only holds while the new row is the last one showing
                $listView = $addState.ListView
                $last     = $listView.Items.Count - 1
                if ($listView.SelectionMode -ne 'Single') { [void]$listView.SelectedItems.Add($result) }
                elseif ($last -ge 0 -and $listView.Items[$last] -ceq $result) { $listView.SelectedIndex = $last }
                else { $listView.SelectedItem = $result }

                if ($addState.CountLabel) {
                    $selected = $listView.SelectedItems.Count
                    $total    = $listView.Items.Count
                    $addState.CountLabel.Text = "($selected/$total)"
                }
            }.GetNewClosure())
        }

        [void]$container.Children.Add($toolbar)

        if (!$Fill) { $listBox.Height = $Height }
        [void]$container.Children.Add($listBox)

        if ($countLabel) {
            $listBox.Tag = @{ CountLabel = $countLabel }

            # Update count on selection change
            $listBox.Add_SelectionChanged({
                $label     = $this.Tag.CountLabel
                $selected  = $this.SelectedItems.Count
                $total     = $this.Items.Count
                $label.Text = "($selected/$total)"
            }.GetNewClosure())

            # Set initial count after window loads
            $listBox.Add_Loaded({
                $label    = $this.Tag.CountLabel
                $selected = $this.SelectedItems.Count
                $total    = $this.Items.Count
                $label.Text = "($selected/$total)"
            }.GetNewClosure())
        }

        if ($Filterable -and $filterBox) {
            $filterBox.Add_TextChanged({
                # $this is the TextBox that fired the event
                $textBox    = $this
                $tagData    = $textBox.Tag
                $clearBtn   = $tagData.ClearButton
                $targetList = $tagData.ListView

                if ($clearBtn) {
                    $clearBtn.Visibility = if ([string]::IsNullOrEmpty($textBox.Text)) { 'Collapsed' } else { 'Visible' }
                }

                # Debounce filter updates - timer stored in Tag to avoid collision between lists
                if ($tagData.Timer) {
                    $tagData.Timer.Stop()
                    $tagData.Timer = $null
                }

                $timer = [System.Windows.Threading.DispatcherTimer]::new()
                $timer.Interval = [TimeSpan]::FromMilliseconds(200)
                $tagData.Timer = $timer

                $timer.Add_Tick({
                    $filterText = $textBox.Text.Trim()
                    $view       = $tagData.View

                    # Filter the view, do NOT swap ItemsSource. Building a throwaway collection per keystroke leaves the ListBox attached to that throwaway forever, and every later Add-UiListItem then lands in the registered collection where the list never sees it.
                    if ($null -ne $view) {
                        $needle = $filterText
                        if ([string]::IsNullOrEmpty($needle)) {
                            $view.Filter = $null
                        }
                        else {
                            # [Predicate[object]] cast is required in 5.1: a bare scriptblock won't bind.
                            $view.Filter = [Predicate[object]]{
                                param($item)
                                if ($null -eq $item) { return $false }
                                $displayText = $null
                                if ($item.PSObject) {
                                    $prop = $item.PSObject.Properties['_DisplayText']
                                    if ($prop) { $displayText = $prop.Value }
                                }
                                if (!$displayText) { $displayText = $item.ToString() }
                                return $displayText.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0
                            }.GetNewClosure()
                        }
                        $view.Refresh()

                        if ($targetList.Tag -and $targetList.Tag.CountLabel) {
                            $label    = $targetList.Tag.CountLabel
                            $selected = $targetList.SelectedItems.Count
                            $total    = $targetList.Items.Count
                            $label.Text = "($selected/$total)"
                        }
                    }

                    $tagData.Timer.Stop()
                    $tagData.Timer = $null
                }.GetNewClosure())

                $timer.Start()
            }.GetNewClosure())
        }

        Set-FullWidthConstraint -Control $container -Parent $parent -FullWidth:$FullWidth

        # WPF properties go on the container so styling hits the whole unit, not just the listBox
        if ($WPFProperties) {
            Set-UiProperties -Control $container -Properties $WPFProperties
        }

        Write-Debug "Adding container with toolbar to parent"
        [void]$parent.Children.Add($container)

        # Fill sizes the container, not the inner listBox - the listBox's only siblings live inside the DockPanel, so the sibling math saw nothing and controls after the list got shoved off viewport. DockPanel LastChildFill hands the listBox the remainder.
        if ($Fill) { Set-UiFillParentHeight -Control $container }

        # EnabledWhen on the container so the toolbar and list disable together
        if ($EnabledWhen) {
            Register-UiCondition -TargetControl $container -Condition $EnabledWhen
        }
    }
    else {
        # Simple listbox without toolbar
        if (!$Fill) { $listBox.Height = $Height }
        $listBox.Margin = [System.Windows.Thickness]::new(4, 4, 4, 8)

        Set-FullWidthConstraint -Control $listBox -Parent $parent -FullWidth:$FullWidth

        if ($WPFProperties) {
            Set-UiProperties -Control $listBox -Properties $WPFProperties
        }

        Write-Debug "Adding simple ListBox to parent"
        [void]$parent.Children.Add($listBox)

        if ($Fill) { Set-UiFillParentHeight -Control $listBox }

        # EnabledWhen on the listbox itself
        if ($EnabledWhen) {
            Register-UiCondition -TargetControl $listBox -Condition $EnabledWhen
        }
    }

    if ($mirrorAttached) {
        Register-UiCollectionCleanup -Control $listBox -Collection $sourceCollection
    }

    # Register the ListBox control (not container) for value access
    Register-UiControlComplete -Name $Variable -Control $listBox
}
