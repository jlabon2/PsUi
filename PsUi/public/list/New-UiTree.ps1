function New-UiTree {
    <#
    .SYNOPSIS
        Creates a hierarchical tree view for displaying nested data.
    .DESCRIPTION
        Builds a WPF TreeView from nested hashtables, objects, or flat path-based data.
        For nested data, each item's display text comes from -DisplayProperty and children
        from -ChildrenProperty. For flat data like Get-ChildItem output, use -PathProperty
        to specify which property contains the hierarchical path (e.g., FullName).
        
        For parent-child relationships (like processes), use -IdProperty and -ParentIdProperty.
    .PARAMETER Variable
        Variable name for accessing this tree in button actions.
    .PARAMETER Items
        Array of tree items. Can be nested (with Children property) or flat with paths.
    .PARAMETER DisplayProperty
        Property name to display as the node text. Defaults to 'Name'.
    .PARAMETER ChildrenProperty
        Property name containing child items for nested data. Defaults to 'Children'.
    .PARAMETER PathProperty
        Property containing a hierarchical path (e.g., FullName for FileInfo objects).
        When specified, the tree builds hierarchy from path segments instead of nested data.
    .PARAMETER PathSeparator
        Separator character for path segments. Defaults to '\' for filesystem paths.
        Use ',' for AD Distinguished Names, '.' for namespaces.
    .PARAMETER ReversePath
        Reverse the path segment order. Use for AD Distinguished Names where leaf is first
        (CN=User,OU=Sales,DC=corp,DC=com becomes DC=com > DC=corp > OU=Sales > CN=User).
    .PARAMETER IdProperty
        Property containing unique ID for parent-child relationships (e.g., Id for processes).
    .PARAMETER ParentIdProperty
        Property containing parent's ID (e.g., ParentProcessId for processes).
    .PARAMETER Height
        Height of the tree control. Defaults to 200. Ignored when -Fill is set.
    .PARAMETER Fill
        Grow to the rest of the window's vertical viewport instead of the fixed -Height.
        Tree resizes with the window. Use when the tree is the dominant content in the view.
    .PARAMETER ExpandAll
        Expand all nodes on load.
    .PARAMETER ParentCheckBoxes
        Checkbox on every item with children. Click a parent to toggle enabled descendants.
        Combine with -ChildCheckBoxes for the full picker.
    .PARAMETER ChildCheckBoxes
        Checkbox on every leaf. Alone, parents become unselectable - the box is the only way in.
    .PARAMETER WhenEnabled
        Scriptblock run per item. Returns $false and the box renders disabled; cascade skips it.
    .PARAMETER Checked
        Scriptblock run per item at build time. Returns $true and the box starts checked.
    .PARAMETER NoCascade
        Independent boxes - parent clicks don't cascade. For tagging workflows.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
    .EXAMPLE
        # Nested hashtable data
        $data = @(
            @{ Name = 'Root'; Children = @(
                @{ Name = 'Child 1' }
                @{ Name = 'Child 2'; Children = @(
                    @{ Name = 'Grandchild' }
                )}
            )}
        )
        New-UiTree -Variable 'tree' -Items $data
    .EXAMPLE
        # Filesystem
        Get-ChildItem C:\Temp -Recurse -Directory | New-UiTree -Variable 'folders' -PathProperty 'FullName'
    .EXAMPLE
        # Active Directory OUs - DN is reversed, comma-separated
        Get-ADOrganizationalUnit -Filter * | New-UiTree -Variable 'ous' -PathProperty 'DistinguishedName' -PathSeparator ',' -ReversePath
    .EXAMPLE
        # Org chart - parent/child by ID using a dotted property path on the parent reference
        $employees = @(
            [PSCustomObject]@{ EmployeeId = 1; Name = 'CEO';    Manager = $null }
            [PSCustomObject]@{ EmployeeId = 2; Name = 'VP Eng'; Manager = [PSCustomObject]@{ EmployeeId = 1 } }
            [PSCustomObject]@{ EmployeeId = 3; Name = 'Dev';    Manager = [PSCustomObject]@{ EmployeeId = 2 } }
        )
        $employees | New-UiTree -Variable 'org' -IdProperty 'EmployeeId' -ParentIdProperty 'Manager.EmployeeId' -DisplayProperty 'Name'
    .EXAMPLE
        # .NET namespaces
        [AppDomain]::CurrentDomain.GetAssemblies().GetTypes() |
            Select -Unique FullName |
            New-UiTree -Variable 'types' -PathProperty 'FullName' -PathSeparator '.'
    .EXAMPLE
        # Services by status; auto-start protected, stopped pre-selected.
        Get-Service | Group-Object Status | ForEach-Object {
            [PSCustomObject]@{ Name = $_.Name; Children = $_.Group }
        } | New-UiTree -Variable 'svc' -ParentCheckBoxes -ChildCheckBoxes `
              -WhenEnabled { $_.StartType -ne 'Automatic' } -Checked { $_.Status -eq 'Stopped' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Variable,

        [Parameter(ValueFromPipeline)]
        [object[]]$Items,

        [Parameter()]
        [string]$DisplayProperty = 'Name',

        [Parameter()]
        [string]$ChildrenProperty = 'Children',

        [Parameter()]
        [string]$PathProperty,

        [Parameter()]
        [string]$PathSeparator = '\',

        [switch]$ReversePath,

        [Parameter()]
        [string]$IdProperty,

        [Parameter()]
        [string]$ParentIdProperty,

        [int]$Height = 200,

        [switch]$Fill,

        [switch]$ExpandAll,

        [switch]$ParentCheckBoxes,

        [switch]$ChildCheckBoxes,

        [scriptblock]$WhenEnabled,

        [scriptblock]$Checked,

        [switch]$NoCascade,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    begin {
        $collectedItems = [System.Collections.Generic.List[object]]::new()
    }

    process {
        # Drop empty rows. $null.PSObject.Properties[$DisplayProperty] in the build loop'll throw "cannot index into a null array"
        # The piped path already skips them ($Items guard). This covers -Items @(...) where the whole array binds at once.
        if ($Items) {
            foreach ($item in $Items) {
                if ($null -ne $item) { $collectedItems.Add($item) }
            }
        }
    }

    end {
        $session   = Assert-UiSession -CallerName 'New-UiTree'
        $parent    = $session.CurrentParent
        # Application.Current is null with no window up (headless test harness) - deref throws.
        $app       = [System.Windows.Application]::Current
        $treeStyle = if ($app) { $app.TryFindResource('ModernTreeViewStyle') } else { $null }

        # Resolve a possibly-dotted property path against an object.
        # 'Parent.Id' on a Process returns $process.Parent.Id (not $process.'Parent.Id').
        $getDotted = {
            param($obj, [string]$pathExpr)
            if ($null -eq $obj -or [string]::IsNullOrEmpty($pathExpr)) { return $null }
            $current = $obj
            foreach ($part in $pathExpr.Split('.')) {
                if ($null -eq $current) { return $null }
                $current = $current.$part
            }
            return $current
        }

        # Create the tree control with base styling. -Fill defers the Height to the helper call below (after Add). Otherwise the fixed -Height applies.
        $treeProps = @{
            BorderThickness = [System.Windows.Thickness]::new(1)
            Margin          = [System.Windows.Thickness]::new(4)
        }
        if (!$Fill) { $treeProps.Height = $Height }
        $tree = [System.Windows.Controls.TreeView]$treeProps

        if ($treeStyle) { $tree.Style = $treeStyle }
        [PsUi.ThemeEngine]::RegisterElement($tree)

        # Use collected items from pipeline or direct parameter
        $allItems = if ($collectedItems.Count -gt 0) { $collectedItems } else { $Items }

        if ($IdProperty -and $ParentIdProperty -and $allItems) {
            # Build from parent-child ID relationships (process trees, org charts)
            $nodeMap = @{}
            
            # First pass: create nodes for each item
            foreach ($item in $allItems) {
                $id = & $getDotted $item $IdProperty
                if ($null -eq $id) { continue }
                
                $displayText = & $getDotted $item $DisplayProperty
                if ($null -eq $displayText) { $displayText = $id.ToString() }
                
                $node = [System.Windows.Controls.TreeViewItem]@{
                    Header = $displayText
                    Tag    = $item
                }
                if ($ExpandAll) { $node.IsExpanded = $true }
                
                $nodeMap[$id] = @{ Node = $node; Item = $item }
            }
            
            # Second pass: connect parent child relatonships
            foreach ($id in $nodeMap.Keys) {
                $entry    = $nodeMap[$id]
                $item     = $entry.Item
                $node     = $entry.Node
                $parentId = & $getDotted $item $ParentIdProperty
                
                if ($parentId -and $nodeMap.ContainsKey($parentId)) {
                    [void]$nodeMap[$parentId].Node.Items.Add($node)
                }
                else {
                    [void]$tree.Items.Add($node)
                }
            }
        }
        elseif ($PathProperty -and $allItems) {
            # Build hierarchy from path strings (filesystem, AD, registry)
            $nodeMap = @{}
            
            foreach ($item in $allItems | Sort-Object $PathProperty) {
                $path = & $getDotted $item $PathProperty
                if (!$path) { continue }
                
                # Split path into segments and optionally reverse for DN-style paths
                $segments = $path.Split($PathSeparator, [System.StringSplitOptions]::RemoveEmptyEntries)
                if ($ReversePath) { [array]::Reverse($segments) }
                
                $currentPath = ''
                $parentNode  = $null
                
                for ($i = 0; $i -lt $segments.Count; $i++) {
                    $segment     = $segments[$i]
                    $currentPath = if ($currentPath) { "$currentPath$PathSeparator$segment" } else { $segment }
                    $isOwnPath   = ($i -eq $segments.Count - 1)
                    
                    # Reuse existing node or create new one
                    if ($nodeMap.ContainsKey($currentPath)) {
                        $parentNode = $nodeMap[$currentPath]
                        # Upsert: an item piped in later may match an existing intermediate's path.
                        # Promote the synthesized Tag to the real source object.
                        if ($isOwnPath) { $parentNode.Tag = $item }
                    }
                    else {
                        # Tag is the source item when this segment IS the item's own path, otherwise a created placeholder carrying the accumulated path so consumers always have something actionable to read from .Tag.
                        $tagData = if ($isOwnPath) { $item } 
                        else { [PSCustomObject]@{ Path = $currentPath; Synthesized = $true }
                    }
                        
                        $node = [System.Windows.Controls.TreeViewItem]@{
                            Header = $segment
                            Tag    = $tagData
                        }
                        
                        if ($ExpandAll) { $node.IsExpanded = $true }
                        
                        if (!$parentNode) { [void]$tree.Items.Add($node) }
                        else { [void]$parentNode.Items.Add($node)  }
                        
                        $nodeMap[$currentPath] = $node
                        $parentNode = $node
                    }
                }
            }
        }
        elseif ($allItems) {
            # Walk nested data structure (hashtables with Children arrays)
            $buildNodes = {
                param($itemList, $parentNode)
                
                foreach ($item in $itemList) {
                    # $allItems can fall back to raw $Items on all null input,skip so the deref below is safe.
                    if ($null -eq $item) { continue }
                    $displayText = $null
                    $children    = $null
                    
                    # Handle both hashtables and PSObjects
                    if ($item -is [hashtable]) {
                        $displayText = $item[$DisplayProperty]
                        $children    = $item[$ChildrenProperty]
                    }
                    elseif ($item.PSObject.Properties[$DisplayProperty]) {
                        $displayText = $item.$DisplayProperty
                        $children    = $item.$ChildrenProperty
                    }
                    else {  $displayText = $item.ToString() }

                    $node = [System.Windows.Controls.TreeViewItem]@{
                        Header = $displayText
                        Tag    = $item
                    }

                    # Recurse into children if present
                    if ($children -and $children.Count -gt 0) {
                        & $buildNodes $children $node
                    }

                    if ($ExpandAll) { $node.IsExpanded = $true }

                    if (!$parentNode) {  [void]$tree.Items.Add($node) }
                    else { [void]$parentNode.Items.Add($node)  }
                }
            }
            
            & $buildNodes $allItems $null
        }

        # Decoration runs after the tree is built so parent/leaf is structural (Items.Count > 0) not predicted. All three build modes converge to the same TreeViewItem layout.
        $useCheckBoxes = $ParentCheckBoxes -or $ChildCheckBoxes
        if ($useCheckBoxes) {

            # Marker the C# extractor reads to flip hydration from snapshot to checked-items array.
            $tree.Tag = @{
                IsCheckBoxTree     = $true
                ParentMode         = [bool]$ParentCheckBoxes
                ChildMode          = [bool]$ChildCheckBoxes
                CascadeInProgress  = $false
            }
            $treeMeta = $tree.Tag

            # Synchronous helpers - only used during build. The cascade handler is stateless.
            $getHeaderCheckBox = {
                param($tvi)
                $hdr = $tvi.Header
                if ($hdr -is [System.Windows.Controls.StackPanel]) {
                    foreach ($child in $hdr.Children) {
                        if ($child -is [System.Windows.Controls.CheckBox]) { return $child }
                    }
                }
                $null
            }

            # Path mode invents stand-in parent nodes that aren't real items - WhenEnabled and Checked skip them.
            $isSynthesized = {
                param($source)
                if ($null -eq $source) { return $true }
                if ($source -is [PSCustomObject]) {
                    $p = $source.PSObject.Properties['Synthesized']
                    return ($p -and $p.Value)
                }
                if ($source -is [hashtable]) { return [bool]$source['Synthesized'] }
                $false
            }

            # One handler instance and two cached descriptors, pulled out of the foreach. 10k row trees notice.
            $dpdIsSelected = [System.ComponentModel.DependencyPropertyDescriptor]::FromProperty( [System.Windows.Controls.TreeViewItem]::IsSelectedProperty, [System.Windows.Controls.TreeViewItem])

            $dpdIsSelectionActive = [System.ComponentModel.DependencyPropertyDescriptor]::FromProperty( [System.Windows.Controls.Primitives.Selector]::IsSelectionActiveProperty, [System.Windows.Controls.TreeViewItem])

            $updateLabelFg = {
                param($sender, $e)
                
                $tviLocal = $sender -as [System.Windows.Controls.TreeViewItem]
                
                if ($null -eq $tviLocal -or $tviLocal.Header -isnot [System.Windows.Controls.StackPanel]) { return }
                $isActiveSel = $tviLocal.IsSelected -and [System.Windows.Controls.Primitives.Selector]::GetIsSelectionActive($tviLocal)
                $key = if ($isActiveSel) { 'SelectionForegroundBrush' } else { 'ControlForegroundBrush' }
                foreach ($childCtrl in $tviLocal.Header.Children) {
                    if ($childCtrl -is [System.Windows.Controls.TextBlock]) {
                        $childCtrl.SetResourceReference(
                            [System.Windows.Controls.TextBlock]::ForegroundProperty, $key)
                    }
                }
            }

            # Walk every TVI and decorate it.
            $decorate = {
                param($items)
                # Drag the outer descriptors and handler into local scope. GetNewClosure only captures locals, parent scope vars resolve to null after this function returns and Loaded fires.
                $dpdSel = $dpdIsSelected
                $dpdAct = $dpdIsSelectionActive
                $upd    = $updateLabelFg
                foreach ($tvi in $items) {
                    $hasChildren = $tvi.Items.Count -gt 0
                    $wantsBox = ($ParentCheckBoxes -and $hasChildren) -or
                                ($ChildCheckBoxes  -and !$hasChildren)

                    # Non checkbox rows in a mixed mode tree shouldn't look selectable. Checkboxes are the selection control.
                    # Focusable=$false kills arrow nav and click select. The expander toggle still works (separate element).
                    if (!$wantsBox -and ($ParentCheckBoxes -or $ChildCheckBoxes)) {  $tvi.Focusable = $false  }

                    if ($wantsBox) {
                        $source     = $tvi.Tag
                        $isFake     = & $isSynthesized $source
                        $headerText = $tvi.Header

                        $cb = [System.Windows.Controls.CheckBox]@{
                            VerticalAlignment = 'Center'
                            Margin            = [System.Windows.Thickness]::new(0, 0, 6, 0)
                        }

                        # Cascade handler is stateless and reads everything from $sender.Tag. The C# extractor walks TreeViewItems not CheckBoxes, so this Tag payload doesn't disturb hydration.
                        $cb.Tag = @{
                            Tvi      = $tvi
                            TreeMeta = $treeMeta
                        }

                        $disableThis = $false
                        if (!$isFake) {
                            # ForEach-Object binds $_. `$source | & $sb` does NOT (verified).
                            if ($Checked) {
                                $checkedResult = $source | ForEach-Object $Checked
                                if ($checkedResult) { $cb.IsChecked = $true }
                            }
                            if ($WhenEnabled) {
                                $enabledResult = $source | ForEach-Object $WhenEnabled
                                if (!$enabledResult) {
                                    $cb.IsEnabled = $false
                                    $disableThis = $true
                                }
                            }
                        }

                        $label = [System.Windows.Controls.TextBlock]@{
                            Text              = [string]$headerText
                            VerticalAlignment = 'Center'
                        }
                        # Default Foreground via DynamicResource so theme swaps reach it.
                        $label.SetResourceReference(
                            [System.Windows.Controls.TextBlock]::ForegroundProperty, 'ControlForegroundBrush')

                        # Watch IsSelected AND IsSelectionActive, Add_Selected misses the inactive case (tree loses focus, row stays selected).
                        # Loaded subscribes, Unloaded unsubscribes. The descriptor holds a strong reference and leaks a tree's worth of TVIs per closed window otherwise.
                        # WPF's memory model is more or less just a series of suggestions.
                        $tvi.Add_Loaded({
                            $dpdSel.AddValueChanged($tvi, $upd)
                            $dpdAct.AddValueChanged($tvi, $upd)
                        }.GetNewClosure())

                        $tvi.Add_Unloaded({
                            $dpdSel.RemoveValueChanged($tvi, $upd)
                            $dpdAct.RemoveValueChanged($tvi, $upd)
                        }.GetNewClosure())

                        $stack = [System.Windows.Controls.StackPanel]@{
                            Orientation = 'Horizontal'
                        }
                        [void]$stack.Children.Add($cb)
                        [void]$stack.Children.Add($label)
                        
                        # Set-CheckBoxStyle has no IsEnabled trigger - disabled boxes look enabled.
                        # Dim the whole header instead of patching the module-wide style.
                        if ($disableThis) { $stack.Opacity = 0.45 }
                        $tvi.Header = $stack

                        # Style AFTER the CheckBox is in the visual tree, DynamicResource lookups resolve better with a parent to walk up from.
                        # Set-CheckBoxStyle registers with ThemeEngine itself.
                        Set-CheckBoxStyle -CheckBox $cb
                    }

                    if ($tvi.Items.Count -gt 0) { & $decorate $tvi.Items }
                }
            }

            & $decorate $tree.Items

            # Attach cascade handlers. Skip when -NoCascade is set, or when only one checkbox level is enabled (nothing to cascade to/from).
            $wireCascade = ($ParentCheckBoxes -and $ChildCheckBoxes -and !$NoCascade)
            if ($wireCascade) {

                # Stateless. State via $sender.Tag, no closure capture. PS finally blocks get silently skipped when WPF fires the click, leaving CascadeInProgress stuck at true and locking subsequent clicks out. Reset inline in both paths.
                $cascadeHandler = {
                    param($sender, $eventArgs)
                    $treeMetaForReset = $null
                    try {
                        $data = $sender.Tag
                        if ($data -isnot [hashtable]) { return }
                        $treeMeta  = $data['TreeMeta']
                        $sourceTvi = $data['Tvi']
                        if ($null -eq $treeMeta -or $sourceTvi -isnot [System.Windows.Controls.TreeViewItem]) { return }
                        if ($treeMeta['CascadeInProgress']) { return }
                        $treeMeta['CascadeInProgress'] = $true
                        $treeMetaForReset = $treeMeta
                        $newState = [bool]$sender.IsChecked

                        # Cascade-down: walk children with a stack, checkbox lookup inlined.
                        # Helper script blocks throw on null lookups when called from the click handler.
                        $dnStack = [System.Collections.Generic.Stack[object]]::new()
                        $dnStack.Push($sourceTvi)
                        while ($dnStack.Count -gt 0) {
                            $node = $dnStack.Pop()
                            if ($null -eq $node) { continue }
                            foreach ($child in $node.Items) {
                                if ($null -eq $child) { continue }
                                $childHdr = $child.Header
                                if ($childHdr -is [System.Windows.Controls.StackPanel]) {
                                    foreach ($el in $childHdr.Children) {
                                        if ($el -is [System.Windows.Controls.CheckBox]) {
                                            if ($el.IsEnabled) { $el.IsChecked = $newState }
                                            break
                                        }
                                    }
                                }
                                $dnStack.Push($child)
                            }
                        }

                        # Cascade up. Walk ancestors via ItemsControlFromItemContainer. .Parent sometimes returns the visual-tree parent - this doesn't.
                        $node = $sourceTvi
                        while ($true) {
                            if ($null -eq $node) { break }
                            $parentTvi = [System.Windows.Controls.ItemsControl]::ItemsControlFromItemContainer($node)
                            if ($parentTvi -isnot [System.Windows.Controls.TreeViewItem]) { break }

                            $parentCb  = $null
                            $parentHdr = $parentTvi.Header
                            if ($parentHdr -is [System.Windows.Controls.StackPanel]) {
                                foreach ($el in $parentHdr.Children) {
                                    if ($el -is [System.Windows.Controls.CheckBox]) { $parentCb = $el; break }
                                }
                            }
                            if ($null -eq $parentCb) { break }

                            $allCheckedOrNone = $true
                            $anyEnabled       = $false
                            foreach ($sib in $parentTvi.Items) {
                                if ($null -eq $sib) { continue }
                                $sibCb  = $null
                                $sibHdr = $sib.Header
                                if ($sibHdr -is [System.Windows.Controls.StackPanel]) {
                                    foreach ($el in $sibHdr.Children) {
                                        if ($el -is [System.Windows.Controls.CheckBox]) { $sibCb = $el; break }
                                    }
                                }
                                if ($null -eq $sibCb -or !$sibCb.IsEnabled) { continue }
                                $anyEnabled = $true
                                if ($sibCb.IsChecked -ne $true) { $allCheckedOrNone = $false }
                            }
                            if (!$anyEnabled) { break }
                            $parentCb.IsChecked = $allCheckedOrNone
                            $node = $parentTvi
                        }

                        # Inline reset - finally is unreliable here.
                        if ($treeMetaForReset) { $treeMetaForReset['CascadeInProgress'] = $false }
                    }
                    catch {
                        # Catch path reset too - any throw otherwise locks the flag and kills subsequent cascades.
                        try { if ($treeMetaForReset) { $treeMetaForReset['CascadeInProgress'] = $false } } catch {}
                        try { Write-Warning ("[CASCADE] " + $_.Exception.Message) } catch {}
                    }
                }

                # Attach the cascade handler to every CheckBox we placed. Synchronous, $getHeaderCheckBox in scope.
                $wireBoxes = {
                    param($items)
                    foreach ($tvi in $items) {
                        $cb = & $getHeaderCheckBox $tvi
                        if ($cb) {
                            $cb.Add_Checked($cascadeHandler)
                            $cb.Add_Unchecked($cascadeHandler)
                        }
                        if ($tvi.Items.Count -gt 0) { & $wireBoxes $tvi.Items }
                    }
                }
                & $wireBoxes $tree.Items

                # Seed initial parent state. If -Checked prechecked anything, walk ancestors and recompute their binary state. Loop, not recursion, to mirror the runtime cascade.
                $treeMeta.CascadeInProgress = $true
                try {
                    # Collect every TVI that starts checked.
                    $allNodes = [System.Collections.Generic.Stack[object]]::new()
                    foreach ($root in $tree.Items) { $allNodes.Push($root) }
                    $checkedTvis = [System.Collections.Generic.List[object]]::new()
                    while ($allNodes.Count -gt 0) {
                        $n = $allNodes.Pop()
                        foreach ($c in $n.Items) { $allNodes.Push($c) }
                        $ncb = & $getHeaderCheckBox $n
                        if ($ncb -and $ncb.IsChecked -eq $true) { [void]$checkedTvis.Add($n) }
                    }

                    # For each checked node, ascend and refresh parent binary state.
                    foreach ($cnode in $checkedTvis) {
                        $node = $cnode
                        while ($true) {
                            $parentTvi = [System.Windows.Controls.ItemsControl]::ItemsControlFromItemContainer($node)
                            if ($parentTvi -isnot [System.Windows.Controls.TreeViewItem]) { break }
                            $parentCb = & $getHeaderCheckBox $parentTvi
                            if (!$parentCb) { break }

                            # Counter names avoid the bare word 'checked' - the function has a [scriptblock]$Checked param and PS is case insensitive.
                            # `$checked = 0` inherits the [scriptblock] constraint and throws at compile time.
                            $allCheckedOrNone = $true
                            $anyEnabled       = $false
                            foreach ($sib in $parentTvi.Items) {
                                $sibCb = & $getHeaderCheckBox $sib
                                if (!$sibCb -or !$sibCb.IsEnabled) { continue }
                                $anyEnabled = $true
                                if ($sibCb.IsChecked -ne $true) { $allCheckedOrNone = $false }
                            }
                            if (!$anyEnabled) { break }
                            $parentCb.IsChecked = $allCheckedOrNone
                            $node = $parentTvi
                        }
                    }
                }
                finally { $treeMeta.CascadeInProgress = $false }
            }
        }

        # Register control for variable hydration
        $session.AddControlSafe($Variable, $tree)

        # Reraise scroll events at the parent ScrollViewer so the tree doesn't swallow them.
        # Only without -Fill - a filled tree leaves the outer ScrollViewer nothing to scroll, so re-raising there kills the wheel entirely. The tree's own scrollbar has to own it.
        if (!$Fill) {
            $tree.Add_PreviewMouseWheel({
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
        }

        if ($WPFProperties) {
            # Tag is reserved only on checkbox trees since they keep hydration metadata there (IsCheckBoxTree et al) and the C# extractor reads it, so a user-set Tag would break checked items hydration.
            # Plain trees never touch $tree.Tag, so let those through. Copy before Remove: [hashtable] binds your own table by reference.
            if ($useCheckBoxes -and $WPFProperties.ContainsKey('Tag')) {
                Write-Warning "New-UiTree: -WPFProperties Tag is reserved (stores tree hydration metadata). Ignoring."
                $WPFProperties = @{} + $WPFProperties
                [void]$WPFProperties.Remove('Tag')
            }
            if ($WPFProperties.Count -gt 0) { Set-UiProperties -Control $tree -Properties $WPFProperties }
        }

        # Attach to parent container
        if ($parent -is [System.Windows.Controls.Panel]) { [void]$parent.Children.Add($tree)  }
        elseif ($parent -is [System.Windows.Controls.ItemsControl]) {  [void]$parent.Items.Add($tree)  }
        elseif ($parent -is [System.Windows.Controls.ContentControl]) {   $parent.Content = $tree  }

        if ($Fill) { Set-UiFillParentHeight -Control $tree }
    }
}
