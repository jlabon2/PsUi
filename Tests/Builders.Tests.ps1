#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Definition blocks and the normalizing they go through before a control sees them
. (Join-Path $PSScriptRoot '_Setup.ps1')

BeforeAll { . (Join-Path $PSScriptRoot '_Setup.ps1') }

# Builders emit definition hashtables and never touch the session, so no session here.
Describe 'Builder functions - what lands in the hashtable' {
    It 'New-UiMenuItem returns a plain hashtable with only bound keys' {
        $item = New-UiMenuItem 'Restart' -Action { $_ } -Icon Refresh
        $item.GetType() | Should -Be ([hashtable])
        $item.Text | Should -Be 'Restart'
        $item.Action | Should -BeOfType [scriptblock]
        $item.Icon | Should -Be 'Refresh'
        $item.Contains('NoAsync') | Should -BeFalse
        $item.Contains('Enabled') | Should -BeFalse
    }

    It 'New-UiMenuItem -Enabled $false survives as a present key' {
        $item = New-UiMenuItem 'X' { 1 } -Enabled $false
        $item.Contains('Enabled') | Should -BeTrue
        $item.Enabled | Should -BeFalse
    }

    It 'New-UiMenuItem -NoAsync:$false still emits the key' {
        $item = New-UiMenuItem 'X' { 1 } -NoAsync:$false
        $item.Contains('NoAsync') | Should -BeTrue
        $item.NoAsync | Should -BeFalse
    }

    It 'New-UiMenuItem still answers to the old -Sync spelling' {
        # The param was called Sync before it was mirroed to line up with New-UiButton. A script written with the old name has to keep working.
        $item = New-UiMenuItem 'X' { 1 } -Sync
        $item.Contains('NoAsync') | Should -BeTrue
        $item.NoAsync | Should -BeTrue
        $item.Contains('Sync') | Should -BeFalse
    }

    It 'New-UiColumn still answers to the old -Sync spelling' {
        $col = New-UiColumn -Name 'A' -Sync
        $col.Contains('NoAsync') | Should -BeTrue
        $col.NoAsync | Should -BeTrue
        $col.Contains('Sync') | Should -BeFalse
    }

    It 'New-UiMenuItem rejects a string -Enabled' {
        # the menu builder casts anything that isn't a scriptblock to [bool], and 'false' casts truthy
        { New-UiMenuItem 'X' { 1 } -Enabled 'false' } | Should -Throw '*-Enabled takes*'
    }

    It 'New-UiMenuItem passes a scriptblock -Enabled through' {
        (New-UiMenuItem 'X' { 1 } -Enabled { $_.Ok }).Enabled | Should -BeOfType [scriptblock]
    }

    It 'New-UiResultAction carries Confirm and ObjectType only when bound' {
        $entry = New-UiResultAction 'Stop' { $_ } -Confirm 'Stop {0}?' -ObjectType 'Process'
        $entry.GetType() | Should -Be ([hashtable])
        $entry.Confirm | Should -Be 'Stop {0}?'
        $entry.ObjectType -is [string[]] | Should -BeTrue

        $plain = New-UiResultAction 'Tag' { $_ }
        $plain.Contains('Confirm') | Should -BeFalse
        $plain.Contains('ObjectType') | Should -BeFalse
        $plain.Contains('Icon') | Should -BeFalse
    }

    It 'New-UiDialogButton defaults Value to the label' {
        (New-UiDialogButton 'Save').Value | Should -Be 'Save'
        (New-UiDialogButton 'Save' 'other').Value | Should -Be 'other'
    }

    It 'New-UiDialogButton switches emit keys only when present' {
        $btn = New-UiDialogButton 'Save' -Accent -Default
        $btn.IsAccent | Should -BeTrue
        $btn.IsDefault | Should -BeTrue
        $btn.Contains('IsCancel') | Should -BeFalse
    }

    It 'New-UiColumn mirrors bound parameters into keys and flattens switches' {
        $col = New-UiColumn Name -ReadOnly -Width '2*' -Verbose
        $col.Name | Should -Be 'Name'
        $col.ReadOnly | Should -BeOfType [bool]
        $col.ReadOnly | Should -BeTrue
        $col.Width | Should -Be '2*'
        $col.Contains('NoAsync') | Should -BeFalse
        # common params never leak into the definition
        $col.Contains('Verbose') | Should -BeFalse
    }

    It 'New-UiColumn throws at definition time on the combos the grid rejects later' {
        { New-UiColumn -Header 'On' -Type Toggle } | Should -Throw '*needs -Binding*'
        { New-UiColumn -Header 'Open' -Type Link } | Should -Throw '*-Url or -Action*'
        { New-UiColumn -Type Button -Text 'Go' -Action { 1 } } | Should -Throw '*or -Header*'
    }

    It 'New-UiColumn Icon rejects a bogus name via the dynamic ValidateSet' {
        { New-UiColumn -Header 'Go' -Type Button -Action { 1 } -Icon 'NotARealGlyphName' } |
            Should -Throw '*does not belong to the set*'
    }

    It 'New-UiHeaderAction emits Icon and Tooltip only when bound' {
        $headerAction = New-UiHeaderAction -Action { 1 }
        $headerAction.Action | Should -BeOfType [scriptblock]
        $headerAction.Contains('Icon') | Should -BeFalse
        $headerAction.Contains('Tooltip') | Should -BeFalse

        $bound = New-UiHeaderAction -Action { 1 } -Icon Refresh -Tooltip 'Reload'
        $bound.Icon    | Should -Be 'Refresh'
        $bound.Tooltip | Should -Be 'Reload'
    }
}

Describe 'New-UiDataGrid - RowContextMenu builder input' -Tag 'RequiresSession' {
    BeforeAll {
        $script:rcmSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:rcmSessionId)
        $script:rcmSession = [PsUi.SessionManager]::Current
        $script:rcmSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
        $script:rcmRows = @(
            [pscustomobject]@{ Name = 'web01'; Online = $true }
            [pscustomobject]@{ Name = 'sql01'; Online = $false }
        )
    }

    AfterAll {
        [PsUi.SessionManager]::DisposeSession($script:rcmSessionId)
    }

    It 'builds MenuItems in emission order ahead of the standard entries' {
        New-UiDataGrid -Variable 'rcmBuilder' -Items $script:rcmRows -RowContextMenu {
            New-UiMenuItem 'Ping' -Action { $_ } -Enabled { $_.Online }
            New-UiMenuItem 'Wake' -Action { $_ } -Enabled $false
        }
        $menu    = ($script:rcmSession.GetControl('rcmBuilder')).ContextMenu
        $headers = @($menu.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] } | ForEach-Object { $_.Header })
        $headers[0] | Should -Be 'Ping'
        $headers[1] | Should -Be 'Wake'
    }

    It '-Enabled $false lands as StaticEnabled on the MenuItem tag' {
        # An explicit $false has to survive instead of vanishing.
        New-UiDataGrid -Variable 'rcmStatic' -Items $script:rcmRows -RowContextMenu {
            New-UiMenuItem 'Wake' -Action { $_ } -Enabled $false
        }
        $menu     = ($script:rcmSession.GetControl('rcmStatic')).ContextMenu
        $wakeItem = @($menu.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] -and $_.Header -eq 'Wake' })[0]
        $wakeItem.Tag.ContainsKey('StaticEnabled') | Should -BeTrue
        $wakeItem.Tag.StaticEnabled | Should -BeFalse
    }

    It 'a New-UiMenuItem outside any block or array still lands as one labeled item' {
        # A builder item is a dictionary too, so the legacy passthrough renders entries named 'Text'
        New-UiDataGrid -Variable 'rcmBare' -Items $script:rcmRows -RowContextMenu (New-UiMenuItem 'Solo' -Action { 1 })
        $menu    = ($script:rcmSession.GetControl('rcmBare')).ContextMenu
        $headers = @($menu.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] } | ForEach-Object { $_.Header })
        $headers[0] | Should -Be 'Solo'
        $headers | Should -Not -Contain 'Action'
    }

    It 'the array form works the same as the block form' {
        New-UiDataGrid -Variable 'rcmArray' -Items $script:rcmRows -RowContextMenu @(
            (New-UiMenuItem 'First' -Action { 1 }),
            (New-UiMenuItem 'Second' -Action { 2 })
        )
        $menu    = ($script:rcmSession.GetControl('rcmArray')).ContextMenu
        $headers = @($menu.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] } | ForEach-Object { $_.Header })
        $headers[0] | Should -Be 'First'
        $headers[1] | Should -Be 'Second'
    }

    It 'duplicate labels throw, case-insensitively' {
        {
            New-UiDataGrid -Variable 'rcmDup' -Items $script:rcmRows -RowContextMenu {
                New-UiMenuItem 'Ping' -Action { 1 }
                New-UiMenuItem 'ping' -Action { 2 }
            }
        } | Should -Throw '*duplicate*'
    }

    It 'an item hashtable without Text throws with the builder hint' {
        { New-UiDataGrid -Variable 'rcmNoText' -Items $script:rcmRows -RowContextMenu @(@{ Action = { 1 } }) } | Should -Throw '*New-UiMenuItem*'
    }

    It 'the legacy ordered form still renders in declared order' {
        New-UiDataGrid -Variable 'rcmLegacy' -Items $script:rcmRows -RowContextMenu ([ordered]@{
            'B first'  = { $_ }
            'A second' = @{ Action = { $_ }; NoAsync = $true }
        })
        $menu    = ($script:rcmSession.GetControl('rcmLegacy')).ContextMenu
        $headers = @($menu.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] } | ForEach-Object { $_.Header })
        $headers[0] | Should -Be 'B first'
        $headers[1] | Should -Be 'A second'
    }

    It 'a stray control call inside the menu block throws instead of landing in the panel' {
        $countBefore = $script:rcmSession.CurrentParent.Children.Count
        {
            New-UiDataGrid -Variable 'rcmStray' -Items $script:rcmRows -RowContextMenu {
                New-UiLabel -Text 'oops'
                New-UiMenuItem 'X' -Action { 1 }
            }
        } | Should -Throw '*content block*'
        $script:rcmSession.CurrentParent.Children.Count | Should -Be $countBefore
    }
}

Describe 'New-UiDataGrid - Columns builder input' -Tag 'RequiresSession' {
    BeforeAll {
        $script:colSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:colSessionId)
        $script:colSession = [PsUi.SessionManager]::Current
        $script:colSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
        $script:colRows = @(
            [pscustomobject]@{ Name = 'web01'; Role = 'IIS' }
            [pscustomobject]@{ Name = 'sql01'; Role = 'SQL' }
        )
    }

    AfterAll {
        [PsUi.SessionManager]::DisposeSession($script:colSessionId)
    }

    It 'the scriptblock form builds the declared columns' {
        New-UiDataGrid -Variable 'colBuilder' -Items $script:colRows -Columns {
            New-UiColumn Name -ReadOnly
            New-UiColumn -Header 'Go' -Type Button -Text 'Go' -Action { $_ }
        }
        $grid = $script:colSession.GetControl('colBuilder')
        $grid.Columns.Count | Should -Be 2
        $grid.Columns[1].Header | Should -Be 'Go'
    }

    It 'strings and builder output mix in one array' {
        New-UiDataGrid -Variable 'colMixed' -Items $script:colRows -Columns @(
            'Name'
            (New-UiColumn Role -Header 'Duty')
        )
        $grid = $script:colSession.GetControl('colMixed')
        $grid.Columns.Count | Should -Be 2
        $grid.Columns[1].Header | Should -Be 'Duty'
    }

    It 'a pure string array still acts as a column filter' {
        # Filter mode hides rather than removes. Every property gets a column
        New-UiDataGrid -Variable 'colFilter' -Items $script:colRows -Columns @('Name')
        $grid    = $script:colSession.GetControl('colFilter')
        $visible = @($grid.Columns | Where-Object { $_.Visibility -eq [System.Windows.Visibility]::Visible })
        $visible.Count | Should -Be 1
        $visible[0].Header | Should -Be 'Name'
    }

    It 'an empty definition block falls back to auto columns' {
        New-UiDataGrid -Variable 'colEmpty' -Items $script:colRows -Columns { }
        ($script:colSession.GetControl('colEmpty')).Columns.Count | Should -Be 2
    }
}

Describe 'ResultActions builder input' -Tag 'RequiresSession' {
    BeforeAll {
        $script:raSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:raSessionId)
        $script:raSession = [PsUi.SessionManager]::Current
        $script:raSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterAll {
        [PsUi.SessionManager]::DisposeSession($script:raSessionId)
    }

    It 'New-UiButton stores the normalized hashtable array on the button context' {
        New-UiButton -Text 'RA1' -Action { 1 } -ResultActions {
            New-UiResultAction 'Stop' { $_ } -Confirm 'Stop {0}?'
            New-UiResultAction 'Tag' { $_ }
        }
        $button  = @($script:raSession.CurrentParent.Children | Where-Object { $_ -is [System.Windows.Controls.Button] })[-1]
        $actions = $button.Tag.ResultActions
        @($actions).Count | Should -Be 2
        $actions[0] | Should -BeOfType [hashtable]
        $actions[0].Text | Should -Be 'Stop'
        $actions[0].Confirm | Should -Be 'Stop {0}?'
        $actions[1].Text | Should -Be 'Tag'
    }

    It 'a single emission binds as a one-element array' {
        New-UiButton -Text 'RA2' -Action { 1 } -ResultActions { New-UiResultAction 'Solo' { $_ } }
        $button = @($script:raSession.CurrentParent.Children | Where-Object { $_ -is [System.Windows.Controls.Button] })[-1]
        # No @() around it. That wrap turns a missing Tag.ResultActions into a count of 1.
        $button.Tag.ResultActions.Count     | Should -Be 1
        $button.Tag.ResultActions[0].Text   | Should -Be 'Solo'
    }

    It 'the legacy hashtable array still binds' {
        New-UiButton -Text 'RA3' -Action { 1 } -ResultActions @(@{ Text = 'L'; Action = { $_ } })
        $button = @($script:raSession.CurrentParent.Children | Where-Object { $_ -is [System.Windows.Controls.Button] })[-1]
        $button.Tag.ResultActions[0].Text | Should -Be 'L'
    }

    It 'New-UiButtonCard and New-UiTool take untyped -ResultActions so definition blocks bind' {
        (Get-Command New-UiButtonCard).Parameters['ResultActions'].ParameterType | Should -Be ([object])
        (Get-Command New-UiTool).Parameters['ResultActions'].ParameterType | Should -Be ([object])
    }
}

Describe 'New-UiChart' -Tag 'RequiresSession' {

    BeforeEach {
        $script:chSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:chSessionId)
        $script:chSession = [PsUi.SessionManager]::Current
        $script:chSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterEach { [PsUi.SessionManager]::DisposeSession($script:chSessionId) }

    It 'A fixed -Width sizes the chart and scales the other side with it' {
        New-UiChart -Variable 'sizedChart' -Type Bar -Data @{ A = 1 } -Width 300
        $container = $script:chSession.CurrentParent.Children[0]
        $viewbox   = @($container.Children | Where-Object { $_ -is [System.Windows.Controls.Viewbox] })[0]

        $container.Width               | Should -Be 300
        $container.HorizontalAlignment | Should -Be 'Left'
        $viewbox.Child.Width           | Should -Be 300
        $viewbox.Child.Height          | Should -Be 120
    }

    It 'An auto sized chart still stretches and keeps the default canvas' {
        New-UiChart -Variable 'autoChart' -Type Bar -Data @{ A = 1 }
        $container = $script:chSession.CurrentParent.Children[0]
        $viewbox   = @($container.Children | Where-Object { $_ -is [System.Windows.Controls.Viewbox] })[0]

        $container.HorizontalAlignment | Should -Be 'Stretch'
        $viewbox.Child.Width           | Should -Be 900
        $viewbox.Child.Height          | Should -Be 360
    }

    It 'Draws the one slice a single point pie chart asks for' {
        New-UiChart -Variable 'onePie' -Type Pie -Data ([ordered]@{ Only = 60 })
        $container = $script:chSession.CurrentParent.Children[0]
        $viewbox   = @($container.Children | Where-Object { $_ -is [System.Windows.Controls.Viewbox] })[0]

        $slices = @($viewbox.Child.Children | Where-Object { $_ -is [System.Windows.Shapes.Path] })
        $slices.Count | Should -Be 1

        $bounds = $slices[0].Data.Bounds
        $bounds.IsEmpty | Should -BeFalse
        $bounds.Width   | Should -BeGreaterThan 1
        $bounds.Height  | Should -BeGreaterThan 1

        $legend = @($container.Children | Where-Object { $_ -is [System.Windows.Controls.WrapPanel] })[0]
        $legend.Children.Count | Should -Be 1
    }

    It 'Update-UiChart keeps the rows when the chart was made with custom property names' {
        New-UiChart -Variable 'propChart' -Type Bar -LabelProperty 'DeviceID' -ValueProperty 'FreeGB' -Data @(
            [pscustomobject]@{ DeviceID = 'C:'; FreeGB = 40 }
        )
        Update-UiChart -Variable 'propChart' -Data @(
            [pscustomobject]@{ DeviceID = 'D:'; FreeGB = 80 }
            [pscustomobject]@{ DeviceID = 'E:'; FreeGB = 20 }
        ) -LabelProperty 'DeviceID' -ValueProperty 'FreeGB'

        $container = $script:chSession.CurrentParent.Children[0]
        $viewbox   = @($container.Children | Where-Object { $_ -is [System.Windows.Controls.Viewbox] })[0]
        $texts     = @($viewbox.Child.Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] } | ForEach-Object { $_.Text })

        # Every row used to drop, which puts the placeholder up and draws no axis at all!
        $texts | Should -Not -Contain 'No data'
        $texts | Should -Contain '80'
    }

    It '-Data drops a null point and keeps the rest' {
        # A null element reaches $item.PSObject.Properties[...] and throws unless the build loop skips it.
        New-UiChart -Variable 'neChart' -Type Bar -Data @(
            [pscustomobject]@{ Label = 'A'; Value = 3 }
            $null
            [pscustomobject]@{ Label = 'B'; Value = 5 }
        )

        $chart = $script:chSession.GetControl('neChart')
        $chart | Should -Not -BeNullOrEmpty

        # A null that took the real points down with it renders the No data placeholder instead of two bars.
        $labels = [System.Collections.Generic.List[string]]::new()
        $stack  = [System.Collections.Generic.Stack[object]]::new()
        $stack.Push($chart)
        while ($stack.Count) {
            $node = $stack.Pop()
            if ($node -is [System.Windows.Controls.TextBlock]) { $labels.Add($node.Text) }
            if ($node.Child) { $stack.Push($node.Child) }
            if ($node.Children) { foreach ($kid in $node.Children) { $stack.Push($kid) } }
        }

        $labels | Should -Contain 'A'
        $labels | Should -Contain 'B'
        $labels | Should -Not -Contain 'No data'
    }
}

Describe 'Null-element rows through the public API' -Tag 'RequiresSession' {

    BeforeEach {
        $script:neSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:neSessionId)
        $script:neSession = [PsUi.SessionManager]::Current
        $script:neSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterEach {
        [PsUi.SessionManager]::DisposeSession($script:neSessionId)
    }

    It 'New-UiDataGrid -Items with a null row builds and drops it (default SafeWrap path)' {
        New-UiDataGrid -Variable 'neGridA' -Items @(
            [pscustomobject]@{ A = 'x' }
            $null
            [pscustomobject]@{ A = 'y' }
        ) -NoToolbar
        $script:neSession.GetListCollection('neGridA').Count | Should -Be 2
    }

    It 'New-UiDataGrid -NoSafeWrap with a null row builds and drops it (direct snapshot path)' {
        New-UiDataGrid -Variable 'neGridB' -NoSafeWrap -Items @(
            [pscustomobject]@{ A = 'x' }
            $null
        ) -NoToolbar
        $script:neSession.GetListCollection('neGridB').Count | Should -Be 1
    }

    It 'New-UiDataGrid -Items @(0) keeps the lone falsy row' {
        New-UiDataGrid -Variable 'neGridZ' -Items @(0) -NoToolbar
        $script:neSession.GetListCollection('neGridZ').Count | Should -Be 1
    }

    It 'Explicit -Columns build over property-less rows (no early-return when rows have no props)' {
        New-UiDataGrid -Variable 'neGridC' -Items @([pscustomobject]@{}, [pscustomobject]@{}) -NoToolbar -Columns @(
            @{ Header = 'Act'; Type = 'Button'; Text = 'Go'; Action = { } }
            @{ Name = 'Name' }
        )
        $grid = $script:neSession.GetControl('neGridC')
        $grid.Columns.Count | Should -BeGreaterOrEqual 2
    }

    It 'Explicit -Columns build when an -ItemsSource collection has NO buildable row (firstItem fallback)' {
        # All null, so the row scan finds nothing and the empty firstItem fallback is what runs.
        $shared = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $shared.Add($null)
        New-UiDataGrid -Variable 'neGridD' -ItemsSource $shared -NoToolbar -WarningAction SilentlyContinue -Columns @(
            @{ Name = 'Name' }
            @{ Header = 'Act'; Type = 'Button'; Text = 'Go'; Action = { } }
        )
        $grid = $script:neSession.GetControl('neGridD')
        $grid.Columns.Count | Should -BeGreaterOrEqual 2
    }

    It 'Set-UiDataGridItems binds a null-carrying replacement and drops the null (owned grid)' {
        New-UiDataGrid -Variable 'neGridE' -Items @([pscustomobject]@{ A = 'seed' }) -NoToolbar
        Set-UiDataGridItems -Variable 'neGridE' -Items @(
            $null
            [pscustomobject]@{ A = 'p' }
            [pscustomobject]@{ A = 'q' }
        )
        $script:neSession.GetListCollection('neGridE').Count | Should -Be 2
    }

    It 'Set-UiDataGridItems keeps null rows out of a list supplied by user code' {
        $shared = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $shared.Add([pscustomobject]@{ A = 'seed' })
        New-UiDataGrid -Variable 'neGridF' -ItemsSource $shared -NoToolbar -WarningAction SilentlyContinue
        Set-UiDataGridItems -Variable 'neGridF' -Items @($null, [pscustomobject]@{ A = 'p' }, [pscustomobject]@{ A = 'q' })

        $shared.Count | Should -Be 2
        @($shared | Where-Object { $null -eq $_ }).Count | Should -Be 0
    }

    It 'Set-UiDataGridItems -Items $null wipes the grid (null means no-rows, same as @())' {
        New-UiDataGrid -Variable 'neGridG' -Items @([pscustomobject]@{ A = 'seed' }) -NoToolbar
        $nothing = @([pscustomobject]@{ A = 'x' }) | Where-Object { $_.A -eq 'no-match' }
        Set-UiDataGridItems -Variable 'neGridG' -Items $nothing
        $script:neSession.GetListCollection('neGridG').Count | Should -Be 0
    }

    It 'New-UiTree -Items with a null item builds and drops it (direct-param path)' {
        New-UiTree -Variable 'neTree' -Items @(
            [pscustomobject]@{ Name = 'A'; Children = @() }
            $null
            [pscustomobject]@{ Name = 'B'; Children = @() }
        )
        $tree = $script:neSession.GetControl('neTree')
        $tree.Items.Count | Should -Be 2
    }

    It 'New-UiTree -Items @($null, $null) builds an empty tree (all-null fallback path)' {
        # Two nulls, because @($null) is falsy and skips the process block, so the null guard never runs.
        New-UiTree -Variable 'neTreeAllNull' -Items @($null, $null)
        $tree = $script:neSession.GetControl('neTreeAllNull')
        $tree.Items.Count | Should -Be 0
    }

}

# Private functions aren't exported, so they need module scope to reach.
InModuleScope PsUi {
    # A parameter alias covers -Sync on the builders. It cannot reach the hashtable form, where the key is just text somebody typed, so the read is what carries the old name there.
    Describe 'Get-UiNoAsyncFlag' {
        It 'Reads the NoAsync key' {
            Get-UiNoAsyncFlag -Definition @{ NoAsync = $true }  | Should -BeTrue
            Get-UiNoAsyncFlag -Definition @{ NoAsync = $false } | Should -BeFalse
        }

        It 'Still honours a hashtable written with the old Sync key' {
            Get-UiNoAsyncFlag -Definition @{ Sync = $true }  | Should -BeTrue
            Get-UiNoAsyncFlag -Definition @{ Sync = $false } | Should -BeFalse
        }

        It 'Lets the new name win when a table carries both' {
            Get-UiNoAsyncFlag -Definition @{ NoAsync = $false; Sync = $true } | Should -BeFalse
            Get-UiNoAsyncFlag -Definition @{ NoAsync = $true; Sync = $false } | Should -BeTrue
        }

        It 'Reads a definition with neither key, and a null one, as async' {
            Get-UiNoAsyncFlag -Definition @{}    | Should -BeFalse
            Get-UiNoAsyncFlag -Definition $null  | Should -BeFalse
        }
    }

    Describe 'ConvertTo-UiDefinitionArray' -Tag 'RequiresSession' {
        BeforeAll {
            $script:normSessionId = [PsUi.SessionManager]::CreateSession()
            [PsUi.SessionManager]::SetCurrentSession($script:normSessionId)
            $script:normSession = [PsUi.SessionManager]::Current
            $script:normSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
        }

        AfterAll {
            [PsUi.SessionManager]::DisposeSession($script:normSessionId)
        }

        It 'collects scriptblock emissions in order' {
            $result = ConvertTo-UiDefinitionArray -InputObject { @{ A = 1 }; @{ B = 2 } } -ParameterName '-X' -CallerName 'T'
            $result.Count | Should -Be 2
            $result[0].A | Should -Be 1
            $result[1].B | Should -Be 2
        }

        It 'a single emission comes back as a one-element array, not a lone hashtable' {
            # Without the unary comma return this would be a 2-key hashtable whose .Count is 2
            $result = ConvertTo-UiDefinitionArray -InputObject { @{ A = 1; B = 2 } } -ParameterName '-X' -CallerName 'T'
            $result -is [array] | Should -BeTrue
            $result.Count | Should -Be 1
        }

        It 'passes a legacy ordered dictionary through untouched' {
            $legacy = [ordered]@{ 'A' = @{ Action = { 1 } } }
            $result = ConvertTo-UiDefinitionArray -InputObject $legacy -ParameterName '-X' -CallerName 'T' -PassThruDictionary
            [object]::ReferenceEquals($result, $legacy) | Should -BeTrue
        }

        It 'wraps a single unwrapped hashtable' {
            $result = ConvertTo-UiDefinitionArray -InputObject @{ A = 1 } -ParameterName '-X' -CallerName 'T'
            $result -is [array] | Should -BeTrue
            $result.Count | Should -Be 1
        }

        It 'copies an [ordered] element into a plain hashtable' {
            $result = ConvertTo-UiDefinitionArray -InputObject ([ordered]@{ A = 1 }) -ParameterName '-X' -CallerName 'T'
            $result[0].GetType() | Should -Be ([hashtable])
            $result[0].A | Should -Be 1
        }

        It 'rejects a non-dictionary element, naming the owning function and parameter' {
            { ConvertTo-UiDefinitionArray -InputObject @(@{ A = 1 }, 42) -ParameterName '-Things' -CallerName 'New-UiWhatever' } | Should -Throw '*New-UiWhatever*-Things*'
        }

        It 'allows string elements only with -AllowString' {
            { ConvertTo-UiDefinitionArray -InputObject @('Name') -ParameterName '-X' -CallerName 'T' } | Should -Throw
            (ConvertTo-UiDefinitionArray -InputObject @('Name') -ParameterName '-X' -CallerName 'T' -AllowString)[0] | Should -Be 'Name'
        }

        It 'nulls CurrentParent inside a definition block and restores it after' {
            $parentBefore = $script:normSession.CurrentParent
            $probe        = @{}
            $null         = ConvertTo-UiDefinitionArray -InputObject { $probe.Parent = [PsUi.SessionManager]::Current.CurrentParent; @{ A = 1 } } -ParameterName '-X' -CallerName 'T'
            $probe.Parent | Should -BeNullOrEmpty
            $script:normSession.CurrentParent | Should -Be $parentBefore
        }

        It 'restores CurrentParent when the block throws' {
            $parentBefore = $script:normSession.CurrentParent
            { ConvertTo-UiDefinitionArray -InputObject { throw 'boom' } -ParameterName '-X' -CallerName 'T' } | Should -Throw 'boom'
            $script:normSession.CurrentParent | Should -Be $parentBefore
        }

        It 'a stray control call inside a definition block throws via Assert-UiSession' {
            { ConvertTo-UiDefinitionArray -InputObject { New-UiLabel -Text 'oops' } -ParameterName '-X' -CallerName 'T' } | Should -Throw '*content block*'
        }
    }

    Describe 'Null-element helpers' {
        It 'ConvertTo-UiDataGridSnapshot binds a null-carrying array and drops the null' {
            $snap = @(ConvertTo-UiDataGridSnapshot -Items @($null, [pscustomobject]@{ A = 1 }))
            $snap.Count | Should -Be 1
            $snap[0].A  | Should -Be 1
        }

        It 'ConvertTo-UiDataGridSnapshot keeps a lone falsy scalar row (0, empty string, $false)' {
            @(ConvertTo-UiDataGridSnapshot -Items @(0)).Count      | Should -Be 1
            @(ConvertTo-UiDataGridSnapshot -Items @('')).Count     | Should -Be 1
            @(ConvertTo-UiDataGridSnapshot -Items @($false)).Count | Should -Be 1
        }

        It 'ConvertTo-SafeDataArray binds a null-carrying array (null passes through, snapshot drops it later)' {
            # Returns ,$DataArray - assign first, then @() around the VARIABLE.
            # @(cmd) around the call renests the comma wrapped array.
            $out = ConvertTo-SafeDataArray -DataArray @($null, [pscustomobject]@{ A = 1 })
            @($out).Count | Should -Be 2
            $null -eq @($out)[0] | Should -BeTrue
        }

        It 'Get-PopulatedProperties binds a null-carrying array and reads the real rows' {
            $props = Get-PopulatedProperties -Items @($null, [pscustomobject]@{ Name = 'x'; Blank = $null })
            $props.Contains('Name')  | Should -BeTrue
            $props.Contains('Blank') | Should -BeFalse
        }

        It 'Get-PopulatedProperties -PropertyNames survives a null item (the string-indexing path)' {
            # With -PropertyNames the loop indexes $item.PSObject.Properties[$name], which throws on a null.
            $props = Get-PopulatedProperties -Items @($null, [pscustomobject]@{ Name = 'x'; Blank = $null }) -PropertyNames @('Name', 'Blank')
            $props.Contains('Name')  | Should -BeTrue
            $props.Contains('Blank') | Should -BeFalse
        }

        It 'ConvertTo-ChartData skips a null data point instead of dying on PSObject.Properties' {
            $pts = @(
                [pscustomobject]@{ Label = 'A'; Value = 3 }
                $null
                [pscustomobject]@{ Label = 'B'; Value = 5 }
            )
            $out = ConvertTo-ChartData -RawData $pts -LabelProperty $null -ValueProperty $null
            $out.Count | Should -Be 2
            @($out | ForEach-Object { $_.Label }) | Should -Be @('A', 'B')
        }

        It 'ConvertTo-ChartData drops NaN and Infinity data points' {
            $pts = @(
                [pscustomobject]@{ Label = 'a'; Value = 10 }
                [pscustomobject]@{ Label = 'b'; Value = [double]::NaN }
                [pscustomobject]@{ Label = 'c'; Value = 20 }
                [pscustomobject]@{ Label = 'd'; Value = [double]::PositiveInfinity }
            )
            $out = ConvertTo-ChartData -RawData $pts -LabelProperty $null -ValueProperty $null
            $out.Count | Should -Be 2
            @($out | ForEach-Object { $_.Label }) | Should -Be @('a', 'c')
        }
    }
}
