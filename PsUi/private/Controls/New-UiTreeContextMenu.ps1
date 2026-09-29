function New-UiTreeContextMenu {
    <#
    .SYNOPSIS
        Builds a TreeView's right-click menu
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.TreeView]$Tree
    )

    $walkNodes = {
        param($root)
        $found = [System.Collections.Generic.List[object]]::new()
        $stack = [System.Collections.Generic.Stack[object]]::new()
        foreach ($item in $root.Items) { if ($null -ne $item) { $stack.Push($item) } }
        while ($stack.Count -gt 0) {
            $node = $stack.Pop()
            if ($node -isnot [System.Windows.Controls.TreeViewItem]) { continue }
            $found.Add($node)
            foreach ($child in $node.Items) { if ($null -ne $child) { $stack.Push($child) } }
        }
        , $found
    }

    $nodeText = {
        param($node)
        if ($null -eq $node) { return '' }
        $header = $node.Header
        if ($header -is [System.Windows.Controls.Panel]) {
            foreach ($child in $header.Children) {
                if ($child -is [System.Windows.Controls.TextBlock]) { return [string]$child.Text }
            }
            return ''
        }
        [string]$header
    }

    $headerBox = {
        param($node)
        $header = $node.Header
        if ($header -is [System.Windows.Controls.Panel]) {
            foreach ($child in $header.Children) {
                if ($child -is [System.Windows.Controls.CheckBox]) { return $child }
            }
        }
        $null
    }

    $setExpanded = {
        param($root, [bool]$state)
        $stack = [System.Collections.Generic.Stack[object]]::new()
        $stack.Push($root)
        while ($stack.Count -gt 0) {
            $node = $stack.Pop()
            if ($node -isnot [System.Windows.Controls.TreeViewItem]) { continue }
            if ($node.Items.Count -gt 0) { $node.IsExpanded = $state }
            foreach ($child in $node.Items) { if ($null -ne $child) { $stack.Push($child) } }
        }
    }

    # No code adds nodes after build
    $allNodes = & $walkNodes $Tree

    # New-UiTree adds hydration metadata on Tag, only checkbox trees get it.
    $treeMeta = $Tree.Tag -as [hashtable]
    $hasBoxes = $null -ne $treeMeta -and $treeMeta['IsCheckBoxTree'] -eq $true

    # IsChecked raises Checked/unchecked, cascade listens to both.
    # The clicked node's own box waits for the flag to lift, and a disabled one is ignored, so -WhenEnabled can leave it out of step with its children.
    $setSubtreeChecked = {
        param($root, [bool]$state)
        if (!$root) { return }

        # A throw below would leave CascadeInProgress stuck at true and every later click returning early.
        trap { Write-Debug "Subtree check: $_"; continue }

        $previous = $false
        if ($treeMeta) {
            $previous = [bool]$treeMeta['CascadeInProgress']
            $treeMeta['CascadeInProgress'] = $true
        }

        # Disabled means -WhenEnabled said no.
        foreach ($below in (& $walkNodes $root)) {
            $box = & $headerBox $below
            if ($box -and $box.IsEnabled) { $box.IsChecked = $state }
        }

        # PS skips finally when WPF fires the click.
        if ($treeMeta) { $treeMeta['CascadeInProgress'] = $previous }

        $ownBox = & $headerBox $root
        if ($ownBox -and $ownBox.IsEnabled) { $ownBox.IsChecked = $state }
    }.GetNewClosure()

    # A rightclick moves niether selection nor focus.
    $clickState = @{ Node = $null }
    $Tree.Add_ContextMenuOpening({
        param($sender, $eventArgs)
        trap { Write-Debug "Tree context menu target walk: $_"; continue }
        $clickState.Node = $null

        $hit = $eventArgs.OriginalSource -as [System.Windows.DependencyObject]
        while ($hit -and $hit -isnot [System.Windows.Controls.TreeViewItem]) {
            # VisualTreeHelper.GetParent throws on a ContentElement, and OriginalSource can be one (a Run inside the label).
            $hit = if ($hit -is [System.Windows.Media.Visual] -or $hit -is [System.Windows.Media.Media3D.Visual3D]) {
                [System.Windows.Media.VisualTreeHelper]::GetParent($hit)
            }
            else { [System.Windows.LogicalTreeHelper]::GetParent($hit) }
        }
        if (!$hit) { return }

        $clickState.Node = $hit

        # Keeps the hydrated SelectedItem honest.
        # A mixed checkbox tree sets Focusable false on rows with no box (the guard matches what a left click can reach).
        if ($hit.Focusable) { $hit.IsSelected = $true }
    }.GetNewClosure())

    # Shift+F10 opens the menu with no mouse
    $currentNode = {
        if ($clickState.Node) { return $clickState.Node }
        $Tree.SelectedItem -as [System.Windows.Controls.TreeViewItem]
    }.GetNewClosure()

    $contextMenu = [System.Windows.Controls.ContextMenu]::new()

    $expandAllItem        = [System.Windows.Controls.MenuItem]::new()
    $expandAllItem.Header = 'Expand All'
    [void]$contextMenu.Items.Add($expandAllItem)

    $expandAllItem.Add_Click({
        trap { Write-Debug "Expand all: $_"; continue }
        foreach ($node in $allNodes) { if ($node.Items.Count -gt 0) { $node.IsExpanded = $true } }
    }.GetNewClosure())

    $collapseAllItem        = [System.Windows.Controls.MenuItem]::new()
    $collapseAllItem.Header = 'Collapse All'
    [void]$contextMenu.Items.Add($collapseAllItem)
    $collapseAllItem.Add_Click({
        trap { Write-Debug "Collapse all: $_"; continue }
        foreach ($node in $allNodes) { if ($node.Items.Count -gt 0) { $node.IsExpanded = $false } }
    }.GetNewClosure())

    [void]$contextMenu.Items.Add([System.Windows.Controls.Separator]::new())

    $expandItem        = [System.Windows.Controls.MenuItem]::new()
    $expandItem.Header = 'Expand'
    [void]$contextMenu.Items.Add($expandItem)
    $expandItem.Add_Click({
        trap { Write-Debug "Expand node: $_"; continue }
        $node = & $currentNode
        if ($node) { & $setExpanded $node $true }
    }.GetNewClosure())

    $collapseItem        = [System.Windows.Controls.MenuItem]::new()
    $collapseItem.Header = 'Collapse'
    [void]$contextMenu.Items.Add($collapseItem)
    $collapseItem.Add_Click({
        trap { Write-Debug "Collapse node: $_"; continue }
        $node = & $currentNode
        if ($node) { & $setExpanded $node $false }
    }.GetNewClosure())

    # Useful when the cascade is off and clicking a parent moves itself only
    $checkItem   = $null
    $uncheckItem = $null
    if ($hasBoxes) {
        [void]$contextMenu.Items.Add([System.Windows.Controls.Separator]::new())

        $checkItem        = [System.Windows.Controls.MenuItem]::new()
        $checkItem.Header = 'Check All Below'
        [void]$contextMenu.Items.Add($checkItem)
        $checkItem.Add_Click({
            trap { Write-Debug "Check all below: $_"; continue }
            $node = & $currentNode
            if ($node) { & $setSubtreeChecked $node $true }
        }.GetNewClosure())

        $uncheckItem        = [System.Windows.Controls.MenuItem]::new()
        $uncheckItem.Header = 'Uncheck All Below'
        [void]$contextMenu.Items.Add($uncheckItem)
        $uncheckItem.Add_Click({
            trap { Write-Debug "Uncheck all below: $_"; continue }
            $node = & $currentNode
            if ($node) { & $setSubtreeChecked $node $false }
        }.GetNewClosure())
    }

    [void]$contextMenu.Items.Add([System.Windows.Controls.Separator]::new())

    $copyItem        = [System.Windows.Controls.MenuItem]::new()
    $copyItem.Header = 'Copy'
    [void]$contextMenu.Items.Add($copyItem)
    $copyItem.Add_Click({
        trap { Write-Debug "Copy node text: $_"; continue }
        $node = & $currentNode
        if (!$node) { return }
        $text = & $nodeText $node
        # SetText throws outright when another process is holding the clipboard open
        if ($text) { [System.Windows.Clipboard]::SetText($text) }
    }.GetNewClosure())

    $contextMenu.Add_Opened({
        trap { Write-Debug "Tree context menu open: $_"; continue }
        $node = & $currentNode
        $anyShut = $false
        $anyOpen = $false
        foreach ($candidate in $allNodes) {
            if ($candidate.Items.Count -eq 0) { continue }
            if ($candidate.IsExpanded) { $anyOpen = $true }
            else { $anyShut = $true }
            if ($anyOpen -and $anyShut) { break }
        }

        $hasChild = $node -and $node.Items.Count -gt 0

        $expandAllItem.IsEnabled   = $anyShut
        $collapseAllItem.IsEnabled = $anyOpen
        $expandItem.IsEnabled      = $hasChild
        $collapseItem.IsEnabled    = $hasChild
        $copyItem.IsEnabled        = $null -ne $node

        # -ParentCheckBoxes puts the box on the node and -ChildCheckBoxes on the leafs under it
        if ($checkItem) {
            $reachable             = $hasChild -or ($node -and $null -ne (& $headerBox $node))
            $checkItem.IsEnabled   = [bool]$reachable
            $uncheckItem.IsEnabled = [bool]$reachable
        }
    }.GetNewClosure())

    $Tree.ContextMenu = $contextMenu
    Set-ContextMenuStyle -ContextMenu $contextMenu
}
