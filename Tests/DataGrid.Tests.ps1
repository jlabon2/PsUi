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
        # MouseDoubleClick only fires from real mouse input, and Pester runs without a window, so this is as far as it goes. It still catches the handler failing to attach.
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
        # ReferenceEquals can't separate the two paths. The walk repoints every variable holding the input.
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
            # New-ObjectSubTab has to star the last column, or wide result grids leave dead space.
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

    It 'Show-UiOutput subtab grid keeps rows wrapped so ETS columns have something to use' {
        InModuleScope PsUi {
            # Show-StreamingOutput holds the PSObject.BaseObject in a List[object], so the grid sees a CLR type and binds its members.
            # This test pins the element type on that list.
            $items = [System.Collections.Generic.List[object]]::new()
            $items.Add((Get-Item $env:WINDIR).PSObject.BaseObject)
            $items[0] -is [System.Management.Automation.PSObject] | Should -BeFalse

            $tabControl = [System.Windows.Controls.TabControl]::new()
            $result     = New-ObjectSubTab -GroupItems $items -TypeName 'DirectoryInfo' -SubTabControl $tabControl -IncludeActionStatus
            $row        = @($result.DataGrid.ItemsSource)[0]

            $row -is [System.Management.Automation.PSObject] | Should -BeTrue

            # Still the same object underneath, so a result action can run commands against it down the pipeline.
            $row -is [System.IO.DirectoryInfo] | Should -BeTrue
            $row.FullName | Should -Be (Get-Item $env:WINDIR).FullName

            # The tab header reads off the underlying type.
            $result.Tab.Header | Should -Be 'DirectoryInfo (1)'
        }
    }

    It 'Results toolbar opens searchable on a Dictionary first tab, with the column button hidden' {
        InModuleScope PsUi {
            $subTabs = [System.Windows.Controls.TabControl]::new()
            [void]$subTabs.Items.Add((New-DictionarySubTab -GroupItems @(@{ Alpha = 1 }, @{ Beta = 2 }) -TypeName 'Hashtable').Tab)
            $subTabs.SelectedIndex = 0

            $toolbarArgs = @{
                SubTabControl = $subTabs
                RightToolbar  = [System.Windows.Controls.StackPanel]::new()
                FilterPanel   = [System.Windows.Controls.StackPanel]::new()
                Toolbar2      = [System.Windows.Controls.DockPanel]::new()
            }
            $controls = Add-MultiTypeFilterControls @toolbarArgs

            $controls.FilterBox.IsEnabled          | Should -BeTrue
            $controls.FilterBox.Tag.Watermark.Text | Should -Be 'Filter...'
            $controls.ColumnButton.Visibility      | Should -Be ([System.Windows.Visibility]::Collapsed)
        }
    }

    It 'Results toolbar opens searchable on a text first tab' {
        InModuleScope PsUi {
            $textTab         = [System.Windows.Controls.TabItem]::new()
            $textTab.Header  = 'String (2)'
            $textTab.Content = New-TextDisplayRichTextBox -Colors (Get-ThemeColors) -Lines @('one', 'two')
            $textTab.Tag     = 'TextType'

            $subTabs = [System.Windows.Controls.TabControl]::new()
            [void]$subTabs.Items.Add($textTab)
            $subTabs.SelectedIndex = 0

            $toolbarArgs = @{
                SubTabControl = $subTabs
                RightToolbar  = [System.Windows.Controls.StackPanel]::new()
                FilterPanel   = [System.Windows.Controls.StackPanel]::new()
                Toolbar2      = [System.Windows.Controls.DockPanel]::new()
            }
            $controls = Add-MultiTypeFilterControls @toolbarArgs

            $controls.FilterBox.IsEnabled          | Should -BeTrue
            $controls.FilterBox.Tag.Watermark.Text | Should -Be 'Filter...'
            $controls.ColumnButton.Visibility      | Should -Be ([System.Windows.Visibility]::Collapsed)
        }
    }

    It 'Results toolbar waits for an object first tab to index, and Set-UiSubTabToolbarState follows every tab' {
        InModuleScope PsUi {
            $items = [System.Collections.Generic.List[object]]::new()
            $items.Add([pscustomobject]@{ Name = 'srv-1' })

            $subTabs   = [System.Windows.Controls.TabControl]::new()
            $objectTab = (New-ObjectSubTab -GroupItems $items -TypeName 'Server' -SubTabControl $subTabs).Tab
            $dictTab   = (New-DictionarySubTab -GroupItems @(@{ Alpha = 1 }) -TypeName 'Hashtable').Tab
            [void]$subTabs.Items.Add($objectTab)
            [void]$subTabs.Items.Add($dictTab)
            $subTabs.SelectedIndex = 0

            $toolbarArgs = @{
                SubTabControl = $subTabs
                RightToolbar  = [System.Windows.Controls.StackPanel]::new()
                FilterPanel   = [System.Windows.Controls.StackPanel]::new()
                Toolbar2      = [System.Windows.Controls.DockPanel]::new()
            }
            $controls = Add-MultiTypeFilterControls @toolbarArgs

            $objectTab.Tag                         | Should -Be 'Indexing'
            $controls.FilterBox.IsEnabled          | Should -BeFalse
            $controls.FilterBox.Tag.Watermark.Text | Should -Be 'Indexing...'
            $controls.ColumnButton.Visibility      | Should -Be ([System.Windows.Visibility]::Visible)

            # The tab switch with the Dictionary tab coming in
            Set-UiSubTabToolbarState -Tab $dictTab -FilterBox $controls.FilterBox
            $controls.FilterBox.IsEnabled     | Should -BeTrue
            $controls.ColumnButton.Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)

            # The poll timer once the index lands on the object tab
            $objectTab.Tag = 'Indexed'
            Set-UiSubTabToolbarState -Tab $objectTab -FilterBox $controls.FilterBox
            $controls.FilterBox.IsEnabled          | Should -BeTrue
            $controls.FilterBox.Tag.Watermark.Text | Should -Be 'Filter...'
            $controls.ColumnButton.Visibility      | Should -Be ([System.Windows.Visibility]::Visible)
        }
    }

    It 'The search index reads a HashSet and a hashtable by their contents' {
        InModuleScope PsUi {
            $set = [System.Collections.Generic.HashSet[string]]::new()
            [void]$set.Add('web')
            [PsUiTest.CountingSequence]::Passes = 0
            $items = [System.Collections.Generic.List[object]]::new()
            $items.Add([pscustomobject]@{ Name = 'srv-1'; Sets = $set; Meta = @{ k = 1 }; Reader = [PsUiTest.CountingSequence]::new() })

            $null = New-ObjectSubTab -GroupItems $items -TypeName 'Server' -SubTabControl ([System.Windows.Controls.TabControl]::new())

            # The index lands from its own runspace
            $deadline = (Get-Date).AddSeconds(10)
            while ((Get-Date) -lt $deadline -and !$items[0].PSObject.Properties['_SearchText']) { Start-Sleep -Milliseconds 50 }

            $items[0]._SearchText | Should -Match 'web'
            $items[0]._SearchText | Should -Match 'k=1'
            $items[0]._SearchText | Should -Not -Match 'HashSet'
            [PsUiTest.CountingSequence]::Passes | Should -Be 0
        }
    }

    It 'The array cell popup leaves a forward only sequence unread' {
        $src  = Join-Path $repoRoot 'PsUi\private\output\Add-ArrayCellPopupHandler.ps1'
        $ast  = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $node = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_PreviewMouseLeftButtonDown' }, $true))[0]
        $text = (("$($node.Arguments[0])" -replace '^\{', '') -replace '\}\.GetNewClosure\(\)$', '') -replace '\$popup\.IsOpen\s*=\s*\$true', '$$popup'

        [PsUiTest.CountingSequence]::Passes = 0
        $cell = [System.Windows.Controls.TextBlock]@{ FontStyle = 'Italic'; Tag = [PsUiTest.CountingSequence]::new() }
        $popup = InModuleScope PsUi -Parameters @{ Text = $text; Cell = $cell } {
            param($Text, $Cell)
            & ([scriptblock]::Create($Text)) ([System.Windows.Controls.DataGrid]::new()) ([pscustomobject]@{ OriginalSource = $Cell; Handled = $false })
        }

        $popup | Should -BeNullOrEmpty
        [PsUiTest.CountingSequence]::Passes | Should -Be 0
    }

    It 'The array cell popup wraps wide lines and keeps its copy button in view' {
        $src  = Join-Path $repoRoot 'PsUi\private\output\Add-ArrayCellPopupHandler.ps1'
        $ast  = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $node = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_PreviewMouseLeftButtonDown' }, $true))[0]

        # The shipping handler, with the open at the end swapped for the popup itself so it comes back built and closed.
        $text  = (("$($node.Arguments[0])" -replace '^\{', '') -replace '\}\.GetNewClosure\(\)$', '') -replace '\$popup\.IsOpen\s*=\s*\$true', '$$popup'
        $line  = 'System.Diagnostics.ProcessModule (a-module-with-a-long-name.dll) and enough text after it to run well past the popup'
        $cell  = [System.Windows.Controls.TextBlock]@{ FontStyle = 'Italic'; Tag = @(1..12 | ForEach-Object { $line }) }
        $popup = InModuleScope PsUi -Parameters @{ Text = $text; Cell = $cell } {
            param($Text, $Cell)
            & ([scriptblock]::Create($Text)) ([System.Windows.Controls.DataGrid]::new()) ([pscustomobject]@{ OriginalSource = $Cell; Handled = $false })
        }

        $border = $popup.Child
        $border.Measure([System.Windows.Size]::new($border.MaxWidth, $border.MaxHeight))
        $border.Arrange([System.Windows.Rect]::new(0, 0, $border.DesiredSize.Width, $border.DesiredSize.Height))
        $border.UpdateLayout()
        $scroll = $border.Child
        $header = $scroll.Content.Children[0]
        $first  = $scroll.Content.Children[1]

        $scroll.HorizontalScrollBarVisibility | Should -Be 'Disabled'
        $scroll.ViewportWidth                 | Should -BeGreaterThan 0
        $scroll.ExtentWidth                   | Should -BeLessOrEqual $scroll.ViewportWidth
        $header.ActualWidth | Should -BeLessOrEqual $scroll.ViewportWidth
        @($header.Children | Where-Object { $_ -is [System.Windows.Controls.Button] }).Count | Should -Be 1
        $first.ActualHeight | Should -BeGreaterThan ($first.FontSize * 2)
    }

    It 'The dictionary popup wraps a wide value beside its key' {
        $src  = Join-Path $repoRoot 'PsUi\private\output\Add-DictionaryValuePopupHandler.ps1'
        $ast  = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $node = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_PreviewMouseLeftButtonDown' }, $true))[0]

        $text  = (("$($node.Arguments[0])" -replace '^\{', '') -replace '\}\.GetNewClosure\(\)$', '') -replace '\$popup\.IsOpen\s*=\s*\$true', '$$popup'
        $line  = 'C:\Program Files\Some Vendor\Some Productin\service-host.exe --config C:\ProgramData\Some Vendor\config\service-host.production.json --log-level verbose'
        $cell  = [System.Windows.Controls.TextBlock]@{ FontStyle = 'Italic'; Tag = @{ CommandLine = $line; Owner = 'platform' } }
        $popup = InModuleScope PsUi -Parameters @{ Text = $text; Cell = $cell } {
            param($Text, $Cell)
            & ([scriptblock]::Create($Text)) ([System.Windows.Controls.DataGrid]::new()) ([pscustomobject]@{ OriginalSource = $Cell; Handled = $false })
        }

        $border = $popup.Child
        $border.Measure([System.Windows.Size]::new($border.MaxWidth, $border.MaxHeight))
        $border.Arrange([System.Windows.Rect]::new(0, 0, $border.DesiredSize.Width, $border.DesiredSize.Height))
        $border.UpdateLayout()
        $scroll = $border.Child
        $row    = @($scroll.Content.Children | Where-Object { $_ -is [System.Windows.Controls.DockPanel] -and $_.Children[1].Text -like "*$line*" })[0]
        $value  = $row.Children[1]

        $scroll.HorizontalScrollBarVisibility | Should -Be 'Disabled'
        $scroll.ExtentWidth                   | Should -BeLessOrEqual $scroll.ViewportWidth
        $value.ActualWidth                    | Should -BeLessOrEqual $scroll.ViewportWidth
        $value.ActualHeight                   | Should -BeGreaterThan ($value.FontSize * 2)
    }

    It 'A tab that never indexes keeps a plain filter tooltip' {
        InModuleScope PsUi {
            # Dictionary tabs set no skipped list, and @($null).Count is 1, so the tooltip promises a list and shows an empty one.
            $tab = [System.Windows.Controls.TabItem]@{ Tag = 'Dictionary' }
            $box = [System.Windows.Controls.TextBox]@{ Tag = @{} }
            Set-UiSubTabToolbarState -Tab $tab -FilterBox $box
            $box.ToolTip | Should -Be 'Filter results'
        }
    }

    It 'The search index says which columns it priced out' {
        InModuleScope PsUi {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($i in 1..40) {
                $row = [pscustomobject]@{ Name = "row $i" }
                $row | Add-Member -MemberType ScriptProperty -Name 'Slow' -Value { Start-Sleep -Milliseconds 40; 'expensive' }
                $items.Add($row)
            }

            $tabControl     = [System.Windows.Controls.TabControl]::new()
            $filterBox      = [System.Windows.Controls.TextBox]@{ Tag = @{} }
            $tabControl.Tag = $filterBox

            $result = New-ObjectSubTab -GroupItems $items -TypeName 'Priced' -SubTabControl $tabControl
            [void]$tabControl.Items.Add($result.Tab)
            $tabControl.SelectedItem = $result.Tab
            $deadline = (Get-Date).AddSeconds(30)
            while ((Get-Date) -lt $deadline -and $result.Tab.Tag -ne 'Indexed') {
                $frame = [System.Windows.Threading.DispatcherFrame]::new()
                [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::Background, [Action]{ $frame.Continue = $false })
                [System.Windows.Threading.Dispatcher]::PushFrame($frame)
                if ($result.Tab.Tag -ne 'Indexed') { [System.Threading.Thread]::Sleep(25) }
            }

            $result.Tab.Tag | Should -Be 'Indexed'
            @($result.Tab.Resources['__SkippedColumns']) | Should -Contain 'Slow'

            Set-UiSubTabToolbarState -Tab $result.Tab -FilterBox $filterBox
            $filterBox.ToolTip | Should -BeLike '*Slow*'

            # Name is cheap so it stays searchable
            "$(@($result.DataGrid.ItemsSource)[0]._SearchText)" | Should -BeLike '*row 1*'
        }
    }

    It 'The dictionary popup reads a service by name' {
        $src  = Join-Path $repoRoot 'PsUi\private\output\Add-DictionaryValuePopupHandler.ps1'
        $ast  = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $node = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_PreviewMouseLeftButtonDown' }, $true))[0]

        $text    = (("$($node.Arguments[0])" -replace '^\{', '') -replace '\}\.GetNewClosure\(\)$', '') -replace '\$popup\.IsOpen\s*=\s*\$true', '$$popup'
        $service = @(Get-Service)[0]
        $cell    = [System.Windows.Controls.TextBlock]@{ Tag = @{ Svc = $service } }
        $popup   = InModuleScope PsUi -Parameters @{ Text = $text; Cell = $cell } {
            param($Text, $Cell)
            & ([scriptblock]::Create($Text)) ([System.Windows.Controls.DataGrid]::new()) ([pscustomobject]@{ OriginalSource = $Cell; Handled = $false })
        }

        $texts = [System.Collections.Generic.List[string]]::new()
        $queue = [System.Collections.Generic.Queue[System.Windows.DependencyObject]]::new()
        $queue.Enqueue($popup.Child)
        while ($queue.Count -gt 0) {
            $element = $queue.Dequeue()
            if ($element -is [System.Windows.Controls.TextBlock]) { $texts.Add($element.Text); continue }
            foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($element)) {
                if ($child -is [System.Windows.DependencyObject]) { $queue.Enqueue($child) }
            }
        }
        $texts | Should -Contain $service.Name
        $texts | Should -Not -Contain 'System.ServiceProcess.ServiceController'
    }

    It 'Sub-tab rows survive the filter box rebuild' {
        InModuleScope PsUi {
            $items = [System.Collections.Generic.List[object]]::new()
            $items.Add((Get-Item $env:WINDIR).PSObject.BaseObject)

            $tabControl = [System.Windows.Controls.TabControl]::new()
            $result     = New-ObjectSubTab -GroupItems $items -TypeName 'DirectoryInfo' -SubTabControl $tabControl
            $observable = $result.DataGrid.Tag.Observable
            $observable.Clear()
            foreach ($item in $result.DataGrid.Tag.UnfilteredItems) { [void]$observable.Add($item) }

            $observable[0] -is [System.Management.Automation.PSObject] | Should -BeTrue
            $observable[0] -is [System.IO.DirectoryInfo]               | Should -BeTrue
        }
    }

    It 'The Action Status column has a row property to bind to' {
        InModuleScope PsUi {
            # The row property holds the status, and it binds because the row kept its PSObject.
            $items = [System.Collections.Generic.List[object]]::new()
            $items.Add((Get-Item $env:WINDIR).PSObject.BaseObject)

            $tabControl = [System.Windows.Controls.TabControl]::new()
            $result     = New-ObjectSubTab -GroupItems $items -TypeName 'DirectoryInfo' -SubTabControl $tabControl -IncludeActionStatus
            $row        = @($result.DataGrid.ItemsSource)[0]

            $statusProp = $row.PSObject.Properties['_ActionStatus']
            $statusProp | Should -Not -BeNullOrEmpty

            $statusCol = @($result.DataGrid.Columns | Where-Object { $_.Header -eq 'Action Status' })[0]
            $statusCol | Should -Not -BeNullOrEmpty
            $statusCol.Binding.Path.Path | Should -Be '_ActionStatus'
        }
    }

    It 'Get-UiSubTabGrid reaches the grid through the empty overlay' {
        InModuleScope PsUi {
            $items = [System.Collections.Generic.List[object]]::new()
            $items.Add((Get-Item $env:WINDIR).PSObject.BaseObject)

            $tabControl = [System.Windows.Controls.TabControl]::new()
            $result     = New-ObjectSubTab -GroupItems $items -TypeName 'DirectoryInfo' -SubTabControl $tabControl

            $result.Tab.Content | Should -Not -BeOfType [System.Windows.Controls.DataGrid]
            Get-UiSubTabGrid -Tab $result.Tab | Should -Be $result.DataGrid

            $textTab         = [System.Windows.Controls.TabItem]::new()
            $textTab.Content = [System.Windows.Controls.RichTextBox]::new()
            Get-UiSubTabGrid -Tab $textTab | Should -BeNullOrEmpty
            Get-UiSubTabGrid -Tab $null    | Should -BeNullOrEmpty
        }
    }

    It 'A dictionary sub-tab survives a null value' {
        InModuleScope PsUi {
            $items = [System.Collections.Generic.List[object]]::new()
            $items.Add(@{ Name = 'server01'; Notes = $null })

            $result = New-DictionarySubTab -GroupItems $items -TypeName 'Hashtable'
            $grid   = Get-UiSubTabGrid -Tab $result.Tab

            $notes = @($grid.Tag.UnfilteredItems | Where-Object { $_.Key -eq 'Notes' })[0]
            $notes.Value         | Should -Be '(null)'
            $notes._IsExpandable | Should -BeFalse
        }
    }

    It 'A dictionary cell is clickable for any list type and inert when the list is empty' {
        InModuleScope PsUi {
            $items = [System.Collections.Generic.List[object]]::new()
            $items.Add([ordered]@{
                ObjArray   = @('web', 'prod')
                ArrayList  = [System.Collections.ArrayList]@('web', 'prod')
                GenList    = [System.Collections.Generic.List[object]]@('web', 'prod')
                EmptyArray = @()
            })

            $rows = @{}
            foreach ($row in (Get-UiSubTabGrid -Tab (New-DictionarySubTab -GroupItems $items -TypeName 'Hashtable').Tab).Tag.UnfilteredItems) {
                $rows[[string]$row.Key] = $row
            }

            foreach ($name in 'ObjArray', 'ArrayList', 'GenList') {
                $rows[$name]._IsExpandable | Should -BeTrue -Because "$name is a list and its cell offers a popup"
                $rows[$name].Value         | Should -Be 'web, prod'
            }
            $rows['EmptyArray']._IsExpandable | Should -BeFalse
            $rows['EmptyArray'].Value         | Should -Be '[empty]'
        }
    }

    It 'The dictionary Value column reaches copy and export' {
        InModuleScope PsUi {
            $items = [System.Collections.Generic.List[object]]::new()
            $items.Add(@{ Name = 'server01' })

            $grid  = Get-UiSubTabGrid -Tab (New-DictionarySubTab -GroupItems $items -TypeName 'Hashtable').Tab
            $paths = @(Get-UiDataGridVisibleColumnPaths -DataGrid $grid)

            $paths | Should -Contain 'Key'
            $paths | Should -Contain 'Value'
        }
    }

    It 'A dictionary sub-tab honours SingleSelect' {
        InModuleScope PsUi {
            $items = [System.Collections.Generic.List[object]]::new()
            $items.Add(@{ Name = 'server01'; Site = 'lon' })

            (New-DictionarySubTab -GroupItems $items -TypeName 'Hashtable').DataGrid.SelectionMode | Should -Be 'Extended'
            (New-DictionarySubTab -GroupItems $items -TypeName 'Hashtable' -SingleSelect).DataGrid.SelectionMode | Should -Be 'Single'
        }
    }

    It 'A HashSet cell shows its contents and offers the click' {
        InModuleScope PsUi {
            $set = [System.Collections.Generic.HashSet[string]]::new()
            [void]$set.Add('web')
            [void]$set.Add('prod')

            $items = [System.Collections.Generic.List[object]]::new()
            $items.Add([ordered]@{ Tags = $set })

            $row = @((Get-UiSubTabGrid -Tab (New-DictionarySubTab -GroupItems $items -TypeName 'Hashtable').Tab).Tag.UnfilteredItems)[0]
            $row.Value         | Should -Be 'web, prod'
            $row._IsExpandable | Should -BeTrue
        }
    }

    It 'The empty overlay follows the grid between populated and empty' {
        InModuleScope PsUi {
            $grid                   = New-StyledDataGrid
            $grid.HeadersVisibility = [System.Windows.Controls.DataGridHeadersVisibility]::Column
            $rows                   = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
            $rows.Add([PSCustomObject]@{ Name = 'a' })
            $grid.ItemsSource = [System.Windows.Data.CollectionViewSource]::GetDefaultView($rows)

            $overlay = Add-UiDataGridEmptyOverlay -HostControl $grid -DataGrid $grid -Message 'No items to display.'
            $message = $overlay.Resources['__EmptyOverlay'].MessageBlock
            $grid.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.FrameworkElement]::LoadedEvent))

            $message.Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)

            $rows.Clear()
            $message.Visibility     | Should -Be ([System.Windows.Visibility]::Visible)
            $message.Text           | Should -Be 'No items to display.'
            $grid.HeadersVisibility | Should -Be ([System.Windows.Controls.DataGridHeadersVisibility]::None)

            $rows.Add([PSCustomObject]@{ Name = 'b' })
            $message.Visibility     | Should -Be ([System.Windows.Visibility]::Collapsed)
            $grid.HeadersVisibility | Should -Be ([System.Windows.Controls.DataGridHeadersVisibility]::Column)
        }
    }

    It 'The empty overlay listens for theme changes and lets go on close' {
        InModuleScope PsUi {
            $themeEvent = [PsUi.ThemeEngine].GetField('ThemeChanged', [System.Reflection.BindingFlags]'NonPublic,Static')
            $countHandlers = {
                $current = $themeEvent.GetValue($null)
                if ($current) { $current.GetInvocationList().Count } else { 0 }
            }.GetNewClosure()
            $before = & $countHandlers

            $window                 = [System.Windows.Window]::new()
            $grid                   = New-StyledDataGrid
            $grid.HeadersVisibility = [System.Windows.Controls.DataGridHeadersVisibility]::Column
            $rows                   = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
            $grid.ItemsSource       = [System.Windows.Data.CollectionViewSource]::GetDefaultView($rows)

            $overlay        = Add-UiDataGridEmptyOverlay -HostControl $grid -DataGrid $grid -Message 'x'
            $window.Content = $overlay
            $grid.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.FrameworkElement]::LoadedEvent))

            $grid.HeadersVisibility | Should -Be ([System.Windows.Controls.DataGridHeadersVisibility]::None)
            (& $countHandlers) | Should -Be ($before + 1)

            Set-DataGridStyle -Grid $grid
            $grid.HeadersVisibility | Should -Be ([System.Windows.Controls.DataGridHeadersVisibility]::Column)
            $themeEvent.GetValue($null).Invoke('Dark')
            $frame = [System.Windows.Threading.DispatcherFrame]::new()
            $null  = $grid.Dispatcher.BeginInvoke([Action]{ $frame.Continue = $false }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::Background)
            [System.Windows.Threading.Dispatcher]::PushFrame($frame)
            $grid.HeadersVisibility | Should -Be ([System.Windows.Controls.DataGridHeadersVisibility]::None)

            # A static event holds the handler forever, so the overlay has to close().
            $window.Close()
            (& $countHandlers) | Should -Be $before
        }
    }

    It 'The popup copy header reads the state hashtable at click time' {
        InModuleScope PsUi {

            $built = New-UiPopupCopyHeader -Colors (Get-ThemeColors)

            $built.Panel.Children.Count | Should -Be 2
            [System.Windows.Controls.DockPanel]::GetDock($built.Panel.Children[0]) | Should -Be 'Right'
            $built.Title | Should -BeOfType [System.Windows.Controls.TextBlock]

            $saved = $null
            try {
                $onClipboard = [System.Windows.Clipboard]::GetDataObject()
                $saved       = [System.Windows.DataObject]::new()
                foreach ($format in $onClipboard.GetFormats()) {
                    try { $saved.SetData($format, $onClipboard.GetData($format)) } catch { Write-Debug "Clipboard format $format : $_" }
                }
                if (@($saved.GetFormats()).Count -eq 0) { $saved = $null }
            }
            catch { Write-Debug "Clipboard read: $_" }
            try {
                $built.State.Text = 'alpha'
                $sentinelSet = $false
                foreach ($attempt in 1..5) {
                    try {
                        [System.Windows.Clipboard]::SetText('sentinel')
                        $sentinelSet = $true
                        break
                    }
                    catch { Start-Sleep -Milliseconds 50 }
                }
                $sentinelSet | Should -BeTrue -Because 'the clipboard stayed busy through five tries'

                $copyButton = $built.Panel.Children[0]
                $copied     = $null
                foreach ($attempt in 1..5) {
                    $copyButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                    try { $copied = [System.Windows.Clipboard]::GetText() } catch { $copied = $null }
                    if ($copied -eq 'alpha') { break }
                    Start-Sleep -Milliseconds 50
                }
                $copied | Should -Be 'alpha'
                $copyButton.Content.Text | Should -Be ([PsUi.ModuleContext]::GetIcon('CheckMark'))
            }
            finally {
                if ($saved) {
                    try { [System.Windows.Clipboard]::SetDataObject($saved, $true) } catch { Write-Debug "Clipboard restore: $_" }
                }
            }
        }
    }

    It 'A collection of strings gets the array column rather than its type name' {
        InModuleScope PsUi {

            $tags = [System.Collections.Generic.List[string]]::new()
            $tags.Add('one')
            $tags.Add('two')
            $item = [PSCustomObject]@{ Name = 'row' }
            $item | Add-Member -MemberType NoteProperty -Name Tags -Value $tags

            $grid = [System.Windows.Controls.DataGrid]::new()
            $null = Add-DataGridColumns -DataGrid $grid -FirstItem $item

            $tagsCol = @($grid.Columns | Where-Object { $_.Header -eq 'Tags' })[0]
            $tagsCol | Should -BeOfType [System.Windows.Controls.DataGridTemplateColumn]
            $nameCol = @($grid.Columns | Where-Object { $_.Header -eq 'Name' })[0]
            $nameCol | Should -BeOfType [System.Windows.Controls.DataGridTextColumn]
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
            # _SearchText holds a word in no visible property, so a match proves the cached index was read.
            $items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
            [void]$items.Add([pscustomobject]@{ Name = 'alice'; _SearchText = 'alice zzmarker' })
            [void]$items.Add([pscustomobject]@{ Name = 'bob';   _SearchText = 'bob' })

            $dg             = [System.Windows.Controls.DataGrid]::new()
            $dg.ItemsSource = $items
            $fb             = [System.Windows.Controls.TextBox]::new()
            New-UiDataGridFilterController -DataGrid $dg -FilterBox $fb | Out-Null

            $view  = [System.Windows.Data.CollectionViewSource]::GetDefaultView($dg.ItemsSource)
            $state = $fb.Tag

            # Skips the debounce by setting FilterText directly and invoking the predicate.
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
        # A null ItemsSource must not register a null collection, which the helpers read back as "not found".
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
        # decimal isn't a .NET primitive, so the editor probe has to take it on its own terms or it downgrades to readonly.
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

    It 'Get-UiValue and Set-UiValue are registered for async-runspace injection' {
        # Grid cell and context menu actions only get this list.
        $pub = [PsUi.ModuleContext]::PublicFunctions
        $pub.ContainsKey('Get-UiValue') | Should -BeTrue
        $pub.ContainsKey('Set-UiValue') | Should -BeTrue
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

    It 'The dictionary tab indexes and exports the value rather than its display string' {
        InModuleScope PsUi {
            $dict  = [ordered]@{ Tags = @('alpha', 'bravo', 'charlie', 'delta', 'echo'); Meta = [ordered]@{ a = 1; b = 2; c = 3; d = 4 } }
            $built = New-DictionarySubTab -GroupItems ([System.Collections.Generic.List[object]]@($dict)) -TypeName 'OrderedDictionary'
            $rows  = $built.DataGrid.Tag.UnfilteredItems

            $rows[0]._SearchText | Should -Match 'charlie'
            $rows[1]._SearchText | Should -Match 'd=4'

            $paths = Get-UiDataGridVisibleColumnPaths -DataGrid $built.DataGrid
            $out   = @(Format-UiDataGridExportRows -Items $rows -Properties $paths)
            $out[0].Value | Should -Be 'alpha, bravo, charlie, delta, echo'
            $out[1].Value | Should -Be 'a=1; b=2; c=3; d=4'
        }
    }

    It 'The public grid index reads a hashtable by its contents and leaves a sequence unread' {
        InModuleScope PsUi {
            [PsUiTest.CountingSequence]::Passes = 0
            $snap = @(ConvertTo-UiDataGridSnapshot -Items @([pscustomobject]@{ Name = 'srv01'; Meta = @{ k = 1 }; Reader = [PsUiTest.CountingSequence]::new() }) -BuildSearchIndex)
            $snap[0]._SearchText | Should -Match 'k=1'
            $snap[0]._SearchText | Should -Not -Match 'Hashtable'

            $plain = [pscustomobject]@{ Name = 'srv01'; Meta = @{ k = 1 }; Reader = [PsUiTest.CountingSequence]::new() }
            Add-UiDataGridSearchText -PsObject $plain
            $plain._SearchText | Should -Match 'k=1'
            [PsUiTest.CountingSequence]::Passes | Should -Be 0
        }
    }

    It 'Copy Cell writes the text a row copy would, raw value included' {
        InModuleScope PsUi {
            ConvertTo-UiExportText -Value @('a', 'b')      | Should -Be 'a, b'
            ConvertTo-UiExportText -Value @{ k = 1 }       | Should -Be 'k=1'
            ConvertTo-UiExportText -Value @(@{ a = 1 }, 2) | Should -Be '@{a=1}, 2'
            ConvertTo-UiExportText -Value 'plain'          | Should -Be 'plain'
            [PsUiTest.CountingSequence]::Passes = 0
            ConvertTo-UiExportText -Value ([PsUiTest.CountingSequence]::new()) | Should -Be '[sequence]'
            [PsUiTest.CountingSequence]::Passes | Should -Be 0

            $row = [pscustomobject]@{ Key = 'Tags'; Value = '[5 items]'; _RawValue = @(1, 2, 3, 4, 5) }
            [object]::ReferenceEquals((Get-UiDataGridCellValue -Row $row -Path 'Value'), $row._RawValue) | Should -BeTrue
            Get-UiDataGridCellValue -Row $row -Path 'Key'   | Should -Be 'Tags'
            Get-UiDataGridCellValue -Row 'scalar' -Path '.' | Should -Be 'scalar'
        }
    }

    It 'A services column reads by name everywhere it is shown' {
        InModuleScope PsUi {
            $service = @(Get-Service)[0]
            ConvertTo-UiExportText -Value @($service, $service) | Should -Be "$($service.Name), $($service.Name)"
            [PsUi.ValueKind]::IndexText(@($service), 25, 512)   | Should -Be $service.Name
            ConvertTo-DisplayValue -Value @{ Svc = $service }   | Should -Be "@{Svc=$($service.Name)}"
        }
    }

    It 'Set-UiWheelRouting flags a control once per mode and hands a Page wheel to the parent' {
        InModuleScope PsUi {
            $panel = [System.Windows.Controls.StackPanel]::new()
            $list  = [System.Windows.Controls.ListBox]::new()
            [void]$panel.Children.Add($list)

            Set-UiWheelRouting -Control $list
            Set-UiWheelRouting -Control $list
            $list.Resources.Contains('__WheelPassthrough') | Should -BeTrue
            $list.Resources.Contains('__WheelCapture')     | Should -BeFalse

            $seen = @{ Count = 0 }
            $panel.Add_MouseWheel({ $seen.Count++ }.GetNewClosure())
            $wheel = [System.Windows.Input.MouseWheelEventArgs]::new([System.Windows.Input.Mouse]::PrimaryDevice, 0, -120)
            $wheel.RoutedEvent = [System.Windows.UIElement]::PreviewMouseWheelEvent
            $list.RaiseEvent($wheel)
            $wheel.Handled | Should -BeTrue
            $seen.Count    | Should -Be 1

            Set-UiWheelRouting -Control $list -Mode Capture
            $list.Resources.Contains('__WheelCapture') | Should -BeTrue
            $again = [System.Windows.Input.MouseWheelEventArgs]::new([System.Windows.Input.Mouse]::PrimaryDevice, 0, -120)
            $again.RoutedEvent = [System.Windows.UIElement]::PreviewMouseWheelEvent
            $list.RaiseEvent($again)
            $again.Handled | Should -BeFalse
            $seen.Count    | Should -Be 1
            Set-UiWheelRouting -Control $list
            $list.Resources.Contains('__WheelCapture') | Should -BeTrue

            $edge = [System.Windows.Controls.ListBox]::new()
            Set-UiWheelRouting -Control $edge -Mode Edge
            $edge.Resources.Contains('__WheelEdge')    | Should -BeTrue
            $edge.Resources.Contains('__WheelCapture') | Should -BeTrue

            $combo = [System.Windows.Controls.ComboBox]::new()
            'a', 'b', 'c' | ForEach-Object { [void]$combo.Items.Add($_) }
            $combo.SelectedIndex = 1
            Set-UiWheelRouting -Control $combo -Mode Capture
            $step = [System.Windows.Input.MouseWheelEventArgs]::new([System.Windows.Input.Mouse]::PrimaryDevice, 0, -120)
            $step.RoutedEvent = [System.Windows.UIElement]::PreviewMouseWheelEvent
            $combo.RaiseEvent($step)
            $combo.SelectedIndex | Should -Be 2
        }
    }

    It 'The tree menu opens and shuts branches, checks below a node and dims what does not apply' {
        $items = @(@{ Name = 'root'; Children = @(@{ Name = 'a'; Children = @(@{ Name = 'a1' }) }, @{ Name = 'b' }) })
        New-UiTree -Variable 'menuTree' -Items $items -ParentCheckBoxes -ChildCheckBoxes
        $tree = $script:regSession.GetControl('menuTree')
        $menu = $tree.ContextMenu
        $menu | Should -Not -BeNullOrEmpty
        $byHeader = @{}
        foreach ($entry in $menu.Items) { if ($entry -is [System.Windows.Controls.MenuItem]) { $byHeader[[string]$entry.Header] = $entry } }
        @($byHeader.Keys | Sort-Object) | Should -Be @('Check All Below', 'Collapse', 'Collapse All', 'Copy', 'Expand', 'Expand All', 'Uncheck All Below')

        $click = { [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent) }
        $root  = $tree.Items[0]
        $nodeA = $root.Items[0]
        $root.IsExpanded | Should -BeFalse
        $byHeader['Expand All'].RaiseEvent((& $click))
        $root.IsExpanded  | Should -BeTrue
        $nodeA.IsExpanded | Should -BeTrue
        $byHeader['Collapse All'].RaiseEvent((& $click))
        $root.IsExpanded | Should -BeFalse

        $root.IsSelected = $true
        $tree.SelectedItem | Should -Be $root
        $byHeader['Expand'].RaiseEvent((& $click))
        $root.IsExpanded  | Should -BeTrue
        $nodeA.IsExpanded | Should -BeTrue

        $byHeader['Check All Below'].RaiseEvent((& $click))
        $boxes = foreach ($node in @($root, $nodeA, $nodeA.Items[0], $root.Items[1])) {
            @($node.Header.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] })[0]
        }
        @($boxes).Count | Should -Be 4
        @($boxes | Where-Object { $_.IsChecked }).Count | Should -Be 4

        # The open handler dims what has no branch left to act on
        $menu.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.ContextMenu]::OpenedEvent))
        $byHeader['Expand All'].IsEnabled   | Should -BeFalse
        $byHeader['Collapse All'].IsEnabled | Should -BeTrue

        New-UiTree -Variable 'plainTree' -Items $items -NoContextMenu
        ($script:regSession.GetControl('plainTree')).ContextMenu | Should -BeNullOrEmpty
    }

    It 'A search that matches no rows leaves the filter alive for the next one' {
        InModuleScope PsUi {
            $items = [System.Collections.Generic.List[object]]::new()
            $items.Add([pscustomobject]@{ Name = 'alpha' })
            $items.Add([pscustomobject]@{ Name = 'beta' })
            $subTabs = [System.Windows.Controls.TabControl]::new()
            $tab = (New-ObjectSubTab -GroupItems $items -TypeName 'Row' -SubTabControl $subTabs).Tab
            [void]$subTabs.Items.Add($tab)
            $subTabs.SelectedIndex = 0
            $deadline = (Get-Date).AddSeconds(10)
            while ((Get-Date) -lt $deadline -and !$items[1].PSObject.Properties['_SearchText']) { Start-Sleep -Milliseconds 50 }

            $toolbarArgs = @{ SubTabControl = $subTabs; RightToolbar = [System.Windows.Controls.StackPanel]::new(); FilterPanel = [System.Windows.Controls.StackPanel]::new(); Toolbar2 = [System.Windows.Controls.DockPanel]::new() }
            $box  = (Add-MultiTypeFilterControls @toolbarArgs).FilterBox
            $grid = Get-UiSubTabGrid -Tab $tab

            $box.Text = 'zzz'
            & $box.Tag.RunFilter $box
            $grid.Tag.Observable.Count                                 | Should -Be 0
            $tab.Content.Resources['__EmptyOverlay'].MessageBlock.Text | Should -Be "No items matched 'zzz'"

            $box.Text = 'beta'
            & $box.Tag.RunFilter $box
            $grid.Tag.Observable.Count | Should -Be 1

            $box.Text = ''
            & $box.Tag.RunFilter $box
            $grid.Tag.Observable.Count                                 | Should -Be 2
            $tab.Content.Resources['__EmptyOverlay'].MessageBlock.Text | Should -Be 'No items to display.'
        }
    }

    It 'Coming back to a tab left mid search puts its rows back' {
        $src   = Join-Path $repoRoot 'PsUi\private\output\Invoke-OnCompleteHandler.ps1'
        $ast   = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $found = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$filterBox' -and $n.Extent.Text.Contains('RunFilter') }, $true))
        $found.Count | Should -Be 1
        InModuleScope PsUi -Parameters @{ Text = $found[0].Extent.Text } {
            param($Text)
            $arrival = [scriptblock]::Create("param(`$selectedTab, `$filterBox)`n" + $Text)

            $rowsA = [System.Collections.Generic.List[object]]::new()
            1..3 | ForEach-Object { $rowsA.Add([pscustomobject]@{ Name = "alpha$_" }) }
            $rowsB = [System.Collections.Generic.List[object]]::new()
            1..2 | ForEach-Object { $rowsB.Add([pscustomobject]@{ Label = "beta$_" }) }
            $subTabs = [System.Windows.Controls.TabControl]::new()
            $tabA = (New-ObjectSubTab -GroupItems $rowsA -TypeName 'TypeA' -SubTabControl $subTabs).Tab
            $tabB = (New-ObjectSubTab -GroupItems $rowsB -TypeName 'TypeB' -SubTabControl $subTabs).Tab
            [void]$subTabs.Items.Add($tabA)
            [void]$subTabs.Items.Add($tabB)
            $subTabs.SelectedIndex = 0
            $deadline = (Get-Date).AddSeconds(10)
            while ((Get-Date) -lt $deadline -and !($rowsA[2].PSObject.Properties['_SearchText'] -and $rowsB[1].PSObject.Properties['_SearchText'])) { Start-Sleep -Milliseconds 50 }

            $toolbarArgs = @{ SubTabControl = $subTabs; RightToolbar = [System.Windows.Controls.StackPanel]::new(); FilterPanel = [System.Windows.Controls.StackPanel]::new(); Toolbar2 = [System.Windows.Controls.DockPanel]::new() }
            $box   = (Add-MultiTypeFilterControls @toolbarArgs).FilterBox
            $gridA = Get-UiSubTabGrid -Tab $tabA

            $box.Text = 'zzz'
            & $box.Tag.RunFilter $box
            $gridA.Tag.Observable.Count | Should -Be 0
            $subTabs.SelectedIndex = 1
            & $arrival $tabB $box
            $box.Text | Should -Be ''
            $subTabs.SelectedIndex = 0
            & $arrival $tabA $box
            $gridA.Tag.Observable.Count | Should -Be 3
        }
    }

    It 'The search index survives a getter that throws on every row' {
        InModuleScope PsUi {
            $items = [System.Collections.Generic.List[object]]::new()
            1..15 | ForEach-Object { $items.Add([psobject]::AsPSObject([PsUiTest.ThrowingGetter]@{ Name = "srv-$_" })) }
            $null = New-ObjectSubTab -GroupItems $items -TypeName 'Server' -SubTabControl ([System.Windows.Controls.TabControl]::new())
            $deadline = (Get-Date).AddSeconds(10)
            while ((Get-Date) -lt $deadline -and !$items[14].PSObject.Properties['_SearchText']) { Start-Sleep -Milliseconds 50 }
            $items[14]._SearchText | Should -Match 'srv-15'
            $items[0]._SearchText  | Should -Match 'srv-1 '
        }
    }

    It 'The array popup lists nested values the way a cell would and counts its header' {
        $src  = Join-Path $repoRoot 'PsUi\private\output\Add-ArrayCellPopupHandler.ps1'
        $ast  = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $node = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_PreviewMouseLeftButtonDown' }, $true))[0]
        $text = (("$($node.Arguments[0])" -replace '^\{', '') -replace '\}\.GetNewClosure\(\)$', '') -replace '\$popup\.IsOpen\s*=\s*\$true', '$$popup'
        $values = [System.Collections.Generic.List[object]]::new()
        $values.Add(@{ a = 1 })
        $values.Add(@(1, 2))
        $values.Add($null)
        $values.Add('plain')
        $cell  = [System.Windows.Controls.TextBlock]@{ FontStyle = 'Italic'; Tag = $values }
        $popup = InModuleScope PsUi -Parameters @{ Text = $text; Cell = $cell } {
            param($Text, $Cell)
            & ([scriptblock]::Create($Text)) ([System.Windows.Controls.DataGrid]::new()) ([pscustomobject]@{ OriginalSource = $Cell; Handled = $false })
        }
        $stack  = $popup.Child.Child.Content
        $header = @($stack.Children[0].Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] })[0]
        $lines  = @($stack.Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] } | ForEach-Object { $_.Text })
        $header.Text | Should -Be '4 items:'
        $lines       | Should -Be @('@{a=1}', '1, 2', '(null)', 'plain')
    }

    It 'The toolbar Copy button ticks only when something reached the clipboard' {
        InModuleScope PsUi {
            $grid = New-StyledDataGrid
            $grid.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new([System.Collections.Generic.List[object]]@([pscustomobject]@{ A = 1 }))
            $toolbar    = New-UiDataGridToolbar -DataGrid $grid -Colors (Get-ThemeColors) -NoFilter -NoExport -NoColumnPicker
            $copyButton = $toolbar.CopyButton
            $copyGlyph  = [PsUi.ModuleContext]::GetIcon('Copy')
            $copyButton.Content.Text | Should -Be $copyGlyph

            Invoke-UiDataGridCopyToClipboard -DataGrid $grid | Should -BeFalse
            $copyButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            $copyButton.Content.Text | Should -Be $copyGlyph
        }
    }

    It 'The dictionary popup header counts keys, singular included' {
        $src  = Join-Path $repoRoot 'PsUi\private\output\Add-DictionaryValuePopupHandler.ps1'
        $ast  = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $node = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_PreviewMouseLeftButtonDown' }, $true))[0]
        $text = (("$($node.Arguments[0])" -replace '^\{', '') -replace '\}\.GetNewClosure\(\)$', '') -replace '\$popup\.IsOpen\s*=\s*\$true', '$$popup'
        $cell = [System.Windows.Controls.TextBlock]@{ FontStyle = 'Italic'; Tag = [ordered]@{ a = 1 } }
        $popup = InModuleScope PsUi -Parameters @{ Text = $text; Cell = $cell } {
            param($Text, $Cell)
            & ([scriptblock]::Create($Text)) ([System.Windows.Controls.DataGrid]::new()) ([pscustomobject]@{ OriginalSource = $Cell; Handled = $false })
        }
        $header = @($popup.Child.Child.Content.Children[0].Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] })[0]
        $header.Text | Should -Be '1 key:'
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

    Describe 'Format-UiDataGridExportRows - value kinds' {
        It 'Writes a HashSet and a hashtable as their contents' {
            $set = [System.Collections.Generic.HashSet[string]]::new()
            [void]$set.Add('web')
            [void]$set.Add('prod')
            $rows = @([PSCustomObject]@{ Sets = $set; Meta = [ordered]@{ k = 1; j = 2 }; Tags = @('a', 'b') })

            $out = @(Format-UiDataGridExportRows -Items $rows -Properties @('Sets', 'Meta', 'Tags'))
            $out[0].Sets | Should -Be 'web, prod'
            $out[0].Meta | Should -Be 'k=1; j=2'
            $out[0].Tags | Should -Be 'a, b'
        }

        It 'Leaves a forward only sequence unread' {
            [PsUiTest.CountingSequence]::Passes = 0
            $rows = @([PSCustomObject]@{ Reader = [PsUiTest.CountingSequence]::new() })

            $out = @(Format-UiDataGridExportRows -Items $rows -Properties @('Reader'))
            $out[0].Reader | Should -Be '[sequence]'
            [PsUiTest.CountingSequence]::Passes | Should -Be 0
        }

        It 'Enumerates a hashtable carrying a Keys key' {
            $rows = @([PSCustomObject]@{ Meta = [ordered]@{ Keys = 'k'; Count = 0 } })
            (Format-UiDataGridExportRows -Items $rows -Properties @('Meta')).Meta | Should -Be 'Keys=k; Count=0'
        }
    }
}
