#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Runspaces and background threads, and what is left behind when an async run ends.
. (Join-Path $PSScriptRoot '_Setup.ps1')

BeforeAll { . (Join-Path $PSScriptRoot '_Setup.ps1') }

# These actually spin up background runspaces - closest thing to integration tests
Describe 'AsyncExecutor Events' {

    It 'Builds and disposes without a run' {
        # The rest of this file gets an AsyncExecutor as setup, so nothing pinned construct and teardown on their own.
        $executor = [PsUi.AsyncExecutor]::new()
        $executor | Should -Not -BeNullOrEmpty
        { $executor.Dispose() } | Should -Not -Throw
    }

    It 'Ends the run and clears IsRunning' {
        $executor = [PsUi.AsyncExecutor]::new()

        # Queue mode buffers output instead of handing it to the UI thread, and there is no window here.
        $executor.UsePipelineQueueMode = $true
        $executor.ExecuteAsync([scriptblock]::Create('Write-Output "test"'), $null, $null, $null, $null, $false)

        $timeout = [DateTime]::Now.AddSeconds(5)
        while ($executor.IsRunning -and [DateTime]::Now -lt $timeout) { Start-Sleep -Milliseconds 50 }

        $executor.IsRunning | Should -BeFalse
        $executor.Dispose()
    }

    It 'Takes an empty scriptblock without hanging' {
        $executor                      = [PsUi.AsyncExecutor]::new()
        $executor.UsePipelineQueueMode = $true
        $executor.ExecuteAsync([scriptblock]::Create(''), $null, $null, $null, $null, $false)

        $timeout = [DateTime]::Now.AddSeconds(5)
        while ($executor.IsRunning -and [DateTime]::Now -lt $timeout) { Start-Sleep -Milliseconds 50 }

        $executor.IsRunning | Should -BeFalse
        $executor.Dispose()
    }

    It 'Should capture pipeline output via queue mode' {
        $executor                      = [PsUi.AsyncExecutor]::new()
        $executor.UsePipelineQueueMode = $true

        $script = [scriptblock]::Create('1..3')
        $executor.ExecuteAsync($script, $null, $null, $null, $null, $false)

        $timeout = [DateTime]::Now.AddSeconds(5)
        while ($executor.IsRunning -and [DateTime]::Now -lt $timeout) {
            Start-Sleep -Milliseconds 50
        }
        Start-Sleep -Milliseconds 100

        $output = $executor.DrainPipelineQueue(100)
        $executor.Dispose()

        $output.Count | Should -Be 3
        $output | Should -Contain 1
        $output | Should -Contain 2
        $output | Should -Contain 3
    }

    It 'Should track IsRunning state correctly' {
        $executor = [PsUi.AsyncExecutor]::new()

        $executor.IsRunning | Should -BeFalse

        $script = [scriptblock]::Create('Start-Sleep -Milliseconds 200')
        $executor.ExecuteAsync($script, $null, $null, $null, $null, $false)

        # Poll for the transition. A fixed sleep here raced a cold runspace pool from both ends.
        $started = [DateTime]::Now.AddSeconds(5)
        while (!$executor.IsRunning -and [DateTime]::Now -lt $started) {
            Start-Sleep -Milliseconds 10
        }
        $executor.IsRunning | Should -BeTrue

        $timeout = [DateTime]::Now.AddSeconds(5)
        while ($executor.IsRunning -and [DateTime]::Now -lt $timeout) {
            Start-Sleep -Milliseconds 50
        }

        $executor.IsRunning | Should -BeFalse
        $executor.Dispose()
    }
}

# End to end on Invoke-UiAsync. This file sorts last in Tests, which matters.
# Cancel needs an Application, a process wide singleton, so it stays out of the other files.
Describe 'Invoke-UiAsync capture and cancel lifecycle' {
    BeforeAll {
        if (![System.Windows.Application]::Current) { $null = New-Object System.Windows.Application }
    }

    It 'Cancel disposes the AsyncExecutor, not just cancels its token' {
        $handle = Invoke-UiAsync -ScriptBlock { 1..100 | ForEach-Object { Start-Sleep -Milliseconds 100 } }

        $spinUp = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $spinUp -and !$handle.Executor.IsRunning) { [System.Threading.Thread]::Sleep(10) }
        $handle.Executor.Cancel()

        # Dispose() nulls the private _cts. Cancel() alone only cancels it.
        $ctsField = [PsUi.AsyncExecutor].GetField('_cts', [System.Reflection.BindingFlags]'Instance,NonPublic')

        # Poll rather than wait out a fixed timer, which sat on its full 700ms for work that lands in about 30.
        $deadline = (Get-Date).AddSeconds(5)
        while ((Get-Date) -lt $deadline -and $null -ne $ctsField.GetValue($handle.Executor)) {
            $frame = [System.Windows.Threading.DispatcherFrame]::new()
            [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
                [Action]{ $frame.Continue = $false })
            [System.Windows.Threading.Dispatcher]::PushFrame($frame)
            if ($null -ne $ctsField.GetValue($handle.Executor)) { [System.Threading.Thread]::Sleep(20) }
        }

        $ctsField.GetValue($handle.Executor) | Should -BeNullOrEmpty
    }
}

# Reads the function source rather than running it, so it needs nothing from the blocks around it.
Describe 'Invoke-UiAsync auto capture exclusions' {
    It 'Keeps its own injection locals under a __ prefix and out of the exclusion list' {
        # Those three names were the function's own locals, and they had leaked into the auto capture exclusion list, so a user variable of the same name was dropped without a word.
        # Auto capture of an It local is not reachable under Pester's scope model, so this pins the source instead.
        $def = (Get-Command Invoke-UiAsync).Definition
        $def | Should -Not -Match "'executor'"
        $def | Should -Not -Match "'varsToInject'"
        $def | Should -Not -Match "'functionsToInject'"
        $def | Should -Match '\$__executor'
    }
}

Describe 'ActiveExecutor release on run end' {
    BeforeAll {
        if (![System.Windows.Application]::Current) { $null = New-Object System.Windows.Application }

        $script:aeSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:aeSessionId)
        $script:aeSession = [PsUi.SessionManager]::Current

        # Bounded message loop. The completion handlers queue onto the UI thread.
        function Wait-Condition {
            param([scriptblock]$Until, [int]$TimeoutSec = 6)
            $deadline = (Get-Date).AddSeconds($TimeoutSec)
            while (!(& $Until) -and (Get-Date) -lt $deadline) {
                $frame = [System.Windows.Threading.DispatcherFrame]::new()
                # ApplicationIdle, not Background. A Background sentinel outranks anything a test queued at idle.
                [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
                    [Action]{ $frame.Continue = $false })
                [System.Windows.Threading.Dispatcher]::PushFrame($frame)
                [System.Threading.Thread]::Sleep(20)
            }
        }
    }

    AfterAll {
        [PsUi.SessionManager]::DisposeSession($script:aeSessionId)
        Remove-Item function:Wait-Condition -ErrorAction SilentlyContinue
        Remove-Variable -Name aeSessionId, aeSession -Scope Script -ErrorAction SilentlyContinue
    }

    It 'completion nulls ActiveExecutor instead of leaving a disposed AsyncExecutor behind' {
        # Otherwise the only clear is SessionContext.Clear() at window teardown.
        $handle = Invoke-UiAsync -ScriptBlock { Start-Sleep -Milliseconds 150; 'ok' }
        [object]::ReferenceEquals($script:aeSession.ActiveExecutor, $handle.Executor) | Should -BeTrue
        Wait-Condition { $null -eq $script:aeSession.ActiveExecutor }
        $script:aeSession.ActiveExecutor | Should -BeNullOrEmpty
    }

    It 'an older run finishing does not clear a newer run out of ActiveExecutor' {
        $slow = Invoke-UiAsync -ScriptBlock { Start-Sleep -Milliseconds 200; 'slow' }
        $long = Invoke-UiAsync -ScriptBlock { Start-Sleep -Seconds 4; 'long' }
        [object]::ReferenceEquals($script:aeSession.ActiveExecutor, $long.Executor) | Should -BeTrue

        Wait-Condition { !$slow.Executor.IsRunning } 3
        $drained = @{ Idle = $false }
        [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
            [Action]{ $drained.Idle = $true })
        Wait-Condition { $drained.Idle } 2
        [object]::ReferenceEquals($script:aeSession.ActiveExecutor, $long.Executor) | Should -BeTrue

        # Cancel releases too.
        $long.Executor.Cancel()
        Wait-Condition { $null -eq $script:aeSession.ActiveExecutor }
        $script:aeSession.ActiveExecutor | Should -BeNullOrEmpty
    }
}

Describe 'Stop-UiAsync inside an async action warns at build' {
    BeforeAll {
        $script:swSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:swSessionId)
        $script:swSession = [PsUi.SessionManager]::Current
        $script:swSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterAll {
        [PsUi.SessionManager]::DisposeSession($script:swSessionId)
        Remove-Variable -Name swSessionId, swSession -Scope Script -ErrorAction SilentlyContinue
    }

    It 'an async action calling Stop-UiAsync warns that it would cancel itself' {
        $warnings = @()
        New-UiButton -Text 'Cancel' -Action { Stop-UiAsync } -WarningVariable warnings -WarningAction SilentlyContinue
        ($warnings -join ' ') | Should -Match 'cancel itself'
    }

    It 'the auto flip to sync suppresses the warning' {
        # -NoAsync lands in PSBoundParameters and that clause alone kills the warning. A spawner flips $NoAsync without binding it, which only the first clause guards.
        # New-UiWindow because it is a cmdlet, and the old scan only saw functions.
        $warnings = @()
        New-UiButton -Text 'CancelSpawn' -Action { New-UiWindow -Title 'x' -Content { }; Stop-UiAsync } -WarningVariable warnings -WarningAction SilentlyContinue
        $warnings.Count | Should -Be 0
    }

    It 'the flip covers each spawner' {
        foreach ($spawner in 'New-UiWindow', 'New-UiChildWindow', 'New-UiTool') {
            $warnings = @()
            New-UiButton -Text $spawner -Action ([scriptblock]::Create("$spawner -Title 'x' -Content { }; Stop-UiAsync")) -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings.Count | Should -Be 0 -Because "$spawner should flip the button to sync"

            # Zero warnings also happens when the scan misses Stop-UiAsync, so read the flip off the Tag.
            $panel = $script:swSession.CurrentParent
            $panel.Children[$panel.Children.Count - 1].Tag.NoAsync | Should -BeTrue -Because "$spawner should set NoAsync"
        }
    }

    It 'an explicit -NoAsync:$false suppresses it too (the user made the call)' {
        $warnings = @()
        New-UiButton -Text 'CancelForced' -NoAsync:$false -Action { Stop-UiAsync } -WarningVariable warnings -WarningAction SilentlyContinue
        $warnings.Count | Should -Be 0
    }

    It 'the name inside a string does not trip the AST scan' {
        $warnings = @()
        New-UiButton -Text 'Docs' -Action { Write-Host 'see Stop-UiAsync docs' } -WarningVariable warnings -WarningAction SilentlyContinue
        $warnings.Count | Should -Be 0
    }
}

# Private helpers behind the async paths, so module scope.
InModuleScope PsUi {
    Describe 'Test-UiActionOpensWindow' {
        It 'Sees each spawner as a call' {
            foreach ($spawner in 'New-UiWindow', 'New-UiChildWindow', 'New-UiTool') {
                Test-UiActionOpensWindow -Action ([scriptblock]::Create("$spawner -Title 'x' -Content { }")) | Should -BeTrue -Because $spawner
            }
        }

        It 'Ignores the name inside a string, and a dialog' {
            Test-UiActionOpensWindow -Action { Write-Host 'see New-UiWindow docs' } | Should -BeFalse
            Test-UiActionOpensWindow -Action { Show-UiMessageDialog -Message 'x' } | Should -BeFalse
        }
    }

    # Through the real pooled runspace, so the hydration order in StateHydrationEngine is what decides.
    Describe 'The session store against a variable picked up from scope' {
        BeforeAll {
            $script:storeId = [PsUi.SessionManager]::CreateSession()
            [PsUi.SessionManager]::SetCurrentSession($script:storeId)
            [PsUi.SessionManager]::Current.SetCapturedVariable('lastRun', 'FROM-STORE')

            function Invoke-StoreProbe {
                param([hashtable]$Bag)
                $executor                      = [PsUi.AsyncExecutor]::new()
                $executor.UsePipelineQueueMode = $true
                $executor.ExecuteAsync([scriptblock]::Create('"seen=$lastRun"'), $null, $Bag, $null, $null, $false)
                $deadline = [DateTime]::Now.AddSeconds(5)
                while ($executor.IsRunning -and [DateTime]::Now -lt $deadline) { Start-Sleep -Milliseconds 50 }
                Start-Sleep -Milliseconds 100
                $out = @($executor.DrainPipelineQueue(100))
                $executor.Dispose()
                "$out"
            }
        }

        AfterAll {
            [PsUi.SessionManager]::DisposeSession($script:storeId)
            Remove-Item function:Invoke-StoreProbe -ErrorAction SilentlyContinue
            Remove-Variable -Name storeId -Scope Script -ErrorAction SilentlyContinue
        }

        It 'Loses while the bag still carries the scope value, which was every click before' {
            Invoke-StoreProbe -Bag @{ lastRun = 'STALE' } | Should -Be 'seen=STALE'
        }

        It 'Wins once the bag has been through Remove-UiStoreShadow' {
            Invoke-StoreProbe -Bag (Remove-UiStoreShadow -Variables @{ lastRun = 'STALE' } -AutoNames 'lastRun') | Should -Be 'seen=FROM-STORE'
        }

        It 'Still loses to a name passed by hand' {
            Invoke-StoreProbe -Bag (Remove-UiStoreShadow -Variables @{ lastRun = 'STALE' } -AutoNames @()) | Should -Be 'seen=STALE'
        }
    }
}
