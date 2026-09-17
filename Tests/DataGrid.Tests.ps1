#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# New-UiDataGrid itself. Build, bind, refresh and export.
. (Join-Path $PSScriptRoot '_Setup.ps1')

BeforeAll { . (Join-Path $PSScriptRoot '_Setup.ps1') }

# Same chrome as Show-UiOutput, minus the window.
Describe 'New-UiDataGrid' -Tag 'RequiresSession' {

    BeforeEach {
        $script:dgSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:dgSessionId)
        $script:dgSession = [PsUi.SessionManager]::Current
        $script:dgSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterEach {
        [PsUi.SessionManager]::DisposeSession($script:dgSessionId)
    }

    It 'Adds a container to the parent and registers the grid for hydration' {
        $items = @(
            [PSCustomObject]@{ A = 1; B = 'x' }
            [PSCustomObject]@{ A = 2; B = 'y' }
        )
        New-UiDataGrid -Variable 'gridA' -Items $items -Height 200

        $script:dgSession.CurrentParent.Children.Count | Should -BeGreaterThan 0
        $registered = $script:dgSession.GetControl('gridA')
        $registered | Should -Not -BeNullOrEmpty
        $registered | Should -BeOfType [System.Windows.Controls.DataGrid]
    }

    It 'Registers the backing collection under the variable name' {
        New-UiDataGrid -Variable 'gridB' -Items @([PSCustomObject]@{ X = 1 }) -NoToolbar
        $coll = $script:dgSession.GetListCollection('gridB')
        $coll | Should -Not -BeNullOrEmpty
        $coll.Count | Should -Be 1
    }

    It 'Throws when both -Items and -ItemsSource are supplied' {
        $external = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        { New-UiDataGrid -Variable 'gridC' -Items @(1) -ItemsSource $external } |
            Should -Throw '*cannot use both*'
    }

    It 'Auto-generates columns from items when -Columns is omitted' {
        $items = @([PSCustomObject]@{ Name = 'a'; Count = 1 })
        New-UiDataGrid -Variable 'gridD' -Items $items -NoToolbar
        $grid = $script:dgSession.GetControl('gridD')
        # Names, not a count. A generator that stopped after the first property still clears a count above zero.
        @($grid.Columns | ForEach-Object { $_.Header }) | Should -Be @('Name', 'Count')
    }

    It '-Columns hashtable with Type=Button creates a template column' {
        $items = @([PSCustomObject]@{ Name = 'a' })
        New-UiDataGrid -Variable 'gridF' -Items $items -NoToolbar -Columns @(
            @{ Name = 'Name' }
            @{ Header = 'Act'; Type = 'Button'; Text = 'Go'; Action = { } }
        )
        $grid   = $script:dgSession.GetControl('gridF')
        $btnCol = $grid.Columns | Where-Object { $_.Header -eq 'Act' }
        $btnCol | Should -BeOfType [System.Windows.Controls.DataGridTemplateColumn]
    }

    It '-Editable flips text columns IsReadOnly off' {
        $items = @([PSCustomObject]@{ Name = 'a'; Count = 1 })
        New-UiDataGrid -Variable 'gridG' -Items $items -Editable -NoToolbar
        $grid     = $script:dgSession.GetControl('gridG')
        $textCols = @($grid.Columns | Where-Object { $_ -is [System.Windows.Controls.DataGridTextColumn] })
        $textCols.Count | Should -BeGreaterThan 0
        foreach ($textCol in $textCols) { $textCol.IsReadOnly | Should -BeFalse }
    }

    It '-Editable + bool first-value renders the bool-glyph TemplateColumn by default' {
        # Bool columns become a template column of glyphs. -NoVisualValues keeps the checkbox.
        $items = @([PSCustomObject]@{ Flag = $true })
        New-UiDataGrid -Variable 'gridH' -Items $items -Editable -NoToolbar -Columns @(
            @{ Name = 'Flag'; Editable = $true }
        )
        $grid = $script:dgSession.GetControl('gridH')
        $col  = $grid.Columns | Where-Object { $_.Header -eq 'Flag' }
        $col | Should -BeOfType [System.Windows.Controls.DataGridTemplateColumn]
        # Editable bool keeps a checkbox in the editing template so doubleclick / F2 toggles.
        $col.CellEditingTemplate | Should -Not -BeNullOrEmpty
    }

    It '-Editable + bool + -NoVisualValues keeps the raw DataGridCheckBoxColumn' {
        $items = @([PSCustomObject]@{ Flag = $true })
        New-UiDataGrid -Variable 'gridHb' -Items $items -Editable -NoToolbar -NoVisualValues -Columns @(
            @{ Name = 'Flag'; Editable = $true }
        )
        $grid = $script:dgSession.GetControl('gridHb')
        $col  = $grid.Columns | Where-Object { $_.Header -eq 'Flag' }
        $col | Should -BeOfType [System.Windows.Controls.DataGridCheckBoxColumn]
    }

    It '-Editable + enum first-value picks DataGridComboBoxColumn with enum values' {
        $items = @([PSCustomObject]@{ State = [System.DayOfWeek]::Monday })
        New-UiDataGrid -Variable 'gridI' -Items $items -Editable -NoToolbar -Columns @(
            @{ Name = 'State'; Editable = $true }
        )
        $grid = $script:dgSession.GetControl('gridI')
        $col  = $grid.Columns | Where-Object { $_.Header -eq 'State' }
        $col | Should -BeOfType [System.Windows.Controls.DataGridComboBoxColumn]
        @($col.ItemsSource).Count | Should -Be 7
    }

    It '-NoSort disables column sorting on the grid' {
        $items = @([PSCustomObject]@{ N = 1 })
        New-UiDataGrid -Variable 'gridJ' -Items $items -NoSort -NoToolbar
        $grid = $script:dgSession.GetControl('gridJ')
        $grid.CanUserSortColumns | Should -BeFalse
    }

    It '-HideEmptyColumns collapses columns where all values are null/empty' {
        $items = @(
            [PSCustomObject]@{ Has = 1; Empty = $null }
            [PSCustomObject]@{ Has = 2; Empty = $null }
        )
        New-UiDataGrid -Variable 'gridK' -Items $items -HideEmptyColumns -NoToolbar
        $grid     = $script:dgSession.GetControl('gridK')
        $emptyCol = $grid.Columns | Where-Object { $_.Header -eq 'Empty' }
        $emptyCol.Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)
    }

    It 'Set-UiDataGridItems replaces the backing collection' {
        New-UiDataGrid -Variable 'gridL' -Items @([PSCustomObject]@{ N = 1 }) -NoToolbar
        Set-UiDataGridItems -Variable 'gridL' -Items @(
            [PSCustomObject]@{ N = 9 }
            [PSCustomObject]@{ N = 8 }
        )
        $coll = $script:dgSession.GetListCollection('gridL')
        $coll.Count | Should -Be 2
        $coll[0].N | Should -Be 9
    }

    It 'Add-UiDataGridItem appends a single row' {
        New-UiDataGrid -Variable 'gridM' -Items @([PSCustomObject]@{ N = 1 }) -NoToolbar
        Add-UiDataGridItem -Variable 'gridM' -Item ([PSCustomObject]@{ N = 2 })
        $coll = $script:dgSession.GetListCollection('gridM')
        $coll.Count | Should -Be 2
    }

    It 'Clear-UiDataGridItems empties the collection' {
        New-UiDataGrid -Variable 'gridN' -Items @([PSCustomObject]@{ N = 1 }; [PSCustomObject]@{ N = 2 }) -NoToolbar
        Clear-UiDataGridItems -Variable 'gridN'
        $coll = $script:dgSession.GetListCollection('gridN')
        $coll.Count | Should -Be 0
    }

    It 'Set-UiDataGridItems on an unknown variable writes an error and returns' {
        $errs = $null
        Set-UiDataGridItems -Variable 'doesNotExist' -Items @('placeholder') -ErrorVariable errs -ErrorAction SilentlyContinue
        $errs | Should -Not -BeNullOrEmpty
    }

    It '-OnCellEdit fires after a cell commit with ($row, $col, $new, $old)' {
        $script:editCalls = [System.Collections.Generic.List[object]]::new()
        $items     = @([PSCustomObject]@{ Name = 'a'; Note = 'old' })
        $gridSplat = @{
            Variable   = 'gridO'
            Items      = $items
            Editable   = $true
            NoToolbar  = $true
            OnCellEdit = { param($row, $col, $new, $old) $script:editCalls.Add(@{ Row = $row; Col = $col; New = $new; Old = $old }) }
        }
        New-UiDataGrid @gridSplat

        $grid    = $script:dgSession.GetControl('gridO')
        $noteCol = $grid.Columns | Where-Object { $_.Header -eq 'Note' }
        $rowItem = @($grid.ItemsSource)[0]

        # CellEditEnding is a plain .NET event, not routed, so RaiseEvent can't reach it.
        # Invoke the protected raiser by reflection instead.
        $editor       = [System.Windows.Controls.TextBox]@{ Text = 'new' }
        $dgRow        = [System.Windows.Controls.DataGridRow]@{ Item = $rowItem }
        $cellArgs     = [System.Windows.Controls.DataGridCellEditEndingEventArgs]::new($noteCol, $dgRow, $editor, [System.Windows.Controls.DataGridEditAction]::Commit)
        $bindingFlags = [System.Reflection.BindingFlags] 'Instance, NonPublic'
        $raiser       = [System.Windows.Controls.DataGrid].GetMethod('OnCellEditEnding', $bindingFlags)
        $raiser.Invoke($grid, @([object]$cellArgs))

        # The user handler defers at Background priority, so drain it with a lower priority continuation.
        $frame = [System.Windows.Threading.DispatcherFrame]::new()
        [void]$grid.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::ContextIdle,
            [Action]{ $frame.Continue = $false })
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)

        $script:editCalls.Count | Should -Be 1
        $script:editCalls[0].Col | Should -Be 'Note'
        $script:editCalls[0].New | Should -Be 'new'
        $script:editCalls[0].Old | Should -Be 'old'
    }

    It '-OnCellEdit hands the property name (not Header) when a column hashtable uses Name + Header' {
        # oldValue resolves through Column.SortMemberPath. $row.$Header read the wrong property whenever Name and Header differ.
        $script:editCalls2 = [System.Collections.Generic.List[object]]::new()
        $items = @([PSCustomObject]@{ Status = 'Running' })
        New-UiDataGrid -Variable 'gridHN' -Items $items -Editable -NoToolbar -Columns @(
            @{ Name = 'Status'; Header = 'Service Status'; Editable = $true }
        ) -OnCellEdit { param($row, $col, $new, $old) $script:editCalls2.Add(@{ Col = $col; New = $new; Old = $old }) }

        $grid    = $script:dgSession.GetControl('gridHN')
        $col     = $grid.Columns | Where-Object { $_.Header -eq 'Service Status' }
        $rowItem = @($grid.ItemsSource)[0]

        $editor       = [System.Windows.Controls.TextBox]@{ Text = 'Stopped' }
        $dgRow        = [System.Windows.Controls.DataGridRow]@{ Item = $rowItem }
        $cellArgs     = [System.Windows.Controls.DataGridCellEditEndingEventArgs]::new($col, $dgRow, $editor, [System.Windows.Controls.DataGridEditAction]::Commit)
        $bindingFlags = [System.Reflection.BindingFlags] 'Instance, NonPublic'
        $raiser       = [System.Windows.Controls.DataGrid].GetMethod('OnCellEditEnding', $bindingFlags)
        $raiser.Invoke($grid, @([object]$cellArgs))

        $frame = [System.Windows.Threading.DispatcherFrame]::new()
        [void]$grid.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::ContextIdle,
            [Action]{ $frame.Continue = $false })
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)

        $script:editCalls2.Count | Should -Be 1
        $script:editCalls2[0].Col | Should -Be 'Status'
        $script:editCalls2[0].New | Should -Be 'Stopped'
        $script:editCalls2[0].Old | Should -Be 'Running'
    }

    It '-OnDoubleClick registers without throwing and leaves the grid usable' {
        # MouseDoubleClick only fires from real mouse input, and Pester runs with no window, so this is as far as it goes. It still catches the handler failing to attach.
        $items = @([PSCustomObject]@{ Name = 'a' })
        { New-UiDataGrid -Variable 'gridDbl' -Items $items -NoToolbar -OnDoubleClick { param($row) } } | Should -Not -Throw

        $grid = $script:dgSession.GetControl('gridDbl')
        $grid | Should -Not -BeNullOrEmpty
        @($grid.ItemsSource).Count | Should -Be 1
    }

    It 'Exports the four commands a grid script calls' {
        # The injection table test below proves they reach an async runspace. This proves a user can reach them at all.
        $exported = (Get-Module PsUi).ExportedFunctions.Keys
        foreach ($name in 'New-UiDataGrid', 'Set-UiDataGridItems', 'Add-UiDataGridItem', 'Clear-UiDataGridItems') {
            $exported | Should -Contain $name
        }
    }

    It 'ConvertTo-UiDataGridSnapshot preserves PSStandardMembers and TypeNames[0] for .NET items' {
        InModuleScope PsUi {
            $proc = Get-Process -Id $PID
            $snap = @(ConvertTo-UiDataGridSnapshot -Items @($proc))
            $snap.Count | Should -Be 1
            $snapItem = $snap[0]

            # Original CLR type leads the TypeNames so Add-DataGridColumns regex fallbacks match
            $snapItem.PSObject.TypeNames[0] | Should -Match 'System\.Diagnostics\.Process'

            # DefaultDisplayPropertySet reattached so -DefaultPropertiesOnly still works
            $stdMembers = $snapItem.PSStandardMembers
            $stdMembers | Should -Not -BeNullOrEmpty
            $defaults = $stdMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaults | Should -Contain 'Id'

            $snapItem._BaseObject | Should -Not -BeNullOrEmpty
            $snapItem._BaseObject.Id | Should -Be $PID
        }
    }

    It 'ConvertTo-UiDataGridSnapshot -BuildSearchIndex attaches _SearchText' {
        InModuleScope PsUi {
            $items = @(
                [PSCustomObject]@{ Name = 'alpha';  City = 'NYC'   }
                [PSCustomObject]@{ Name = 'bravo';  City = 'Tokyo' }
            )
            $snap = @(ConvertTo-UiDataGridSnapshot -Items $items -BuildSearchIndex)
            # Every property, not just the first. Name alone leaves the filter blind past column one.
            $snap[0]._SearchText | Should -Be 'alpha NYC '
            $snap[1]._SearchText | Should -Be 'bravo Tokyo '
        }
    }

    It 'Add-UiDataGridItem appends to an -ItemsSource grid (wrap + mirror)' {
        # ItemsSource rows go in raw, so the mirror keeps the real object, not a PSCustomObject copy.
        # SilentlyContinue eats the bind warning, which always fires under Pester scopes.
        $external = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $external.Add([PSCustomObject]@{ X = 1 })
        New-UiDataGrid -Variable 'gridQ' -ItemsSource $external -NoToolbar -WarningAction SilentlyContinue

        $newRow = [PSCustomObject]@{ X = 2 }
        Add-UiDataGridItem -Variable 'gridQ' -Item $newRow

        # The session tracks the wrap on ItemsSource. The mirror keeps the original rows.
        $wrapper = $script:dgSession.GetListCollection('gridQ')
        $wrapper.Count  | Should -Be 2
        $external.Count | Should -Be 2
        $external[1]    | Should -Be $newRow
    }

    It '-NoSafeWrap warns when combined with -ItemsSource' {
        $external = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $warnings = $null
        New-UiDataGrid -Variable 'gridR' -ItemsSource $external -NoToolbar -NoSafeWrap -WarningVariable warnings -WarningAction SilentlyContinue
        $warnings | Should -Not -BeNullOrEmpty
        ($warnings -join ' ') | Should -Match 'NoSafeWrap'
    }
}

Describe 'New-UiDataGrid - variable bind rules' -Tag 'RequiresSession' {

    BeforeEach {
        $script:bcSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:bcSessionId)
        $script:bcSession = [PsUi.SessionManager]::Current
        $script:bcSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterEach {
        [PsUi.SessionManager]::DisposeSession($script:bcSessionId)
    }

    It 'Auto bind repoints the script variable at the wrap' {
        # The walk climbs to global and stops, so only a global sits in its path from a Pester It.
        $global:psuiAutoBindProbe = [System.Collections.ArrayList]::new()
        [void]$global:psuiAutoBindProbe.Add([PSCustomObject]@{ A = 1 })
        try {
            New-UiDataGrid -Variable 'gridAB' -ItemsSource $global:psuiAutoBindProbe -NoToolbar
            $global:psuiAutoBindProbe.GetType().FullName | Should -Match '^PsUi\.AsyncObservableCollection'
        }
        finally {
            Remove-Variable -Name psuiAutoBindProbe -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It '-NoBind leaves the script variable on the original list' {
        # ReferenceEquals cannot separate the two paths. The walk repoints every variable holding the input.
        $global:psuiNoBindProbe = [System.Collections.ArrayList]::new()
        [void]$global:psuiNoBindProbe.Add([PSCustomObject]@{ A = 1 })
        try {
            New-UiDataGrid -Variable 'gridNB' -ItemsSource $global:psuiNoBindProbe -NoBind -NoToolbar
            $global:psuiNoBindProbe.GetType().Name | Should -Be 'ArrayList'
            ($script:bcSession.GetListCollection('gridNB')).Count | Should -Be 1
        }
        finally {
            Remove-Variable -Name psuiNoBindProbe -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It '-NoBind leaves a [ref] pointing at what it pointed at' {
        # The help promises the thing you passed keeps its value. A [ref] is that thing, and its Value was repointed at the wrap regardless.
        $list = [System.Collections.ArrayList]::new()
        [void]$list.Add([PSCustomObject]@{ A = 1 })
        $holder = [ref]$list
        New-UiDataGrid -Variable 'gridNBRef' -ItemsSource $holder -NoBind -NoToolbar
        $holder.Value.GetType().Name | Should -Be 'ArrayList'
        ($script:bcSession.GetListCollection('gridNBRef')).Count | Should -Be 1
    }

    It 'Auto-bind warns when no reachable variable ref-equals the input' {
        # A warning fires so the silent drop surfaces. It fires for a plain local too.
        $holder = [PSCustomObject]@{ Items = [System.Collections.ArrayList]::new() }
        [void]$holder.Items.Add([PSCustomObject]@{ A = 1 })

        $warnings  = $null
        $gridSplat = @{
            Variable        = 'gridZW'
            ItemsSource     = $holder.Items
            NoToolbar       = $true
            WarningVariable = 'warnings'
            WarningAction   = 'SilentlyContinue'
        }
        New-UiDataGrid @gridSplat

        $warnings | Should -Not -BeNullOrEmpty
        ($warnings -join ' ') | Should -Match 'could not repoint'
    }
}

# Regression net for the overhaul. The subtle ones are snapshot fidelity and the edit cancel branch.
Describe 'New-UiDataGrid - overhaul regression' -Tag 'RequiresSession' {

    BeforeEach {
        $script:regSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:regSessionId)
        $script:regSession = [PsUi.SessionManager]::Current
        $script:regSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterEach {
        [PsUi.SessionManager]::DisposeSession($script:regSessionId)
    }

    It 'Build-UiDataGridColumns Filter kind reorders visible columns and hides the rest' {
        $items = @(
            [pscustomobject]@{ Name = 'a'; Dept = 'X'; Email = 'a@x' }
            [pscustomobject]@{ Name = 'b'; Dept = 'Y'; Email = 'b@y' }
        )
        New-UiDataGrid -Variable 'gridFilter' -Items $items -Columns 'Email', 'Name' -NoToolbar

        $grid    = $script:regSession.GetControl('gridFilter')
        $visible = @($grid.Columns |
            Where-Object { $_.Visibility -eq [System.Windows.Visibility]::Visible } |
            Sort-Object DisplayIndex)
        $visible[0].Header | Should -Be 'Email'
        $visible[1].Header | Should -Be 'Name'
        $deptCol = $grid.Columns | Where-Object { $_.Header -eq 'Dept' }
        $deptCol.Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)
    }

    It 'Add-UiDataGridDefaultSort parses multi-key entries with Descending suffix' {
        $items = @(
            [pscustomobject]@{ Name = 'a'; Dept = 'X' }
            [pscustomobject]@{ Name = 'b'; Dept = 'Y' }
        )
        New-UiDataGrid -Variable 'gridSort' -Items $items -NoToolbar -DefaultSort 'Name -Descending', 'Dept'

        $grid = $script:regSession.GetControl('gridSort')
        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($grid.ItemsSource)
        $view.SortDescriptions.Count | Should -Be 2
        $view.SortDescriptions[0].PropertyName | Should -Be 'Name'
        $view.SortDescriptions[0].Direction    | Should -Be ([System.ComponentModel.ListSortDirection]::Descending)
        $view.SortDescriptions[1].PropertyName | Should -Be 'Dept'
        $view.SortDescriptions[1].Direction    | Should -Be ([System.ComponentModel.ListSortDirection]::Ascending)
    }

    It 'Show-UiOutput sub-tab grid stars its last data column so the row fills the width' {
        InModuleScope PsUi {
            # New-ObjectSubTab used to skip the last column star, so wide result grids left dead space.
            $items = [System.Collections.Generic.List[object]]::new()
            1..3 | ForEach-Object { $items.Add([pscustomobject]@{ Name = "srv-$_"; Region = 'us-east'; Load = ($_ * 10) }) }
            $tabControl = [System.Windows.Controls.TabControl]::new()

            $result = New-ObjectSubTab -GroupItems $items -TypeName 'Server' -SubTabControl $tabControl
            $grid   = $result.DataGrid

            $visible = @($grid.Columns | Where-Object { $_.Visibility -eq [System.Windows.Visibility]::Visible })
            $visible.Count | Should -BeGreaterThan 1

            # Only the rightmost visible column is starred. The rest stay Auto.
            @($visible | Where-Object { $_.Width.IsStar }).Count | Should -Be 1
            $visible[$visible.Count - 1].Width.IsStar | Should -BeTrue
            $visible[0].Width.IsStar                  | Should -BeFalse
        }
    }

    It 'Set-LastDataColumnStar picks the rightmost column before DisplayIndex is assigned' {
        InModuleScope PsUi {
            # DisplayIndex is -1 until first render, so the old sort of all -1s starred an arbitrary column.
            $grid = [System.Windows.Controls.DataGrid]::new()
            foreach ($header in 'First', 'Second', 'Third') {
                $col         = [System.Windows.Controls.DataGridTextColumn]::new()
                $col.Header  = $header
                $col.Binding = [System.Windows.Data.Binding]::new($header)
                [void]$grid.Columns.Add($col)
            }
            @($grid.Columns | Where-Object { $_.DisplayIndex -ge 0 }).Count | Should -Be 0

            Set-LastDataColumnStar -DataGrid $grid

            $grid.Columns[2].Width.IsStar | Should -BeTrue
            $grid.Columns[1].Width.IsStar | Should -BeFalse
            $grid.Columns[0].Width.IsStar | Should -BeFalse
        }
    }

    It 'New-UiDataGridFilterController predicate uses _SearchText, empty filter passes everything' {
        InModuleScope PsUi {
            # The public path hides the filter box inside the toolbar return, so hook the controller directly.
            # _SearchText holds a word in no visible property, so a match proves the cached index is what was read.
            $items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
            [void]$items.Add([pscustomobject]@{ Name = 'alice'; _SearchText = 'alice zzmarker' })
            [void]$items.Add([pscustomobject]@{ Name = 'bob';   _SearchText = 'bob' })

            $dg             = [System.Windows.Controls.DataGrid]::new()
            $dg.ItemsSource = $items
            $fb             = [System.Windows.Controls.TextBox]::new()
            New-UiDataGridFilterController -DataGrid $dg -FilterBox $fb | Out-Null

            $view  = [System.Windows.Data.CollectionViewSource]::GetDefaultView($dg.ItemsSource)
            $state = $fb.Tag

            # Bypass debounce - set FilterText directly and invoke the predicate.
            $state.FilterText = 'zzmarker'
            $view.Filter.Invoke($items[0]) | Should -BeTrue
            $view.Filter.Invoke($items[1]) | Should -BeFalse

            $state.FilterText = ''
            $view.Filter.Invoke($items[0]) | Should -BeTrue
            $view.Filter.Invoke($items[1]) | Should -BeTrue
        }
    }

    It 'Add-UiDataGridEditHandling cancels CellEditEnding on a $false Validator and never fires OnCellEdit' {
        $script:capturedNew = '<initial>'
        $script:capturedOld = '<initial>'
        $items = @([pscustomobject]@{ Name = 'a' })

        New-UiDataGrid -Variable 'gridValCancel' -Items $items -Editable -NoToolbar -Columns @(
            @{ Name = 'Name'; Validator = { param($new, $row) $new -ne '' } }
        ) -OnCellEdit {
            param($row, $col, $new, $old)
            $script:capturedNew = $new
            $script:capturedOld = $old
        }

        $grid    = $script:regSession.GetControl('gridValCancel')
        $col     = $grid.Columns | Where-Object { $_.Header -eq 'Name' }
        $rowItem = @($grid.ItemsSource)[0]

        # Empty editor, Validator returns $false, so the handler must set Cancel and skip the deferral.
        $editor       = [System.Windows.Controls.TextBox]@{ Text = '' }
        $dgRow        = [System.Windows.Controls.DataGridRow]@{ Item = $rowItem }
        $cellArgs     = [System.Windows.Controls.DataGridCellEditEndingEventArgs]::new($col, $dgRow, $editor, [System.Windows.Controls.DataGridEditAction]::Commit)
        $bindingFlags = [System.Reflection.BindingFlags] 'Instance, NonPublic'
        $raiser       = [System.Windows.Controls.DataGrid].GetMethod('OnCellEditEnding', $bindingFlags)
        $raiser.Invoke($grid, @([object]$cellArgs))

        # Drain any deferred work so a faulty OnCellEdit registration would surface.
        $frame = [System.Windows.Threading.DispatcherFrame]::new()
        [void]$grid.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::ContextIdle,
            [Action]{ $frame.Continue = $false })
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)

        $cellArgs.Cancel    | Should -BeTrue
        # Still the seeded value, so OnCellEdit never fired.
        $script:capturedNew | Should -Be '<initial>'
        $script:capturedOld | Should -Be '<initial>'
    }

    It 'New-UiDataGrid -ItemsSource $null registers an owned collection so Add/Set/Clear keep working' {
        # A null ItemsSource used to register a null collection the helpers read back as "not found".
        New-UiDataGrid -Variable 'nullSrc' -ItemsSource $null -NoToolbar
        # Explicit null check. The collection starts empty, which -BeNullOrEmpty would also pass.
        ($null -eq $script:regSession.GetListCollection('nullSrc')) | Should -BeFalse
        Add-UiDataGridItem -Variable 'nullSrc' -Item ([pscustomobject]@{ Name = 'a' })
        $script:regSession.GetListCollection('nullSrc').Count | Should -Be 1
        Set-UiDataGridItems -Variable 'nullSrc' -Items @([pscustomobject]@{ Name = 'x' }, [pscustomobject]@{ Name = 'y' })
        $script:regSession.GetListCollection('nullSrc').Count | Should -Be 2
        Clear-UiDataGridItems -Variable 'nullSrc'
        $script:regSession.GetListCollection('nullSrc').Count | Should -Be 0
    }

    It 'A -Columns name list hides the columns left off it' {
        $items = @([PSCustomObject]@{ Name = 'a'; Count = 1; Hidden = 'no' })
        New-UiDataGrid -Variable 'gridE' -Items $items -Columns 'Name', 'Count' -NoToolbar

        $grid    = $script:regSession.GetControl('gridE')
        $visible = @($grid.Columns | Where-Object { $_.Visibility -eq [System.Windows.Visibility]::Visible } | ForEach-Object { $_.Header })
        $visible | Should -Contain 'Name'
        $visible | Should -Contain 'Count'
        $visible | Should -Not -Contain 'Hidden'
    }

    It 'Explicit -Columns editable path makes a decimal column editable, not just int/double' {
        # decimal isn't a .NET primitive, so the editor probe used to downgrade it to readonly.
        $items = @([pscustomobject]@{ Price = [decimal]9.99; Qty = [int]3 })
        New-UiDataGrid -Variable 'decGrid' -Items $items -Editable -NoToolbar -Columns @(
            @{ Name = 'Price'; Editable = $true }
            @{ Name = 'Qty';   Editable = $true }
        )
        $grid  = $script:regSession.GetControl('decGrid')
        $price = $grid.Columns | Where-Object { $_.Header -eq 'Price' }
        # Pin the column first. Should -BeFalse passes on the $null a missing column hands back.
        $price | Should -Not -BeNullOrEmpty
        $price.IsReadOnly | Should -Be $false
    }

    It 'Add/Set/Clear-UiDataGridItems are registered for async-runspace injection' {
        # Without this a grid cell or context menu async action throws CommandNotFound.
        $pub = [PsUi.ModuleContext]::PublicFunctions
        $pub.ContainsKey('Add-UiDataGridItem')    | Should -BeTrue
        $pub.ContainsKey('Set-UiDataGridItems')   | Should -BeTrue
        $pub.ContainsKey('Clear-UiDataGridItems') | Should -BeTrue
    }

    It 'Filter controller clears the old view''s predicate on an ItemsSource swap' {
        InModuleScope PsUi {
            $grid  = [System.Windows.Controls.DataGrid]::new()
            $listA = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
            [void]$listA.Add([pscustomobject]@{ Name = 'a' })
            $grid.ItemsSource = $listA
            $box              = [System.Windows.Controls.TextBox]::new()
            # Grid must sit in a Window so the ItemsSource changed hook attaches.
            $win         = [System.Windows.Window]::new()
            $win.Content = $grid
            New-UiDataGridFilterController -DataGrid $grid -FilterBox $box | Out-Null

            $viewA = [System.Windows.Data.CollectionViewSource]::GetDefaultView($listA)
            $viewA.Filter | Should -Not -BeNullOrEmpty

            $listB = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
            [void]$listB.Add([pscustomobject]@{ Name = 'b' })
            # Fires rebindFilter, which has to null the old view's predicate.
            $grid.ItemsSource = $listB

            $viewA.Filter | Should -BeNullOrEmpty
        }
    }
}

# Private functions aren't exported, so they need module scope to reach.
InModuleScope PsUi {
    Describe 'Format-UiDataGridExportRows - formula sanitization' {

        It 'prefixes cells starting with =/+/-/@/tab/CR/LF when -Sanitize is set' {
            $rows = @(
                [PSCustomObject]@{ Cell = '=cmd|''/c calc''!A1' }
                [PSCustomObject]@{ Cell = '+evil' }
                [PSCustomObject]@{ Cell = '-100' }
                [PSCustomObject]@{ Cell = '@AT' }
                [PSCustomObject]@{ Cell = "`tTabStart" }
                [PSCustomObject]@{ Cell = "`rCarriageReturn" }
                [PSCustomObject]@{ Cell = "`nLineFeed" }
                [PSCustomObject]@{ Cell = 'safe value' }
            )

            $out = @(Format-UiDataGridExportRows -Items $rows -Properties @('Cell') -Sanitize)

            $out[0].Cell | Should -Be "'=cmd|'/c calc'!A1"
            $out[1].Cell | Should -Be "'+evil"
            $out[2].Cell | Should -Be "'-100"
            $out[3].Cell | Should -Be "'@AT"
            $out[4].Cell | Should -Be ("'`tTabStart")
            $out[5].Cell | Should -Be ("'`rCarriageReturn")
            $out[6].Cell | Should -Be ("'`nLineFeed")
            $out[7].Cell | Should -Be 'safe value'
        }

        It 'passes cells through unchanged when -Sanitize is not set' {
            $rows = @( [PSCustomObject]@{ Cell = '=cmd|''/c calc''!A1' } )
            $out  = @(Format-UiDataGridExportRows -Items $rows -Properties @('Cell'))
            $out[0].Cell | Should -Be '=cmd|''/c calc''!A1'
        }
    }
}
