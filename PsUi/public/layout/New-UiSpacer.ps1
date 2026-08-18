function New-UiSpacer {
    <#
    .SYNOPSIS
        Creates a transparent spacer that fills remaining space in the current parent.
    .DESCRIPTION
        A layout helper that consumes available space, pushing the controls around it
        apart. It needs a parent that actually hands out leftover room: a star sized
        New-UiGrid cell or a DockPanel. A plain stacking panel gives children only the
        space they ask for, so a spacer there collapses to nothing.

        In a DockPanel with LastChildFill = true, add as the last child (no dock)
        to fill the gap between left- and right-docked controls.

        In a StatusBar (which uses a DockPanel internally), drop New-UiSpacer
        between left content and right content.
    .EXAMPLE
        # Push Cancel button to the right side of a status bar
        New-UiStatusBar -Content {
            New-UiLabel -Text 'Ready'
            New-UiSpacer
            New-UiButton -Text 'Cancel' -NoOutput -Action { }
        }
        # Result: [Ready                        Cancel]
    .EXAMPLE
        # Push Back and Next to opposite edges of the row
        New-UiGrid -Columns 'Auto, *, Auto' -Content {
            New-UiButton -Text 'Back' -Action { }
            New-UiSpacer
            New-UiButton -Text 'Next' -Action { }
        }
    #>
    [CmdletBinding()]
    param()

    $session = Get-UiSession
    if (!$session) { return }
    $parent = $session.CurrentParent

    $spacer = [System.Windows.Controls.Border]::new()
    $spacer.HorizontalAlignment = 'Stretch'
    $spacer.VerticalAlignment   = 'Stretch'

    # Tag so StatusBar and other parents can identify spacers by convention
    $spacer.Tag = @{ IsSpacer = $true }

    # Don't set Dock: an undocked child in a DockPanel fills remaining space.
    # In other containers, Stretch alignment does the right thing.

    if ($parent -is [System.Windows.Controls.Panel]) {
        [void]$parent.Children.Add($spacer)
    }
    elseif ($parent -is [System.Windows.Controls.ItemsControl]) {
        [void]$parent.Items.Add($spacer)
    }
}
