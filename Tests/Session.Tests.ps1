#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Session isolation and the implicit window build.
. (Join-Path $PSScriptRoot '_Setup.ps1')

BeforeAll { . (Join-Path $PSScriptRoot '_Setup.ps1') }

# Two windows open at once shouldn't step on each other's controls
Describe 'Session Isolation' {
    It 'Hands back the session it just made' {
        # The isolation tests below all lean on this round trip and none of them assert it.
        $id = [PsUi.SessionManager]::CreateSession()
        try {
            [PsUi.SessionManager]::SetCurrentSession($id)
            [PsUi.SessionManager]::Current           | Should -Not -BeNullOrEmpty
            [PsUi.SessionManager]::Current.SessionId | Should -Be $id
        }
        finally { [PsUi.SessionManager]::DisposeSession($id) }
    }

    It 'Stores a control through AddControlSafe and gives it back' {
        # Every control in the module registers this way, and it was only ever setup for something else.
        $id = [PsUi.SessionManager]::CreateSession()
        try {
            [PsUi.SessionManager]::SetCurrentSession($id)
            $session = [PsUi.SessionManager]::Current
            $session.AddControlSafe('storedButton', [System.Windows.Controls.Button]::new())
            $session.GetControl('storedButton') | Should -Not -BeNullOrEmpty
        }
        finally { [PsUi.SessionManager]::DisposeSession($id) }
    }

    It 'Should maintain separate state for multiple sessions' {
        $session1Id = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($session1Id)
        $session1               = [PsUi.SessionManager]::Current
        $session1.CurrentParent = [System.Windows.Controls.StackPanel]::new()

        $textBox1 = [System.Windows.Controls.TextBox]@{ Text = 'Session1Value' }
        $session1.AddControlSafe('sharedName', $textBox1)

        $session2Id = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($session2Id)
        $session2               = [PsUi.SessionManager]::Current
        $session2.CurrentParent = [System.Windows.Controls.StackPanel]::new()

        $textBox2 = [System.Windows.Controls.TextBox]@{ Text = 'Session2Value' }
        $session2.AddControlSafe('sharedName', $textBox2)

        try {
            [PsUi.SessionManager]::SetCurrentSession($session1Id)
            $retrieved1 = [PsUi.SessionManager]::Current.GetSafeVariable('sharedName')
            $retrieved1.Text | Should -Be 'Session1Value'

            [PsUi.SessionManager]::SetCurrentSession($session2Id)
            $retrieved2 = [PsUi.SessionManager]::Current.GetSafeVariable('sharedName')
            $retrieved2.Text | Should -Be 'Session2Value'
        }
        finally {
            [PsUi.SessionManager]::DisposeSession($session1Id)
            [PsUi.SessionManager]::DisposeSession($session2Id)
        }
    }

    It 'Should not leak controls between sessions' {
        $session1Id = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($session1Id)
        $session1 = [PsUi.SessionManager]::Current

        $button = [System.Windows.Controls.Button]@{ Content = 'OnlyInSession1' }
        $session1.AddControlSafe('uniqueButton', $button)

        $session2Id = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($session2Id)
        $session2 = [PsUi.SessionManager]::Current

        try {
            $retrieved = $session2.GetControl('uniqueButton')
            $retrieved | Should -BeNullOrEmpty
        }
        finally {
            [PsUi.SessionManager]::DisposeSession($session1Id)
            [PsUi.SessionManager]::DisposeSession($session2Id)
        }
    }

    It 'Should track correct active session count' {
        $initialCount = [PsUi.SessionManager]::ActiveSessionCount

        $id1 = [PsUi.SessionManager]::CreateSession()
        $id2 = [PsUi.SessionManager]::CreateSession()
        $id3 = [PsUi.SessionManager]::CreateSession()

        try { [PsUi.SessionManager]::ActiveSessionCount | Should -Be ($initialCount + 3) }
        finally {
            [PsUi.SessionManager]::DisposeSession($id1)
            [PsUi.SessionManager]::DisposeSession($id2)
            [PsUi.SessionManager]::DisposeSession($id3)
        }

        [PsUi.SessionManager]::ActiveSessionCount | Should -Be $initialCount
    }
}

# Private functions aren't exported, so they need module scope to reach.
InModuleScope PsUi {
    # A control with no window builds one from the calling script's text.
    # Opening it needs a screen and the stop would end the run, so both live in scratch\Drive-Window.ps1.
    Describe 'Get-UiImplicitSpan' {
        BeforeAll {
            # Stand ins that belong to the module, so the frame walk reads them as PsUi and climbs out to the sample.
            $script:fakeControlNames = 'New-FakeUiControl', 'New-FakeUiWidget'
            $module   = $ExecutionContext.SessionState.Module
            $commands = Get-UiCommandList
            foreach ($name in $script:fakeControlNames) {
                $body = [scriptblock]::Create("Get-UiImplicitSpan -CallerName '$name'")
                Set-Item "function:script:$name" -Value $module.NewBoundScriptBlock($body)
                [void]$commands.Add($name)
            }

            # A stand in maker, named on the list and doing nothing. A real one would put a modal up and hang the run when the check that stops it breaks.
            # Show rather than New, so the repeat check does not fire first on the verb and assert the wrong message.
            [void](Get-UiWindowMakerList).Add('Show-FakeUiDialog')
            Set-Item 'function:script:Show-FakeUiDialog' -Value $module.NewBoundScriptBlock({ })

            # Each sample gets its own script text, the way a pasted block does.
            function Get-SampleSpan {
                param([string]$Source)
                @(& ([scriptblock]::Create($Source)))[0]
            }
        }

        AfterAll {
            $commands = Get-UiCommandList
            foreach ($name in $script:fakeControlNames) {
                [void]$commands.Remove($name)
                Remove-Item "function:$name" -ErrorAction SilentlyContinue
            }
            [void](Get-UiWindowMakerList).Remove('Show-FakeUiDialog')
            Remove-Item function:Show-FakeUiDialog -ErrorAction SilentlyContinue
            Remove-Item function:Get-SampleSpan -ErrorAction SilentlyContinue

            # The command list and the functions are module state and so is this, so it goes too.
            Remove-Variable -Name fakeControlNames -Scope Script
        }

        # -Be rather than -Match. A finder returning the whole script would pass a -Match.
        It 'Covers a contiguous run of controls' {
            $source = "New-FakeUiControl 'a'`nNew-FakeUiWidget 'b'"
            $span   = Get-SampleSpan $source
            $span.Text | Should -Be $source
            $span.StartLine | Should -Be 1
        }

        It 'Keeps a plain statement sitting between two controls' {
            $source = "New-FakeUiControl 'a'`n`$x = 2 + 2`nNew-FakeUiWidget 'b'"
            $span   = Get-SampleSpan $source
            $span.Text | Should -Be $source
        }

        It 'Starts at the control, not at the setup above it' {
            $span = Get-SampleSpan "`$items = 1, 2, 3`nNew-FakeUiControl `$items"
            $span.StartLine | Should -Be 2
            $span.Text | Should -Be 'New-FakeUiControl $items'
        }

        It 'Takes the whole loop when a control sits inside one' {
            $source = "foreach (`$i in 1..2) { New-FakeUiControl `$i }"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Takes the whole if when a control sits in a branch' {
            $source = "if (`$true) { New-FakeUiControl 'then' } else { New-FakeUiControl 'else' }"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Takes the enclosing loop when a helper builds the control' {
            $span = Get-SampleSpan "function Add-Row { param(`$i) New-FakeUiControl `$i }`nforeach (`$i in 1..2) { Add-Row `$i }"
            $span.StartLine | Should -Be 2
            $span.Text | Should -Be 'foreach ($i in 1..2) { Add-Row $i }'
        }

        It 'Covers both controls written on one line' {
            $source = "New-FakeUiControl 'a'; New-FakeUiWidget 'b'"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Finds the statements when the control sits in a process block' {
            $span = Get-SampleSpan "process { New-FakeUiControl 'a'; New-FakeUiWidget 'b' }"
            $span.Text | Should -Be "New-FakeUiControl 'a'; New-FakeUiWidget 'b'"
        }

        It 'Finds the statements when the control sits in a begin block' {
            $span = Get-SampleSpan "begin { New-FakeUiControl 'a' } end { 1 }"
            $span.Text | Should -Be "New-FakeUiControl 'a'"
        }

        It 'Stops before a window opener wrapped in a ForEach-Object' {
            # The block runs while the statement runs, so the opener would go up while the implicit window is still being built. if ($false) keeps it from actually opening here.
            $source = "New-FakeUiControl 'a'`nif (`$false) { 1..2 | ForEach-Object { New-UiWindow -Title 'x' -Content { } } }`nNew-FakeUiWidget 'b'"
            (Get-SampleSpan $source).Text | Should -Be "New-FakeUiControl 'a'"
        }

        It 'Reaches no further for a control named only inside a stored block' {
            # An assignment keeps the block for later, so nothing in it gets built and there is no reason to reach it.
            $source = "New-FakeUiControl 'a'`n`$onClick = { New-FakeUiWidget 'ghost' }"
            (Get-SampleSpan $source).Text | Should -Be "New-FakeUiControl 'a'"
        }

        It 'Stops before a command that opens a window of its own' {
            $span = Get-SampleSpan "New-FakeUiControl 'a'`nif (`$false) { New-UiWindow -Title 'x' -Content { } }`nNew-FakeUiWidget 'b'"
            $span.Text | Should -Be "New-FakeUiControl 'a'"
        }

        It 'Reaches past a window maker that only appears inside a scriptblock argument' {
            # An -Action does not run at build time. Drop the nested filter and this stops at statement 0.
            $source = "New-FakeUiControl -Action { New-UiWindow -Title 'x' -Content { } }`nNew-FakeUiWidget 'b'"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Keeps a control built inside a ForEach-Object block' {
            # ForEach-Object runs its block on the spot, so those controls are built now and belong in the window.
            $source = "New-FakeUiControl 'a'`n'x','y' | ForEach-Object { New-FakeUiWidget `$_ }"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Stops before the native object picker' {
            # Show-WindowsObjectPicker is a modal that does not answer to Show-Ui*, so it needs its own line on the maker list.
            $source = "New-FakeUiControl 'a'`nif (`$false) { Show-WindowsObjectPicker -ObjectType User }`nNew-FakeUiWidget 'b'"
            (Get-SampleSpan $source).Text | Should -Be "New-FakeUiControl 'a'"
        }

        It 'Reaches past a helper defined after the control' {
            # A function body does not run where it is written, so a window inside one must not end the read.
            $source = "New-FakeUiControl 'a'`nfunction Open-Child { New-UiWindow -Title 'c' -Content { } }`nNew-FakeUiWidget 'b'"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Keeps every call to a helper that builds controls' {
            # Add-Row is not a PsUi command, so without the helper scan only the first call landed in the window.
            $source = "function Add-Row { param(`$i) New-FakeUiWidget `$i }`nNew-FakeUiControl 'a'`nAdd-Row 1`nAdd-Row 2"
            (Get-SampleSpan $source).Text | Should -Be "New-FakeUiControl 'a'`nAdd-Row 1`nAdd-Row 2"
        }

        It 'Keeps calling a helper whose button opens a window' {
            # The window sits inside the button's -Action, so the helper builds and does not open. A raw body scan read it as an opener and stopped at the first call.
            $source = "function Add-Row { param(`$i) New-FakeUiWidget -Action { New-UiWindow -Title 'd' -Content { } } }`nNew-FakeUiControl 'a'`nAdd-Row 1`nAdd-Row 2"
            (Get-SampleSpan $source).Text | Should -Be "New-FakeUiControl 'a'`nAdd-Row 1`nAdd-Row 2"
        }

        It 'Stops before a helper that opens a window' {
            # Same scan, other direction. Calling Show-It has to stop the read the way New-UiWindow does.
            $source = "New-FakeUiControl 'a'`nfunction Show-It { New-UiWindow -Title 'x' -Content { } }`nif (`$false) { Show-It }`nNew-FakeUiWidget 'b'"
            (Get-SampleSpan $source).Text | Should -Be "New-FakeUiControl 'a'"
        }

        It 'Reaches a helper that only calls another helper' {
            # Add-Rows mentions no PsUi command itself. One hop was as far as the scan looked, so everything after it went missing.
            $source = "function Add-Row { param(`$i) New-FakeUiWidget `$i }`nfunction Add-Rows { Add-Row 1; Add-Row 2 }`nNew-FakeUiControl 'a'`nAdd-Rows"
            (Get-SampleSpan $source).Text | Should -Be "New-FakeUiControl 'a'`nAdd-Rows"
        }

        It 'Stops before a helper that only calls a window opener' {
            $source = "function Show-It { New-UiWindow -Title 'x' -Content { } }`nfunction Show-All { Show-It }`nNew-FakeUiControl 'a'`nif (`$false) { Show-All }`nNew-FakeUiWidget 'b'"
            (Get-SampleSpan $source).Text | Should -Be "New-FakeUiControl 'a'"
        }

        It 'Converges on a chain declared backwards' {
            # Three links, outermost first, so each pass can settle only one of them.
            $source = "function Add-Table { Add-Rows }`nfunction Add-Rows { Add-Row 1 }`nfunction Add-Row { param(`$i) New-FakeUiWidget `$i }`nNew-FakeUiControl 'a'`nAdd-Table"
            (Get-SampleSpan $source).Text | Should -Be "New-FakeUiControl 'a'`nAdd-Table"
        }

        It 'Refuses when a write already ran in the same loop' {
            # The whole foreach becomes the window content, so Set-Variable would run a second time.
            $source = "foreach (`$i in 1..2) { Set-Variable -Name seen -Value `$i; New-FakeUiControl `$i }"
            { Get-SampleSpan $source } | Should -Throw '*sits inside a foreach, which already ran Set-Variable*'
        }

        It 'Counts a write after the control when the statement loops' {
            # Trip one ran the whole body before trip two reached the control.
            $source = "foreach (`$i in 1..2) { New-FakeUiControl `$i; Set-Variable -Name seen -Value `$i }"
            { Get-SampleSpan $source } | Should -Throw '*already ran Set-Variable*'
        }

        It 'Leaves a write after the control alone when nothing loops' {
            $source = "if (`$true) { New-FakeUiControl 'a'; Set-Variable -Name seen -Value 1 }"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Lets a read in the loop header through' {
            $source = "foreach (`$n in (Get-Date).Year) { New-FakeUiControl `$n }"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Judges an alias by the command behind it' {
            $source = "foreach (`$i in 1..2) { sv seen `$i; New-FakeUiControl `$i }"
            { Get-SampleSpan $source } | Should -Throw '*already ran Set-Variable*'
        }

        It 'Lets a loop make a value for each control' {
            # These carry a mutating verb and hand back an object. Refusing them refuses the ordinary way to build a row per item.
            foreach ($maker in 'New-Object PSObject', 'New-Guid', 'New-TimeSpan -Seconds 1') {
                $source = "foreach (`$i in 1..2) { `$v = $maker; New-FakeUiControl `$i }"
                (Get-SampleSpan $source).Text | Should -Be $source -Because "$maker only makes a value"
            }
        }

        It 'Lets a loop over a csv build controls' {
            $csv = Join-Path $TestDrive 'rows.csv'
            Set-Content -Path $csv -Value "Name`nada`nbee"
            $source = "foreach (`$row in (Import-Csv '$csv')) { New-FakeUiControl `$row.Name }"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Leaves a write in the arm the run never took alone' {
            $source = "if (`$false) { Set-Variable -Name seen -Value 1 } else { New-FakeUiControl 'a' }"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Counts a write in another arm when a loop can take both' {
            # An earlier trip round the loop could have gone down the other arm, so inside one the arm skip stands down.
            $source = "foreach (`$i in 1..2) { if (`$i -gt 1) { Set-Variable -Name seen -Value `$i } else { New-FakeUiControl `$i } }"
            { Get-SampleSpan $source } | Should -Throw '*already ran Set-Variable*'
        }

        It 'Counts an Add-Member in the loop' {
            # The object it changes can outlive the statement, and a second pass over the same one is a duplicate member error.
            $source = "`$row = [pscustomobject]@{ N = 0 }`nforeach (`$i in 1..2) { Add-Member -InputObject `$row -NotePropertyName Extra -NotePropertyValue `$i; New-FakeUiControl `$i }"
            { Get-SampleSpan $source } | Should -Throw '*already ran Add-Member*'
        }

        It 'Leaves a write above a ForEach-Object pipeline alone' {
            # The block and the pipeline holding it arrive as two frames over one Ast, and the outer one used to be scanned from the top of the file.
            $source = "Set-Variable -Name seen -Value 0`n1..2 | ForEach-Object { New-FakeUiControl `$_ }"
            (Get-SampleSpan $source).Text | Should -Be '1..2 | ForEach-Object { New-FakeUiControl $_ }'
        }

        It 'Ignores a write inside a block handed to a control' {
            # An -Action runs at click time inside the window, and PsUi is the one running it.
            $source = "foreach (`$i in 1..2) { New-FakeUiControl `$i -Action { Set-Variable -Name seen -Value `$i } }"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Gives up when the position and the frame come from different text' {
            # Invoke-Expression compiles its own scriptblock, so the offsets would cut from the wrong source.
            Get-SampleSpan "Invoke-Expression `"New-FakeUiControl 'ie'`"" | Should -BeNullOrEmpty
        }

        It 'Keeps a control built inside a ForEach method block' {
            # The block hangs off the array rather than off a command, and reading only the command parent dropped every name inside it.
            $source = "New-FakeUiControl 'a'`n(1..2).ForEach({ New-FakeUiWidget `$_ })"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Keeps a control built inside a Where method block' {
            $source = "New-FakeUiControl 'a'`n(1..2).Where({ New-FakeUiWidget `$_ })"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Reaches the definition when the control is built through a stored block' {
            # The read used to start at the call, leaving the assignment out, so the window rebuilt with an empty variable and came up with nothing in it.
            $source = "`$sb = { New-FakeUiControl 'x' }`n& `$sb"
            (Get-SampleSpan $source).Text | Should -Be $source
        }

        It 'Still starts at the control when the setup above it is only a value' {
            # The reach back is for a block the statement runs, not for anything the statement happens to mention.
            $source = "`$items = 1, 2, 3`nNew-FakeUiControl `$items"
            (Get-SampleSpan $source).Text | Should -Be "New-FakeUiControl `$items"
        }

        It 'Keeps going past a helper that only stores the block it was handed' {
            # Nothing in Use-Later runs the block, so the dialog named inside it never opens and must not end the read.
            $source = "function Use-Later { param([scriptblock]`$Cb) `$script:kept = `$Cb }`nNew-FakeUiControl 'a'`nUse-Later -Cb { Show-FakeUiDialog }`nNew-FakeUiWidget 'b'"
            (Get-SampleSpan $source).Text | Should -Be "New-FakeUiControl 'a'`nUse-Later -Cb { Show-FakeUiDialog }`nNew-FakeUiWidget 'b'"
        }

        It 'Stops before a helper that runs the block it was handed' {
            # Run-Now does call it, so the dialog really does go up and the read has to stop first.
            $source = "function Run-Now { param([scriptblock]`$Cb) & `$Cb }`nNew-FakeUiControl 'a'`nRun-Now -Cb { Show-FakeUiDialog }`nNew-FakeUiWidget 'b'"
            (Get-SampleSpan $source).Text | Should -Be "New-FakeUiControl 'a'"
        }

        It 'Refuses when a window maker shares the statement with the control' {
            # Both get cut into the content whole, and there is no trimming a maker out of the middle of a loop body.
            $source = "foreach (`$i in 1..2) { New-FakeUiControl `$i; Show-FakeUiDialog }"
            { Get-SampleSpan $source } | Should -Throw '*same statement as Show-FakeUiDialog*'
        }

        It 'Stops rather than refusing when the maker is in the next statement' {
            $source = "New-FakeUiControl 'a'`nShow-FakeUiDialog`nNew-FakeUiWidget 'b'"
            (Get-SampleSpan $source).Text | Should -Be "New-FakeUiControl 'a'"
        }

        It 'Counts a write written with its module in front of it' {
            # The verb test reads from the start of the string, and a qualifier put a dot and a backslash where the dash was meant to be.
            $source = "foreach (`$i in 1..2) { Microsoft.PowerShell.Utility\Set-Variable -Name seen -Value `$i; New-FakeUiControl `$i }"
            { Get-SampleSpan $source } | Should -Throw '*already ran Set-Variable*'
        }

        It 'Counts a redirect that already wrote a file' {
            # A redirect hangs off the command rather than being one, so a scan that only reads command names never saw the write.
            # The sample really does run the redirect before the control throws, so it writes under TestDrive rather than wherever the suite happened to start.
            $target = (Join-Path $TestDrive 'redirected.txt').Replace('\', '\\')
            $source = "foreach (`$i in 1..2) { Write-Output `$i > '$target'; New-FakeUiControl `$i }"
            { Get-SampleSpan $source } | Should -Throw '*already ran a redirect*'
        }

        It 'Reads a stored block the same way inside a helper as at the top level' {
            # The helper body scan ran without the storer set, so a block handed to a helper that only keeps it read as run, and the helper around it turned into a window opener.
            $source = "function Add-Tab { param([scriptblock]`$Body) `$kept = `$Body }`nfunction Setup { Add-Tab { Show-FakeUiDialog }; New-FakeUiControl 'a' }`nSetup"
            { Get-SampleSpan $source } | Should -Not -Throw
        }

        It 'Lets a stream thrown away at $null through' {
            # The twin of the test above. 2>$null is a FileRedirectionAst like any other and writes nothing, and counting it turned the everyday way to quieten a command into a dead window.
            $source = "foreach (`$i in 1..2) { Get-Item 'variable:doesNotExist' 2>`$null; New-FakeUiControl `$i }"
            { Get-SampleSpan $source } | Should -Not -Throw
        }

        It 'Counts a write an inline invoked block already ran' {
            # { }.Invoke() runs where it stands, and reading it as a stored block hid the write inside it from the repeat check.
            $source = "foreach (`$i in 1..2) { { Set-Variable -Name seen -Value 1 }.Invoke(); New-FakeUiControl `$i }"
            { Get-SampleSpan $source } | Should -Throw '*already ran Set-Variable*'
        }

        It 'Keeps a control built through a block invoked after it' {
            # A call through a variable has no command name, so the forward scan walked straight past it and left the controls inside out of the window.
            $source = "`$foot = { New-FakeUiControl 'b' }`nNew-FakeUiControl 'a'`n& `$foot"
            (Get-SampleSpan $source).Text | Should -BeLike '*& $foot*'
        }

        It 'Reaches back for the definition of a block invoked after the control' {
            # The assignment has to come along as well, or the window runs & $null.
            $source = "`$foot = { New-FakeUiControl 'b' }`nNew-FakeUiControl 'a'`n& `$foot"
            (Get-SampleSpan $source).Text | Should -BeLike '$foot = {*'
        }

        It 'Stops before a window maker inside a block invoked after the control' {
            # The stand in maker, because the sample really runs and a real one would put a modal up and hang the suite.
            # The control after the call is what proves the stop. A scan that cannot see into the block walks past it and picks that control up.
            $source = "`$open = { Show-FakeUiDialog }`nNew-FakeUiControl 'a'`n& `$open`nNew-FakeUiControl 'c'"
            (Get-SampleSpan $source).Text | Should -Not -BeLike "*'c'*"
        }

        It 'Refuses a window maker sitting between the control and the block it was built from' {
            # The reach sweeps those lines into the window and they get the same maker check the control's own statement gets.
            $source = "`$foot = { New-FakeUiControl 'b' }`nShow-FakeUiDialog`nNew-FakeUiControl 'a'`n& `$foot"
            { Get-SampleSpan $source } | Should -Throw '*sits between the two*'
        }

        It 'Skips a function defined between the control and the block it was built from' {
            # A definition runs nothing, so a write in its body is not a write that already ran.
            $source = "`$render = { New-FakeUiControl 'x' }`nfunction Save-Log { Set-Variable -Name seen -Value 1 }`n& `$render"
            { Get-SampleSpan $source } | Should -Not -Throw
        }

        It 'Reaches back through a block that calls another block' {
            # One hop found the outer block and left the inner one's assignment outside, so the window ran & $null.
            $source = "`$header = { New-FakeUiControl 'h' }`n`$body = { & `$header; New-FakeUiControl 'b' }`n& `$body"
            (Get-SampleSpan $source).Text | Should -BeLike '$header = {*'
        }

        It 'Counts a write a closure invoked on the spot already ran' {
            # GetNewClosure hands the same block back, so .GetNewClosure().Invoke() runs it where it stands the same as .Invoke() does.
            $source = "foreach (`$i in 1..2) { { Set-Variable -Name seen -Value 1 }.GetNewClosure().Invoke(); New-FakeUiControl `$i }"
            { Get-SampleSpan $source } | Should -Throw '*already ran Set-Variable*'
        }

        It 'Refuses a write a block called before the control already ran' {
            # & $wipe has no command name of its own, so the guard over the swept in lines has to read the block behind it or the write runs again.
            $source = "`$wipe = { Set-Variable -Name seen -Value 1 }`n`$draw = { New-FakeUiControl 'a' }`n& `$wipe`n& `$draw"
            { Get-SampleSpan $source } | Should -Throw '*run Set-Variable a second time*'
        }

        It 'Refuses a window maker sharing the block the control is built in' {
            # The whole block goes in the window, so a maker after the control in it goes up mid build the same as one sharing a plain statement.
            $source = "`$sb = { New-FakeUiControl 'a'; Show-FakeUiDialog }`n& `$sb"
            { Get-SampleSpan $source } | Should -Throw '*shares a block with Show-FakeUiDialog*'
        }

        It 'Counts a write inside a block handed to a helper that builds controls' {
            # The repeat check used to ask with the exempt set, which holds the script's builders, so a block handed to one read as deferred and its write was skipped. The non builder twin refused all along.
            $source = "function Render-Row { param([scriptblock]`$Cb) & `$Cb; New-FakeUiControl 'row' }`nforeach (`$i in 1..2) { Render-Row -Cb { Set-Variable -Name seen -Value 1 }; New-FakeUiControl `$i }"
            { Get-SampleSpan $source } | Should -Throw '*already ran Set-Variable*'
        }

        It 'Counts a write a block in parentheses ran on the spot' {
            $source = "foreach (`$i in 1..2) { ({ Set-Variable -Name seen -Value 1 }).Invoke(); New-FakeUiControl `$i }"
            { Get-SampleSpan $source } | Should -Throw '*already ran Set-Variable*'
        }

        It 'Counts a write behind two closure hops' {
            $source = "foreach (`$i in 1..2) { { Set-Variable -Name seen -Value 1 }.GetNewClosure().GetNewClosure().Invoke(); New-FakeUiControl `$i }"
            { Get-SampleSpan $source } | Should -Throw '*already ran Set-Variable*'
        }

        It 'Reads a block handed over with a colon the same way as one handed over plain' {
            # -Body:{ } hangs the block off the parameter, and that branch has to ask the storer set too or the two spellings disagree.
            # Hold rather than Add, since Add is a mutating verb and the helper itself would trip the repeat check before the block was ever looked at.
            $source = "function Hold-Tab { param([scriptblock]`$Body) `$kept = `$Body }`nforeach (`$i in 1..2) { Hold-Tab -Body:{ Set-Variable -Name seen -Value 1 }; New-FakeUiControl `$i }"
            { Get-SampleSpan $source } | Should -Not -Throw
        }

        It 'Refuses a write sitting between the control and the block it was built from' {
            # Reaching back for the assignment sweeps the lines in between into the window, and those already ran once.
            $source = "`$go = { New-FakeUiControl 'leaf' }`nSet-Variable -Name marker -Value 'ran'`n& `$go"
            { Get-SampleSpan $source } | Should -Throw '*run Set-Variable a second time*'
        }

    }

    Describe 'Get-UiStatementCommandList' {
        BeforeAll {
            # The real call sites hand down every PsUi command. Which of its blocks runs now is settled by the parameter the block binds to, not by the command.
            $script:sampleDeferrers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($name in 'New-UiButton', 'New-UiPanel', 'New-UiWindow', 'New-UiLabel', 'Show-UiMessageDialog') { [void]$script:sampleDeferrers.Add($name) }

            function Get-StatementNames {
                param([string]$Source)
                $ast = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$null, [ref]$null)
                Get-UiStatementCommandList -Statement $ast.EndBlock.Statements[0] -Deferrers $script:sampleDeferrers
            }
        }

        AfterAll {
            Remove-Item function:Get-StatementNames -ErrorAction SilentlyContinue
            Remove-Variable -Name sampleDeferrers -Scope Script -ErrorAction SilentlyContinue
        }

        It 'Leaves out a block PsUi runs on a click' {
            (Get-StatementNames "New-UiButton -Text 'x' -Action { New-UiWindow -Title 'y' -Content { } }") -join ',' | Should -Be 'New-UiButton'
        }

        It 'Keeps a block that runs on the spot' {
            # ForEach-Object runs its block while the statement runs, so the control inside it is built now and the read has to reach it.
            (Get-StatementNames "'x' | ForEach-Object { New-UiButton -Text `$_ }") -join ',' | Should -Be 'ForEach-Object,New-UiButton'
        }

        It 'Keeps a block the call operator runs' {
            (Get-StatementNames "& { New-UiButton -Text 'x' }") -join ',' | Should -Be 'New-UiButton'
        }

        # The whole list, because a Should -Not -Contain against this one holds whatever comes back.
        It 'Leaves out a block that was stored rather than run' {
            # An assignment keeps the block for later, or for never, so nothing in it is built here.
            (Get-StatementNames "`$onClick = { New-UiButton -Text 'Ghost' }").Count | Should -Be 0
        }

        It 'Leaves a function body out' {
            # A function body is a ScriptBlockAst, so the deferred check used to miss it entirely.
            (Get-StatementNames "function Open-Child { New-UiWindow -Title 'c' -Content { } }").Count | Should -Be 0
        }

        It 'Hands back a list rather than a lone string when one name matches' {
            # A single name unrolls to a scalar without the comma on the return, and AddRange on the receiving side then walks it a character at a time.
            $found = Get-StatementNames "New-UiLabel 'a'"
            $found.GetType().Name | Should -Be 'List`1'
            $found.Count | Should -Be 1
        }

        It 'Keeps a block the ForEach method runs' {
            # The block hangs off the array, not off a command, and reading only the command parent dropped every name inside it.
            (Get-StatementNames "(1..2).ForEach({ New-UiButton -Text `$_ })") -join ',' | Should -Be 'New-UiButton'
        }

        It 'Keeps a block the Where method runs' {
            (Get-StatementNames "(1..2).Where({ New-UiButton -Text 'x' })") -join ',' | Should -Be 'New-UiButton'
        }

        It 'Leaves out a block handed to a method that stores it' {
            (Get-StatementNames "`$list.Add({ New-UiButton -Text 'x' })").Count | Should -Be 0
        }

        It 'Keeps a block the Invoke method runs on the spot' {
            # Which side of the dot the block sits on is the whole question. Here it is the thing being called, not an argument to something else.
            (Get-StatementNames "{ New-UiButton -Text 'x' }.Invoke()") -join ',' | Should -Be 'New-UiButton'
        }

        It 'Reads a qualified command without its module in front' {
            (Get-StatementNames "PsUi\New-UiPanel -Content { Show-UiMessageDialog -Message 'x' }") -join ',' | Should -Be 'New-UiPanel,Show-UiMessageDialog'
        }

        It 'Keeps a block bound to Content' {
            # A layout command dot sources Content while it builds itself, so a maker in there really does go up now.
            (Get-StatementNames "New-UiPanel -Content { Show-UiMessageDialog -Message 'x' }") -join ',' | Should -Be 'New-UiPanel,Show-UiMessageDialog'
        }

        It 'Keeps a block with no parameter name on a command that takes Content by position' {
            (Get-StatementNames "New-UiPanel { Show-UiMessageDialog -Message 'x' }") -join ',' | Should -Be 'New-UiPanel,Show-UiMessageDialog'
        }

        It 'Keeps a block sitting behind a switch' {
            # -FullWidth takes no value, so the block behind it is still binding to Content by position and reading the element in front alone gets it wrong.
            (Get-StatementNames "New-UiPanel -FullWidth { Show-UiMessageDialog -Message 'x' }") -join ',' | Should -Be 'New-UiPanel,Show-UiMessageDialog'
        }
    }

    Describe 'Get-UiWindowMakerList' {
        It 'Counts the dialogs but not the status bar helper' {
            $makers = Get-UiWindowMakerList
            $makers.Contains('New-UiWindow') | Should -BeTrue
            $makers.Contains('Out-Datagrid') | Should -BeTrue
            $makers.Contains('Show-UiMessageDialog') | Should -BeTrue
            # Show-UiStatusBar only decorates a window that already exists.
            $makers.Contains('Show-UiStatusBar') | Should -BeFalse
            # Native modal, and the only opener that escapes the Show-Ui* sweep.
            $makers.Contains('Show-WindowsObjectPicker') | Should -BeTrue
        }
    }

    Describe 'Get-UiCommandList' {
        It 'Holds the controls and none of the window makers' {
            $commands = Get-UiCommandList
            $commands.Contains('New-UiLabel') | Should -BeTrue
            $commands.Contains('New-UiWindow') | Should -BeFalse
        }

        It 'Matches a command name whatever its casing' {
            (Get-UiCommandList).Contains('new-uilabel') | Should -BeTrue
        }
    }

    Describe 'New-UiImplicitContent' {
        It 'Puts the script path in front so $PSScriptRoot still resolves' {
            # Both names are reserved, so the capture never carries them.
            $span = [pscustomobject]@{ Text = "New-UiLabel 'a'"; StartLine = 1; ScriptName = 'C:\dir sp\my script.ps1' }
            $text = (New-UiImplicitContent -Span $span).ToString()
            $text | Should -BeLike "*`$PSScriptRoot = 'C:\dir sp'*"
            $text | Should -BeLike "*`$PSCommandPath = 'C:\dir sp\my script.ps1'*"
        }

        It 'Pads by one less than the start line so error lines match the file' {
            # The window's try opens on the content's own first line, so nothing above the content costs a line.
            $span = [pscustomobject]@{ Text = "New-UiLabel 'a'"; StartLine = 5; ScriptName = $null }
            $text = (New-UiImplicitContent -Span $span).ToString()
            ($text -split "`n").Count | Should -Be 5
        }

        It 'Adds nothing at all when the content starts on line one with no file' {
            $span = [pscustomobject]@{ Text = "New-UiLabel 'a'"; StartLine = 1; ScriptName = $null }
            (New-UiImplicitContent -Span $span).ToString() | Should -Be "New-UiLabel 'a'"
        }
    }

    Describe 'New-UiPathPrefix' {
        AfterEach { Remove-Variable -Name uiQuoteCharacters -Scope Script -ErrorAction SilentlyContinue }

        It 'Carries an apostrophe in a folder name through as part of the name' {
            New-UiPathPrefix -ScriptName "C:\O'Brien\run.ps1" | Should -BeLike "*`$PSScriptRoot = 'C:\O''Brien'*"
        }

        It 'Leaves a folder named with a smart quote as a name and not as code' {
            # All four of these read as an apostrophe to the parser, so one left undoubled ends the literal and the rest of the folder name runs.
            foreach ($code in 0x2018, 0x2019, 0x201A, 0x201B) {
                $quote  = [char]$code
                $prefix = New-UiPathPrefix -ScriptName "C:\a$quote; Start-Process calc; $quote\run.ps1"
                $named  = 'U+{0:X4}' -f $code

                $tokens = $null
                $errors = $null
                $ast    = [System.Management.Automation.Language.Parser]::ParseInput($prefix, [ref]$tokens, [ref]$errors)
                $errors | Should -BeNullOrEmpty -Because "$named has to parse"
                $ast.EndBlock.Statements.Count | Should -Be 2 -Because "$named must add no statement"
                @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)).Count | Should -Be 0 -Because "$named must leave no command behind"
            }
        }

        It 'Hands back nothing when the quoting does not read back' {
            # The apostrophe on its own stands in for a sixth quote character turning up in some later parser. The prefix has to come back empty rather than carry a folder name in as code.
            $script:uiQuoteCharacters = @([char]0x27)
            $quote = [char]0x2019
            New-UiPathPrefix -ScriptName "C:\a$quote; Start-Process calc; $quote\run.ps1" | Should -Be ''
        }
    }

    Describe 'Get-UiDotSourcedPath' {
        BeforeAll {
            $script:dotHelper = Join-Path $TestDrive 'dotsourced.ps1'
            Set-Content -LiteralPath $script:dotHelper -Value 'function Show-Thing { }'
            $script:dotOwner = Join-Path $TestDrive 'dotowner.ps1'
        }

        It 'Follows a dot source the script runs itself' {
            $root = [System.Management.Automation.Language.Parser]::ParseInput(". '$script:dotHelper'", [ref]$null, [ref]$null)
            (Get-UiDotSourcedPath -Root $root -ScriptName $script:dotOwner).Count | Should -Be 1
        }

        It 'Follows one inside a branch, since the script still runs that itself' {
            $root = [System.Management.Automation.Language.Parser]::ParseInput("if (`$true) { . '$script:dotHelper' }", [ref]$null, [ref]$null)
            (Get-UiDotSourcedPath -Root $root -ScriptName $script:dotOwner).Count | Should -Be 1
        }

        It 'Leaves one inside a function body unread' {
            # It would define into that function's scope and be gone on return, so reading the file buys nothing. Keeping Test-Path off it also stops a target in a branch nothing called from being touched, and a UNC one of those would have this machine reaching out to whatever host it points at.
            $root = [System.Management.Automation.Language.Parser]::ParseInput("function Outer { . '$script:dotHelper' }", [ref]$null, [ref]$null)
            (Get-UiDotSourcedPath -Root $root -ScriptName $script:dotOwner).Count | Should -Be 0
        }

        It 'Leaves one inside a stored block unread' {
            $root = [System.Management.Automation.Language.Parser]::ParseInput("`$sb = { . '$script:dotHelper' }", [ref]$null, [ref]$null)
            (Get-UiDotSourcedPath -Root $root -ScriptName $script:dotOwner).Count | Should -Be 0
        }
    }

    Describe 'Invoke-UiImplicitWindow' {
        BeforeAll {
            # _Setup.ps1 turns the window off for the whole run. These tests want the guards underneath it.
            $script:savedNoImplicit = $env:PsUiNoImplicitWindow
            $script:hostExe         = (Get-Process -Id $PID).Path
            $script:repoPsd1        = (Resolve-Path (Join-Path $PSScriptRoot '..\PsUi\PsUi.psd1')).Path

            # A child host, killed if it holds on, so a guard that fails costs a test and not the run.
            function Invoke-ChildHost {
                param([string[]]$Arguments, [string]$Log, [string]$Keys)
                $startSplat = @{
                    FilePath                = $script:hostExe
                    ArgumentList            = $Arguments
                    RedirectStandardOutput  = $Log
                    PassThru                = $true
                    WindowStyle             = 'Hidden'
                }
                if ($Keys) { $startSplat['RedirectStandardInput'] = $Keys }
                $proc = Start-Process @startSplat

                # Windows PowerShell hands back a process that has let go of its handle, and ExitCode reads $null forever after. Touching Handle first keeps it.
                $null   = $proc.Handle
                $exited = $proc.WaitForExit(30000)
                if (!$exited) { $proc.Kill(); $null = $proc.WaitForExit(5000) }
                @{ Exited = $exited; ExitCode = $proc.ExitCode; Output = @(Get-Content $Log -ErrorAction SilentlyContinue) }
            }

            # The in process stand down tests below clear the env var and call for real, so a guard that regressed would build a window and park the run. This throws instead, and the assertion goes red.
            $module = $ExecutionContext.SessionState.Module
            Set-Item 'function:script:New-UiWindow' -Value $module.NewBoundScriptBlock({ throw 'New-UiWindow was reached by a test that expected a stand down.' })

            # Same three lines at the top of every child script. The env var is cleared so the guard under test is the one doing the work.
            function New-ChildScript {
                param([string]$Name, [string]$Body)
                $path = Join-Path $TestDrive $Name
                Set-Content -Path $path -Value "`$env:PsUiNoImplicitWindow = `$null`nImport-Module '$script:repoPsd1'`n$Body"
                $path
            }

            # A prompt read carrying the sets the join needs, the way Get-UiImplicitSpan hands them back. Helpers empty, since a typed line defines none.
            function New-PromptSpan {
                param([string]$Text, [bool]$Complete = $true, $ScriptName)
                $commands  = Get-UiCommandList
                $stoppers  = Get-UiWindowMakerList
                $deferrers = [System.Collections.Generic.HashSet[string]]::new([string[]]@($commands), [StringComparer]::OrdinalIgnoreCase)
                $deferrers.UnionWith($stoppers)
                # Built in place. An empty HashSet handed back out of a scriptblock enumerates to nothing and the property lands null.
                $helpers = @{
                    Builders     = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                    Stoppers     = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                    BlockStorers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                }
                [pscustomobject]@{ Text = $Text; StartLine = 1; ScriptName = $ScriptName; Complete = $Complete; Commands = $commands; Stoppers = $stoppers; Deferrers = $deferrers; Helpers = $helpers }
            }

            # Keys the way a paste leaves them in PSReadLine's queue, one entry per character and a carriage return for Enter.
            function New-KeyQueue {
                param([string]$Text)
                $queue = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
                foreach ($char in [char[]]$Text) { $queue.Enqueue([System.ConsoleKeyInfo]::new($char, [System.ConsoleKey]::NoName, $false, $false, $false)) }
                ,$queue
            }
        }

        AfterAll {
            $env:PsUiNoImplicitWindow = $script:savedNoImplicit
            Remove-Item function:New-UiWindow, function:Invoke-ChildHost, function:New-ChildScript, function:New-PromptSpan, function:New-KeyQueue -ErrorAction SilentlyContinue
            Remove-Variable -Name uiPasteJoinAlways, uiPasteJoinNever -Scope Script -ErrorAction SilentlyContinue
            Remove-Variable -Name savedNoImplicit, hostExe, repoPsd1 -Scope Script -ErrorAction SilentlyContinue
        }

        BeforeEach {
            # The session id guard runs first, so the thread has to be clean.
            [PsUi.SessionManager]::ClearCurrentSession()
            $env:PsUiNoImplicitWindow = $null
        }

        It 'Stands down when PsUiNoImplicitWindow is set' {
            # A child host does the asking. In process this passes at the -NonInteractive guard above it whenever the test host carries that switch.
            $script = New-ChildScript -Name 'envvar.ps1' -Body "`$env:PsUiNoImplicitWindow = '1'`ntry { New-UiLabel -Text 'x' } catch { `$_.Exception.Message }"
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-File', "`"$script`"") -Log (Join-Path $TestDrive 'envvar.txt')
            $run.Exited | Should -BeTrue
            ($run.Output -join ' ') | Should -Match 'must be called inside'
        }

        It 'Stands down under every spelling of -NonInteractive and leaves the old error in place' {
            # A build step that used to fail fast must not park a window. Both hosts answer to a slash, and pwsh also takes a double dash that 5.1 cannot parse at all.
            $spellings = @('-NonInteractive', '/noninteractive')
            if ($PSVersionTable.PSVersion.Major -ge 6) { $spellings += '--noninteractive' }
            $script = New-ChildScript -Name 'noni.ps1' -Body "try { New-UiLabel -Text 'x' } catch { `$_.Exception.Message }"
            foreach ($spelling in $spellings) {
                $run = Invoke-ChildHost -Arguments @('-NoProfile', $spelling, '-File', "`"$script`"") -Log (Join-Path $TestDrive 'noni.txt')
                $run.Exited | Should -BeTrue -Because "$spelling must not park a window"
                ($run.Output -join ' ') | Should -Match 'must be called inside'
            }
        }

        It 'Ends a script file with exit code 0 and runs nothing after the window' {
            # The script shadows New-UiWindow with a function, so nothing opens. Write-Host, because the implicit path discards what the window call returns.
            $script = New-ChildScript -Name 'ends.ps1' -Body "function New-UiWindow { param(`$Title, `$Content) Write-Host `"shadow window `$Title`" }`nNew-UiLabel -Text 'x'`n'AFTER'"
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-File', "`"$script`"") -Log (Join-Path $TestDrive 'ends.txt')
            $run.Exited | Should -BeTrue
            $run.ExitCode | Should -Be 0
            $run.Output | Should -Contain 'shadow window ends'
            $run.Output | Should -Not -Contain 'AFTER'
        }

        It 'Climbs out of a dot sourced helper to the script that ran it' {
            # The helper is in its own file, but the window copies over functions no module owns, so Add-Row will be there and the calling script is the one read.
            $helper = Join-Path $TestDrive 'dothelper.ps1'
            Set-Content -Path $helper -Value 'function Add-Row { param($i) New-UiLabel -Text "row $i" }'
            $shadow = "function New-UiWindow { param(`$Title, `$Content) Write-Host (`"TITLE=`" + `$Title); Write-Host (`$Content.ToString().Trim() -replace '\s+', ' ') }"
            $script = New-ChildScript -Name 'dotmain.ps1' -Body "$shadow`n. '$helper'`nAdd-Row 1`nAdd-Row 2"
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-File', "`"$script`"") -Log (Join-Path $TestDrive 'dotmain.txt')
            $run.Exited | Should -BeTrue

            # Titled after the script the user ran, not the library it dot sourced.
            ($run.Output -join ' ') | Should -BeLike '*TITLE=dotmain*'

            # Add-Row is on the call stack, so the chain seeds it as a builder whether or not the file was read. The dot source scan on its own is pinned by the opener test below, where the helper never runs before the control.
            ($run.Output -join ' ') | Should -BeLike '*Add-Row 1*'
            ($run.Output -join ' ') | Should -BeLike '*Add-Row 2*'
        }

        It 'Stops before a dot sourced helper that opens a window' {
            # The one case only reading the file can answer. Show-Dash never runs before the control, so the stack never holds it and the chain has nothing to seed from.
            $helper = Join-Path $TestDrive 'dotopener.ps1'
            Set-Content -Path $helper -Value 'function Show-Dash { Show-UiMessageDialog -Message "hi" }'
            $shadow = "function New-UiWindow { param(`$Title, `$Content) Write-Host ('SPAN=' + (`$Content.ToString().Trim() -replace '\s+', ' ')) }"
            $script = New-ChildScript -Name 'dotstop.ps1' -Body "$shadow`n. '$helper'`nNew-UiLabel -Text 'first'`nShow-Dash`nNew-UiLabel -Text 'after'"
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-File', "`"$script`"") -Log (Join-Path $TestDrive 'dotstop.txt')

            ($run.Output -join ' ') | Should -BeLike "*New-UiLabel -Text 'first'*"
            ($run.Output -join ' ') | Should -Not -BeLike '*Show-Dash*'
            ($run.Output -join ' ') | Should -Not -BeLike "*New-UiLabel -Text 'after'*"
        }

        It 'Stops at the script holding the control, not the one that launched it' {
            # The launcher would otherwise be the one read, and all that sits up there is the line that ran the file, so the window would run the whole thing a second time.
            $shadow = "function New-UiWindow { param(`$Title, `$Content) Write-Host (`"TITLE=`" + `$Title); Write-Host (`$Content.ToString().Trim() -replace '\s+', ' ') }"
            $inner  = New-ChildScript -Name 'inner.ps1' -Body "$shadow`nNew-UiLabel -Text 'inside'"
            $outer  = New-ChildScript -Name 'outer.ps1' -Body "Write-Host 'START'`n& '$inner'"
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-File', "`"$outer`"") -Log (Join-Path $TestDrive 'launch.txt')
            $run.Exited | Should -BeTrue
            ($run.Output -join ' ') | Should -BeLike '*TITLE=inner*'
            ($run.Output -join ' ') | Should -BeLike "*New-UiLabel -Text 'inside'*"

            # The launch line itself must stay out. The path shows up either way, since the preamble seeds $PSCommandPath with it.
            ($run.Output -join ' ') | Should -Not -BeLike "*& '*"
        }

        It 'Counts a write an earlier turn of a recursion already ran' {
            # Every level of Add-Level is one Ast, and folding them into a single hop hid the write the shallow levels ran on the way down.
            # A real file, because a sample built at runtime defines its helper in module scope and the frame walk reads those frames as PsUi and skips straight past them.
            # Caught and printed rather than left to throw, because only stdout is redirected and the two hosts disagree about where an unhandled error lands.
            $shadow = "function New-UiWindow { param(`$Title, `$Content) Write-Host ('SPAN=' + (`$Content.ToString().Trim() -replace '\s+', ' ')) }"
            $body   = "$shadow`nfunction Add-Level { param(`$n) if (`$n -gt 0) { Set-Variable -Name seen -Value `$n; Add-Level -n (`$n - 1) } else { New-UiLabel -Text 'leaf' } }`ntry { Add-Level -n 2 } catch { Write-Host ('REFUSED=' + `$_.Exception.Message) }"
            $script = New-ChildScript -Name 'recurse.ps1' -Body $body
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-File', "`"$script`"") -Log (Join-Path $TestDrive 'recurse.txt')
            ($run.Output -join ' ') | Should -BeLike '*REFUSED=*already ran Set-Variable*'
        }

        It 'Still builds for a recursion that only makes controls' {
            # The guard against the revived hops turning ordinary recursion into a refusal.
            $shadow = "function New-UiWindow { param(`$Title, `$Content) Write-Host ('SPAN=' + (`$Content.ToString().Trim() -replace '\s+', ' ')) }"
            $body   = "$shadow`nfunction Add-Level { param(`$n) if (`$n -gt 0) { Add-Level -n (`$n - 1) } else { New-UiLabel -Text 'leaf' } }`nAdd-Level -n 2"
            $script = New-ChildScript -Name 'recursebuild.ps1' -Body $body
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-File', "`"$script`"") -Log (Join-Path $TestDrive 'recursebuild.txt')
            ($run.Output -join ' ') | Should -BeLike '*SPAN=*Add-Level -n 2*'
        }

        It 'Builds a window for a control that resolves its own session' {
            # New-UiChart and friends used to call Get-UiSession straight, so a script opening with one lost that control and the window started at the next.
            $shadow = "function New-UiWindow { param(`$Title, `$Content) Write-Host (`$Content.ToString().Trim() -replace '\s+', ' ') }"
            $script = New-ChildScript -Name 'chartfirst.ps1' -Body "$shadow`nNew-UiChart -Variable 'c' -Type Bar -Data @{ a = 1 }`nNew-UiLabel -Text 'after'"
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-File', "`"$script`"") -Log (Join-Path $TestDrive 'chartfirst.txt')
            $run.Exited | Should -BeTrue
            ($run.Output -join ' ') | Should -BeLike '*New-UiChart*'
        }

        It 'Keeps a control called with its module in front of it' {
            # The command list holds plain names, so a qualified call matched nothing and the control was cut from the window. A real file, because the sample harness would run the second label with no window to put it in.
            $shadow = "function New-UiWindow { param(`$Title, `$Content) Write-Host ('SPAN=' + (`$Content.ToString().Trim() -replace '\s+', ' ')) }"
            $script = New-ChildScript -Name 'qualified.ps1' -Body "$shadow`nNew-UiLabel -Text 'a'`nPsUi\New-UiLabel -Text 'b'"
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-File', "`"$script`"") -Log (Join-Path $TestDrive 'qualified.txt')
            $run.Exited | Should -BeTrue
            ($run.Output -join ' ') | Should -BeLike '*PsUi\New-UiLabel*'
        }

        It 'Stops before a helper sitting beside the module function that called the control' {
            # Add-Row is a sibling in the psm1, and the window runspace only copies over functions no module owns, so content reaching Add-Row would die on a missing command.
            $module = Join-Path $TestDrive 'SpanMod.psm1'
            Set-Content -Path $module -Value @'
function New-UiWindow { param($Title, $Content) Write-Host ($Content.ToString().Trim() -replace '\s+', ' ') }
function Add-Row { param($i) New-UiLabel -Text "row $i" }
function Show-Dash { New-UiLabel -Text 'top'; Add-Row 1 }
'@
            $script = New-ChildScript -Name 'modspan.ps1' -Body "Import-Module '$module'`nShow-Dash"
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-File', "`"$script`"") -Log (Join-Path $TestDrive 'modspan.txt')
            $run.Exited | Should -BeTrue
            ($run.Output -join ' ') | Should -BeLike "*New-UiLabel -Text 'top'*"
            ($run.Output -join ' ') | Should -Not -BeLike '*Add-Row 1*'
        }

        It 'Leaves a live prompt alive when no script file is running' {
            # exit ends the nearest script file. At a prompt there is none, so it would close the console instead.
            $module = Join-Path $TestDrive 'ExitMod.psm1'
            Set-Content -Path $module -Value @'
function New-UiWindow { param($Title, $Content) Write-Host "shadow window $Title" }
function Show-Dash { New-UiLabel -Text 'x' }
'@
            # Typed one line at a time, so the window call is its own pipeline the way it is at a real prompt.
            $keys = Join-Path $TestDrive 'exitkeys.txt'
            Set-Content -Path $keys -Encoding Ascii -Value "`$env:PsUiNoImplicitWindow = `$null`nImport-Module '$script:repoPsd1'`nImport-Module '$module'`nShow-Dash`nWrite-Host 'CONSOLE-AFTER'`nexit"
            $run = Invoke-ChildHost -Arguments @('-NoProfile', '-NoExit') -Log (Join-Path $TestDrive 'modexit.txt') -Keys $keys
            $run.Exited | Should -BeTrue
            $run.Output | Should -Contain 'shadow window ExitMod'
            $run.Output | Should -Contain 'CONSOLE-AFTER'
        }

        It 'Leaves the console alive when the script was run from a command' {
            # exit ends the script and not the host. The throw it replaced took the whole command down with code 1.
            $script = New-ChildScript -Name 'cmd.ps1' -Body "function New-UiWindow { param(`$Title, `$Content) Write-Host `"shadow window `$Title`" }`nNew-UiLabel -Text 'x'`n'AFTER'"
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-Command', "`"& '$script'; 'CONSOLE-AFTER'`"") -Log (Join-Path $TestDrive 'cmd.txt')
            $run.Exited | Should -BeTrue
            $run.ExitCode | Should -Be 0
            $run.Output | Should -Contain 'CONSOLE-AFTER'
            $run.Output | Should -Not -Contain 'AFTER'
        }

        It 'Stands down on a PsUi background thread' {
            # A button action outliving its window reports no session too.
            $Global:AsyncExecutor = 'pretend'
            try {
                Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState | Should -Be $false
            }
            finally {
                Remove-Variable -Name AsyncExecutor -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'Stands down when an injected session id is present' {
            $Global:__PsUiSessionId = [guid]::NewGuid().ToString()
            try {
                Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState | Should -Be $false
            }
            finally {
                Remove-Variable -Name __PsUiSessionId -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'Stands down when a session is live on this thread' {
            $id = [PsUi.SessionManager]::CreateSession()
            [PsUi.SessionManager]::SetCurrentSession($id)
            try {
                Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState | Should -Be $false
            }
            finally { [PsUi.SessionManager]::DisposeSession($id) }
        }

        It 'Names the file and the line a failing control sits on' {
            # The content is rebuilt as fresh text inside the window, so the line an error carries is arithmetic rather than something PowerShell tracked for us. It shipped one too high and nothing in here noticed.
            # The real New-UiWindow runs rather than a shadow, since it is the one doing the counting. A content error throws before the window is ever shown.
            $lines = @(
                'trap { Write-Host "CAUGHT $($_.Exception.Message)"; continue }'
                "New-UiLabel -Text 'a'"
                "New-UiLabel -Foo 'boom'"
            )
            $script = New-ChildScript -Name 'lineno.ps1' -Body ($lines -join "`n")
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-File', "`"$script`"") -Log (Join-Path $TestDrive 'lineno.txt')
            $run.Exited | Should -BeTrue

            # New-ChildScript writes two lines of its own ahead of the body, so the bad control lands on 5. -Match, because -BeLike would read the brackets as a character range.
            ($run.Output -join ' ') | Should -Match '\[lineno\.ps1:5\]'
        }

        It 'Keeps that line still when -Debug and -Verbose are on' {
            # An explicit window, because the implicit one never passes either switch. Both paths share the arithmetic, and these two used to prepend a line each and take the reported line down the file with them.
            $lines = @(
                "`$env:PsUiNoImplicitWindow = '1'"
                'try {'
                "    New-UiWindow -Debug -Verbose -Title 'T' -Content {"
                "        New-UiLabel -Text 'a'"
                "        New-UiLabel -Foo 'boom'"
                '    }'
                '}'
                'catch { Write-Host "CAUGHT $($_.Exception.Message)" }'
            )
            $script = New-ChildScript -Name 'dbgline.ps1' -Body ($lines -join "`n")
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-File', "`"$script`"") -Log (Join-Path $TestDrive 'dbgline.txt')
            $run.Exited | Should -BeTrue

            ($run.Output -join ' ') | Should -Match '\[dbgline\.ps1:7\]'
        }

        It 'Names the line a control inside a nested container sits on' {
            # A card, tab or panel runs its own block through Invoke-UiContent, and the line it reads comes off the session rather than the block, which arrives with no file on it.
            # The window call is deliberately not on the same line as its content block. While the two share a line the old count and the right one agree, so the drift only shows once they are apart.
            $lines = @(
                "`$env:PsUiNoImplicitWindow = '1'"
                'try {'
                "    New-UiWindow -Title 'T' -Content ("
                '        {'
                "            New-UiPanel -Header 'P' -Content {"
                "                New-UiLabel -Text 'a'"
                "                New-UiLabel -Foo 'boom'"
                '            }'
                '        }'
                '    )'
                '}'
                'catch { Write-Host "CAUGHT $($_.Exception.Message)" }'
            )
            $script = New-ChildScript -Name 'nestedline.ps1' -Body ($lines -join "`n")
            $run    = Invoke-ChildHost -Arguments @('-NoProfile', '-File', "`"$script`"") -Log (Join-Path $TestDrive 'nestedline.txt')
            $run.Exited | Should -BeTrue

            # Two lines of New-ChildScript preamble, so the bad control lands on 9.
            ($run.Output -join ' ') | Should -Match '\[nestedline\.ps1:9\]'
        }

        It 'Builds as before when the queue is empty' {
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Get-UiPromptKeyQueue { ,[System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new() }

            # The stand in New-UiWindow throws on arrival, and arriving is the point.
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
        }

        It 'Builds as before with no PSReadLine to ask' {
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Get-UiPromptKeyQueue { $null }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
        }

        It 'Leaves a script file alone' {
            # A file is one submission already, so the queue is never asked about.
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" -ScriptName (Join-Path $TestDrive 'filespan.ps1') }
            Mock Get-UiPromptKeyQueue { $null }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            Should -Invoke Get-UiPromptKeyQueue -Times 0 -Exactly
        }

        It 'Joins the pasted lines behind the control into one window' {
            # The keys are mocked rather than seeded for real, since real keys would be typed into the developer's prompt once the run ends. Every key behind the taken line has to come out, or PSReadLine types it into the next prompt.
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            $script:pasteQueue = New-KeyQueue "New-UiButton -Text 'Go' -Action { }`r"
            $before = $script:pasteQueue.Count
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Confirm-UiPasteJoin { $true }
            Mock Get-UiPromptKeyQueue { ,$script:pasteQueue }
            Mock New-UiImplicitContent { $script:joined = $Span; { } }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            $script:joined.Text | Should -Be "New-UiLabel -Text 'a'`nNew-UiButton -Text 'Go' -Action { }"
            $script:pasteQueue.Count | Should -Be 0
            Remove-Variable -Name pasteQueue, joined -Scope Script
        }

        It 'Leaves a pasted line that builds nothing where it is' {
            # Write-Host runs after the window closes, the way the tail of a script would.
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            $script:pasteQueue = New-KeyQueue "New-UiLabel -Text 'test2'`rWrite-Host 'test'`r"
            $before = $script:pasteQueue.Count
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Confirm-UiPasteJoin { $true }
            Mock Get-UiPromptKeyQueue { ,$script:pasteQueue }
            Mock New-UiImplicitContent { $script:joined = $Span; { } }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            $script:joined.Text | Should -Be "New-UiLabel -Text 'a'`nNew-UiLabel -Text 'test2'"
            $script:pasteQueue.Count | Should -Be 18
            Remove-Variable -Name pasteQueue, joined -Scope Script
        }

        It 'Stops before a pasted dialog and leaves it queued' {
            # Taking the controls past it would put them ahead of the dialog, so the join ends before it and nothing is dequeued.
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            $script:pasteQueue = New-KeyQueue "Show-UiMessageDialog -Message hi`rNew-UiButton -Text 'Go'`r"
            $before = $script:pasteQueue.Count
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Confirm-UiPasteJoin { $true }
            Mock Get-UiPromptKeyQueue { ,$script:pasteQueue }
            Mock New-UiImplicitContent { $script:joined = $Span; { } }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            $script:joined.Text | Should -Be "New-UiLabel -Text 'a'"
            $script:pasteQueue.Count | Should -Be $before
            Remove-Variable -Name pasteQueue, joined -Scope Script
        }

        It 'Stops on a pasted line that builds and opens a window both' {
            # The block runs where it stands, so the one statement holds both a control and a dialog. Taking it would put the modal up while the window is still being built, which is what the stopper check is for.
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            $script:pasteQueue = New-KeyQueue "& { New-UiLabel -Text 'x'; Show-UiMessageDialog -Message hi }`r"
            $before = $script:pasteQueue.Count
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Confirm-UiPasteJoin { $true }
            Mock Get-UiPromptKeyQueue { ,$script:pasteQueue }
            Mock New-UiImplicitContent { $script:joined = $Span; { } }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            $script:joined.Text | Should -Be "New-UiLabel -Text 'a'"
            $script:pasteQueue.Count | Should -Be $before
            Remove-Variable -Name pasteQueue, joined -Scope Script
        }

        It 'Takes a last line pasted with no Enter behind it' {
            # A copy button hands over no trailing newline, so the last control sits in the queue with no Enter and would open a lone window on the next one.
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            $script:pasteQueue = New-KeyQueue "New-UiButton -Text 'Go'"
            $before = $script:pasteQueue.Count
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Confirm-UiPasteJoin { $true }
            Mock Get-UiPromptKeyQueue { ,$script:pasteQueue }
            Mock New-UiImplicitContent { $script:joined = $Span; { } }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            $script:joined.Text | Should -Be "New-UiLabel -Text 'a'`nNew-UiButton -Text 'Go'"
            $script:pasteQueue.Count | Should -Be 0
            Remove-Variable -Name pasteQueue, joined -Scope Script
        }

        It 'Leaves a half typed line alone' {
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            $script:pasteQueue = New-KeyQueue "New-UiButton -Text 'Go' -Action {"
            $before = $script:pasteQueue.Count
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Confirm-UiPasteJoin { $true }
            Mock Get-UiPromptKeyQueue { ,$script:pasteQueue }
            Mock New-UiImplicitContent { $script:joined = $Span; { } }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            $script:joined.Text | Should -Be "New-UiLabel -Text 'a'"
            $script:pasteQueue.Count | Should -Be $before
            Remove-Variable -Name pasteQueue, joined -Scope Script
        }

        It 'Leaves the queue alone when the typed line stopped short of its end' {
            # A dialog on the typed line stopped the read before the line ended, and lines behind it would land after the dialog.
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            $script:pasteQueue = New-KeyQueue "New-UiButton -Text 'Go'`r"
            $before = $script:pasteQueue.Count
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" -Complete $false }
            Mock Confirm-UiPasteJoin { $true }
            Mock Get-UiPromptKeyQueue { ,$script:pasteQueue }
            Mock New-UiImplicitContent { $script:joined = $Span; { } }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            $script:joined.Text | Should -Be "New-UiLabel -Text 'a'"
            $script:pasteQueue.Count | Should -Be $before
            Should -Invoke Get-UiPromptKeyQueue -Times 0 -Exactly
            Remove-Variable -Name pasteQueue, joined -Scope Script
        }

        It 'Stops at a pasted line that builds nothing, even with a control behind it' {
            # Reading a file takes the plain script between two controls. Nothing queued has been entered yet, so the take ends at the Write-Host and the control behind it opens its own window later.
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            $script:pasteQueue = New-KeyQueue "New-UiLabel -Text 'b'`rWrite-Host x`rNew-UiLabel -Text 'c'`r"
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Confirm-UiPasteJoin { $true }
            Mock Get-UiPromptKeyQueue { ,$script:pasteQueue }
            Mock New-UiImplicitContent { $script:joined = $Span; { } }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            $script:joined.Text | Should -Be "New-UiLabel -Text 'a'`nNew-UiLabel -Text 'b'"
            $script:pasteQueue.Count | Should -Be 35
            Remove-Variable -Name pasteQueue, joined -Scope Script
        }

        It 'Leaves the paste queued when the answer is no' {
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            $script:pasteQueue = New-KeyQueue "New-UiButton -Text 'Go'`r"
            $before = $script:pasteQueue.Count
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Confirm-UiPasteJoin { $false }
            Mock Get-UiPromptKeyQueue { ,$script:pasteQueue }
            Mock New-UiImplicitContent { $script:joined = $Span; { } }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            $script:joined.Text | Should -Be "New-UiLabel -Text 'a'"
            $script:pasteQueue.Count | Should -Be $before
            Remove-Variable -Name pasteQueue, joined -Scope Script
        }

        It 'Takes nothing when a window maker shares the last control line' {
            # The cut lands on a line boundary, so taking that control would carry the dialog with it and put a modal up mid build.
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            $script:pasteQueue = New-KeyQueue "New-UiLabel -Text 'two'; Show-UiMessageDialog -Message hi`r"
            $before = $script:pasteQueue.Count
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Confirm-UiPasteJoin { $true }
            Mock Get-UiPromptKeyQueue { ,$script:pasteQueue }
            Mock New-UiImplicitContent { $script:joined = $Span; { } }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            $script:joined.Text | Should -Be "New-UiLabel -Text 'a'"
            $script:pasteQueue.Count | Should -Be $before
            Remove-Variable -Name pasteQueue, joined -Scope Script
        }

        It 'Takes nothing when a half open block shares the control line' {
            # Taking through the line end would hand New-UiImplicitContent an unclosed brace, and the keys would already be gone.
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            $script:pasteQueue = New-KeyQueue "New-UiLabel -Text 'b'; if (`$true) {`r    Write-Host x`r}`r"
            $before = $script:pasteQueue.Count
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Confirm-UiPasteJoin { $true }
            Mock Get-UiPromptKeyQueue { ,$script:pasteQueue }
            Mock New-UiImplicitContent { $script:joined = $Span; { } }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            $script:joined.Text | Should -Be "New-UiLabel -Text 'a'"
            $script:pasteQueue.Count | Should -Be $before
            Remove-Variable -Name pasteQueue, joined -Scope Script
        }

        It 'Takes nothing when a write shares the control line' {
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            $script:pasteQueue = New-KeyQueue "New-UiLabel -Text 'b'; Remove-Item C:\temp\gone.txt`r"
            $before = $script:pasteQueue.Count
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Confirm-UiPasteJoin { $true }
            Mock Get-UiPromptKeyQueue { ,$script:pasteQueue }
            Mock New-UiImplicitContent { $script:joined = $Span; { } }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            $script:joined.Text | Should -Be "New-UiLabel -Text 'a'"
            $script:pasteQueue.Count | Should -Be $before
            Remove-Variable -Name pasteQueue, joined -Scope Script
        }

        It 'Keeps the good lines when the tail of a paste will not parse' {
            # The retry drops the last line and tries again. Text already ending in a newline used to cut at that same newline and give up on the whole paste.
            if ([Environment]::GetCommandLineArgs() -match '^(--?|/)noni') { Set-ItResult -Skipped -Because 'the host carries -NonInteractive, which stands the window down first' }
            $script:pasteQueue = New-KeyQueue "New-UiLabel -Text 'b'`rNew-UiButton -Text 'x' -Action { Write-Host hi`r"
            $before = $script:pasteQueue.Count
            Mock Get-UiImplicitSpan { New-PromptSpan -Text "New-UiLabel -Text 'a'" }
            Mock Confirm-UiPasteJoin { $true }
            Mock Get-UiPromptKeyQueue { ,$script:pasteQueue }
            Mock New-UiImplicitContent { $script:joined = $Span; { } }
            { Invoke-UiImplicitWindow -CallerName 'New-UiLabel' -CallerState $ExecutionContext.SessionState } | Should -Throw -ExpectedMessage '*was reached*'
            $script:joined.Text | Should -Be "New-UiLabel -Text 'a'`nNew-UiLabel -Text 'b'"
            $script:pasteQueue.Count | Should -Be 47
            Remove-Variable -Name pasteQueue, joined -Scope Script
        }

        It 'Keeps never ahead of always when a session carries both' {
            # Never alone proves little here, since a test host with no way to prompt also lands on false. Setting both is what tells the two apart, because skipping the never check hands the answer to always.
            $script:uiPasteJoinAlways = $true
            $script:uiPasteJoinNever  = $true
            Confirm-UiPasteJoin -Text "New-UiLabel -Text 'a'" | Should -BeFalse
            Remove-Variable -Name uiPasteJoinAlways, uiPasteJoinNever -Scope Script
        }

        It 'Counts the dequeue off a fresh read of the queue' {
            # The first read can catch a carriage return before its line feed has landed. The text reads the same either way and the key count does not, so a count taken from the stale read leaves an Enter behind to submit an empty line at the next prompt.
            $queue = New-KeyQueue "a`r`nb`r"
            $stale = [pscustomobject]@{ Text = "a`n"; EntryEnds = @(1, 2); Queue = $queue }
            Remove-UiPendingInput -Pending $stale -Chars 2 | Should -BeTrue

            # Three keys behind those two characters, not two.
            $queue.Count | Should -Be 2
        }

        It 'Remembers yes to all and stops asking' {
            # The point of the two sticky answers is the paste after this one, so the host is set to refuse the second time round. A true can then only have come from memory.
            Mock Read-UiPasteChoice -MockWith { 1 }
            Confirm-UiPasteJoin -Text "New-UiLabel -Text 'a'" | Should -BeTrue
            Mock Read-UiPasteChoice -MockWith { 2 }
            Confirm-UiPasteJoin -Text "New-UiLabel -Text 'b'" | Should -BeTrue
            Remove-Variable -Name uiPasteJoinAlways, uiPasteJoinNever -Scope Script -ErrorAction SilentlyContinue
        }

        It 'Remembers no to all and stops asking' {
            # The same the other way up. The host is set to agree the second time, so a false can only have come from memory.
            Mock Read-UiPasteChoice -MockWith { 3 }
            Confirm-UiPasteJoin -Text "New-UiLabel -Text 'a'" | Should -BeFalse
            Mock Read-UiPasteChoice -MockWith { 0 }
            Confirm-UiPasteJoin -Text "New-UiLabel -Text 'b'" | Should -BeFalse
            Remove-Variable -Name uiPasteJoinAlways, uiPasteJoinNever -Scope Script -ErrorAction SilentlyContinue
        }

        It 'Stops asking once it has been told never' {
            # The host is mocked into agreeing, so a false can only have come from the remembered answer. Mocked rather than left live because a regression here would otherwise sit waiting on a real prompt for input that never arrives.
            Mock Read-UiPasteChoice -MockWith { 0 }
            $script:uiPasteJoinNever = $true
            Confirm-UiPasteJoin -Text "New-UiLabel -Text 'a'" | Should -BeFalse
            Should -Invoke Read-UiPasteChoice -Times 0 -Exactly
            Remove-Variable -Name uiPasteJoinNever -Scope Script
        }

        It 'Stops asking once it has been told always' {
            # The host is mocked into refusing, so a true can only have come from the remembered answer, and the prompt is never reached.
            Mock Read-UiPasteChoice -MockWith { 2 }
            $script:uiPasteJoinAlways = $true
            Confirm-UiPasteJoin -Text "New-UiLabel -Text 'a'" | Should -BeTrue
            Should -Invoke Read-UiPasteChoice -Times 0 -Exactly
            Remove-Variable -Name uiPasteJoinAlways -Scope Script
        }

        It 'Reads a CRLF pair as one line break and counts both keys' {
            $pending = Get-UiPendingInput -Queue (New-KeyQueue "a`r`nb`r")
            $pending.Text | Should -Be "a`nb`n"
            $pending.EntryEnds | Should -Be @(1, 3, 4, 5)
        }

        It 'Joins on yes and on yes to all, and on nothing else' {
            # The four sit in PowerShell's own order, so yes to all is 1 and no to all is 3. A host with no way to ask hands back -1, and so does one the user cancels out of. Neither is a yes, and neither is on the list.
            foreach ($case in @(@(0, $true), @(1, $true), @(2, $false), @(3, $false), @(-1, $false))) {
                Mock Read-UiPasteChoice -MockWith ([scriptblock]::Create("$($case[0])"))
                Confirm-UiPasteJoin -Text "New-UiLabel -Text 'a'" | Should -Be $case[1] -Because "answer $($case[0])"
                Remove-Variable -Name uiPasteJoinAlways, uiPasteJoinNever -Scope Script -ErrorAction SilentlyContinue
            }
        }

        It 'Keeps the lines ahead of a break in the middle of a paste' {
            $span = New-PromptSpan -Text "New-UiLabel -Text 'a'"
            $text = "New-UiLabel -Text 'one'`nNew-UiLabel -Text 'two'`nif (`$true) {`nNew-UiLabel -Text 'three'"
            (Get-UiPendingSpan -Text $text -Span $span).Text | Should -Be "New-UiLabel -Text 'one'`nNew-UiLabel -Text 'two'"
        }

        It 'Keeps the good lines when blank lines follow the break' {
            # The retry gives up a line at a time off the end, and trailing blank lines are where that matters. Cutting at the newline the text already ends on takes nothing off, and the whole paste goes with it.
            $span = New-PromptSpan -Text "New-UiLabel -Text 'a'"
            (Get-UiPendingSpan -Text "New-UiLabel -Text 'b'`n@(`n`n`n" -Span $span).Text | Should -Be "New-UiLabel -Text 'b'"
        }

        It 'Gives up quickly on a long paste whose first line never closes' {
            # The cut lands on the line the parse error points at instead of walking back a line per parse. Four thousand lines the other way is four thousand parses, which runs into seconds, and the stopwatch below catches that.
            $span  = New-PromptSpan -Text "New-UiLabel -Text 'a'"
            $text  = "if (`$true) {`n" + ((1..4000 | ForEach-Object { "New-UiLabel -Text 'row$_'" }) -join "`n")
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            Get-UiPendingSpan -Text $text -Span $span | Should -BeNullOrEmpty
            $watch.Stop()
            $watch.Elapsed.TotalSeconds | Should -BeLessThan 5
        }

        It 'Still finds the two PSReadLine fields the guard reflects on' {
            # A rename in a PSReadLine release turns the guard off without a sound, so this is the line that goes red when it happens.
            Import-Module PSReadLine -ErrorAction SilentlyContinue
            $type = 'Microsoft.PowerShell.PSConsoleReadLine' -as [type]
            if (!$type) { Set-ItResult -Skipped -Because 'PSReadLine is not on this box' }
            $type.GetField('_singleton', [System.Reflection.BindingFlags]'NonPublic,Static') | Should -Not -BeNullOrEmpty
            $type.GetField('_queuedKeys', [System.Reflection.BindingFlags]'NonPublic,Instance') | Should -Not -BeNullOrEmpty

            # The walk itself, since checking the fields by hand leaves the function that reads them untouched. A host that has never run ReadLine has no singleton to reach, and $null there is the right answer.
            # Compared against $null rather than piped, because an empty queue enumerates to nothing and every emptiness test then reads it as absent.
            $singleton = $type.GetField('_singleton', [System.Reflection.BindingFlags]'NonPublic,Static').GetValue($null)
            $queue     = Get-UiPromptKeyQueue
            if ($singleton) { ($null -ne $queue) | Should -BeTrue }
            else { ($null -eq $queue) | Should -BeTrue }
        }
    }

    # A helper defined in here belongs to the module, so the frame walk skips it as PsUi's. The chain is built by hand from the parsed source instead.
    Describe 'Get-UiRepeatedCommand' {
        BeforeAll {
            function Get-RepeatFor {
                param([string]$Source)
                $ast        = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$null, [ref]$null)
                $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
                $call       = $definition.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'New-UiLabel' }, $true)
                $callSite   = @($ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] })[0]
                $chain      = @(
                    @{ Name = $definition.Name; Ast = $definition; Offset = $call.Extent.StartOffset }
                    @{ Name = 'sample'; Ast = $ast; Offset = $callSite.Extent.StartOffset }
                )
                # Exempt carries the helper, since it is a builder. Deferrers carries only the PsUi names, the way Get-UiImplicitSpan hands them over, or a block given to the helper would read as stored.
                $exempt    = [System.Collections.Generic.HashSet[string]]::new([string[]]@('New-UiLabel', 'New-UiButton', $definition.Name), [StringComparer]::OrdinalIgnoreCase)
                $deferrers = [System.Collections.Generic.HashSet[string]]::new([string[]]@('New-UiLabel', 'New-UiButton'), [StringComparer]::OrdinalIgnoreCase)
                Get-UiRepeatedCommand -Chain $chain -Statement $callSite -Exempt $exempt -Deferrers $deferrers
            }
        }

        AfterAll { Remove-Item function:Get-RepeatFor -ErrorAction SilentlyContinue }

        It 'Names the helper that ran a write before the control' {
            $found = Get-RepeatFor "function Add-Row { param(`$i) Set-Variable -Name seen -Value `$i; New-UiLabel `$i }`nAdd-Row 1"
            $found.Name  | Should -Be 'Set-Variable'
            $found.Where | Should -Be 'Add-Row'
        }

        It 'Passes a helper whose write comes after the control' {
            Get-RepeatFor "function Add-Row { param(`$i) New-UiLabel `$i; Set-Variable -Name seen -Value `$i }`nAdd-Row 1" | Should -BeNullOrEmpty
        }

        It 'Counts the write when the helper loops over it' {
            $found = Get-RepeatFor "function Add-Row { foreach (`$i in 1..2) { New-UiLabel `$i; Set-Variable -Name seen -Value `$i } }`nAdd-Row"
            $found.Name | Should -Be 'Set-Variable'
        }

        It 'Leaves a native program alone' {
            Get-RepeatFor "function Add-Row { ipconfig | Out-Null; New-UiLabel 'a' }`nAdd-Row" | Should -BeNullOrEmpty
        }

        It 'Leaves a stored block alone and still reads one the call operator runs' {
            # A block in a hashtable or on the right of an assignment runs later or never. The call operator runs it on the spot.
            $stored = "function Add-Row { `$p = @{ Action = { Remove-Item 'C:\nope' } }; New-UiButton @p; New-UiLabel 'a' }`nAdd-Row"
            Get-RepeatFor $stored | Should -BeNullOrEmpty

            $assigned = "function Add-Row { `$block = { Remove-Item 'C:\nope' }; New-UiLabel 'a' }`nAdd-Row"
            Get-RepeatFor $assigned | Should -BeNullOrEmpty

            $invoked = "function Add-Row { & { Remove-Item 'C:\nope' }; New-UiLabel 'a' }`nAdd-Row"
            (Get-RepeatFor $invoked).Name | Should -Be 'Remove-Item'
        }

        It 'Judges an alias against the exempt list too' {
            # The alias name carries a mutating verb of its own. Without resolving it to the control behind it, the check refuses the window it was about to build.
            Set-Alias -Name New-RowLabel -Value New-UiLabel -Scope Global
            try { Get-RepeatFor "function Add-Row { New-RowLabel 'a'; New-UiLabel 'b' }`nAdd-Row" | Should -BeNullOrEmpty }
            finally { Remove-Item alias:New-RowLabel -ErrorAction SilentlyContinue }
        }

        It 'Leaves a strict mode preamble alone' {
            Get-RepeatFor "function Add-Row { Set-StrictMode -Version Latest; New-UiLabel 'a' }`nAdd-Row" | Should -BeNullOrEmpty
        }

        It 'Counts every spelling of a pipeline loop' {
            foreach ($spelling in 'ForEach-Object', '%', 'foreach') {
                $found = Get-RepeatFor "function Add-Row { 1..2 | $spelling { New-UiLabel `$_; Set-Variable -Name seen -Value `$_ } }`nAdd-Row"
                $found.Name | Should -Be 'Set-Variable' -Because "$spelling loops the write back round"
            }
        }
    }

    Describe 'Remove-UiStoreShadow' {
        BeforeAll {
            $script:shadowId = [PsUi.SessionManager]::CreateSession()
            [PsUi.SessionManager]::SetCurrentSession($script:shadowId)
            [PsUi.SessionManager]::Current.SetCapturedVariable('lastRun', 'FROM-STORE')
        }

        AfterAll {
            [PsUi.SessionManager]::DisposeSession($script:shadowId)
            Remove-Variable -Name shadowId -Scope Script -ErrorAction SilentlyContinue
        }

        It 'Drops a scope name the store holds and keeps the rest' {
            $bag = Remove-UiStoreShadow -Variables @{ lastRun = 'STALE'; other = 1 } -AutoNames 'lastRun', 'other'
            $bag.ContainsKey('lastRun') | Should -BeFalse
            $bag['other'] | Should -Be 1
        }

        It 'Leaves a name passed by hand alone' {
            (Remove-UiStoreShadow -Variables @{ lastRun = 'STALE' } -AutoNames 'other')['lastRun'] | Should -Be 'STALE'
        }

        It 'Matches the store key without regard to case' {
            (Remove-UiStoreShadow -Variables @{ LASTRUN = 'STALE' } -AutoNames 'LASTRUN').ContainsKey('LASTRUN') | Should -BeFalse
        }
    }

    Describe 'Assert-UiSession' {
        It 'Still names the command when a session exists with no parent' {
            # A definition block nulls CurrentParent, and that has to keep throwing.
            $id = [PsUi.SessionManager]::CreateSession()
            [PsUi.SessionManager]::SetCurrentSession($id)
            try {
                { Assert-UiSession -CallerName 'New-UiThing' } | Should -Throw '*New-UiThing must be called inside*'
            }
            finally { [PsUi.SessionManager]::DisposeSession($id) }
        }
    }
}
