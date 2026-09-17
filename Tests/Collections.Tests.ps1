#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# The observable collection wrap and the cross thread adds that go through it.
. (Join-Path $PSScriptRoot '_Setup.ps1')

BeforeAll { . (Join-Path $PSScriptRoot '_Setup.ps1') }

Describe 'AsyncObservableCollection - Mirror behavior' {

    BeforeEach {
        $script:disp = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    }

    It 'wrapper.Add pushes through to an attached ObservableCollection mirror' {
        $mirror  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($script:disp)
        $wrapper.AttachMirror($mirror)

        $wrapper.Add('a')
        $wrapper.Add('b')

        $wrapper.Count | Should -Be 2
        $mirror.Count  | Should -Be 2
        $mirror[0]     | Should -Be 'a'
        $mirror[1]     | Should -Be 'b'
    }

    It 'mirror.Add propagates back into the wrapper (INPC mirror)' {
        $mirror  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($script:disp)
        $wrapper.AttachMirror($mirror)

        $mirror.Add('a')
        $mirror.Add('b')

        $wrapper.Count | Should -Be 2
        $wrapper[0]    | Should -Be 'a'
        $wrapper[1]    | Should -Be 'b'
    }

    It 'wrapper CollectionChanged fires exactly once per Add (no mirror double-fire)' {
        $mirror  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($script:disp)
        $wrapper.AttachMirror($mirror)

        $state   = @{ Wrapper = 0; Mirror = 0 }
        $wrapper.add_CollectionChanged({ $state.Wrapper++ }.GetNewClosure())
        $mirror.add_CollectionChanged({ $state.Mirror++ }.GetNewClosure())

        $wrapper.Add('a')
        $state.Wrapper | Should -Be 1
        $state.Mirror  | Should -Be 1

        $mirror.Add('b')
        $state.Wrapper | Should -Be 2
        $state.Mirror  | Should -Be 2
    }

    It 'ReplaceAll fires exactly one Reset notification' {
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($script:disp)
        $wrapper.Add('seed1')
        $wrapper.Add('seed2')

        $state   = @{ Fires = 0; LastAction = $null }
        $handler = {
            param($sender, $eventArgs)
            $state.Fires++
            $state.LastAction = $eventArgs.Action
        }.GetNewClosure()
        $wrapper.add_CollectionChanged($handler)

        $items = [System.Collections.Generic.List[object]]@('a', 'b', 'c', 'd', 'e')
        $wrapper.ReplaceAll($items)

        $state.Fires      | Should -Be 1
        $state.LastAction | Should -Be ([System.Collections.Specialized.NotifyCollectionChangedAction]::Reset)
        $wrapper.Count    | Should -Be 5
    }

    It 'ArrayList mirror works one-way (wrapper.Add lands but Mirror.Add does not push back)' {
        $mirror  = [System.Collections.ArrayList]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($script:disp)
        $wrapper.AttachMirror($mirror)

        $wrapper.Add('a')
        $mirror.Count | Should -Be 1

        # ArrayList has no INPC so mirror side adds don't flow back.
        [void]$mirror.Add('zzz')
        $wrapper.Count | Should -Be 1
        $wrapper[0]    | Should -Be 'a'
    }

    It 'DetachMirror stops cross-firing in both directions' {
        $mirror  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($script:disp)
        $wrapper.AttachMirror($mirror)

        $wrapper.Add('a')
        $mirror.Count | Should -Be 1

        $wrapper.DetachMirror()

        $wrapper.Add('b')
        # mirror frozen at detach point
        $mirror.Count  | Should -Be 1
        $wrapper.Count | Should -Be 2

        # mirror no longer drives the wrap after detach
        $mirror.Add('z')
        $wrapper.Count | Should -Be 2
    }

    It 'IList.Add (cast-and-call) queues onto the owning thread via the virtual override' {
        # IList adds still queue onto the owning thread because InsertItem is overridden, not hidden.
        $mirror  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($script:disp)
        $wrapper.AttachMirror($mirror)

        # -as returns the same reference and PS picks the public Add, so reach the interface by reflection.
        $ilistAdd = [System.Collections.IList].GetMethod('Add')
        [void]$ilistAdd.Invoke($wrapper, @([object]'a'))

        $wrapper.Count | Should -Be 1
        $mirror.Count  | Should -Be 1
        $mirror[0]     | Should -Be 'a'
    }

    It 'wrapper.Remove syncs mirror (RemoveItem override path)' {
        $mirror  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($script:disp)
        $wrapper.AttachMirror($mirror)

        $wrapper.Add('keep')
        $wrapper.Add('drop')
        $wrapper.Add('also-keep')

        $removed = $wrapper.Remove('drop')
        $removed       | Should -BeTrue
        $wrapper.Count | Should -Be 2
        $mirror.Count  | Should -Be 2
        ($wrapper -join ',') | Should -Be 'keep,also-keep'
        ($mirror  -join ',') | Should -Be 'keep,also-keep'
    }

    It 'wrapper.RemoveAt syncs mirror' {
        $mirror  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($script:disp)
        $wrapper.AttachMirror($mirror)

        $wrapper.Add('a'); $wrapper.Add('b'); $wrapper.Add('c')
        $wrapper.RemoveAt(1)

        $wrapper.Count | Should -Be 2
        $mirror.Count  | Should -Be 2
        ($wrapper -join ',') | Should -Be 'a,c'
        ($mirror  -join ',') | Should -Be 'a,c'
    }

    It 'wrapper indexer Set syncs mirror (SetItem override path)' {
        $mirror  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($script:disp)
        $wrapper.AttachMirror($mirror)

        $wrapper.Add('a'); $wrapper.Add('b'); $wrapper.Add('c')
        $wrapper[1] = 'B'

        $wrapper[1] | Should -Be 'B'
        $mirror[1]  | Should -Be 'B'
        $wrapper.Count | Should -Be 3
        $mirror.Count  | Should -Be 3
    }

    It 'wrapper.Clear syncs mirror (ClearItems override path)' {
        $mirror  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($script:disp)
        $wrapper.AttachMirror($mirror)

        $wrapper.Add('a'); $wrapper.Add('b'); $wrapper.Add('c')
        $wrapper.Clear()

        $wrapper.Count | Should -Be 0
        $mirror.Count  | Should -Be 0
    }

    It 'ReplaceAll on a wrapper with a mirror clears + refills the mirror' {
        $mirror  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($script:disp)
        $wrapper.AttachMirror($mirror)

        $wrapper.Add('old1'); $wrapper.Add('old2')
        $mirror.Count | Should -Be 2

        $replacement = [System.Collections.Generic.List[object]]@('new1', 'new2', 'new3')
        $wrapper.ReplaceAll($replacement)

        $wrapper.Count | Should -Be 3
        $mirror.Count  | Should -Be 3
        ($wrapper -join ',') | Should -Be 'new1,new2,new3'
        ($mirror  -join ',') | Should -Be 'new1,new2,new3'
    }
}

Describe 'AsyncObservableCollection - adds from another thread' {

    It 'wrapper.Add from a background MTA runspace queues onto the UI thread and pushes mirror' {
        $disp    = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
        $mirror  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($disp)
        $wrapper.AttachMirror($mirror)

        # Spawn a real background runspace that calls $wrapper.Add.
        # $wrapper.Add sees CheckAccess=false, queues an Invoke to the UI thread, blocks on it.
        $bg = Start-BackgroundAdd -Wrapper $wrapper -Item 'bg-item'
        Wait-BackgroundAdd -Invocation $bg
        (Complete-BackgroundAdd -Invocation $bg) | Should -BeTrue

        $wrapper.Count | Should -Be 1
        $wrapper[0]    | Should -Be 'bg-item'
        $mirror.Count  | Should -Be 1
        $mirror[0]     | Should -Be 'bg-item'
    }

}

Describe 'New-UiList - cross thread mutation' {
    BeforeAll {
        $script:xtSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:xtSessionId)
        $script:xtSession = [PsUi.SessionManager]::Current
        $script:xtSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterAll {
        [PsUi.SessionManager]::DisposeSession($script:xtSessionId)
    }

    It 'a background add against an -Items list lands instead of throwing' {
        # Red before the fix. The registered collection's Add is the last line of Add-UiListItem.
        New-UiList -Variable 'xtList' -Items @('one', 'two') -WarningAction SilentlyContinue
        $coll = $script:xtSession.GetListCollection('xtList')

        $bg = Start-BackgroundAdd -Wrapper $coll -Item 'from-background'
        Wait-BackgroundAdd -Invocation $bg
        (Complete-BackgroundAdd -Invocation $bg) | Should -BeTrue

        # Complete-BackgroundAdd swallows EndInvoke errors, so assert on contents.
        $coll.Count | Should -Be 3
        $coll[2]    | Should -Be 'from-background'
    }

    It 'a background add against a wrapped -ItemsSource reaches wrap and original' {
        $original = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $original.Add('seed')
        New-UiList -Variable 'xtBound' -ItemsSource $original -WarningAction SilentlyContinue
        $wrap = $script:xtSession.GetListCollection('xtBound')

        $bg = Start-BackgroundAdd -Wrapper $wrap -Item 'bg'
        Wait-BackgroundAdd -Invocation $bg
        (Complete-BackgroundAdd -Invocation $bg) | Should -BeTrue

        $wrap.Count     | Should -Be 2
        $original.Count | Should -Be 2
    }
}
