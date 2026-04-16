function Set-ResponsiveConstraints {
    <#
    .SYNOPSIS
        Applies responsive sizing logic to controls based on parent width.
        Used with New-UIContentArea to create a responsive layout.
        Kind of hacky but works within WPF's layout system.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Control,

        [switch]$FullWidth,

        [int]$MaxColumns
    )

    $session = Get-UiSession
    if (!$session) { return }

    $parent = $session.CurrentParent
    if (!$parent) { return }

    # Standardize margins (8px on all sides = 16px total horizontal)
    $defaultMargin = 8
    $Control.Margin = [System.Windows.Thickness]::new($defaultMargin)

    # Check for StackPanel inside TabItem (Special case for tabs)
    $isInsideTabItem = $false
    if ($parent -is [System.Windows.Controls.StackPanel]) {
        
        # StackPanels inside TabItems get special margin handling
        # Try Parent property first, then TemplatedParent for content elements
        $parentOfParent = $parent.Parent
        
        if ($null -eq $parentOfParent) {  $parentOfParent = $parent.TemplatedParent }
        if ($parentOfParent -is [System.Windows.Controls.TabItem]) { $isInsideTabItem = $true }

        # Also check if we're inside a TabControl by walking up
        if (!$isInsideTabItem) {

            $ancestor = $parent
            for ($i = 0; $i -lt 5; $i++) {
                if ($null -eq $ancestor) { break }
                if ($ancestor -is [System.Windows.Controls.TabControl]) {
                    $isInsideTabItem = $true
                    break
                }
                $ancestor = $ancestor.Parent
            }
        }
    }

    if ($isInsideTabItem) { $Control.HorizontalAlignment = 'Stretch'  }
    elseif ($parent -is [System.Windows.Controls.WrapPanel]) {
        
        # This is the main responsive container (New-UIContentArea)
        # Mark this control with its full-width status via Tag for later detection
        if ($FullWidth) {
            $Control.Tag = 'FullWidth'
        }
        
        # Resize with parent - full-width if marked, or if last item in odd-numbered list
        # This creates a better balance to avoid lonely items on a new row
        $parent.Add_SizeChanged({
            param($sender, $eventArgs)

            $paddingBuffer = 18
            $availableWidth = $sender.ActualWidth - $paddingBuffer

            # Safety check
            if ($availableWidth -le 0) { return }

            # Determine if this is the last item that would be alone in its row
            $shouldBeFullWidth = $false
            $isMarkedFullWidth = ($Control.Tag -eq 'FullWidth')

            if (!$isMarkedFullWidth) {

                # Count GroupBox/TabControl siblings (panels)
                $panels = @($sender.Children | Where-Object {
                    $_ -is [System.Windows.Controls.GroupBox] -or
                    $_ -is [System.Windows.Controls.TabControl]
                })
                $panelCount = $panels.Count

                # Find the current control's index
                $currentIndex = -1
                for ($i = 0; $i -lt $panelCount; $i++) {
                    if ($panels[$i] -eq $Control) {
                        $currentIndex = $i
                        break
                    }
                }

                # If this is the last panel, check if it would be alone
                if ($currentIndex -eq ($panelCount - 1)) {

                    # Count how many REGULAR (non-full-width) panels come BEFORE this one
                    $regularCountBefore = 0

                    for ($i = 0; $i -lt $currentIndex; $i++) {
                        $panel = $panels[$i]

                        # FullWidth panels don't count toward the 2-per-row layout
                        if ($panel.Tag -ne 'FullWidth') { $regularCountBefore++ }

                    }

                    # If there's an EVEN number of regular panels before this one,
                    # they fill complete rows (2 per row), so this panel starts alone
                    if (($regularCountBefore % 2) -eq 0) { $shouldBeFullWidth = $true }
                }
            }

            if ($isMarkedFullWidth -or $shouldBeFullWidth) { $Control.Width = $availableWidth }
            else {
                # Use MaxColumns if explicitly passed, otherwise default to 2
                # This is for the WINDOW's content area layout, independent of panel internals
                $maxCols = if ($MaxColumns -gt 0) { $MaxColumns } else { 2 }

                # Calculate column width based on available space and max columns
                $minColumnWidth = 350  # Minimum usable width for a column

                # Determine how many columns can fit
                $possibleCols = [Math]::Floor($availableWidth / $minColumnWidth)
                $actualCols   = [Math]::Min($possibleCols, $maxCols)
                $actualCols   = [Math]::Max($actualCols, 1)  # At least 1 column

                # Set width based on column count
                if ($actualCols -eq 1) {  $Control.Width = $availableWidth }
                else { $Control.Width = ($availableWidth / $actualCols) - 8  }
            }
        }.GetNewClosure())
    }
}