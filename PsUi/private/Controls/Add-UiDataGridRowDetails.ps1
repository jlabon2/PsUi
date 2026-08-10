function Add-UiDataGridRowDetails {
    <#
    .SYNOPSIS
        Expandable per row detail panel from -RowDetailsTemplate. $_ is the row.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid,

        [Parameter(Mandatory)]
        [scriptblock]$Template
    )

    $DataGrid.RowDetailsVisibilityMode = [System.Windows.Controls.DataGridRowDetailsVisibilityMode]::VisibleWhenSelected

    $panelFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.StackPanel])
    $panelFactory.SetValue([System.Windows.Controls.StackPanel]::MarginProperty, [System.Windows.Thickness]::new(24, 8, 12, 8))
    $panelFactory.SetValue([System.Windows.Controls.StackPanel]::OrientationProperty, [System.Windows.Controls.Orientation]::Vertical)

    $tpl = [System.Windows.DataTemplate]::new()
    $tpl.VisualTree = $panelFactory
    $DataGrid.RowDetailsTemplate = $tpl

    # InvokeWithContext - $_ doesn't survive the trip across the module boundary by itself.
    $templateRef = $Template
    $DataGrid.Add_LoadingRowDetails({
        param($sender, $eventArgs)
        $panel = $eventArgs.DetailsElement -as [System.Windows.Controls.Panel]
        if (!$panel) { return }

        $row = $eventArgs.Row.Item
        if ($null -eq $row) { return }

        #  WPF hands the same panel to different rows during scroll. Guarding on child count alone misfires when the recycled panel still holds another row's children. The identity check on $panel.Tag proves it actually belongs to this one.
        if ($null -ne $panel.Tag -and [object]::ReferenceEquals($panel.Tag, $row)) { return }
        $panel.Children.Clear()
        $panel.Tag = $row

        $sess = Get-UiSession
        if (!$sess) { return }

        # PS's CheckActionPreference NREs on leaving the try block when the scriptblock is invoked off pipeline (WPF routed event delegate). The NRE propagates to the window's Dispatcher.UnhandledException handler and prints a stack trace even when the template ran fine, just to keep morale up. trap covers cleanup on the error path. The final assignment covers success. 
        $previousParent = $sess.CurrentParent
        $sess.CurrentParent = $panel

        trap {
            $sess.CurrentParent = $previousParent
            Write-Debug "RowDetailsTemplate failed: $($_.Exception.Message)"
            continue
        }

        $vars = [System.Collections.Generic.List[psvariable]]::new()
        $vars.Add([psvariable]::new('_', $row))
        $vars.Add([psvariable]::new('row', $row))
        # Third InvokeWithContext arg is args[] - if $row is itself an object[] it splats into the scriptblock's $args.
        [void]$templateRef.InvokeWithContext($null, $vars)

        $sess.CurrentParent = $previousParent
    }.GetNewClosure())

    # WPF recycles row containers as they scroll out, so clear the panel so the next row gets a fresh one. Tag goes back to $null so the identity guard doesn't skip the next row.
    $DataGrid.Add_UnloadingRowDetails({
        param($sender, $eventArgs)
        $panel = $eventArgs.DetailsElement -as [System.Windows.Controls.Panel]
        if ($panel) {
            $panel.Children.Clear()
            $panel.Tag = $null
        }
    })

    # The LoadingRowDetails closure captures the user's $Template scriptblock. The grid's lifetime is set by the session (session dies with window), so the closure dies on window close. Clearing RowDetailsTemplate on Window.Closed drops the template's element refs early, which matters when an external script stil holds the grid after the window is gone.
    $detachState = @{ Done = $false }
    $DataGrid.Add_Loaded({
        if ($detachState.Done) { return }
        $window = [System.Windows.Window]::GetWindow($this)
        if (!$window) { return }
        $grid = $this
        
        $window.Add_Closed({
            try { $grid.RowDetailsTemplate = $null } catch { Write-Debug "RowDetails template clear: $_" }
        }.GetNewClosure())
        
        $detachState.Done = $true
    }.GetNewClosure())
}
