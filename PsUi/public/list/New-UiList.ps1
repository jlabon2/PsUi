function New-UiList {
    <#
    .SYNOPSIS
        Creates a selectable list of items with optional filtering and selection controls.
    .DESCRIPTION
        Builds a themed ListBox with optional real-time text filtering, select-all/none
        buttons, and a manual add button. Supports both static arrays and dynamic
        ObservableCollection binding. Use -DisplayFormat for object lists where each
        item is a hashtable with named properties.
    .PARAMETER Variable
        Variable name for the list.
    .PARAMETER Items
        Array of static items to display. Mutually exclusive with ItemsSource.
    .PARAMETER ItemsSource
        A collection (e.g., ObservableCollection) to bind as the list's data source.
        Use this for dynamic collections that update at runtime.
    .PARAMETER DisplayFormat
        Format string for displaying objects. Use property names in braces.
        Example: "{Username} ({AccountType})" shows "jsmith (Admin)".
        When specified, Add-UiListItem automatically generates display text from hashtables.
    .PARAMETER MultiSelect
        Allow multiple selection.
    .PARAMETER Filterable
        Adds a filter textbox above the list. As the user types, items are filtered
        in real-time. Includes a clear button (X) that appears when text is entered.
    .PARAMETER SelectionControls
        Adds "All" and "None" buttons for quick select/deselect operations.
        Most useful with -MultiSelect. Buttons appear in the filter toolbar.
    .PARAMETER AllowAdd
        Adds a "+" button to the toolbar that opens an input dialog for manually
        adding items to the list. Useful when items can't be auto-discovered.
    .PARAMETER AddPrompt
        Custom prompt text for the add item dialog. Defaults to "Enter item to add:".
    .PARAMETER Height
        Fixed height in pixels. Defaults to 150.
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
        Add-UiListItem 'queue' @{ Username = 'jsmith'; FullName = 'John'; AccountType = 'Admin' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Variable,

        [Parameter()]
        [string[]]$Items,

        [Parameter()]
        [System.Collections.IEnumerable]$ItemsSource,

        [Parameter()]
        [string]$DisplayFormat,

        [switch]$MultiSelect,

        [switch]$Filterable,

        [switch]$SelectionControls,

        [switch]$AllowAdd,

        [string]$AddPrompt = 'Enter item to add:',

        [int]$Height = 150,

        [switch]$FullWidth,

        [Parameter()]
        [object]$EnabledWhen,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    if ($Items -and $ItemsSource) {
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

    # Bubble scroll events to parent ScrollViewer so list doesn't swallow them
    $listBox.Add_PreviewMouseWheel({
        param($sender, $eventArgs)
        if (!$eventArgs.Handled) {
            $eventArgs.Handled = $true
            $newEvent = [System.Windows.Input.MouseWheelEventArgs]::new($eventArgs.MouseDevice, $eventArgs.Timestamp, $eventArgs.Delta)
            $newEvent.RoutedEvent = [System.Windows.UIElement]::MouseWheelEvent
            $newEvent.Source = $sender
            $parentElement = $sender.Parent -as [System.Windows.UIElement]
            if ($parentElement) { $parentElement.RaiseEvent($newEvent) }
        }
    })

    if ($DisplayFormat) {
        Write-Debug "Registering DisplayFormat: $DisplayFormat"
        $listBox.DisplayMemberPath = '_DisplayText'
        $session.RegisterListDisplayFormat($Variable, $DisplayFormat)
    }

    Set-ListBoxStyle -ListBox $listBox

    # Build the data source (needed before filtering setup)
    # When filtering is enabled, we MUST use a collection with CollectionView
    $sourceCollection = $null
    if ($null -ne $ItemsSource) {
        Write-Debug "Binding external ItemsSource collection"
        $sourceCollection = $ItemsSource
        
        # If it's an AsyncObservableCollection, update dispatcher
        if ($ItemsSource.GetType().Name -like 'AsyncObservableCollection*') {
            try { $ItemsSource.UpdateDispatcher() }
            catch { Write-Debug "Failed to update dispatcher: $_" }
        }

        # Register for Add-UiListItem access
        if ($ItemsSource -is [System.Collections.IList]) {
            $session.RegisterListCollection($Variable, $ItemsSource)
        }
        elseif ($ItemsSource | Get-Member -Name 'Add' -MemberType Method) {
            $session.RegisterListCollection($Variable, $ItemsSource)
        }
    }
    elseif ($Items) {
        # Convert static items to ObservableCollection for filtering support
        Write-Debug "Converting $($Items.Count) static items to collection"
        $sourceCollection = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        foreach ($item in $Items) { [void]$sourceCollection.Add($item) }
        
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

    # Build the container - either a simple wrapper or one with toolbar
    if ($needsToolbar) {
        # Create outer container with DockPanel layout
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
                FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
                FontSize            = 14
                Foreground          = ConvertTo-UiBrush $colors.SecondaryText
                VerticalAlignment   = 'Center'
                Margin              = [System.Windows.Thickness]::new(0, 0, 6, 0)
                Tag                 = 'SecondaryTextBrush'
            }
            [PsUi.ThemeEngine]::RegisterElement($searchIcon)
            [System.Windows.Controls.Grid]::SetColumn($searchIcon, 0)
            [void]$toolbar.Children.Add($searchIcon)

            # Container grid holds the textbox and clear button
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
                FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
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

            # Store refs in filterBox.Tag for TextChanged handler (including timer slot)
            # SourceCollection stores unfiltered items for collection-based filtering
            $filterBox.Tag = @{
                ClearButton      = $clearBtn
                ListView         = $listBox
                Timer            = $null
                SourceCollection = $sourceCollection
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
                FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
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

            # Wire up the add button - shows input dialog and adds to collection
            $addState = @{
                Collection  = $sourceCollection
                PromptText  = $AddPrompt
                CountLabel  = $countLabel
                ListView    = $listBox
            }
            $addBtn.Add_Click({
                $result = Show-UiInputDialog -Title 'Add Item' -Prompt $addState.PromptText
                if (![string]::IsNullOrWhiteSpace($result)) {
                    [void]$addState.Collection.Add($result)
                    
                    # Auto-select the newly added item (keeps existing selections)
                    $addState.ListView.SelectedItems.Add($result)
                    
                    # Update count label if present
                    if ($addState.CountLabel) {
                        $selected = $addState.ListView.SelectedItems.Count
                        $total    = $addState.ListView.Items.Count
                        $addState.CountLabel.Text = "($selected/$total)"
                    }
                }
            }.GetNewClosure())
        }

        [void]$container.Children.Add($toolbar)

        $listBox.Height = $Height
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

                # Show/hide clear button
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
                    $filterText     = $textBox.Text.Trim()
                    $sourceItems    = $tagData.SourceCollection
                    $displayBinding = $targetList.DisplayMemberPath

                    # Rebuild collection to filter (avoids delegate issues)
                    if ($null -ne $sourceItems) {
                        # Snapshot current selection so we can restore after rebuild
                        $savedSelection = [System.Collections.Generic.HashSet[object]]::new()
                        foreach ($sel in $targetList.SelectedItems) { [void]$savedSelection.Add($sel) }

                        $filteredItems = [System.Collections.Generic.List[object]]::new()
                        
                        foreach ($item in $sourceItems) {
                            if ($null -eq $item) { continue }
                            
                            # Empty filter shows all
                            if ([string]::IsNullOrEmpty($filterText)) {
                                $filteredItems.Add($item)
                                continue
                            }
                            
                            # Get display text - try _DisplayText property first, then ToString
                            $displayText = $null
                            if ($item.PSObject) {
                                $prop = $item.PSObject.Properties['_DisplayText']
                                if ($prop) { $displayText = $prop.Value }
                            }
                            if (!$displayText) { $displayText = $item.ToString() }
                            
                            if ($displayText.IndexOf($filterText, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                $filteredItems.Add($item)
                            }
                        }
                        
                        # Create new view from filtered items
                        $newCollection = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
                        foreach ($item in $filteredItems) { [void]$newCollection.Add($item) }
                        
                        $newView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($newCollection)
                        $targetList.ItemsSource = $newView

                        # Restore selections that survived the filter
                        if ($savedSelection.Count -gt 0) {
                            foreach ($item in $filteredItems) {
                                if ($savedSelection.Contains($item)) {
                                    [void]$targetList.SelectedItems.Add($item)
                                }
                            }
                        }

                        # Update selection count after filter
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

        # Apply custom WPF properties to container (user may want to style the whole unit)
        if ($WPFProperties) {
            Set-UiProperties -Control $container -Properties $WPFProperties
        }

        Write-Debug "Adding container with toolbar to parent"
        [void]$parent.Children.Add($container)

        # Wire up EnabledWhen on the container (disables toolbar and list together)
        if ($EnabledWhen) {
            Register-UiCondition -TargetControl $container -Condition $EnabledWhen
        }
    }
    else {
        # Simple listbox without toolbar
        $listBox.Height = $Height
        $listBox.Margin = [System.Windows.Thickness]::new(4, 4, 4, 8)

        Set-FullWidthConstraint -Control $listBox -Parent $parent -FullWidth:$FullWidth

        if ($WPFProperties) {
            Set-UiProperties -Control $listBox -Properties $WPFProperties
        }

        Write-Debug "Adding simple ListBox to parent"
        [void]$parent.Children.Add($listBox)

        # Wire up EnabledWhen on the listbox itself
        if ($EnabledWhen) {
            Register-UiCondition -TargetControl $listBox -Condition $EnabledWhen
        }
    }

    # Register the ListBox control (not container) for value access
    Register-UiControlComplete -Name $Variable -Control $listBox
}
