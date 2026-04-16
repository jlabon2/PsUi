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
        Height of the tree control. Defaults to 200.
    .PARAMETER ExpandAll
        Expand all nodes on load.
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
        # Process tree - parent/child by ID
        Get-Process | New-UiTree -Variable 'procs' -IdProperty 'Id' -ParentIdProperty 'Parent.Id' -DisplayProperty 'ProcessName'
    .EXAMPLE
        # .NET namespaces
        [AppDomain]::CurrentDomain.GetAssemblies().GetTypes() | 
            Select -Unique FullName | 
            New-UiTree -Variable 'types' -PathProperty 'FullName' -PathSeparator '.'
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

        [switch]$ExpandAll,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    begin {
        $collectedItems = [System.Collections.Generic.List[object]]::new()
    }

    process {
        if ($Items) {
            foreach ($item in $Items) { $collectedItems.Add($item) }
        }
    }

    end {
        $session   = Assert-UiSession -CallerName 'New-UiTree'
        $parent    = $session.CurrentParent
        $treeStyle = [System.Windows.Application]::Current.TryFindResource('ModernTreeViewStyle')

        # Create the tree control with base styling
        $tree = [System.Windows.Controls.TreeView]@{
            Height          = $Height
            BorderThickness = [System.Windows.Thickness]::new(1)
            Margin          = [System.Windows.Thickness]::new(4)
        }

        if ($treeStyle) { $tree.Style = $treeStyle }
        [PsUi.ThemeEngine]::RegisterElement($tree)

        # Use collected items from pipeline or direct parameter
        $allItems = if ($collectedItems.Count -gt 0) { $collectedItems } else { $Items }

        if ($IdProperty -and $ParentIdProperty -and $allItems) {
            # Build from parent-child ID relationships (process trees, org charts)
            $nodeMap = @{}
            
            # First pass: create nodes for each item
            foreach ($item in $allItems) {
                $id = $item.$IdProperty
                if ($null -eq $id) { continue }
                
                $displayText = if ($item.PSObject.Properties[$DisplayProperty]) { $item.$DisplayProperty } else { $id.ToString() }
                
                $node = [System.Windows.Controls.TreeViewItem]@{
                    Header = $displayText
                    Tag    = $item
                }
                if ($ExpandAll) { $node.IsExpanded = $true }
                
                $nodeMap[$id] = @{ Node = $node; Item = $item }
            }
            
            # Second pass: wire parent-child relatonships
            foreach ($id in $nodeMap.Keys) {
                $entry    = $nodeMap[$id]
                $item     = $entry.Item
                $node     = $entry.Node
                $parentId = $item.$ParentIdProperty
                
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
                $path = $item.$PathProperty
                if (!$path) { continue }
                
                # Split path into segments and optionally reverse for DN-style paths
                $segments = $path.Split($PathSeparator, [System.StringSplitOptions]::RemoveEmptyEntries)
                if ($ReversePath) { [array]::Reverse($segments) }
                
                $currentPath = ''
                $parentNode  = $null
                
                for ($i = 0; $i -lt $segments.Count; $i++) {
                    $segment     = $segments[$i]
                    $currentPath = if ($currentPath) { "$currentPath$PathSeparator$segment" } else { $segment }
                    
                    # Reuse existing node or create new one
                    if ($nodeMap.ContainsKey($currentPath)) {
                        $parentNode = $nodeMap[$currentPath]
                    }
                    else {
                        $isLeaf  = ($i -eq $segments.Count - 1)
                        $tagData = if ($isLeaf) { $item } else { $null }
                        
                        $node = [System.Windows.Controls.TreeViewItem]@{
                            Header = $segment
                            Tag    = $tagData
                        }
                        
                        if ($ExpandAll) { $node.IsExpanded = $true }
                        
                        if (!$parentNode) {
                            [void]$tree.Items.Add($node)
                        }
                        else {
                            [void]$parentNode.Items.Add($node)
                        }
                        
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
                    else {
                        $displayText = $item.ToString()
                    }

                    $node = [System.Windows.Controls.TreeViewItem]@{
                        Header = $displayText
                        Tag    = $item
                    }

                    # Recurse into children if present
                    if ($children -and $children.Count -gt 0) {
                        & $buildNodes $children $node
                    }

                    if ($ExpandAll) { $node.IsExpanded = $true }

                    if (!$parentNode) {
                        [void]$tree.Items.Add($node)
                    }
                    else {
                        [void]$parentNode.Items.Add($node)
                    }
                }
            }
            
            & $buildNodes $allItems $null
        }

        # Register control for variable hydration
        $session.AddControlSafe($Variable, $tree)

        # Bubble scroll events to parent ScrollViewer so tree doesn't swallow them
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

        if ($WPFProperties) {
            Set-UiProperties -Control $tree -Properties $WPFProperties
        }

        # Attach to parent container
        if ($parent -is [System.Windows.Controls.Panel]) {
            [void]$parent.Children.Add($tree)
        }
        elseif ($parent -is [System.Windows.Controls.ItemsControl]) {
            [void]$parent.Items.Add($tree)
        }
        elseif ($parent -is [System.Windows.Controls.ContentControl]) {
            $parent.Content = $tree
        }
    }
}
