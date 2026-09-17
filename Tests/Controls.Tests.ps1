#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Controls that need a session and a parent panel to build into.
. (Join-Path $PSScriptRoot '_Setup.ps1')

BeforeAll { . (Join-Path $PSScriptRoot '_Setup.ps1') }

# Real session, no window, so the controls land straight on CurrentParent.
Describe 'Control Creation' -Tag 'RequiresSession' {
    BeforeAll {
        $script:testSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:testSessionId)
        $script:testSession = [PsUi.SessionManager]::Current

        $script:testSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterAll {
        [PsUi.SessionManager]::DisposeSession($script:testSessionId)
    }

    It 'New-UiLabel should add TextBlock to parent' {
        # New-UiLabel adds to CurrentParent, doesnt return
        $parent      = $script:testSession.CurrentParent
        $countBefore = $parent.Children.Count

        New-UiLabel -Text 'Test Label'

        $parent.Children.Count | Should -Be ($countBefore + 1)
        $lastChild = $parent.Children[$parent.Children.Count - 1]
        $lastChild | Should -BeOfType [System.Windows.Controls.TextBlock]
        $lastChild.Text | Should -Be 'Test Label'
    }

    It 'New-UiSeparator should add separator element to parent' {
        # It builds a Border, because the themed separator needs a gradient brush.
        $parent      = $script:testSession.CurrentParent
        $countBefore = $parent.Children.Count

        New-UiSeparator

        $parent.Children.Count | Should -Be ($countBefore + 1)
        $lastChild = $parent.Children[$parent.Children.Count - 1]
        $lastChild | Should -BeOfType [System.Windows.Controls.Border]
    }

    It 'New-UiLabel with -Style Header should have larger font' {
        $parent      = $script:testSession.CurrentParent
        $countBefore = $parent.Children.Count

        New-UiLabel -Text 'Header' -Style Header
        New-UiLabel -Text 'Body' -Style Body

        $header = $parent.Children[$countBefore]
        $body   = $parent.Children[$countBefore + 1]

        $header.FontSize | Should -BeGreaterThan $body.FontSize
    }
}

# Throw on dumb parameter combos instead of silently doing something weird
Describe 'Error Handling' {

    It 'New-UiButton should throw on mutually exclusive parameters' {
        $testId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($testId)
        $session               = [PsUi.SessionManager]::Current
        $session.CurrentParent = [System.Windows.Controls.StackPanel]::new()

        try {
            { New-UiButton -Text 'Test' -Action {} -NoOutput -HideEmptyOutput } |
                Should -Throw "*mutually exclusive*"
        }
        finally { [PsUi.SessionManager]::DisposeSession($testId) }
    }
}

Describe 'Control Creation - Inputs and Toggles' {
    BeforeAll {
        # New-UiInput warns about a missing ModernTextBoxStyle whenever no window has loaded the styles.
        $global:WarningPreference = 'SilentlyContinue'
        $script:sessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:sessionId)
        $script:session = [PsUi.SessionManager]::Current
        $script:session.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterAll {
        $global:WarningPreference = 'Continue'
        [PsUi.SessionManager]::DisposeSession($script:sessionId)
    }

    It 'New-UiInput creates a text input and registers it' {
        New-UiInput -Variable 'testUser' -Label 'Username'

        $control = $script:session.GetControl('testUser')
        $control | Should -Not -BeNullOrEmpty
        $control | Should -BeOfType [System.Windows.Controls.TextBox]
    }

    It 'New-UiInput applies default value' {
        New-UiInput -Variable 'testDefault' -Label 'With Default' -Default 'hello'

        $proxy = $script:session.GetSafeVariable('testDefault')
        $proxy.Text | Should -Be 'hello'
    }

    It 'New-UiToggle creates a CheckBox' {
        $parent = $script:session.CurrentParent
        $before = $parent.Children.Count

        New-UiToggle -Variable 'testFlag' -Label 'Enable Feature'

        $parent.Children.Count | Should -BeGreaterThan $before
        $control = $script:session.GetControl('testFlag')
        $control | Should -Not -BeNullOrEmpty
        $control | Should -BeOfType [System.Windows.Controls.CheckBox]
    }

    It 'New-UiToggle applies default checked state' {
        New-UiToggle -Variable 'preChecked' -Label 'On by Default' -Checked
        $proxy = $script:session.GetSafeVariable('preChecked')
        $proxy.IsChecked | Should -BeTrue
    }

    It 'New-UiGlyph adds a glyph TextBlock with the active icon font' {
        $parent = $script:session.CurrentParent
        $before = $parent.Children.Count

        New-UiGlyph -Name 'Settings'

        $added = $parent.Children[$before]
        $added | Should -BeOfType [System.Windows.Controls.TextBlock]
        $added.FontFamily.Source | Should -Match 'Segoe (MDL2|Fluent)'
    }
}

Describe 'Control Creation - Selection Controls' {
    BeforeAll {
        $global:WarningPreference = 'SilentlyContinue'
        $script:sessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:sessionId)
        $script:session = [PsUi.SessionManager]::Current
        $script:session.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterAll {
        $global:WarningPreference = 'Continue'
        [PsUi.SessionManager]::DisposeSession($script:sessionId)
    }

    It 'New-UiDropdown creates a ComboBox and registers it' {
        New-UiDropdown -Variable 'testEnv' -Label 'Environment' -Items @('Dev', 'QA', 'Prod')

        $control = $script:session.GetControl('testEnv')
        $control | Should -Not -BeNullOrEmpty
        $control | Should -BeOfType [System.Windows.Controls.ComboBox]
    }

    It 'New-UiDropdown applies default selection' {
        New-UiDropdown -Variable 'testRegion' -Label 'Region' -Items @('East', 'West', 'Central') -Default 'West'

        $proxy = $script:session.GetSafeVariable('testRegion')
        $proxy.SelectedItem | Should -Be 'West'
    }

    It 'New-UiDropdown with -OnChange fires on selection change' {
        $script:onChangeValue = $null
        New-UiDropdown -Variable 'testOnChange' -Label 'Pick' -Items @('A', 'B', 'C') -OnChange {
            param($val)
            $script:onChangeValue = $val
        }
        $proxy              = $script:session.GetSafeVariable('testOnChange')
        $proxy.SelectedItem = 'B'
        $script:onChangeValue | Should -Be 'B'
    }

    It 'New-UiDropdown uses ObservableCollection (supports Add-UiListItem)' {
        New-UiDropdown -Variable 'testDyn' -Label 'Dynamic' -Items @('X', 'Y')
        Add-UiListItem -Variable 'testDyn' -Item 'Z'
        $items = Get-UiListItems -Variable 'testDyn'
        $items | Should -Contain 'Z'
        $items.Count | Should -Be 3
    }

    It 'New-UiDropdown supports Remove-UiListItem' {
        New-UiDropdown -Variable 'testRemove' -Label 'Remove' -Items @('A', 'B', 'C')
        Remove-UiListItem -Variable 'testRemove' -Item 'B'
        $items = Get-UiListItems -Variable 'testRemove'
        $items | Should -Not -Contain 'B'
        $items.Count | Should -Be 2
    }

    It 'New-UiDropdown supports Clear-UiList' {
        New-UiDropdown -Variable 'testClear' -Label 'Clear' -Items @('A', 'B', 'C')
        Clear-UiList -Variable 'testClear'
        $items = Get-UiListItems -Variable 'testClear'
        $items.Count | Should -Be 0
    }

    It 'New-UiSlider creates a slider with correct range' {
        New-UiSlider -Variable 'testVolume' -Label 'Volume' -Minimum 0 -Maximum 100 -Default 75

        $proxy = $script:session.GetSafeVariable('testVolume')
        $proxy.Control.Minimum | Should -Be 0
        $proxy.Control.Maximum | Should -Be 100
        $proxy.Control.Value   | Should -Be 75
    }

    It 'New-UiDatePicker defaults to today' {
        $today = [datetime]::Today
        New-UiDatePicker -Variable 'testDate' -Label 'Pick Date'

        $proxy = $script:session.GetSafeVariable('testDate')
        $proxy.Control.SelectedDate.Date | Should -Be $today
    }
}

# Own session, so these -Variable names never collide with the selection block above.
Describe 'Control Creation - Progress Bars' {
    BeforeAll {
        $global:WarningPreference = 'SilentlyContinue'
        $script:sessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:sessionId)
        $script:session = [PsUi.SessionManager]::Current
        $script:session.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterAll {
        $global:WarningPreference = 'Continue'
        [PsUi.SessionManager]::DisposeSession($script:sessionId)
    }

    It 'New-UiProgress creates indeterminate progress bar' {
        New-UiProgress -Variable 'testProg' -Indeterminate
        $proxy = $script:session.GetSafeVariable('testProg')
        $proxy.Control.IsIndeterminate | Should -BeTrue
    }

    It 'New-UiProgress defaults to determinate with 0 value' {
        New-UiProgress -Variable 'testProg2'
        $proxy = $script:session.GetSafeVariable('testProg2')
        $proxy.Control.IsIndeterminate | Should -BeFalse
        $proxy.Control.Value           | Should -Be 0
    }

    It 'New-UiProgress honors custom Min/Max/Default and clamps Default in range' {
        New-UiProgress -Variable 'testProg3' -Minimum 10 -Maximum 50 -Default 999
        $proxy = $script:session.GetSafeVariable('testProg3')
        $proxy.Control.Minimum | Should -Be 10
        $proxy.Control.Maximum | Should -Be 50
        # Clamped to Maximum.
        $proxy.Control.Value   | Should -Be 50
    }

    It 'New-UiProgress rejects Maximum <= Minimum' {
        { New-UiProgress -Variable 'testProgBad' -Minimum 100 -Maximum 50 } | Should -Throw

        # The guard is -le, and only this half tells -le from -lt.
        { New-UiProgress -Variable 'testProgSame' -Minimum 50 -Maximum 50 } | Should -Throw
    }

    It 'New-UiProgress stores severity metadata in Tag' {
        New-UiProgress -Variable 'testProgSev' -Severity Warning
        $proxy = $script:session.GetSafeVariable('testProgSev')
        $proxy.Control.Tag.Severity | Should -Be 'Warning'
        $proxy.Control.Tag.BrushTag | Should -Be 'WarningBrush'
    }

    It 'New-UiProgress with -Label populates the Tag.LabelBlock' {
        New-UiProgress -Variable 'testProgLbl' -Label 'Loading'
        $proxy = $script:session.GetSafeVariable('testProgLbl')
        $proxy.Control.Tag.LabelBlock      | Should -Not -BeNullOrEmpty
        $proxy.Control.Tag.LabelBlock.Text | Should -Be 'Loading'
    }

    It 'New-UiProgress with -ShowValue populates the Tag.ValueBlock' {
        New-UiProgress -Variable 'testProgVal' -ShowValue -Default 25
        $proxy = $script:session.GetSafeVariable('testProgVal')
        $proxy.Control.Tag.ValueBlock      | Should -Not -BeNullOrEmpty
        $proxy.Control.Tag.ValueBlock.Text | Should -Be '25%'
    }

    It 'New-UiProgress ShowValue text updates when Value changes' {
        New-UiProgress -Variable 'testProgFmt' -ShowValue -ValueFormat '{0}/{1}' -Maximum 200
        $proxy               = $script:session.GetSafeVariable('testProgFmt')
        $proxy.Control.Value = 75
        $proxy.Control.Tag.ValueBlock.Text | Should -Be '75/200'
    }

    It 'New-UiProgress warns and strips Tag from -WPFProperties' {
        $warnings = @()
        New-UiProgress -Variable 'testProgTag' -WPFProperties @{ Tag = 'hijack' } -WarningVariable warnings -WarningAction SilentlyContinue
        $proxy = $script:session.GetSafeVariable('testProgTag')
        # Tag must still be the metadata hashtable, not the string that was passed
        $proxy.Control.Tag | Should -BeOfType [hashtable]
        $warnings.Count    | Should -BeGreaterThan 0
    }

    It 'Set-UiProperties refuses a Tag on a control that already holds one' {
        # Eighteen controls keep their own bookkeeping on Tag and only three of them guarded it, so the guard sits at the one place they all go through.
        $warnings    = @()
        $control     = [System.Windows.Controls.TextBlock]::new()
        $control.Tag = @{ BrushTag = 'AccentBrush' }
        InModuleScope PsUi -Parameters @{ Control = $control } {
            param($Control)
            Set-UiProperties -Control $Control -Properties @{ Tag = 'hijack'; FontSize = 19 }
        } -WarningVariable warnings -WarningAction SilentlyContinue

        $control.Tag      | Should -BeOfType [hashtable]
        $control.FontSize | Should -Be 19
        $warnings.Count   | Should -BeGreaterThan 0
    }

    It 'Set-UiProperties still lets a Tag through on a control that has none' {
        # A deliberate Tag is a real thing to want. Only one already holding the control's own state is defended.
        $control = [System.Windows.Controls.TextBlock]::new()
        InModuleScope PsUi -Parameters @{ Control = $control } {
            param($Control)
            Set-UiProperties -Control $Control -Properties @{ Tag = 'mine' }
        }
        $control.Tag | Should -Be 'mine'
    }

    It 'New-UiButton takes a width smaller than its own padding' {
        # The ViewBox constraint is the width minus sixteen, and WPF throws outright on a negative Max, so anything under that crashed the build.
        { New-UiButton -Text 'x' -Width 12 -Action { } } | Should -Not -Throw
        { New-UiButton -Text 'y' -Width 120 -Height 4 -Action { } } | Should -Not -Throw
    }

    It 'New-UiButton -Height alone still scales its text to fit' {
        # A plain text button only ever got a ViewBox when given a width, so a short one with no width let the text overflow the height it was told to keep.
        $parent = (Get-UiSession).CurrentParent
        New-UiButton -Text 'z' -Height 16 -Action { }
        $button = $parent.Children[$parent.Children.Count - 1]
        $button.Content | Should -BeOfType [System.Windows.Controls.Viewbox]
        $button.Content.MaxHeight | Should -Be 8
    }

    It 'Set-UiProgress -Increment adds to current value and clamps to Maximum' {
        New-UiProgress -Variable 'testProgInc' -Maximum 10 -Default 8
        # 8 plus 5 is 13, which clamps back to the Maximum of 10.
        Set-UiProgress -Variable 'testProgInc' -Increment 5
        $proxy = $script:session.GetSafeVariable('testProgInc')
        $proxy.Control.Value | Should -Be 10
    }

    It 'Set-UiProgress -Value clamps below Minimum' {
        New-UiProgress -Variable 'testProgClampLo' -Minimum 5 -Maximum 10 -Default 7
        Set-UiProgress -Variable 'testProgClampLo' -Value -100
        $proxy = $script:session.GetSafeVariable('testProgClampLo')
        $proxy.Control.Value | Should -Be 5
    }

    It 'Set-UiProgress -Severity updates Tag.Severity and Tag.BrushTag' {
        New-UiProgress -Variable 'testProgRetint' -Severity Info
        Set-UiProgress -Variable 'testProgRetint' -Severity Error
        $proxy = $script:session.GetSafeVariable('testProgRetint')
        $proxy.Control.Tag.Severity | Should -Be 'Error'
        $proxy.Control.Tag.BrushTag | Should -Be 'ErrorBrush'
    }

    It 'Set-UiProgress -Label updates a label-equipped bar' {
        New-UiProgress -Variable 'testProgLabelUpd' -Label 'Initial'
        Set-UiProgress -Variable 'testProgLabelUpd' -Label 'Updated'
        $proxy = $script:session.GetSafeVariable('testProgLabelUpd')
        $proxy.Control.Tag.LabelBlock.Text | Should -Be 'Updated'
    }

    It 'Set-UiProgress with no parameters does nothing and does not throw' {
        New-UiProgress -Variable 'testProgNoop' -Default 42
        { Set-UiProgress -Variable 'testProgNoop' } | Should -Not -Throw
        $proxy = $script:session.GetSafeVariable('testProgNoop')
        $proxy.Control.Value | Should -Be 42
    }

    It 'Set-UiProgress against a name nothing registered walks away quietly' {
        # There is an early return for this and it had no test, so a throw creeping in would only ever surface in someone's window.
        { Set-UiProgress -Variable 'doesNotExist' -Value 50 } | Should -Not -Throw
    }

}

Describe 'Control Creation - List Controls' {
    BeforeAll {
        $global:WarningPreference = 'SilentlyContinue'
        $script:sessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:sessionId)
        $script:session = [PsUi.SessionManager]::Current
        $script:session.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterAll {
        $global:WarningPreference = 'Continue'
        [PsUi.SessionManager]::DisposeSession($script:sessionId)
    }

    It 'New-UiList creates a list with static items' {
        New-UiList -Variable 'testServers' -Items @('srv01', 'srv02', 'srv03')

        $control = $script:session.GetControl('testServers')
        $control | Should -Not -BeNullOrEmpty
        $control | Should -BeOfType [System.Windows.Controls.ListBox]
        $control.Items.Count | Should -Be 3
    }

    It 'New-UiList supports MultiSelect mode' {
        New-UiList -Variable 'testMulti' -Items @('A', 'B', 'C') -MultiSelect

        $control = $script:session.GetControl('testMulti')
        $control.SelectionMode | Should -Be 'Extended'
    }

    It 'New-UiList rejects Items and ItemsSource together' {
        {
            New-UiList -Variable 'conflicted' -Items @(1, 2) -ItemsSource @(3, 4)
        } | Should -Throw '*cannot use both*'
    }

    # Regression cover for the -Items seed fix in New-UiList.
    It '-Items registers an AsyncObservableCollection' {
        New-UiList -Variable 'wrapStatic' -Items @('a', 'b', 'c')
        $coll = $script:session.GetListCollection('wrapStatic')
        $coll.GetType().FullName | Should -Match '^PsUi\.AsyncObservableCollection'
        $coll.Count | Should -Be 3
    }

    It 'the no-items branch registers an AsyncObservableCollection' {
        New-UiList -Variable 'wrapEmpty'
        $coll = $script:session.GetListCollection('wrapEmpty')
        $coll.GetType().FullName | Should -Match '^PsUi\.AsyncObservableCollection'
        $coll.Count | Should -Be 0
    }

    It 'the list collection never reads as grid owned' {
        # Builds its own list, because reading a sibling It's leaves this red when the file runs one test.
        New-UiList -Variable 'ownProbe' -Items @('a')
        $coll = $script:session.GetListCollection('ownProbe')
        InModuleScope PsUi -Parameters @{ Coll = $coll } {
            param($Coll)
            Test-UiDataGridOwned -Collection $Coll | Should -BeFalse
        }
    }

    It '-Items with one empty string keeps the item' {
        # @('') was falsy under the old check and fell into the no items branch, dropping the item.
        New-UiList -Variable 'wrapBlank' -Items @('')
        ($script:session.GetListCollection('wrapBlank')).Count | Should -Be 1
    }

    It '-ItemsSource with a plain ObservableCollection wraps and mirrors' {
        # Quiet because the repoint walk can't reach Pester locals, so it always warns here.
        $original = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $original.Add('seed')
        New-UiList -Variable 'wrapBound' -ItemsSource $original -WarningAction SilentlyContinue

        $wrap = $script:session.GetListCollection('wrapBound')
        $wrap.GetType().FullName | Should -Match '^PsUi\.AsyncObservableCollection'
        [object]::ReferenceEquals($wrap, $original) | Should -BeFalse

        Add-UiListItem -Variable 'wrapBound' -Item 'added'
        $wrap.Count     | Should -Be 2
        $original.Count | Should -Be 2
        $original[1]    | Should -Be 'added'
    }

    It '-ItemsSource with a fixed size array wraps without a mirror and Add works' {
        New-UiList -Variable 'wrapArray' -ItemsSource @('x', 'y') -WarningAction SilentlyContinue
        { Add-UiListItem -Variable 'wrapArray' -Item 'z' } | Should -Not -Throw
        ($script:session.GetListCollection('wrapArray')).Count | Should -Be 3
    }

    It '-ItemsSource passes an AsyncObservableCollection through by reference' {
        $async = [PsUi.AsyncObservableCollection[object]]::new()
        $async.Add('q')
        New-UiList -Variable 'wrapPass' -ItemsSource $async
        [object]::ReferenceEquals($script:session.GetListCollection('wrapPass'), $async) | Should -BeTrue
    }

    It 'New-UiList -NoBind leaves the script variable alone and still wraps the grid side' {
        # The probe below tests the resolver on its own. This is the same promise through the public builder, which is where a user meets it.
        $mine = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        New-UiList -Variable 'wrapNoBind' -ItemsSource $mine -NoBind
        $mine.GetType().FullName | Should -Match '^System\.Collections\.ObjectModel\.ObservableCollection'
        ($script:session.GetListCollection('wrapNoBind')).GetType().FullName | Should -Match '^PsUi\.AsyncObservableCollection'
    }

    It '-NoBind skips the repoint that auto bind performs' {
        # The walk starts two frames up and never sees a Pester It local, so call it from a module function.
        InModuleScope PsUi {
            function Invoke-ListResolveProbe {
                param($Source, [switch]$NoBind)
                Resolve-UiListSource -Source $Source -NoBind:$NoBind
            }

            try {
                $mine  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
                $bound = Invoke-ListResolveProbe -Source $mine
                $bound.Repointed.Count | Should -BeGreaterThan 0
                # A count alone cannot tell a correct walk from one starting on Resolve-UiListSource's own frame.
                [object]::ReferenceEquals($mine, $bound.Collection) | Should -BeTrue

                $yours = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
                $free  = Invoke-ListResolveProbe -Source $yours -NoBind
                $free.Repointed.Count | Should -Be 0
                $free.Collection.GetType().FullName | Should -Match '^PsUi\.AsyncObservableCollection'
            }
            finally { Remove-Item function:Invoke-ListResolveProbe -ErrorAction SilentlyContinue }
        }
    }

    It 'Remove-UiListItem with no -Item removes the selected row' {
        # Runs on the creating thread, so it pins the behavior and not the thread fix.
        New-UiList -Variable 'rmSelected' -Items @('keep', 'drop')
        $listBox              = $script:session.GetControl('rmSelected')
        $listBox.SelectedItem = $listBox.Items[1]
        Remove-UiListItem -Variable 'rmSelected'
        ($script:session.GetListCollection('rmSelected')).Count | Should -Be 1
        ($script:session.GetListCollection('rmSelected'))[0] | Should -Be 'keep'
    }
}

Describe 'New-UiImage Parameter Validation' {
    It 'Has mandatory -Path in Path parameter set' {
        $cmd       = Get-Command New-UiImage
        $pathParam = $cmd.Parameters['Path']
        $pathAttrs = $pathParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        ($pathAttrs | Where-Object { $_.Mandatory -eq $true }) | Should -Not -BeNullOrEmpty
    }

    It 'Has mandatory -Base64 in Base64 parameter set' {
        $cmd      = Get-Command New-UiImage
        $b64Param = $cmd.Parameters['Base64']
        $b64Attrs = $b64Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        ($b64Attrs | Where-Object { $_.Mandatory -eq $true }) | Should -Not -BeNullOrEmpty
    }

    It 'Path and Base64 are in different parameter sets' {
        # Adding Path to the Base64 set makes both sides arrays, and an array never equals a scalar.
        { New-UiImage -Path 'a.png' -Base64 'abc' } | Should -Throw '*Parameter set cannot be resolved*'
    }
}

Describe 'WPFProperties attached properties' -Tag 'RequiresSession' {
    BeforeAll {
        $script:wpSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:wpSessionId)
        $script:wpSession = [PsUi.SessionManager]::Current
        $script:wpSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterAll {
        [PsUi.SessionManager]::DisposeSession($script:wpSessionId)
    }

    It 'Grid.Row and Grid.Column land on the control' {
        # [Type]::GetType returned $null for every WPF type, so this skipped silently for years.
        $parent = $script:wpSession.CurrentParent
        New-UiPanel -Content { } -WPFProperties @{ 'Grid.Row' = 1; 'Grid.Column' = 2 }
        $child = $parent.Children[$parent.Children.Count - 1]
        [System.Windows.Controls.Grid]::GetRow($child) | Should -Be 1
        [System.Windows.Controls.Grid]::GetColumn($child) | Should -Be 2
    }

    It 'attached values convert like instance properties' {
        $parent = $script:wpSession.CurrentParent
        New-UiPanel -Content { } -WPFProperties @{ 'DockPanel.Dock' = 'Left'; 'Grid.Row' = '1' }
        $child = $parent.Children[$parent.Children.Count - 1]
        [System.Windows.Controls.DockPanel]::GetDock($child) | Should -Be ([System.Windows.Controls.Dock]::Left)
        [System.Windows.Controls.Grid]::GetRow($child) | Should -Be 1
    }

    It 'an unknown owner type skips without throwing' {
        # The per property catch hides everything, so Should -Not -Throw passes on a swallowed crash too.
        $records = New-UiPanel -Content { } -WPFProperties @{ 'Bogus.Thing' = 1 } -Verbose 4>&1 3>&1
        (@($records | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message -join '|') |
            Should -Match "Owner type 'Bogus' not found"
        @($records | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
    }
}
