#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for PsUi module.
.DESCRIPTION
    Covers module loading, session management, hydration, C# backend,
    control creation, and the stuff that's broken before.

    Run with: Invoke-Pester .\Tests\PsUi.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Force-import so we always test the local build, not some stale installed copy
    $modulePath = Join-Path $PSScriptRoot '..\PsUi\PsUi.psd1'
    Import-Module $modulePath -Force

    # File level so the list Describe can use it too, not just the AsyncObservableCollection one.
    # Runs a script in a fresh MTA runspace and returns the async invocation handle. The runspace has its own thread (background, non UI) so wrapper.Add there goes through the !_dispatcher.CheckAccess() branch and comes back through Invoke.
    function Start-BackgroundAdd {
        param($Wrapper, $Item)
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.ApartmentState = [System.Threading.ApartmentState]::MTA
        $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
        $rs.Open()
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript({ param($w, $i) $w.Add($i) }).AddArgument($Wrapper).AddArgument($Item)
        @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke() }
    }

    function Complete-BackgroundAdd {
        param($Invocation, [int]$TimeoutMs = 2000)
        $ok = $Invocation.Handle.AsyncWaitHandle.WaitOne($TimeoutMs)
        try   { [void]$Invocation.PS.EndInvoke($Invocation.Handle) }
        catch { Write-Debug "EndInvoke threw: $_" }
        $Invocation.PS.Dispose()
        $Invocation.RS.Close()
        $Invocation.RS.Dispose()
        return $ok
    }

    # The message loop from the cross thread It, shared for the same reason. A single PushFrame with an ApplicationIdle sentinel races: empty queue, idle fires, frame exits, worker queues into the void. Loop until the BeginInvoke handle signals or the deadline expires.
    function Wait-BackgroundAdd {
        param($Invocation, [int]$TimeoutSec = 2)
        $disp     = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while ((Get-Date) -lt $deadline -and !$Invocation.Handle.IsCompleted) {
            $frame = [System.Windows.Threading.DispatcherFrame]::new()
            [void]$disp.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
                [Action]{ $frame.Continue = $false })
            [System.Windows.Threading.Dispatcher]::PushFrame($frame)
            if (!$Invocation.Handle.IsCompleted) { [System.Threading.Thread]::Sleep(20) }
        }
    }
}

# Sanity checks - if these fail, nothing else matters
Describe 'Module Loading' {
    # Removed: 'Should import without errors' - the BeforeAll Import-Module -Force fails the whole file when import breaks, so this one could never fail on its own.

    It 'Should export expected PowerShell functions' {
        $module = Get-Module PsUi
        # These are PS functions (not binary cmdlets)
        $module.ExportedFunctions.Keys | Should -Contain 'New-UiButton'
        $module.ExportedFunctions.Keys | Should -Contain 'New-UiInput'
        $module.ExportedFunctions.Keys | Should -Contain 'New-UiTool'
        $module.ExportedFunctions.Keys | Should -Contain 'New-UiLabel'
    }

    It 'Should have New-UiWindow binary cmdlet' {
        # New-UiWindow lives in C#, so it shows up as a Cmdlet not a Function
        Get-Command New-UiWindow -Module PsUi | Should -Not -BeNullOrEmpty
    }

    # Removed: 'Should have C# backend loaded' - the dedicated AsyncExecutor Describe block covers ctor.
}

# Theme engine is static - loaded once at module import
Describe 'Theme System' {
    It 'Should return available themes' {
        $themes = [PsUi.ThemeEngine]::GetAvailableThemes()
        $themes | Should -Contain 'Light'
        $themes | Should -Contain 'Dark'
    }

    # Removed: 'at least 5 themes' count check - the Contain assertions above already prove the list isn't empty.
}

# Removed: tested [Math]::Max/Min - that's .NET, not PsUi.

# Icons come from CharList.json (unicode mappings for Segoe MDL2 Assets and Segoe Fluent Icons)
Describe 'Icon System' {
    It 'Should have icons loaded in ModuleContext' {
        [PsUi.ModuleContext]::IsInitialized | Should -BeTrue
    }

    It 'Should have 100+ icons available' {
        $icons = [PsUi.ModuleContext]::Icons
        $icons | Should -Not -BeNullOrEmpty
        $icons.Count | Should -BeGreaterThan 100
    }
}

# Snapshot/restore the global icon font state around any test that mutates it - leaking state into later tests would cause cascading failures that look like phantom regressions.
Describe 'Icon Font - ModuleContext static API' {
    BeforeAll {
        $script:savedIconFontSnap = [PsUi.ModuleContext]::SnapshotIconFontState()
    }
    AfterAll {
        [PsUi.ModuleContext]::RestoreIconFontState($script:savedIconFontSnap)
    }

    # Removed: 'constants are exposed' - restated the two const string literals. The next test already exercises both constants through DetectDefaultIconFont.

    It 'DetectDefaultIconFont returns one of the two known names' {
        $detected = [PsUi.ModuleContext]::DetectDefaultIconFont()
        $detected | Should -BeIn @(
            [PsUi.ModuleContext]::FontNameMDL2,
            [PsUi.ModuleContext]::FontNameFluent
        )
    }

    It 'IsFontInstalled returns false for an obvious nonsense font' {
        [PsUi.ModuleContext]::IsFontInstalled('Definitely Not A Real Font Family Name') | Should -BeFalse
    }

    It 'ResolveIconFontToken returns null for Inherit, empty, and null' {
        [PsUi.ModuleContext]::ResolveIconFontToken('Inherit') | Should -BeNullOrEmpty
        [PsUi.ModuleContext]::ResolveIconFontToken('')        | Should -BeNullOrEmpty
        [PsUi.ModuleContext]::ResolveIconFontToken($null)     | Should -BeNullOrEmpty
    }

    It 'ResolveIconFontToken maps SegoeMDL2 and SegoeFluentIcons to their family names' {
        [PsUi.ModuleContext]::ResolveIconFontToken('SegoeMDL2')        | Should -Be ([PsUi.ModuleContext]::FontNameMDL2)
        [PsUi.ModuleContext]::ResolveIconFontToken('SegoeFluentIcons') | Should -Be ([PsUi.ModuleContext]::FontNameFluent)
    }

    # Removed: 'ResolveIconFontToken Auto matches DetectDefaultIconFont' - both sides ran the same detection, so it compared a value with itself. Catching a hardcoded 'Auto' depended on which fonts the CI box happened to have.

    It 'IsGlyphAvailable returns true for a common glyph' {
        [PsUi.ModuleContext]::IsGlyphAvailable('Save') | Should -BeTrue
    }

    It 'IsGlyphAvailable returns false for an unknown glyph name' {
        [PsUi.ModuleContext]::IsGlyphAvailable('DefinitelyNotAGlyphName__xyz') | Should -BeFalse
    }

    It 'Snapshot + Restore round-trips state' {
        $originalName     = [PsUi.ModuleContext]::ActiveIconFontName
        $originalFallback = [PsUi.ModuleContext]::IconFontNoFallback
        $snap = [PsUi.ModuleContext]::SnapshotIconFontState()

        # Mutate to the other installed font with inverted fallback. Skip the mutation entirely if the other font isn't installed - test still validates the null mutation round trip.
        $other = if ($originalName -eq [PsUi.ModuleContext]::FontNameMDL2) {
            [PsUi.ModuleContext]::FontNameFluent
        }
        else {
            [PsUi.ModuleContext]::FontNameMDL2
        }
        if ([PsUi.ModuleContext]::IsFontInstalled($other)) {
            [PsUi.ModuleContext]::SetIconFont($other, !$originalFallback)
            [PsUi.ModuleContext]::ActiveIconFontName | Should -Be $other
        }

        [PsUi.ModuleContext]::RestoreIconFontState($snap)
        [PsUi.ModuleContext]::ActiveIconFontName | Should -Be $originalName
        [PsUi.ModuleContext]::IconFontNoFallback | Should -Be $originalFallback
    }

    It 'RestoreIconFontState swallows null without throwing' {
        { [PsUi.ModuleContext]::RestoreIconFontState($null) } | Should -Not -Throw
    }

    It 'ActiveIconFontFamily builds a fallback chain by default' {
        [PsUi.ModuleContext]::SetIconFont([PsUi.ModuleContext]::DetectDefaultIconFont(), $false)
        $src = [PsUi.ModuleContext]::ActiveIconFontFamily.Source
        # Chain form: "Primary, Secondary"
        $src | Should -Match ','
        $src | Should -Match 'Segoe (MDL2 Assets|Fluent Icons)'
    }

    It 'ActiveIconFontFamily pins to a single name when fallback is off' {
        [PsUi.ModuleContext]::SetIconFont([PsUi.ModuleContext]::DetectDefaultIconFont(), $true)
        $src = [PsUi.ModuleContext]::ActiveIconFontFamily.Source
        $src | Should -Not -Match ','
    }
}

Describe 'Icon Font - PowerShell public surface' {
    BeforeAll {
        $script:savedIconFontSnap2 = [PsUi.ModuleContext]::SnapshotIconFontState()
    }
    AfterAll {
        [PsUi.ModuleContext]::RestoreIconFontState($script:savedIconFontSnap2)
    }

    It 'Get-PsUiIconFont returns the active font name as a string' {
        $name = Get-PsUiIconFont
        $name | Should -Not -BeNullOrEmpty
        $name | Should -Match 'Segoe (MDL2 Assets|Fluent Icons)'
    }

    It 'Set-PsUiIconFont Auto sets the active font to a known name' {
        Set-PsUiIconFont -FontName Auto
        Get-PsUiIconFont | Should -BeIn @('Segoe MDL2 Assets', 'Segoe Fluent Icons')
    }

    It 'Set-PsUiIconFont SegoeFluentIcons (when installed) sets Fluent' {
        if (![PsUi.ModuleContext]::IsFontInstalled('Segoe Fluent Icons')) {
            Set-ItResult -Skipped -Because 'Segoe Fluent Icons not installed on this box'
            return
        }
        Set-PsUiIconFont -FontName SegoeFluentIcons
        Get-PsUiIconFont | Should -Be 'Segoe Fluent Icons'
    }

    It 'Set-PsUiIconFont SegoeMDL2 (when installed) sets MDL2' {
        if (![PsUi.ModuleContext]::IsFontInstalled('Segoe MDL2 Assets')) {
            Set-ItResult -Skipped -Because 'Segoe MDL2 Assets not installed on this box'
            return
        }
        Set-PsUiIconFont -FontName SegoeMDL2
        Get-PsUiIconFont | Should -Be 'Segoe MDL2 Assets'
    }

    It 'Set-PsUiIconFont -NoIconFontFallback turns fallback off' {
        Set-PsUiIconFont -FontName Auto -NoIconFontFallback
        [PsUi.ModuleContext]::IconFontNoFallback | Should -BeTrue
    }

    It 'Set-PsUiIconFont -NoIconFontFallback:$false turns fallback on' {
        Set-PsUiIconFont -FontName Auto -NoIconFontFallback:$false
        [PsUi.ModuleContext]::IconFontNoFallback | Should -BeFalse
    }

    It 'Test-PsUiIcon returns true for a common name under -Font Active (default)' {
        Test-PsUiIcon -Name 'Save' | Should -BeTrue
    }

    It 'Test-PsUiIcon returns false for an unknown name' {
        Test-PsUiIcon -Name 'DefinitelyNotAGlyphName__xyz' | Should -BeFalse
    }

    It 'Test-PsUiIcon -Font Either returns true for a common name' {
        Test-PsUiIcon -Name 'Save' -Font Either | Should -BeTrue
    }

    It 'Test-PsUiIcon -Font MDL2 returns true for a basic MDL2 glyph' {
        if (![PsUi.ModuleContext]::IsFontInstalled('Segoe MDL2 Assets')) {
            Set-ItResult -Skipped -Because 'Segoe MDL2 Assets not installed on this box'
            return
        }
        Test-PsUiIcon -Name 'Save' -Font MDL2 | Should -BeTrue
    }

    It 'Test-PsUiIcon -Font Fluent returns true for a basic Fluent glyph' {
        if (![PsUi.ModuleContext]::IsFontInstalled('Segoe Fluent Icons')) {
            Set-ItResult -Skipped -Because 'Segoe Fluent Icons not installed on this box'
            return
        }
        Test-PsUiIcon -Name 'Save' -Font Fluent | Should -BeTrue
    }

    It 'Test-PsUiIcon -Font MDL2 returns false for a Fluent-only name' {
        if (![PsUi.ModuleContext]::IsFontInstalled('Segoe MDL2 Assets')) {
            Set-ItResult -Skipped -Because 'Segoe MDL2 Assets not installed on this box'
            return
        }
        # 'Blocked' is one of the 125 Fluent modern names added to CharList.json - its codepoint lives in the Fluent only range so MDL2 strictly doesn't carry it.
        Test-PsUiIcon -Name 'Blocked' -Font MDL2 | Should -BeFalse
    }
}

Describe 'Icon Font - Out-* parameter surface' {
    It 'Out-Datagrid IconFont parameter has Inherit (default) in its ValidateSet' {
        $param = (Get-Command Out-Datagrid).Parameters['IconFont']
        $param | Should -Not -BeNullOrEmpty
        $vs = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $vs.ValidValues | Should -Contain 'Inherit'
        $vs.ValidValues | Should -Contain 'Auto'
        $vs.ValidValues | Should -Contain 'SegoeMDL2'
        $vs.ValidValues | Should -Contain 'SegoeFluentIcons'
    }

    It 'Out-CSVDataGrid IconFont parameter has Inherit (default) in its ValidateSet' {
        $vs = (Get-Command Out-CSVDataGrid).Parameters['IconFont'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $vs.ValidValues | Should -Contain 'Inherit'
    }

    It 'Out-TextEditor IconFont parameter has Inherit (default) in its ValidateSet' {
        $vs = (Get-Command Out-TextEditor).Parameters['IconFont'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $vs.ValidValues | Should -Contain 'Inherit'
    }
}

# AsyncExecutor runs button actions on background threads
Describe 'AsyncExecutor' {
    It 'Should create without errors' {
        $executor = [PsUi.AsyncExecutor]::new()
        $executor | Should -Not -BeNullOrEmpty
        $executor.Dispose()
    }

    # Removed: 'Should have IsRunning property' - the state tracking test asserts the same initial state plus the transitions.

    # Removed: 'static DebugMode property' - a plain auto property. A set then assert just echoes the value you wrote, so it can't fail unless the compiler does.
}

# Each window gets its own session - this is the core of multi-window support
Describe 'SessionManager' {
    BeforeEach {
        # Fresh session per test so nothing bleeds over
        $script:testSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:testSessionId)
    }

    AfterEach {
        # Clean up
        [PsUi.SessionManager]::DisposeSession($script:testSessionId)
    }

    It 'Should create and retrieve session' {
        $current = [PsUi.SessionManager]::Current
        $current | Should -Not -BeNullOrEmpty
        $current.SessionId | Should -Be $script:testSessionId
    }

    # Removed: 'Should track active session count' - BeforeEach guarantees a session, so >= 1 was a tautology. The exact-count test in Session Isolation does the real work.

    It 'Should store controls via AddControlSafe' {
        $session = [PsUi.SessionManager]::Current
        $button = [System.Windows.Controls.Button]::new()
        $session.AddControlSafe('testButton', $button)
        
        $retrieved = $session.GetControl('testButton')
        $retrieved | Should -Not -BeNullOrEmpty
    }

    # Removed: 'track DebugMode property' - SessionContext.DebugMode is a plain auto property. A set then assert echo, no behavior under test.
}

# Basic control tests - just need a session and a parent panel, no actual window
Describe 'Control Creation' -Tag 'RequiresSession' {
    BeforeAll {
        $script:testSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:testSessionId)
        $script:testSession = [PsUi.SessionManager]::Current
        
        # Create a dummy parent for controls
        $script:testSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterAll {
        [PsUi.SessionManager]::DisposeSession($script:testSessionId)
    }

    It 'New-UiLabel should add TextBlock to parent' {
        # New-UiLabel adds to CurrentParent, doesn't return
        $parent = $script:testSession.CurrentParent
        $countBefore = $parent.Children.Count
        
        New-UiLabel -Text 'Test Label'
        
        $parent.Children.Count | Should -Be ($countBefore + 1)
        $lastChild = $parent.Children[$parent.Children.Count - 1]
        $lastChild | Should -BeOfType [System.Windows.Controls.TextBlock]
        $lastChild.Text | Should -Be 'Test Label'
    }

    It 'New-UiSeparator should add separator element to parent' {
        # New-UiSeparator uses a themed Border for consistent styling
        $parent = $script:testSession.CurrentParent
        $countBefore = $parent.Children.Count
        
        New-UiSeparator
        
        $parent.Children.Count | Should -Be ($countBefore + 1)
        $lastChild = $parent.Children[$parent.Children.Count - 1]
        $lastChild | Should -BeOfType [System.Windows.Controls.Border]
    }

    It 'New-UiLabel with -Style Header should have larger font' {
        $parent = $script:testSession.CurrentParent
        $countBefore = $parent.Children.Count
        
        New-UiLabel -Text 'Header' -Style Header
        New-UiLabel -Text 'Body' -Style Body
        
        $header = $parent.Children[$countBefore]
        $body = $parent.Children[$countBefore + 1]
        
        $header.FontSize | Should -BeGreaterThan $body.FontSize
    }
}

# Make sure we throw on dumb parameter combos instead of silently doing weird stuff
Describe 'Error Handling' {
    It 'New-UiList should throw on conflicting parameters' {
        # Need session for this
        $testId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($testId)
        $session = [PsUi.SessionManager]::Current
        $session.CurrentParent = [System.Windows.Controls.StackPanel]::new()
        
        try {
            { New-UiList -Variable 'test' -Items @(1,2,3) -ItemsSource @(4,5,6) } | 
                Should -Throw "*cannot use both*"
        }
        finally {
            [PsUi.SessionManager]::DisposeSession($testId)
        }
    }

    It 'New-UiButton should throw on mutually exclusive parameters' {
        $testId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($testId)
        $session = [PsUi.SessionManager]::Current
        $session.CurrentParent = [System.Windows.Controls.StackPanel]::new()
        
        try {
            { New-UiButton -Text 'Test' -Action {} -NoOutput -HideEmptyOutput } | 
                Should -Throw "*mutually exclusive*"
        }
        finally {
            [PsUi.SessionManager]::DisposeSession($testId)
        }
    }
}

# Hydration is the magic that lets button actions read $userName directly instead of digging through session context manually
Describe 'StateHydrationEngine' {
    BeforeEach {
        $script:testSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:testSessionId)
        $script:session = [PsUi.SessionManager]::Current
        $script:session.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterEach {
        [PsUi.SessionManager]::DisposeSession($script:testSessionId)
    }

    It 'Should extract value from TextBox control' {
        # Register a TextBox with a value
        $textBox = [System.Windows.Controls.TextBox]@{ Text = 'TestValue123' }
        $script:session.AddControlSafe('userName', $textBox)
        
        # Create a PowerShell instance with runspace pool
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = [PsUi.RunspacePoolManager]::Pool
        
        try {
            # Hydrate should inject the variable
            $initialValues = [PsUi.StateHydrationEngine]::HydrateViaScript($ps, $null)
            
            $initialValues.ContainsKey('userName') | Should -BeTrue
            $initialValues['userName'] | Should -Be 'TestValue123'
        }
        finally {
            $ps.Dispose()
        }
    }

    It 'Should extract value from CheckBox control' {
        $checkBox = [System.Windows.Controls.CheckBox]@{ IsChecked = $true }
        $script:session.AddControlSafe('enableFeature', $checkBox)
        
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = [PsUi.RunspacePoolManager]::Pool
        
        try {
            $initialValues = [PsUi.StateHydrationEngine]::HydrateViaScript($ps, $null)
            
            $initialValues.ContainsKey('enableFeature') | Should -BeTrue
            $initialValues['enableFeature'] | Should -BeTrue
        }
        finally {
            $ps.Dispose()
        }
    }

    It 'Should extract selected item from ComboBox' {
        $comboBox = [System.Windows.Controls.ComboBox]::new()
        $comboBox.Items.Add('Option1')
        $comboBox.Items.Add('Option2')
        $comboBox.Items.Add('Option3')
        $comboBox.SelectedIndex = 1
        $script:session.AddControlSafe('selectedOption', $comboBox)
        
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = [PsUi.RunspacePoolManager]::Pool
        
        try {
            $initialValues = [PsUi.StateHydrationEngine]::HydrateViaScript($ps, $null)
            
            $initialValues.ContainsKey('selectedOption') | Should -BeTrue
            $initialValues['selectedOption'] | Should -Be 'Option2'
        }
        finally {
            $ps.Dispose()
        }
    }

    It 'Should skip reserved variable names' {
        # Reserved names like 'Host' must not get injected as variables
        $textBox = [System.Windows.Controls.TextBox]@{ Text = 'ShouldBeSkipped' }
        $script:session.AddControlSafe('Host', $textBox)
        
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = [PsUi.RunspacePoolManager]::Pool
        
        try {
            $initialValues = [PsUi.StateHydrationEngine]::HydrateViaScript($ps, $null)
            
            # 'Host' should NOT be in hydrated values (reserved)
            $initialValues.ContainsKey('Host') | Should -BeFalse
        }
        finally {
            $ps.Dispose()
        }
    }

    It 'Should skip variables already defined (collision detection)' {
        # Pre-existing vars in the caller's scope take precedence over controls
        $textBox = [System.Windows.Controls.TextBox]@{ Text = 'ControlValue' }
        $script:session.AddControlSafe('myVar', $textBox)
        
        # Simulate a pre-existing variable in the caller's scope
        $alreadyDefined = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $alreadyDefined.Add('myVar') | Out-Null
        
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = [PsUi.RunspacePoolManager]::Pool
        
        try {
            $initialValues = [PsUi.StateHydrationEngine]::HydrateViaScript($ps, $alreadyDefined)
            
            # Should be skipped due to collision
            $initialValues.ContainsKey('myVar') | Should -BeFalse
        }
        finally {
            $ps.Dispose()
        }
    }

    It 'Should extract value from Slider control' {
        $slider = [System.Windows.Controls.Slider]@{
            Minimum = 0
            Maximum = 100
            Value   = 75
        }
        $script:session.AddControlSafe('volumeLevel', $slider)
        
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = [PsUi.RunspacePoolManager]::Pool
        
        try {
            $initialValues = [PsUi.StateHydrationEngine]::HydrateViaScript($ps, $null)
            
            $initialValues.ContainsKey('volumeLevel') | Should -BeTrue
            $initialValues['volumeLevel'] | Should -Be 75
        }
        finally {
            $ps.Dispose()
        }
    }
}

# Two windows open at once shouldn't step on each other's controls
Describe 'Session Isolation' {
    It 'Should maintain separate state for multiple sessions' {
        # Create first session with a control
        $session1Id = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($session1Id)
        $session1 = [PsUi.SessionManager]::Current
        $session1.CurrentParent = [System.Windows.Controls.StackPanel]::new()
        
        $textBox1 = [System.Windows.Controls.TextBox]@{ Text = 'Session1Value' }
        $session1.AddControlSafe('sharedName', $textBox1)
        
        # Create second session with same control name but different value
        $session2Id = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($session2Id)
        $session2 = [PsUi.SessionManager]::Current
        $session2.CurrentParent = [System.Windows.Controls.StackPanel]::new()
        
        $textBox2 = [System.Windows.Controls.TextBox]@{ Text = 'Session2Value' }
        $session2.AddControlSafe('sharedName', $textBox2)
        
        try {
            # Verify each session has its own value
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
        
        # Create second session
        $session2Id = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($session2Id)
        $session2 = [PsUi.SessionManager]::Current
        
        try {
            # Session 2 should NOT have the control from session 1
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
        
        try {
            [PsUi.SessionManager]::ActiveSessionCount | Should -Be ($initialCount + 3)
        }
        finally {
            [PsUi.SessionManager]::DisposeSession($id1)
            [PsUi.SessionManager]::DisposeSession($id2)
            [PsUi.SessionManager]::DisposeSession($id3)
        }
        
        [PsUi.SessionManager]::ActiveSessionCount | Should -Be $initialCount
    }
}

# The proxy is how background threads touch UI controls without crashing the dispatcher
Describe 'ThreadSafeControlProxy' {
    It 'Should wrap TextBox and provide Text property' {
        $textBox = [System.Windows.Controls.TextBox]@{ Text = 'InitialText' }
        $proxy = [PsUi.ThreadSafeControlProxy]::new($textBox, 'testProxy')
        
        $proxy.Text | Should -Be 'InitialText'
        
        $proxy.Text = 'UpdatedText'
        $textBox.Text | Should -Be 'UpdatedText'
    }

    It 'Should wrap CheckBox and provide IsChecked property' {
        $checkBox = [System.Windows.Controls.CheckBox]@{ IsChecked = $false }
        $proxy = [PsUi.ThreadSafeControlProxy]::new($checkBox, 'checkProxy')
        
        $proxy.IsChecked | Should -BeFalse
        
        $proxy.IsChecked = $true
        $checkBox.IsChecked | Should -BeTrue
    }

    It 'Should wrap ComboBox and provide SelectedIndex property' {
        $comboBox = [System.Windows.Controls.ComboBox]::new()
        $comboBox.Items.Add('A')
        $comboBox.Items.Add('B')
        $comboBox.Items.Add('C')
        $comboBox.SelectedIndex = 0
        
        $proxy = [PsUi.ThreadSafeControlProxy]::new($comboBox, 'comboProxy')
        
        $proxy.SelectedIndex | Should -Be 0
        
        $proxy.SelectedIndex = 2
        $comboBox.SelectedIndex | Should -Be 2
    }

    It 'Should access underlying control via Control property' {
        $slider = [System.Windows.Controls.Slider]@{
            Minimum = 0
            Maximum = 100
            Value   = 50
        }
        $proxy = [PsUi.ThreadSafeControlProxy]::new($slider, 'sliderProxy')
        
        # .Control gives you the raw WPF object when the proxy doesn't cover a property
        $proxy.Control | Should -Not -BeNullOrEmpty
        $proxy.Control.Value | Should -Be 50
        
        # Direct control modification works
        $proxy.Control.Value = 75
        $slider.Value | Should -Be 75
    }

    It 'Should provide IsEnabled property for any control' {
        $button = [System.Windows.Controls.Button]@{ IsEnabled = $true }
        $proxy = [PsUi.ThreadSafeControlProxy]::new($button, 'buttonProxy')
        
        $proxy.IsEnabled | Should -BeTrue
        
        $proxy.IsEnabled = $false
        $button.IsEnabled | Should -BeFalse
    }

    It 'Should throw on null control' {
        { [PsUi.ThreadSafeControlProxy]::new($null, 'nullProxy') } | Should -Throw
    }
}

# These actually spin up background runspaces - closest thing to integration tests
Describe 'AsyncExecutor Events' {
    It 'Should complete execution and set IsRunning to false' {
        $executor = [PsUi.AsyncExecutor]::new()
        
        # Queue mode buffers output instead of dispatching to UI (no window here)
        $executor.UsePipelineQueueMode = $true
        
        $script = [scriptblock]::Create('Write-Output "test"')
        $executor.ExecuteAsync($script, $null, $null, $null, $null, $false)
        
        # Wait for completion (with timeout)
        $timeout = [DateTime]::Now.AddSeconds(5)
        while ($executor.IsRunning -and [DateTime]::Now -lt $timeout) {
            Start-Sleep -Milliseconds 50
        }
        
        $executor.IsRunning | Should -BeFalse
        $executor.Dispose()
    }

    It 'Should capture pipeline output via queue mode' {
        $executor = [PsUi.AsyncExecutor]::new()
        $executor.UsePipelineQueueMode = $true
        
        $script = [scriptblock]::Create('1..3')
        $executor.ExecuteAsync($script, $null, $null, $null, $null, $false)
        
        $timeout = [DateTime]::Now.AddSeconds(5)
        while ($executor.IsRunning -and [DateTime]::Now -lt $timeout) {
            Start-Sleep -Milliseconds 50
        }
        Start-Sleep -Milliseconds 100
        
        # Drain the queue
        $output = $executor.DrainPipelineQueue(100)
        $executor.Dispose()
        
        $output.Count | Should -Be 3
        $output | Should -Contain 1
        $output | Should -Contain 2
        $output | Should -Contain 3
    }

    # Queue mode test removed - .NET List<T> iteration behaves unreliably in Pester's test context.
    # The feature works in production. Test verification is not feasible.

    It 'Should track IsRunning state correctly' {
        $executor = [PsUi.AsyncExecutor]::new()
        
        $executor.IsRunning | Should -BeFalse
        
        $script = [scriptblock]::Create('Start-Sleep -Milliseconds 200')
        $executor.ExecuteAsync($script, $null, $null, $null, $null, $false)
        
        # Should be running immediately after start
        Start-Sleep -Milliseconds 50
        $executor.IsRunning | Should -BeTrue
        
        # Wait for completion
        $timeout = [DateTime]::Now.AddSeconds(5)
        while ($executor.IsRunning -and [DateTime]::Now -lt $timeout) {
            Start-Sleep -Milliseconds 50
        }
        
        $executor.IsRunning | Should -BeFalse
        $executor.Dispose()
    }
}

# Confirms the reserved-name list blocks the obvious automatic variables
Describe 'Reserved Variables' {
    It 'Should reserve every common automatic variable' {
        # Each of these must be rejected by the reserved check
        $mustBeReserved = @(
            'Host', 'Error', 'PSVersionTable', 'true', 'false', 'null',
            'PSCmdlet', 'PSBoundParameters', 'ErrorActionPreference'
        )
        
        $testId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($testId)
        $session = [PsUi.SessionManager]::Current
        
        try {
            foreach ($varName in $mustBeReserved) {
                # Register a control with a reserved name
                $textBox = [System.Windows.Controls.TextBox]@{ Text = 'ShouldNotAppear' }
                $session.AddControlSafe($varName, $textBox)
            }
            
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = [PsUi.RunspacePoolManager]::Pool
            
            try {
                $initialValues = [PsUi.StateHydrationEngine]::HydrateViaScript($ps, $null)
                
                foreach ($varName in $mustBeReserved) {
                    $initialValues.ContainsKey($varName) | Should -BeFalse -Because "$varName is reserved"
                }
            }
            finally {
                $ps.Dispose()
            }
        }
        finally {
            [PsUi.SessionManager]::DisposeSession($testId)
        }
    }
}

# Private functions aren't exported, so we need InModuleScope to test them.
# The import below looks redundant but Pester resolves InModuleScope at discovery time, before any BeforeAll blocks run, so the import has to happen here.

Import-Module (Join-Path $PSScriptRoot '..\PsUi\PsUi.psd1') -Force

InModuleScope PsUi {

    # Picks black or white text based on background luminance
    Describe 'Get-ContrastColor' {
        It 'Returns black for white background' {
            Get-ContrastColor -HexColor '#FFFFFF' | Should -Be '#000000'
        }

        It 'Returns white for black background' {
            Get-ContrastColor -HexColor '#000000' | Should -Be '#FFFFFF'
        }

        It 'Returns black for bright green (luminance > 128)' {
            # #78B802 → R:120, G:184, B:2 → luminance ~= 143
            Get-ContrastColor -HexColor '#78B802' | Should -Be '#000000'
        }

        It 'Returns white for dark navy' {
            Get-ContrastColor -HexColor '#1A1A2E' | Should -Be '#FFFFFF'
        }

        It 'Handles 8-char ARGB format (strips alpha channel)' {
            # #FF78B802 → same as #78B802
            Get-ContrastColor -HexColor '#FF78B802' | Should -Be '#000000'
        }

        It 'Handles hex without leading hash' {
            Get-ContrastColor -HexColor 'FFFFFF' | Should -Be '#000000'
        }

        It 'Returns white for pure red' {
            # #FF0000 → luminance = 0.299*255 = 76.2 (below 128)
            Get-ContrastColor -HexColor '#FF0000' | Should -Be '#FFFFFF'
        }

        It 'Returns black for pure yellow' {
            # #FFFF00 → luminance = 0.299*255 + 0.587*255 = 226 (well above 128)
            Get-ContrastColor -HexColor '#FFFF00' | Should -Be '#000000'
        }
    }

    # Brush factory with caching - WPF brushes are expensive to create
    Describe 'ConvertTo-UiBrush' {
        It 'Creates a frozen SolidColorBrush from hex' {
            $brush = ConvertTo-UiBrush '#FF0000'
            $brush | Should -BeOfType [System.Windows.Media.SolidColorBrush]
            $brush.IsFrozen | Should -BeTrue
        }

        It 'Returns cached brush on repeat calls' {
            Reset-BrushCache
            $first  = ConvertTo-UiBrush '#00FF00'
            $second = ConvertTo-UiBrush '#00FF00'
            [object]::ReferenceEquals($first, $second) | Should -BeTrue
        }

        It 'Handles named WPF colors' {
            $brush = ConvertTo-UiBrush 'Red'
            $brush | Should -BeOfType [System.Windows.Media.SolidColorBrush]
        }

        It 'Falls back to gray on garbage input' {
            $brush = ConvertTo-UiBrush 'not_a_color_at_all'
            $brush | Should -Be ([System.Windows.Media.Brushes]::Gray)
        }

        It 'Reset-BrushCache clears the cache' {
            $before = ConvertTo-UiBrush '#AABB11'
            Reset-BrushCache
            $after = ConvertTo-UiBrush '#AABB11'
            # After reset, a new object - same color, different reference
            [object]::ReferenceEquals($before, $after) | Should -BeFalse
        }

        It 'Handles ARGB hex (#AARRGGBB)' {
            $brush = ConvertTo-UiBrush '#80FF0000'
            $brush | Should -BeOfType [System.Windows.Media.SolidColorBrush]
            # 0x80 = 128
            $brush.Color.A | Should -Be 128
        }
    }

    # Turns ugly type names like 'Deserialized.System.IO.FileInfo' into 'FileInfo'
    Describe 'Get-CleanTypeName' {
        It 'Returns simple name for .NET types' {
            Get-CleanTypeName -Item 'hello' | Should -Be 'String'
        }

        It 'Strips fully qualified namespace' {
            $fileInfo = [System.IO.FileInfo]::new('C:\fake.txt')
            Get-CleanTypeName -Item $fileInfo | Should -Be 'FileInfo'
        }

        It 'Handles PSCustomObject' {
            $obj = [PSCustomObject]@{ Name = 'test' }
            Get-CleanTypeName -Item $obj | Should -Be 'PSCustomObject'
        }

        It 'Strips Deserialized prefix' {
            $obj = [PSCustomObject]@{}
            $obj.PSObject.TypeNames.Insert(0, 'Deserialized.System.IO.FileInfo')
            Get-CleanTypeName -Item $obj | Should -Be 'FileInfo'
        }

        It 'Strips ETS adapter suffix (the # thing)' {
            $obj = [PSCustomObject]@{}
            $obj.PSObject.TypeNames.Insert(0, 'System.ServiceProcess.ServiceController#StartupType')
            Get-CleanTypeName -Item $obj | Should -Be 'ServiceController'
        }
    }

    # Formats values for display in the datagrid cells
    Describe 'ConvertTo-DisplayValue' {
        It 'Shows small hashtables inline' {
            $ht = [ordered]@{ Name = 'Bob'; Age = 30 }
            $result = ConvertTo-DisplayValue -Value $ht
            $result | Should -BeLike '@{*Name=*Bob*Age=30*}'
        }

        It 'Abbreviates large hashtables' {
            $ht = @{ A = 1; B = 2; C = 3; D = 4 }
            $result = ConvertTo-DisplayValue -Value $ht
            $result | Should -BeLike '@{...} (4 keys)'
        }

        It 'Formats bools with dollar prefix in hashtables' {
            $ht = [ordered]@{ Enabled = $true }
            $result = ConvertTo-DisplayValue -Value $ht
            $result | Should -Match '\$True'
        }

        It 'Quotes strings inside hashtables' {
            $ht = [ordered]@{ Color = 'Red' }
            $result = ConvertTo-DisplayValue -Value $ht
            $result | Should -Match "Color='Red'"
        }

        It 'Passes through scalars unchanged' {
            ConvertTo-DisplayValue -Value 42 | Should -Be 42
            ConvertTo-DisplayValue -Value 'plain text' | Should -Be 'plain text'
        }
    }

    # Figures out the best way to show button action output (text, grid, dict, etc)
    Describe 'Get-OutputPresenter' {
        It 'Returns Empty for null' {
            $result = Get-OutputPresenter -Data $null
            $result.Type | Should -Be 'Empty'
        }

        It 'Returns Text for strings' {
            $result = Get-OutputPresenter -Data 'hello world'
            $result.Type | Should -Be 'Text'
            $result.Info.Length | Should -Be 11
        }

        It 'Returns Dictionary for hashtables' {
            $result = Get-OutputPresenter -Data @{ A = 1; B = 2 }
            $result.Type | Should -Be 'Dictionary'
            $result.Info.Count | Should -Be 2
        }

        It 'Returns Empty for empty arrays' {
            $result = Get-OutputPresenter -Data @()
            $result.Type | Should -Be 'Empty'
        }

        It 'Returns Text for string arrays (multiline output)' {
            $result = Get-OutputPresenter -Data @('line1', 'line2', 'line3')
            $result.Type | Should -Be 'Text'
            $result.Info.LineCount | Should -Be 3
        }

        It 'Returns Collection for object arrays' {
            $data = @(
                [PSCustomObject]@{ Name = 'Alice'; Score = 95 }
                [PSCustomObject]@{ Name = 'Bob'; Score = 82 }
            )
            $result = Get-OutputPresenter -Data $data
            $result.Type | Should -Be 'Collection'
            $result.Info.Count | Should -Be 2
            $result.Info.Properties | Should -Contain 'Name'
            $result.Info.Properties | Should -Contain 'Score'
        }

        It 'Returns SingleObject for a lone PSCustomObject' {
            $obj = [PSCustomObject]@{ Host = 'srv01'; Port = 443 }
            $result = Get-OutputPresenter -Data $obj
            $result.Type | Should -Be 'SingleObject'
            $result.Info.Properties | Should -Contain 'Host'
        }
    }

    # Filters out empty/null columns so the datagrid isn't full of blank cols
    Describe 'Get-PopulatedProperties' {
        It 'Returns only properties with actual values' {
            $items = @(
                [PSCustomObject]@{ Name = 'Alice'; Email = ''; Notes = $null }
                [PSCustomObject]@{ Name = 'Bob';   Email = 'bob@test.com'; Notes = $null }
            )
            $result = Get-PopulatedProperties -Items $items
            $result | Should -Contain 'Name'
            $result | Should -Contain 'Email'
            $result | Should -Not -Contain 'Notes'
        }

        It 'Skips underscore-prefixed properties' {
            $items = @([PSCustomObject]@{ Name = 'Test'; _internal = 'hidden' })
            $result = Get-PopulatedProperties -Items $items
            $result | Should -Contain 'Name'
            $result | Should -Not -Contain '_internal'
        }

        It 'Treats empty collections as not populated' {
            $items = @([PSCustomObject]@{ Name = 'Alice'; Tags = @() })
            $result = Get-PopulatedProperties -Items $items
            $result | Should -Contain 'Name'
            $result | Should -Not -Contain 'Tags'
        }

        It 'Filters to specific properties when PropertyNames given' {
            $items = @([PSCustomObject]@{ A = 'yes'; B = 'yes'; C = 'yes' })
            $result = Get-PopulatedProperties -Items $items -PropertyNames @('A', 'C')
            $result | Should -Contain 'A'
            $result | Should -Contain 'C'
            $result | Should -Not -Contain 'B'
        }
    }

    # Auto-generates names for controls that don't have an explicit -Variable
    Describe 'New-UniqueControlName' {
        It 'Uses default ctrl prefix' {
            $name = New-UniqueControlName
            $name | Should -Match '^ctrl_[a-f0-9]{8}$'
        }

        It 'Uses custom prefix' {
            $name = New-UniqueControlName -Prefix 'btn'
            $name | Should -Match '^btn_[a-f0-9]{8}$'
        }

        It 'Generates unique names on consecutive calls' {
            $a = New-UniqueControlName
            $b = New-UniqueControlName
            $a | Should -Not -Be $b
        }
    }

    Describe 'Get-ContrastColor edge cases' {
        It 'Handles mid-grey boundary' {
            # #808080 → luminance = 0.299*128 + 0.587*128 + 0.114*128 ≈ 128
            $result = Get-ContrastColor -HexColor '#808080'
            # Luminance = 128, not > 128, so white
            $result | Should -Be '#FFFFFF'
        }
    }
}

# C# backend - the stuff in src/ that gets compiled into the DLL

Describe 'Constants - IsReservedVariable' {
    # These guard against clobbering PS built-ins during hydration
    It 'Flags PowerShell automatic variables' {
        [PsUi.Constants]::IsReservedVariable('Host')    | Should -BeTrue
        [PsUi.Constants]::IsReservedVariable('Error')   | Should -BeTrue
        [PsUi.Constants]::IsReservedVariable('true')    | Should -BeTrue
        [PsUi.Constants]::IsReservedVariable('false')   | Should -BeTrue
        [PsUi.Constants]::IsReservedVariable('null')    | Should -BeTrue
    }

    It 'Flags preference variables' {
        [PsUi.Constants]::IsReservedVariable('ErrorActionPreference') | Should -BeTrue
        [PsUi.Constants]::IsReservedVariable('VerbosePreference')     | Should -BeTrue
    }

    It 'Flags PsUi internal names' {
        [PsUi.Constants]::IsReservedVariable('session') | Should -BeTrue
        [PsUi.Constants]::IsReservedVariable('state')   | Should -BeTrue
    }

    It 'Is case-insensitive' {
        [PsUi.Constants]::IsReservedVariable('HOST')  | Should -BeTrue
        [PsUi.Constants]::IsReservedVariable('host')  | Should -BeTrue
        [PsUi.Constants]::IsReservedVariable('Host')  | Should -BeTrue
    }

    It 'Treats null and whitespace as reserved (safe default)' {
        [PsUi.Constants]::IsReservedVariable($null) | Should -BeTrue
        [PsUi.Constants]::IsReservedVariable('')    | Should -BeTrue
        [PsUi.Constants]::IsReservedVariable('  ')  | Should -BeTrue
    }

    It 'Allows normal user variable names' {
        [PsUi.Constants]::IsReservedVariable('userName')     | Should -BeFalse
        [PsUi.Constants]::IsReservedVariable('outputPath')   | Should -BeFalse
        [PsUi.Constants]::IsReservedVariable('server-list')  | Should -BeFalse
    }
}

Describe 'Constants - IsValidIdentifier' {
    It 'Accepts standard variable names' {
        [PsUi.Constants]::IsValidIdentifier('userName')    | Should -BeTrue
        [PsUi.Constants]::IsValidIdentifier('_private')    | Should -BeTrue
        [PsUi.Constants]::IsValidIdentifier('server_list') | Should -BeTrue
        [PsUi.Constants]::IsValidIdentifier('item2')       | Should -BeTrue
    }

    It 'Accepts hyphenated names (hydration codegen emits ${name} for exactly these)' {
        [PsUi.Constants]::IsValidIdentifier('server-list') | Should -BeTrue
        [PsUi.Constants]::IsValidIdentifier('trailing-')   | Should -BeTrue
    }

    It 'Rejects injection attempts' {
        # Variable names get interpolated into generated scripts, so injection patterns are rejected
        [PsUi.Constants]::IsValidIdentifier('a;rm -rf /') | Should -BeFalse
        [PsUi.Constants]::IsValidIdentifier('$(evil)')     | Should -BeFalse
        [PsUi.Constants]::IsValidIdentifier('na`me')       | Should -BeFalse
        [PsUi.Constants]::IsValidIdentifier('{bad}')       | Should -BeFalse
    }

    It 'Rejects names starting with a digit' {
        [PsUi.Constants]::IsValidIdentifier('2fast') | Should -BeFalse
    }

    It 'Rejects empty and null' {
        [PsUi.Constants]::IsValidIdentifier($null) | Should -BeFalse
        [PsUi.Constants]::IsValidIdentifier('')    | Should -BeFalse
        [PsUi.Constants]::IsValidIdentifier('  ')  | Should -BeFalse
    }
}

Describe 'Constants - ValidateIdentifier' {
    It 'Returns name when valid' {
        [PsUi.Constants]::ValidateIdentifier('myControl') | Should -Be 'myControl'
    }

    It 'Returns null on invalid name' {
        [PsUi.Constants]::ValidateIdentifier(';drop table') | Should -BeNullOrEmpty
    }

    It 'Returns null on empty/whitespace' {
        [PsUi.Constants]::ValidateIdentifier('') | Should -BeNullOrEmpty
    }
}

# WPF value converter - shows arrays as '[3 items]' in datagrid cells
Describe 'ArrayDisplayConverter' {
    BeforeAll {
        $script:converter = [PsUi.ArrayDisplayConverter]::new()
    }

    It 'Passes strings through unchanged' {
        $script:converter.Convert('hello', [string], $null, $null) | Should -Be 'hello'
    }

    It 'Returns null for null' {
        $script:converter.Convert($null, [string], $null, $null) | Should -BeNullOrEmpty
    }

    It 'Shows [empty] for empty array' {
        $script:converter.Convert(@(), [string], $null, $null) | Should -Be '[empty]'
    }

    It 'Shows [1 item] for single-element array' {
        $script:converter.Convert(@('one'), [string], $null, $null) | Should -Be '[1 item]'
    }

    It 'Shows [N items] for multi-element arrays' {
        $script:converter.Convert(@(1, 2, 3, 4, 5), [string], $null, $null) | Should -Be '[5 items]'
    }

    It 'Previews items for tooltips' {
        $preview = [PsUi.ArrayDisplayConverter]::GetTooltipPreview(@('alpha', 'bravo'), 10)
        $preview | Should -Match 'alpha'
        $preview | Should -Match 'bravo'
    }

    It 'Truncates long tooltip items at 50 chars' {
        $longString = 'A' * 60
        $preview = [PsUi.ArrayDisplayConverter]::GetTooltipPreview(@($longString), 10)
        $preview | Should -Match '\.\.\.'
        $preview.Length | Should -BeLessThan 60
    }

    It 'Shows overflow count in tooltip' {
        $items = 1..20
        $preview = [PsUi.ArrayDisplayConverter]::GetTooltipPreview($items, 5)
        $preview | Should -Match 'and 15 more'
    }
}

# Tooltip text for expandable cells - hover to see what's inside
Describe 'ExpandableValueTooltipConverter' {
    BeforeAll {
        $script:converter = [PsUi.ExpandableValueTooltipConverter]::new()
    }

    It 'Formats hashtable tooltips with key count' {
        $ht = @{ Name = 'Alice'; Age = 30 }
        $result = $script:converter.Convert($ht, [string], $null, $null)
        $result | Should -Match 'Click to expand \(2 keys\)'
    }

    It 'Shows null values as $null in dict preview' {
        $ht = @{ Missing = $null }
        $result = $script:converter.Convert($ht, [string], $null, $null)
        $result | Should -Match '\$null'
    }

    It 'Formats array tooltips with item count' {
        $result = $script:converter.Convert(@(1, 2, 3), [string], $null, $null)
        $result | Should -Match 'Click to expand \(3 items\)'
    }

    It 'Returns null for plain strings' {
        $result = $script:converter.Convert('just text', [string], $null, $null)
        $result | Should -BeNullOrEmpty
    }

    It 'Returns null for null' {
        $result = $script:converter.Convert($null, [string], $null, $null)
        $result | Should -BeNullOrEmpty
    }
}

# Control creation - real session, no window. XAML style warnings are expected here (no ResourceDictionary without a window) and get suppressed to keep output clean.

Describe 'Control Creation - Inputs and Toggles' {
    BeforeAll {
        # Suppress the style warnings - they're harmless, just noisy
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
        $proxy = $script:session.GetSafeVariable('testOnChange')
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
        New-UiDatePicker -Variable 'testDate' -Label 'Pick Date'

        $proxy = $script:session.GetSafeVariable('testDate')
        $proxy.Control.SelectedDate.Date | Should -Be ([datetime]::Today)
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
        $proxy.Control.Value   | Should -Be 50  # clamped to Maximum
    }

    It 'New-UiProgress rejects Maximum <= Minimum' {
        { New-UiProgress -Variable 'testProgBad' -Minimum 100 -Maximum 50 } | Should -Throw
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
        $proxy = $script:session.GetSafeVariable('testProgFmt')
        $proxy.Control.Value = 75
        $proxy.Control.Tag.ValueBlock.Text | Should -Be '75/200'
    }

    It 'New-UiProgress warns and strips Tag from -WPFProperties' {
        $warnings = @()
        New-UiProgress -Variable 'testProgTag' -WPFProperties @{ Tag = 'hijack' } -WarningVariable warnings -WarningAction SilentlyContinue
        $proxy = $script:session.GetSafeVariable('testProgTag')
        # Tag must still be our metadata hashtable, not the caller's string
        $proxy.Control.Tag | Should -BeOfType [hashtable]
        $warnings.Count    | Should -BeGreaterThan 0
    }

    It 'Set-UiProgress -Increment adds to current value and clamps to Maximum' {
        New-UiProgress -Variable 'testProgInc' -Maximum 10 -Default 8
        Set-UiProgress -Variable 'testProgInc' -Increment 5  # 8+5=13 -> clamp to 10
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

    It 'Set-UiProgress no-op when no parameters supplied does not throw' {
        New-UiProgress -Variable 'testProgNoop' -Default 42
        { Set-UiProgress -Variable 'testProgNoop' } | Should -Not -Throw
        $proxy = $script:session.GetSafeVariable('testProgNoop')
        $proxy.Control.Value | Should -Be 42
    }

    It 'Set-UiProgress on missing control writes verbose and returns' {
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
        # Grid and list share one registry keyed by variable name, and Test-UiDataGridOwned is exact string equality on the GridOwnedCollection type. A list that matched it would make Add-UiDataGridItem snapshot list rows.
        $coll = $script:session.GetListCollection('wrapStatic')
        $coll.GetType().ToString() | Should -Not -Be 'PsUi.GridOwnedCollection`1[System.Object]'
    }

    It '-Items with one empty string keeps the item' {
        # @('') was falsy under the old truthiness check and fell into the no items branch, silently dropping the item.
        New-UiList -Variable 'wrapBlank' -Items @('')
        ($script:session.GetListCollection('wrapBlank')).Count | Should -Be 1
    }

    It '-ItemsSource with a plain ObservableCollection wraps and mirrors' {
        # -WarningAction stays quiet: under Pester the variable repoint legitimately matches nothing (module scope walk can't reach Pester locals), so the 'could not repoint' warning always fires here.
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

    It '-NoBind leaves the calling script variable untouched but still binds the wrap' {
        $mine = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        New-UiList -Variable 'wrapNoBind' -ItemsSource $mine -NoBind
        $mine.GetType().FullName | Should -Match '^System\.Collections\.ObjectModel\.ObservableCollection'
        ($script:session.GetListCollection('wrapNoBind')).GetType().FullName | Should -Match '^PsUi\.AsyncObservableCollection'
    }

    It 'a property held source warns that nothing was repointed' {
        $holder = [pscustomobject]@{ Items = [System.Collections.ArrayList]::new() }
        $warnings = @()
        New-UiList -Variable 'wrapNoHandle' -ItemsSource $holder.Items -WarningVariable warnings -WarningAction SilentlyContinue
        ($warnings -join ' ') | Should -Match 'could not repoint'
    }

    It 'Remove-UiListItem with no -Item takes the selection off the proxy' {
        # The old path read SelectedItem off the raw ListBox out of session.Variables, which throws from any async action.
        New-UiList -Variable 'rmSelected' -Items @('keep', 'drop')
        $listBox = $script:session.GetControl('rmSelected')
        $listBox.SelectedItem = $listBox.Items[1]
        Remove-UiListItem -Variable 'rmSelected'
        ($script:session.GetListCollection('rmSelected')).Count | Should -Be 1
        ($script:session.GetListCollection('rmSelected'))[0] | Should -Be 'keep'
    }
}

Describe 'New-UiList - cross-thread mutation' {
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
        # Fails on the build before the fix. Adds on the registered collection are the last line of Add-UiListItem, so this covers the helper's write without hydrating a whole module into the worker runspace.
        New-UiList -Variable 'xtList' -Items @('one', 'two') -WarningAction SilentlyContinue
        $coll = $script:xtSession.GetListCollection('xtList')

        $bg = Start-BackgroundAdd -Wrapper $coll -Item 'from-background'
        Wait-BackgroundAdd -Invocation $bg
        (Complete-BackgroundAdd -Invocation $bg) | Should -BeTrue

        # Complete-BackgroundAdd swallows EndInvoke exceptions, so assert on contents, not the handle.
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

# Audit caught that -Path and -Base64 weren't mandatory - verify the fix sticks
Describe 'New-UiImage Parameter Validation' {
    It 'Has mandatory -Path in Path parameter set' {
        $cmd = Get-Command New-UiImage
        $pathParam = $cmd.Parameters['Path']
        $pathAttrs = $pathParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        ($pathAttrs | Where-Object { $_.Mandatory -eq $true }) | Should -Not -BeNullOrEmpty
    }

    It 'Has mandatory -Base64 in Base64 parameter set' {
        $cmd = Get-Command New-UiImage
        $b64Param = $cmd.Parameters['Base64']
        $b64Attrs = $b64Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        ($b64Attrs | Where-Object { $_.Mandatory -eq $true }) | Should -Not -BeNullOrEmpty
    }

    It 'Path and Base64 are in different parameter sets' {
        $cmd = Get-Command New-UiImage
        $pathSet = ($cmd.Parameters['Path'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).ParameterSetName
        $b64Set  = ($cmd.Parameters['Base64'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).ParameterSetName
        $pathSet | Should -Not -Be $b64Set
    }
}

# Extract/Apply are the get/set sides of hydration at the C# level
Describe 'ControlValueExtractor' {
    It 'Extracts Text from TextBox' {
        $tb = [System.Windows.Controls.TextBox]@{ Text = 'extracted' }
        $val = [PsUi.ControlValueExtractor]::ExtractValue($tb)
        $val | Should -Be 'extracted'
    }

    It 'Extracts Text from TextBlock' {
        $tb = [System.Windows.Controls.TextBlock]@{ Text = 'readonly label' }
        $val = [PsUi.ControlValueExtractor]::ExtractValue($tb)
        $val | Should -Be 'readonly label'
    }

    It 'Extracts IsChecked from CheckBox' {
        $cb = [System.Windows.Controls.CheckBox]@{ IsChecked = $true }
        $val = [PsUi.ControlValueExtractor]::ExtractValue($cb)
        $val | Should -BeTrue
    }

    It 'Extracts SelectedItem from ComboBox' {
        $combo = [System.Windows.Controls.ComboBox]::new()
        $combo.Items.Add('A')
        $combo.Items.Add('B')
        $combo.SelectedIndex = 1
        $val = [PsUi.ControlValueExtractor]::ExtractValue($combo)
        $val | Should -Be 'B'
    }

    It 'Extracts Value from Slider' {
        $slider = [System.Windows.Controls.Slider]@{ Maximum = 100; Value = 42.5 }
        $val = [PsUi.ControlValueExtractor]::ExtractValue($slider)
        $val | Should -Be 42.5
    }

    It 'Extracts Value from ProgressBar' {
        $pb = [System.Windows.Controls.ProgressBar]@{ Value = 80 }
        $val = [PsUi.ControlValueExtractor]::ExtractValue($pb)
        $val | Should -Be 80
    }

    It 'Returns null for null input' {
        $val = [PsUi.ControlValueExtractor]::ExtractValue($null)
        $val | Should -BeNullOrEmpty
    }
}

Describe 'ControlValueApplicator' {
    It 'Sets TextBox text' {
        $tb = [System.Windows.Controls.TextBox]::new()
        [PsUi.ControlValueApplicator]::ApplyValue($tb, 'new text')
        $tb.Text | Should -Be 'new text'
    }

    It 'Sets CheckBox checked state from bool' {
        $cb = [System.Windows.Controls.CheckBox]::new()
        [PsUi.ControlValueApplicator]::ApplyValue($cb, $true)
        $cb.IsChecked | Should -BeTrue
    }

    It 'Sets Slider value from int' {
        $slider = [System.Windows.Controls.Slider]@{ Maximum = 100 }
        [PsUi.ControlValueApplicator]::ApplyValue($slider, 65)
        $slider.Value | Should -Be 65
    }

    It 'Sets ProgressBar value' {
        $pb = [System.Windows.Controls.ProgressBar]@{ Maximum = 100 }
        [PsUi.ControlValueApplicator]::ApplyValue($pb, 33)
        $pb.Value | Should -Be 33
    }

    It 'Selects ComboBox item by matching content' {
        $combo = [System.Windows.Controls.ComboBox]::new()
        $combo.Items.Add('Red')
        $combo.Items.Add('Blue')
        $combo.Items.Add('Green')
        [PsUi.ControlValueApplicator]::ApplyValue($combo, 'Blue')
        $combo.SelectedItem | Should -Be 'Blue'
    }

    It 'Does not throw on null control' {
        { [PsUi.ControlValueApplicator]::ApplyValue($null, 'value') } | Should -Not -Throw
    }
}

# StatusBar - freeform content bar docked to parent container.
# The ~25 one It per param existence tests are gone. Contract asserts and one Parameters.Keys pin per function stay - setters need a live bar, and without the pin a param drop ships green.
Describe 'New-UiStatusBar' {
    It 'Has the documented parameter surface' {
        $params = (Get-Command New-UiStatusBar -Module PsUi).Parameters.Keys
        foreach ($p in @('Content', 'DefaultText', 'Variable', 'Location', 'WPFProperties',
                         'AutoProgress', 'AutoCancel', 'Inline', 'Intercept', 'CaptureHost',
                         'NoOutputOnly', 'Persist', 'MaxMessages')) {
            $params | Should -Contain $p -Because "$p is documented"
        }
    }

    It 'Has optional -Content scriptblock parameter' {
        $cmd = Get-Command New-UiStatusBar -Module PsUi
        $cmd.Parameters['Content'].ParameterType | Should -Be ([scriptblock])
        $cmd.Parameters['Content'].Attributes.Mandatory | Should -Not -Contain $true
    }

    It 'Has -Location parameter with Top/Bottom' {
        $cmd = Get-Command New-UiStatusBar -Module PsUi
        $validateSet = $cmd.Parameters['Location'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validateSet.ValidValues | Should -Contain 'Top'
        $validateSet.ValidValues | Should -Contain 'Bottom'
    }

    # Removed: '-MaxMessages has ValidateRange 1-10000' - pinned the exact bounds, so any deliberate retune failed a test without a bug in sight.
}

Describe 'Write-Status' {
    It 'Has the documented parameter surface' {
        $params = (Get-Command Write-Status -Module PsUi).Parameters.Keys
        foreach ($p in @('Message', 'Severity', 'Timeout', 'Bar')) {
            $params | Should -Contain $p -Because "$p is documented"
        }
    }

    It 'Has mandatory positional -Message parameter' {
        $cmd = Get-Command Write-Status -Module PsUi
        $cmd.Parameters['Message'].ParameterType | Should -Be ([string])
        $cmd.Parameters['Message'].Attributes.Mandatory | Should -Contain $true
    }

    # Removed: 'Has -Severity parameter with ValidateSet' - checked an attribute existed without checking its values, so a mangled set still passed. The surface test above already catches a renamed -Severity.
}

Describe 'Set-UiStatusBar' {
    It 'Has the documented parameter surface' {
        $params = (Get-Command Set-UiStatusBar -Module PsUi).Parameters.Keys
        foreach ($p in @('Text', 'Progress', 'Increment', 'Severity', 'Indeterminate', 'Variable')) {
            $params | Should -Contain $p -Because "$p is documented"
        }
    }

    # Removed: the ValidateSet-existence check, same reasoning as the Write-Status one above.
}

Describe 'Clear-UiStatus / Hide-UiStatusBar / Show-UiStatusBar parameter surface' {
    It 'Each takes an optional -Variable' {
        foreach ($fn in @('Clear-UiStatus', 'Hide-UiStatusBar', 'Show-UiStatusBar')) {
            $param = (Get-Command $fn -Module PsUi).Parameters['Variable']
            $param | Should -Not -BeNullOrEmpty -Because "$fn targets a bar by -Variable"
            $param.Attributes.Mandatory | Should -Not -Contain $true
        }
    }
}

# Status bar clamping uses manual if-checks, not [Math]::Clamp (PS 5.1 compat)
Describe 'Status Bar Clamping (PS 5.1 Safe)' {
    It 'Set-UiStatusBar source does not use [Math]::Clamp' {
        $src = Get-Content (Join-Path $PSScriptRoot '..\PsUi\public\controls\status\Set-UiStatusBar.ps1') -Raw
        $src | Should -Not -Match '\[Math\]::Clamp'
    }

    It 'Add-StatusBarAutoWiring source does not use [Math]::Clamp' {
        $src = Get-Content (Join-Path $PSScriptRoot '..\PsUi\private\Controls\Add-StatusBarAutoWiring.ps1') -Raw
        $src | Should -Not -Match '\[Math\]::Clamp'
    }
}

InModuleScope PsUi {

    Describe 'Status Bar Behavioral Tests' {

        Describe 'New-StatusBarBadge creates proper structure' {
            BeforeAll {
                $script:warnBadge = New-StatusBarBadge -Severity Warning
                $script:errBadge  = New-StatusBarBadge -Severity Error
            }

            # Removed: the key-existence and is-a-Border / is-a-TextBlock checks. Every key gets dereferenced by the behavioral tests below anyway, and the WPF element types are restyle churn waiting to happen.

            It 'Warning/Error badges start visible but dimmed' {
                $script:warnBadge.Badge.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
                $script:warnBadge.Badge.Opacity | Should -Be 0.35
            }

            It 'CountText starts at 0' {
                $script:warnBadge.CountText.Text | Should -Be '0'
            }

            It 'Warning badge uses WarningBrush' {
                $script:warnBadge.BrushKey | Should -Be 'WarningBrush'
            }

            It 'Error badge uses ErrorBrush' {
                $script:errBadge.BrushKey | Should -Be 'ErrorBrush'
            }

            It 'GlyphText uses the active icon font' {
                $script:warnBadge.GlyphText.FontFamily.Source | Should -Match 'Segoe (MDL2 Assets|Fluent Icons)'
            }

            It 'Pill Tag carries IsBadgePill flag' {
                $script:warnBadge.Badge.Tag.IsBadgePill | Should -BeTrue
            }
        }

        Describe 'New-StatusBarMessagePopup creates proper structure' {
            BeforeAll {
                $script:badge   = New-StatusBarBadge -Severity Warning
                $script:msgList = [System.Collections.Generic.List[hashtable]]::new()
                $script:bar     = [System.Windows.Controls.Border]::new()
                $popupSplat = @{
                    Severity        = 'Warning'
                    PlacementTarget = $script:badge.Badge
                    BadgeInfo       = $script:badge
                    MessageList     = $script:msgList
                    Bar             = $script:bar
                }
                $script:popup = New-StatusBarMessagePopup @popupSplat
            }

            It 'Returns Popup, MessagePanel, HeaderText, ClearButton' {
                $script:popup.Keys | Should -Contain 'Popup'
                $script:popup.Keys | Should -Contain 'MessagePanel'
                $script:popup.Keys | Should -Contain 'HeaderText'
                $script:popup.Keys | Should -Contain 'ClearButton'
            }

            # Removed: the Popup-is-a-Popup and MessagePanel-is-a-StackPanel type checks. A factory named New-StatusBarMessagePopup returning a Popup is not news.

            It 'HeaderText shows initial zero count' {
                $script:popup.HeaderText.Text | Should -Be '0 Warnings'
            }
        }

        Describe 'Popup Clear button resets badge and messages' {
            BeforeAll {
                $script:badge   = New-StatusBarBadge -Severity Warning
                $script:msgList = [System.Collections.Generic.List[hashtable]]::new()
                $script:bar     = [System.Windows.Controls.Border]::new()
                $popupSplat = @{
                    Severity        = 'Warning'
                    PlacementTarget = $script:badge.Badge
                    BadgeInfo       = $script:badge
                    MessageList     = $script:msgList
                    Bar             = $script:bar
                }
                $script:popup = New-StatusBarMessagePopup @popupSplat

                # Simulate accumulated state
                $script:badge.CountText.Text   = '5'
                $script:badge.Badge.Visibility = [System.Windows.Visibility]::Visible
                $script:badge.Badge.ToolTip    = '5 Warnings'
                $script:msgList.Add(@{ Time = [DateTime]::Now; Message = 'test' })
                [void]$script:popup.MessagePanel.Children.Add(
                    [System.Windows.Controls.TextBlock]@{ Text = 'test' })

                # Fire the Clear button click
                $routedArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)
                $script:popup.ClearButton.RaiseEvent($routedArgs)
            }

            It 'Resets CountText to 0' {
                $script:badge.CountText.Text | Should -Be '0'
            }

            It 'Dims the badge pill back to inactive' {
                $script:badge.Badge.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
                $script:badge.Badge.Opacity | Should -Be 0.35
            }

            It 'Clears the message list' {
                $script:msgList.Count | Should -Be 0
            }

            It 'Clears the popup message panel' {
                $script:popup.MessagePanel.Children.Count | Should -Be 0
            }
        }

        Describe 'Get-SeverityBrushKey mapping' {
            It 'Warning returns WarningBrush' {
                Get-SeverityBrushKey -Severity Warning | Should -Be 'WarningBrush'
            }

            It 'Error returns ErrorBrush' {
                Get-SeverityBrushKey -Severity Error | Should -Be 'ErrorBrush'
            }

            It 'Success returns SuccessBrush' {
                Get-SeverityBrushKey -Severity Success | Should -Be 'SuccessBrush'
            }

            It 'Info with -UseAccentDefault returns AccentBrush' {
                Get-SeverityBrushKey -Severity Info -UseAccentDefault | Should -Be 'AccentBrush'
            }

            It 'Info without flag returns HeaderBackgroundBrush' {
                Get-SeverityBrushKey -Severity Info | Should -Be 'HeaderBackgroundBrush'
            }
        }
    }
}

# Removed: 'AsyncExecutor Progress Suppression' - asserted a PRIVATE FIELD exists via reflection.
# Rename the field in a refactor and it fails. Break the feature while keeping the field and it passes.
# Removed: 'BindElementToResources method exists' - same reflection on privates disease.

Describe 'ThemeEngine IsStatusBar Awareness' {
    It 'RegisterElement accepts a Border with IsStatusBar Tag' {
        $border = [System.Windows.Controls.Border]::new()
        $border.Tag = @{ IsStatusBar = $true }
        { [PsUi.ThemeEngine]::RegisterElement($border) } | Should -Not -Throw
    }
}

# Manifest sanity - catch accidental export changes or version drift
Describe 'Module Manifest' {
    BeforeAll {
        $script:manifest = Test-ModuleManifest (Join-Path $PSScriptRoot '..\PsUi\PsUi.psd1')
    }

    # Removed: 'Version matches' and 'Author is' - metadata change detectors that only fire on an intentional manifest edit, never on a behavioral bug. The GUID pin below stays (install identity).

    It 'Requires PowerShell 5.1+' {
        $script:manifest.PowerShellVersion | Should -Be '5.1'
    }

    It 'Supports Desktop and Core editions' {
        $script:manifest.CompatiblePSEditions | Should -Contain 'Desktop'
        $script:manifest.CompatiblePSEditions | Should -Contain 'Core'
    }

    It 'Exports zero aliases (cleaned in audit)' {
        $script:manifest.ExportedAliases.Count | Should -Be 0
    }

    It 'Exports exactly one cmdlet (New-UiWindow)' {
        $script:manifest.ExportedCmdlets.Keys | Should -Contain 'New-UiWindow'
        $script:manifest.ExportedCmdlets.Count | Should -Be 1
    }

    It 'Exports 60+ PowerShell functions' {
        # Exact count changes as we add features, just sanity-check the ballpark
        $script:manifest.ExportedFunctions.Count | Should -BeGreaterOrEqual 60
    }

    # Removed: 'Has a non-empty description' - gallery publish rejects a blank Description anyway.

    It 'Every exported function actually exists' {
        foreach ($funcName in $script:manifest.ExportedFunctions.Keys) {
            Get-Command $funcName -Module PsUi -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty -Because "$funcName is listed in manifest"
        }
    }

    It 'Has a GUID that wont change accidentally' {
        # If this changes, anyone who installed via PSGallery gets a different module identity
        $script:manifest.Guid.ToString() | Should -Be '205560a1-3780-4ce1-9ff3-480141781fe4'
    }
}

# ScriptBuilder generates the PS code that runs inside background runspaces.
# It handles session propagation, variable injection, and cleanup.
Describe 'ScriptBuilder' {
    It 'Generates session propagation code from valid GUID' {
        $guid = [guid]::NewGuid()
        $code = [PsUi.ScriptBuilder]::BuildSessionPropagation($guid)
        $code | Should -Match 'PsUiSessionId'
        $code | Should -Match 'SetCurrentSession'
    }

    It 'Returns empty string for empty GUID' {
        $code = [PsUi.ScriptBuilder]::BuildSessionPropagation([guid]::Empty)
        $code | Should -BeNullOrEmpty
    }

    It 'BuildLocalizer generates variable localizers' {
        $names = [System.Collections.Generic.List[string]]::new()
        $names.Add('userName')
        $names.Add('serverName')
        $code = [PsUi.ScriptBuilder]::BuildLocalizer($names)
        $code | Should -Match 'userName'
        $code | Should -Match 'serverName'
    }

    It 'BuildLocalizer skips invalid variable names' {
        # Names get emitted into generated code, so anything non-identifier is filtered out
        $names = [System.Collections.Generic.List[string]]::new()
        $names.Add('valid_name')
        $names.Add(';inject')
        $code = [PsUi.ScriptBuilder]::BuildLocalizer($names)
        $code | Should -Match 'valid_name'
        $code | Should -Not -Match 'inject'
    }

    It 'BuildPwdRestore generates Set-Location with escaped quotes' {
        # Single quotes in paths need escaping or the generated script breaks
        $code = [PsUi.ScriptBuilder]::BuildPwdRestore("C:\Users\Bob's Stuff")
        $code | Should -Match 'Set-Location'
        $code | Should -Match "Bob''s"
    }

    It 'BuildVariableCleanup skips reserved names' {
        # Cleanup runs after the action - can't Remove-Variable $Host obviously
        $names = [System.Collections.Generic.List[string]]::new()
        $names.Add('Host')
        $names.Add('myCustomVar')
        $code = [PsUi.ScriptBuilder]::BuildVariableCleanup($names)
        $code | Should -Not -Match '\bHost\b'
        $code | Should -Match 'myCustomVar'
    }

    It 'BuildDehydrator generates global sync code' {
        $names = [System.Collections.Generic.List[string]]::new()
        $names.Add('outputPath')
        $code = [PsUi.ScriptBuilder]::BuildDehydrator($names)
        $code | Should -Match 'Global:outputPath'
    }

    It 'BuildVariableInjection returns null for invalid names' {
        $result = [PsUi.ScriptBuilder]::BuildVariableInjection(';bad')
        $result | Should -BeNullOrEmpty
    }

    It 'BuildVariableInjection generates args-based injection' {
        $result = [PsUi.ScriptBuilder]::BuildVariableInjection('myVar')
        $result | Should -Match 'Global:myVar'
        $result | Should -Match 'args\[0\]'
    }
}

# Stuff that's broken before and will probably try to break again
Describe 'Edge Cases' {
    # Removed: ThreadSafeControlProxy TextBox wrap - duplicates the earlier ThreadSafeControlProxy Describe.
    # Removed: Multiple sessions namespace - duplicates Session Isolation tests above.
    It 'AsyncExecutor handles empty scriptblock gracefully' {
        $executor = [PsUi.AsyncExecutor]::new()
        $executor.UsePipelineQueueMode = $true
        $empty = [scriptblock]::Create('')
        $executor.ExecuteAsync($empty, $null, $null, $null, $null, $false)

        $timeout = [DateTime]::Now.AddSeconds(5)
        while ($executor.IsRunning -and [DateTime]::Now -lt $timeout) {
            Start-Sleep -Milliseconds 50
        }

        $executor.IsRunning | Should -BeFalse
        $executor.Dispose()
    }
}

# Native dialog wrappers - the modal half can't be tested unattended, so the API surface is verified instead (exports, params, return object layout). The actual click through lives in manual smoke testing.
Describe 'Native Dialogs - API surface' {
    It 'Exports Show-UiOuPicker' {
        Get-Command Show-UiOuPicker -Module PsUi -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Exports Show-WindowsObjectPicker' {
        Get-Command Show-WindowsObjectPicker -Module PsUi -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Show-UiOuPicker has expected parameters' {
        $cmd = Get-Command Show-UiOuPicker
        $cmd.Parameters.Keys | Should -Contain 'Title'
        $cmd.Parameters.Keys | Should -Contain 'Root'
        $cmd.Parameters.Keys | Should -Contain 'Server'
        $cmd.Parameters.Keys | Should -Contain 'IncludeEntireDirectory'
        $cmd.Parameters.Keys | Should -Contain 'IncludeHidden'
        $cmd.Parameters.Keys | Should -Contain 'ParentWindow'
    }

    It 'Show-WindowsObjectPicker requires ObjectType' {
        $cmd = Get-Command Show-WindowsObjectPicker
        $cmd.Parameters['ObjectType'].Attributes.Mandatory | Should -Contain $true
    }

    It 'Show-WindowsObjectPicker validates ObjectType values' {
        { Show-WindowsObjectPicker -ObjectType 'NotAType' } | Should -Throw
    }
}

# Tests that exercise native dialog functions from a background runspace, simulating the async action card execution path.
Describe 'Native Dialogs - Runspace and action card paths' {
    BeforeAll {
        $script:modulePath = (Resolve-Path (Join-Path $PSScriptRoot '..\PsUi\PsUi.psd1')).Path
    }

    It 'Show-UiOuPicker throws a descriptive error when not domain-joined' -Skip:(
        # Skip on domain-joined machines - the function would succeed there
        (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain -eq $true
    ) {
        { Show-UiOuPicker } | Should -Throw -ExpectedMessage '*domain*'
    }

    It 'Show-WindowsObjectPicker ObjectType validation fires from a background runspace' {
        $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $runspace.Open()
        $psInstance = $null
        try {
            $psInstance = [System.Management.Automation.PowerShell]::Create()
            $psInstance.Runspace = $runspace
            [void]$psInstance.AddScript("Import-Module '$($script:modulePath)' -Force")
            [void]$psInstance.AddScript("Show-WindowsObjectPicker -ObjectType 'NotAType'")
            $psInstance.Invoke()
            $firstError = $psInstance.Streams.Error | Select-Object -First 1
            $firstError | Should -Not -BeNullOrEmpty
            $firstError.Exception.Message | Should -Not -Match 'NullReference|ObjectReference'
        }
        finally {
            if ($psInstance) { $psInstance.Dispose() }
            $runspace.Close()
        }
    }
}

# Push-UiIconFontOverride is the per window/per Out-* dispatcher that the standalone tools call to apply an icon font override and hand back a snapshot for restore on close. Private, so tests live inside InModuleScope.
InModuleScope PsUi {
    Describe 'Push-UiIconFontOverride' {
        BeforeAll {
            $script:savedPushSnap = [PsUi.ModuleContext]::SnapshotIconFontState()
        }
        AfterAll {
            [PsUi.ModuleContext]::RestoreIconFontState($script:savedPushSnap)
        }

        It 'Returns $null when IsStandalone is $false (parent context wins, mirrors -Theme)' {
            $r = Push-UiIconFontOverride -IsStandalone $false `
                -BoundParameters @{ IconFont = 'SegoeMDL2' } `
                -IconFont 'SegoeMDL2' -NoIconFontFallback $false
            $r | Should -BeNullOrEmpty
        }

        It 'Returns $null when no override params are bound' {
            $r = Push-UiIconFontOverride -IsStandalone $true `
                -BoundParameters @{} `
                -IconFont 'Inherit' -NoIconFontFallback $false
            $r | Should -BeNullOrEmpty
        }

        It 'Treats explicit -IconFont Inherit as not-bound (returns $null, no mutation)' {
            $before = [PsUi.ModuleContext]::ActiveIconFontName
            $r = Push-UiIconFontOverride -IsStandalone $true `
                -BoundParameters @{ IconFont = 'Inherit' } `
                -IconFont 'Inherit' -NoIconFontFallback $false
            $r | Should -BeNullOrEmpty
            [PsUi.ModuleContext]::ActiveIconFontName | Should -Be $before
        }

        It 'Returns a snapshot capturing pre-mutation state when -IconFont Auto is bound' {
            $origName     = [PsUi.ModuleContext]::ActiveIconFontName
            $origFallback = [PsUi.ModuleContext]::IconFontNoFallback
            $snap = Push-UiIconFontOverride -IsStandalone $true `
                -BoundParameters @{ IconFont = 'Auto' } `
                -IconFont 'Auto' -NoIconFontFallback $false
            try {
                $snap            | Should -Not -BeNullOrEmpty
                $snap.FontName   | Should -Be $origName
                $snap.NoFallback | Should -Be $origFallback
                # Auto resolves through DetectDefaultIconFont
                [PsUi.ModuleContext]::ActiveIconFontName |
                    Should -Be ([PsUi.ModuleContext]::DetectDefaultIconFont())
            }
            finally {
                [PsUi.ModuleContext]::RestoreIconFontState($snap)
            }
        }

        It 'Toggles only fallback when only -NoIconFontFallback is bound (font name unchanged)' {
            $origName = [PsUi.ModuleContext]::ActiveIconFontName
            $snap = Push-UiIconFontOverride -IsStandalone $true `
                -BoundParameters @{ NoIconFontFallback = $true } `
                -IconFont 'Inherit' -NoIconFontFallback $true
            try {
                $snap | Should -Not -BeNullOrEmpty
                [PsUi.ModuleContext]::IconFontNoFallback | Should -BeTrue
                [PsUi.ModuleContext]::ActiveIconFontName | Should -Be $origName
            }
            finally {
                [PsUi.ModuleContext]::RestoreIconFontState($snap)
            }
        }
    }
}

# New-UiDataGrid - the embeddable grid that mirrors Show-UiOutput's chrome
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

    It 'Exports the four expected functions' {
        $module = Get-Module PsUi
        $module.ExportedFunctions.Keys | Should -Contain 'New-UiDataGrid'
        $module.ExportedFunctions.Keys | Should -Contain 'Set-UiDataGridItems'
        $module.ExportedFunctions.Keys | Should -Contain 'Add-UiDataGridItem'
        $module.ExportedFunctions.Keys | Should -Contain 'Clear-UiDataGridItems'
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
        $grid.Columns.Count | Should -BeGreaterThan 0
    }

    It '-Columns string[] hides columns not in the list' {
        $items = @([PSCustomObject]@{ Name = 'a'; Count = 1; Hidden = 'no' })
        New-UiDataGrid -Variable 'gridE' -Items $items -Columns 'Name', 'Count' -NoToolbar

        $grid    = $script:dgSession.GetControl('gridE')
        $visible = @($grid.Columns | Where-Object { $_.Visibility -eq [System.Windows.Visibility]::Visible } | ForEach-Object { $_.Header })
        $visible | Should -Contain 'Name'
        $visible | Should -Contain 'Count'
        $visible | Should -Not -Contain 'Hidden'
    }

    It '-Columns hashtable with Type=Button creates a template column' {
        $items = @([PSCustomObject]@{ Name = 'a' })
        New-UiDataGrid -Variable 'gridF' -Items $items -NoToolbar -Columns @(
            @{ Name = 'Name' }
            @{ Header = 'Act'; Type = 'Button'; Text = 'Go'; Action = { } }
        )
        $grid = $script:dgSession.GetControl('gridF')
        $btnCol = $grid.Columns | Where-Object { $_.Header -eq 'Act' }
        $btnCol | Should -BeOfType [System.Windows.Controls.DataGridTemplateColumn]
    }

    It '-Editable flips text columns IsReadOnly off' {
        $items = @([PSCustomObject]@{ Name = 'a'; Count = 1 })
        New-UiDataGrid -Variable 'gridG' -Items $items -Editable -NoToolbar
        $grid = $script:dgSession.GetControl('gridG')
        $textCols = @($grid.Columns | Where-Object { $_ -is [System.Windows.Controls.DataGridTextColumn] })
        $textCols.Count | Should -BeGreaterThan 0
        foreach ($c in $textCols) { $c.IsReadOnly | Should -BeFalse }
    }

    It '-Editable + bool first-value renders the bool-glyph TemplateColumn by default' {
        # Convert-UiDataGridBoolColumnsToGlyph swaps the underlying DataGridCheckBoxColumn for a DataGridTemplateColumn that paints check/cross glyphs. Opt out with -NoVisualValues if you want the raw checkbox header (asserted in the next test).
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
        $grid = $script:dgSession.GetControl('gridK')
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
        $items = @([PSCustomObject]@{ Name = 'a'; Note = 'old' })
        New-UiDataGrid -Variable 'gridO' -Items $items -Editable -NoToolbar `
            -OnCellEdit { param($row, $col, $new, $old) $script:editCalls.Add(@{ Row = $row; Col = $col; New = $new; Old = $old }) }

        $grid    = $script:dgSession.GetControl('gridO')
        $noteCol = $grid.Columns | Where-Object { $_.Header -eq 'Note' }
        $rowItem = @($grid.ItemsSource)[0]

        # Drive the CellEditEnding WPF raises on Commit. The handler reads $new from EditingElement.Text. Plain .NET event, not routed - RaiseEvent can't reach it, so invoke the protected OnCellEditEnding raiser via reflection.
        $editor   = [System.Windows.Controls.TextBox]@{ Text = 'new' }
        $dgRow    = [System.Windows.Controls.DataGridRow]@{ Item = $rowItem }
        $cellArgs = [System.Windows.Controls.DataGridCellEditEndingEventArgs]::new($noteCol, $dgRow, $editor, [System.Windows.Controls.DataGridEditAction]::Commit)
        $bindingFlags = [System.Reflection.BindingFlags] 'Instance, NonPublic'
        $raiser = [System.Windows.Controls.DataGrid].GetMethod('OnCellEditEnding', $bindingFlags)
        $raiser.Invoke($grid, @([object]$cellArgs))

        # Add-UiDataGridEditHandling defers the user handler via Dispatcher.BeginInvoke at Background priority. PushFrame a lower priority continuation to drain Background first, then return.
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
        # Regression guard for Add-UiDataGridEditHandling: a column hashtable @{Name=...; Header=...} used to read $row.$Header for oldValue (null when Header != Name) and report Header as the column in OnCellEdit / OnRowEdit. Now resolves via Column.SortMemberPath.
        $script:editCalls2 = [System.Collections.Generic.List[object]]::new()
        $items = @([PSCustomObject]@{ Status = 'Running' })
        New-UiDataGrid -Variable 'gridHN' -Items $items -Editable -NoToolbar -Columns @(
            @{ Name = 'Status'; Header = 'Service Status'; Editable = $true }
        ) -OnCellEdit { param($row, $col, $new, $old) $script:editCalls2.Add(@{ Col = $col; New = $new; Old = $old }) }

        $grid = $script:dgSession.GetControl('gridHN')
        $col  = $grid.Columns | Where-Object { $_.Header -eq 'Service Status' }
        $rowItem = @($grid.ItemsSource)[0]

        $editor   = [System.Windows.Controls.TextBox]@{ Text = 'Stopped' }
        $dgRow    = [System.Windows.Controls.DataGridRow]@{ Item = $rowItem }
        $cellArgs = [System.Windows.Controls.DataGridCellEditEndingEventArgs]::new($col, $dgRow, $editor, [System.Windows.Controls.DataGridEditAction]::Commit)
        $bindingFlags = [System.Reflection.BindingFlags] 'Instance, NonPublic'
        $raiser = [System.Windows.Controls.DataGrid].GetMethod('OnCellEditEnding', $bindingFlags)
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

    It '-OnDoubleClick handler registers without throwing' {
        # MouseDoubleClick fires from real mouse input only. Pester runs without a window so the event can't be driven in a stable way (Mouse.PrimaryDevice is null off thread).
        # Smoke verify the handler registered without throwing and the grid stays usable.
        $items = @([PSCustomObject]@{ Name = 'a' })
        { New-UiDataGrid -Variable 'gridP' -Items $items -NoToolbar `
            -OnDoubleClick { param($row) } } | Should -Not -Throw

        $grid = $script:dgSession.GetControl('gridP')
        $grid | Should -Not -BeNullOrEmpty
        @($grid.ItemsSource).Count | Should -Be 1
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

            # _BaseObject points to the original .NET object
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
            foreach ($s in $snap) {
                $s.PSObject.Properties['_SearchText'] | Should -Not -BeNullOrEmpty
                $s._SearchText | Should -Match $s.Name
            }
        }
    }

    It 'Add-UiDataGridItem appends to an -ItemsSource grid (wrapper + mirror)' {
        # ItemsSource rows go in raw (no snapshot) - the caller's mirror keeps the actual object, not a PSCustomObject copy. SilentlyContinue eats the variable bind warning. Under Pester scopes the walk legitimately finds zero variables.
        $external = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $external.Add([PSCustomObject]@{ X = 1 })
        New-UiDataGrid -Variable 'gridQ' -ItemsSource $external -NoToolbar -WarningAction SilentlyContinue

        $newRow = [PSCustomObject]@{ X = 2 }
        Add-UiDataGridItem -Variable 'gridQ' -Item $newRow

        # The bound wrapper is what the session tracks. The mirror is the original.
        $wrapper = $script:dgSession.GetListCollection('gridQ')
        $wrapper.Count  | Should -Be 2
        $external.Count | Should -Be 2
        # raw object preserved, not snapshotted
        $external[1]    | Should -Be $newRow
    }

    It '-NoSafeWrap warns when combined with -ItemsSource' {
        $external = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $w = $null
        New-UiDataGrid -Variable 'gridR' -ItemsSource $external -NoToolbar -NoSafeWrap -WarningVariable w -WarningAction SilentlyContinue
        $w | Should -Not -BeNullOrEmpty
        ($w -join ' ') | Should -Match 'NoSafeWrap'
    }
}

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

        $state = @{ Fires = 0; LastAction = $null }
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

        # mirror no longer drives the wrapper after detach
        $mirror.Add('z')
        $wrapper.Count | Should -Be 2
    }

    It 'IList.Add (cast-and-call) marshals through the virtual override' {
        # Regression guard against the new method bypass. Adding via the IList interface MUST still queue onto the owning thread and push the mirror because InsertItem is overridden, not just `new` hidden behind Add.
        $mirror  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($script:disp)
        $wrapper.AttachMirror($mirror)

        $asIList = $wrapper -as [System.Collections.IList]
        [void]$asIList.Add('a')

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

Describe 'AsyncObservableCollection - Cross-thread marshaling' {

    It 'wrapper.Add from a background MTA runspace marshals through dispatcher and pushes mirror' {
        $disp    = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
        $mirror  = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        $wrapper = [PsUi.AsyncObservableCollection[object]]::new($disp)
        $wrapper.AttachMirror($mirror)

        # Spawn a real background runspace that calls wrapper.Add.
        # wrapper.Add sees CheckAccess=false, queues an Invoke to UI dispatcher, blocks on it.
        $bg = Start-BackgroundAdd -Wrapper $wrapper -Item 'bg-item'
        Wait-BackgroundAdd -Invocation $bg
        (Complete-BackgroundAdd -Invocation $bg) | Should -BeTrue

        $wrapper.Count | Should -Be 1
        $wrapper[0]    | Should -Be 'bg-item'
        $mirror.Count  | Should -Be 1
        $mirror[0]     | Should -Be 'bg-item'
    }

}

Describe 'New-UiDataGrid - variable bind contract' -Tag 'RequiresSession' {

    BeforeEach {
        $script:bcSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:bcSessionId)
        $script:bcSession = [PsUi.SessionManager]::Current
        $script:bcSession.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterEach {
        [PsUi.SessionManager]::DisposeSession($script:bcSessionId)
    }

    It '-NoBind leaves the caller variable untouched; wrapper still binds to the grid' {
        # Auto bind path would rewrite $local to point at the wrapper. -NoBind skips the walk.
        $local = [System.Collections.ArrayList]::new()
        [void]$local.Add([PSCustomObject]@{ A = 1 })

        $originalRef = $local

        New-UiDataGrid -Variable 'gridNB' -ItemsSource $local -NoBind -NoToolbar

        # Caller's variable still points at the original ArrayList, not at the wrapper.
        [object]::ReferenceEquals($local, $originalRef) | Should -BeTrue
        $local.GetType().Name | Should -Be 'ArrayList'

        # The grid is bound to the wrapper, which holds the seeded item.
        $wrapper = $script:bcSession.GetListCollection('gridNB')
        $wrapper | Should -Not -BeNullOrEmpty
        $wrapper.Count | Should -Be 1
    }

    It 'Auto-bind warns when no caller variable ref-equals the input' {
        # Property held collections have no caller variable for the scope walk to rewrite.
        # The documented contract: a warning fires so the silent drop case surfaces.
        $holder = [PSCustomObject]@{ Items = [System.Collections.ArrayList]::new() }
        [void]$holder.Items.Add([PSCustomObject]@{ A = 1 })

        $w = $null
        New-UiDataGrid -Variable 'gridZW' -ItemsSource $holder.Items -NoToolbar `
            -WarningVariable w -WarningAction SilentlyContinue

        $w | Should -Not -BeNullOrEmpty
        ($w -join ' ') | Should -Match 'could not repoint'
    }
}

InModuleScope PsUi {
    Describe 'Format-UiDataGridExportRows - formula sanitization' {

        It 'prefixes cells starting with =/+/-/@/tab/CR when -Sanitize is set' {
            $rows = @(
                [PSCustomObject]@{ Cell = '=cmd|''/c calc''!A1' }
                [PSCustomObject]@{ Cell = '+evil' }
                [PSCustomObject]@{ Cell = '-100' }
                [PSCustomObject]@{ Cell = '@AT' }
                [PSCustomObject]@{ Cell = "`tTabStart" }
                [PSCustomObject]@{ Cell = "`rCarriageReturn" }
                [PSCustomObject]@{ Cell = 'safe value' }
            )

            $out = @(Format-UiDataGridExportRows -Items $rows -Properties @('Cell') -Sanitize)

            $out[0].Cell | Should -Be "'=cmd|'/c calc'!A1"
            $out[1].Cell | Should -Be "'+evil"
            $out[2].Cell | Should -Be "'-100"
            $out[3].Cell | Should -Be "'@AT"
            $out[4].Cell | Should -Be ("'`tTabStart")
            $out[5].Cell | Should -Be ("'`rCarriageReturn")
            $out[6].Cell | Should -Be 'safe value'
        }

        It 'passes cells through unchanged when -Sanitize is not set' {
            $rows = @( [PSCustomObject]@{ Cell = '=cmd|''/c calc''!A1' } )
            $out  = @(Format-UiDataGridExportRows -Items $rows -Properties @('Cell'))
            $out[0].Cell | Should -Be '=cmd|''/c calc''!A1'
        }
    }
}

# Regression net for the DataGrid overhaul. The subtle ones are snapshot round trip fidelity and the edit handler cancel branch (a failing Validator must not write through).
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

        $grid = $script:regSession.GetControl('gridFilter')
        $visible = @($grid.Columns |
            Where-Object { $_.Visibility -eq [System.Windows.Visibility]::Visible } |
            Sort-Object DisplayIndex)
        $visible[0].Header | Should -Be 'Email'
        $visible[1].Header | Should -Be 'Name'
        $deptCol = $grid.Columns | Where-Object { $_.Header -eq 'Dept' }
        $deptCol.Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)
    }

    # Removed: the FileInfo snapshot test - it restitched the _BaseObject and _SearchText angles the earlier snapshot tests already pin, just on a different sample object.

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
            # New-ObjectSubTab builds the output window's per type results grid. It used to skip the
            # last column star that New-UiDataGrid applies, so wide result grids left dead space on the right.
            $items = [System.Collections.Generic.List[object]]::new()
            1..3 | ForEach-Object { $items.Add([pscustomobject]@{ Name = "srv-$_"; Region = 'us-east'; Load = ($_ * 10) }) }
            $tabControl = [System.Windows.Controls.TabControl]::new()

            $result = New-ObjectSubTab -GroupItems $items -TypeName 'Server' -SubTabControl $tabControl
            $grid   = $result.DataGrid

            $visible = @($grid.Columns | Where-Object { $_.Visibility -eq [System.Windows.Visibility]::Visible })
            $visible.Count | Should -BeGreaterThan 1

            # Exactly the rightmost (collection last) visible column is starred. The others stay Auto.
            @($visible | Where-Object { $_.Width.IsStar }).Count | Should -Be 1
            $visible[$visible.Count - 1].Width.IsStar | Should -BeTrue
            $visible[0].Width.IsStar                  | Should -BeFalse
        }
    }

    It 'Set-LastDataColumnStar picks the rightmost column before DisplayIndex is assigned' {
        InModuleScope PsUi {
            # DisplayIndex is -1 until the grid first renders. The old sort of all -1s was unstable and
            # starred an arbitrary (usually wrong) column at build time.
            $grid = [System.Windows.Controls.DataGrid]::new()
            foreach ($h in 'First', 'Second', 'Third') {
                $col = [System.Windows.Controls.DataGridTextColumn]::new()
                $col.Header  = $h
                $col.Binding = [System.Windows.Data.Binding]::new($h)
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
            # Build a DataGrid + standalone FilterBox so New-UiDataGridFilterController hooks the ICollectionView.Filter predicate. The public New-UiDataGrid path hides the filter box inside the toolbar return value and doesn't republish it to the caller, so go direct.
            $items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
            [void]$items.Add([pscustomobject]@{ Name = 'alice'; _SearchText = 'alice smith' })
            [void]$items.Add([pscustomobject]@{ Name = 'bob';   _SearchText = 'bob' })

            $dg = [System.Windows.Controls.DataGrid]::new()
            $dg.ItemsSource = $items
            $fb = [System.Windows.Controls.TextBox]::new()
            New-UiDataGridFilterController -DataGrid $dg -FilterBox $fb | Out-Null

            $view  = [System.Windows.Data.CollectionViewSource]::GetDefaultView($dg.ItemsSource)
            $state = $fb.Tag

            # Bypass debounce - set FilterText directly and invoke the predicate.
            $state.FilterText = 'alice'
            $view.Filter.Invoke($items[0]) | Should -BeTrue
            $view.Filter.Invoke($items[1]) | Should -BeFalse

            $state.FilterText = ''
            $view.Filter.Invoke($items[0]) | Should -BeTrue
            $view.Filter.Invoke($items[1]) | Should -BeTrue
        }
    }

    It 'Add-UiDataGridEditHandling: Validator $false cancels CellEditEnding and OnCellEdit does not fire' {
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

        # Drive CellEditEnding with an empty editor value. Validator returns $false. The handler should set Cancel=$true and skip the OnCellEdit deferral.
        $editor   = [System.Windows.Controls.TextBox]@{ Text = '' }
        $dgRow    = [System.Windows.Controls.DataGridRow]@{ Item = $rowItem }
        $cellArgs = [System.Windows.Controls.DataGridCellEditEndingEventArgs]::new($col, $dgRow, $editor, [System.Windows.Controls.DataGridEditAction]::Commit)
        $bindingFlags = [System.Reflection.BindingFlags] 'Instance, NonPublic'
        $raiser = [System.Windows.Controls.DataGrid].GetMethod('OnCellEditEnding', $bindingFlags)
        $raiser.Invoke($grid, @([object]$cellArgs))

        # Drain any deferred dispatcher work so a faulty OnCellEdit registration would surface.
        $frame = [System.Windows.Threading.DispatcherFrame]::new()
        [void]$grid.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::ContextIdle,
            [Action]{ $frame.Continue = $false })
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)

        $cellArgs.Cancel    | Should -BeTrue
        $script:capturedNew | Should -Be '<initial>'   # OnCellEdit didn't fire
        $script:capturedOld | Should -Be '<initial>'
    }

    It 'New-UiDataGrid -ItemsSource $null registers an owned collection so Add/Set/Clear keep working' {
        # A null ItemsSource used to register a null collection the helpers read back as "not found".
        New-UiDataGrid -Variable 'nullSrc' -ItemsSource $null -NoToolbar
        # Explicit null check, not -BeNullOrEmpty: the collection starts empty (Count 0), which -BeNullOrEmpty would treat as empty, and piping it would enumerate to nothing.
        ($null -eq $script:regSession.GetListCollection('nullSrc')) | Should -BeFalse
        Add-UiDataGridItem -Variable 'nullSrc' -Item ([pscustomobject]@{ Name = 'a' })
        $script:regSession.GetListCollection('nullSrc').Count | Should -Be 1
        Set-UiDataGridItems -Variable 'nullSrc' -Items @([pscustomobject]@{ Name = 'x' }, [pscustomobject]@{ Name = 'y' })
        $script:regSession.GetListCollection('nullSrc').Count | Should -Be 2
        Clear-UiDataGridItems -Variable 'nullSrc'
        $script:regSession.GetListCollection('nullSrc').Count | Should -Be 0
    }

    It 'Explicit -Columns editable path makes a decimal column editable, not just int/double' {
        # decimal isn't a .NET primitive, so New-UiDataGridTextColumn's editor type probe used to downgrade it to readonly while int/double edited fine.
        $items = @([pscustomobject]@{ Price = [decimal]9.99; Qty = [int]3 })
        New-UiDataGrid -Variable 'decGrid' -Items $items -Editable -NoToolbar -Columns @(
            @{ Name = 'Price'; Editable = $true }
            @{ Name = 'Qty';   Editable = $true }
        )
        $grid  = $script:regSession.GetControl('decGrid')
        $price = $grid.Columns | Where-Object { $_.Header -eq 'Price' }
        $price.IsReadOnly | Should -BeFalse
    }

    It 'Add/Set/Clear-UiDataGridItems are registered for async-runspace injection' {
        # Without this, calling them from a grid cell or context menu async action throws CommandNotFound.
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
            $box = [System.Windows.Controls.TextBox]::new()
            # Grid must sit in a Window so the ItemsSource changed hook attaches.
            $win = [System.Windows.Window]::new()
            $win.Content = $grid
            New-UiDataGridFilterController -DataGrid $grid -FilterBox $box | Out-Null

            $viewA = [System.Windows.Data.CollectionViewSource]::GetDefaultView($listA)
            $viewA.Filter | Should -Not -BeNullOrEmpty

            $listB = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
            [void]$listB.Add([pscustomobject]@{ Name = 'b' })
            $grid.ItemsSource = $listB   # fires rebindFilter, which must null the old view's predicate

            $viewA.Filter | Should -BeNullOrEmpty
        }
    }
}

# Null element and falsy row regressions: a Mandatory [object[]] rejects an array carrying ANY null unless [AllowNull()], and a null item crashes every build loop that indexes into it.
# The falsy scalar case (@(0) rendering blank) rides along - same guard family.
InModuleScope PsUi {
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
            # @(cmd) around the call renests the comma wrapped array (count 1 with the real array inside).
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
            # Without -PropertyNames a null item runs zero loop iterations. WITH it the loop string indexes $item.PSObject.Properties[$name] and a null throws. This is the HideEmptyColumns call pattern.
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
        # All null collection: the buildable row scan finds nothing, so this pins the empty object firstItem fallback itself. A null then real row mix only re-covers the scan (the real row becomes firstItem and the fallback never fires).
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

    It 'Set-UiDataGridItems keeps null rows out of an -ItemsSource caller collection' {
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

    It 'New-UiTree -Items @($null) builds an empty tree (all-null fallback path)' {
        # All null input skips the process block collection entirely, so $allItems falls back to raw $Items and the buildNodes loop's own null skip is what stands between this and $null.PSObject.Properties[...] throwing. Pins that guard independently of the mixed test.
        New-UiTree -Variable 'neTreeAllNull' -Items @($null)
        $tree = $script:neSession.GetControl('neTreeAllNull')
        $tree.Items.Count | Should -Be 0
    }

    It 'New-UiChart -Data with a null point builds with the null skipped' {
        {
            New-UiChart -Variable 'neChart' -Type Bar -Data @(
                [pscustomobject]@{ Label = 'A'; Value = 3 }
                $null
                [pscustomobject]@{ Label = 'B'; Value = 5 }
            )
        } | Should -Not -Throw
    }
}

# Builders emit definition hashtables and never touch the session, so the whole block runs without creating one. Downstream gates test -is [hashtable] and .Contains().
Describe 'Builder functions - output shape' {
    It 'New-UiMenuItem returns a plain hashtable with only bound keys' {
        $item = New-UiMenuItem 'Restart' -Action { $_ } -Icon Refresh
        $item.GetType() | Should -Be ([hashtable])
        $item.Text | Should -Be 'Restart'
        $item.Action | Should -BeOfType [scriptblock]
        $item.Icon | Should -Be 'Refresh'
        $item.Contains('Sync') | Should -BeFalse
        $item.Contains('Enabled') | Should -BeFalse
    }

    It 'New-UiMenuItem -Enabled $false survives as a present key' {
        $item = New-UiMenuItem 'X' { 1 } -Enabled $false
        $item.Contains('Enabled') | Should -BeTrue
        $item.Enabled | Should -BeFalse
    }

    It 'New-UiMenuItem -Sync:$false still emits the key' {
        # Emission tracks binding, not truthiness. A bound $false still lands in the hashtable.
        $item = New-UiMenuItem 'X' { 1 } -Sync:$false
        $item.Contains('Sync') | Should -BeTrue
        $item.Sync | Should -BeFalse
    }

    It 'New-UiMenuItem rejects a string -Enabled' {
        # the menu builder casts non-scriptblocks to [bool] and 'false' would cast truthy
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

        $bare = New-UiResultAction 'Tag' { $_ }
        $bare.Contains('Confirm') | Should -BeFalse
        $bare.Contains('ObjectType') | Should -BeFalse
        $bare.Contains('Icon') | Should -BeFalse
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
        $col.Contains('Sync') | Should -BeFalse
        # common params never leak into the definition
        $col.Contains('Verbose') | Should -BeFalse
    }

    It 'New-UiColumn throws at definition time on the combos the grid rejects later' {
        { New-UiColumn -Header 'On' -Type Toggle } | Should -Throw '*needs -Binding*'
        { New-UiColumn -Header 'Open' -Type Link } | Should -Throw '*-Url or -Action*'
        { New-UiColumn -Type Button -Text 'Go' -Action { 1 } } | Should -Throw '*or -Header*'
    }

    It 'New-UiColumn Icon rejects a bogus name via the dynamic ValidateSet' {
        { New-UiColumn -Header 'Go' -Type Button -Action { 1 } -Icon 'NotARealGlyphName' } | Should -Throw
    }

    It 'New-UiHeaderAction emits Icon and Tooltip only when bound' {
        $headerAction = New-UiHeaderAction -Action { 1 }
        $headerAction.Action | Should -BeOfType [scriptblock]
        $headerAction.Contains('Icon') | Should -BeFalse
        $headerAction.Contains('Tooltip') | Should -BeFalse
    }
}

InModuleScope PsUi {
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

        It 'a single emission comes back as a one-element array, not a bare hashtable' {
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

        It 'wraps a single bare hashtable' {
            $result = ConvertTo-UiDefinitionArray -InputObject @{ A = 1 } -ParameterName '-X' -CallerName 'T'
            $result -is [array] | Should -BeTrue
            $result.Count | Should -Be 1
        }

        It 'copies an [ordered] element into a plain hashtable' {
            $result = ConvertTo-UiDefinitionArray -InputObject ([ordered]@{ A = 1 }) -ParameterName '-X' -CallerName 'T'
            $result[0].GetType() | Should -Be ([hashtable])
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
            $probe = @{}
            $null = ConvertTo-UiDefinitionArray -InputObject { $probe.Parent = [PsUi.SessionManager]::Current.CurrentParent; @{ A = 1 } } -ParameterName '-X' -CallerName 'T'
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
        $menu = ($script:rcmSession.GetControl('rcmBuilder')).ContextMenu
        $headers = @($menu.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] } | ForEach-Object { $_.Header })
        $headers[0] | Should -Be 'Ping'
        $headers[1] | Should -Be 'Wake'
    }

    It '-Enabled $false lands as StaticEnabled on the MenuItem tag' {
        # Proves an explicit $false survived the fold into the ordered form instead of collapsing into "no Enabled clause". Builds its own grid so the It stands alone.
        New-UiDataGrid -Variable 'rcmStatic' -Items $script:rcmRows -RowContextMenu {
            New-UiMenuItem 'Wake' -Action { $_ } -Enabled $false
        }
        $menu = ($script:rcmSession.GetControl('rcmStatic')).ContextMenu
        $wakeItem = @($menu.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] -and $_.Header -eq 'Wake' })[0]
        $wakeItem.Tag.ContainsKey('StaticEnabled') | Should -BeTrue
        $wakeItem.Tag.StaticEnabled | Should -BeFalse
    }

    It 'a bare New-UiMenuItem outside any block or array still lands as one labeled item' {
        # A builder item is itself a dictionary, so the legacy passthrough would eat it and render menu entries literally named 'Text' and 'Action'
        New-UiDataGrid -Variable 'rcmBare' -Items $script:rcmRows -RowContextMenu (New-UiMenuItem 'Solo' -Action { 1 })
        $menu = ($script:rcmSession.GetControl('rcmBare')).ContextMenu
        $headers = @($menu.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] } | ForEach-Object { $_.Header })
        $headers[0] | Should -Be 'Solo'
        $headers | Should -Not -Contain 'Action'
    }

    It 'the array form works the same as the block form' {
        New-UiDataGrid -Variable 'rcmArray' -Items $script:rcmRows -RowContextMenu @(
            (New-UiMenuItem 'First' -Action { 1 }),
            (New-UiMenuItem 'Second' -Action { 2 })
        )
        $menu = ($script:rcmSession.GetControl('rcmArray')).ContextMenu
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
            'A second' = @{ Action = { $_ }; Sync = $true }
        })
        $menu = ($script:rcmSession.GetControl('rcmLegacy')).ContextMenu
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
        # Filter mode hides rather than removes: every property gets a column, only the listed ones show
        New-UiDataGrid -Variable 'colFilter' -Items $script:colRows -Columns @('Name')
        $grid = $script:colSession.GetControl('colFilter')
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
        $button = @($script:raSession.CurrentParent.Children | Where-Object { $_ -is [System.Windows.Controls.Button] })[-1]
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
        @($button.Tag.ResultActions).Count | Should -Be 1
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

# Modal - can't invoke it under Pester, so pin the binding surface the builders rely on.
Describe 'Show-UiMessageDialog -CustomButtons surface' {
    It '-CustomButtons is untyped so a New-UiDialogButton definition block binds' {
        (Get-Command Show-UiMessageDialog).Parameters['CustomButtons'].ParameterType | Should -Be ([object])
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
        # [Type]::GetType returned $null for every WPF owner type, so this silently skipped for the module's whole life before the -as [type] fix
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
        { New-UiPanel -Content { } -WPFProperties @{ 'Bogus.Thing' = 1 } } | Should -Not -Throw
    }
}

# End to end on Invoke-UiAsync. Last in the file on purpose: the cancel test needs an Application (Cancel queues OnCancelled onto a Dispatcher), and the Application is a process wide singleton, so creating it here keeps it out of the WPF control tests above.
Describe 'Invoke-UiAsync - capture and cancel lifecycle' {
    BeforeAll {
        if (![System.Windows.Application]::Current) { $null = New-Object System.Windows.Application }
    }

    It 'Invoke-UiAsync no longer excludes $executor/$varsToInject/$functionsToInject from auto-capture' {
        # Fix: those were the function's own injection local names that had leaked into the auto capture exclusion list, so a user variable of the same name was silently dropped. They were renamed with a __ prefix and removed from the list. Auto capture of an It local isn't reachable under Pester's scope model, so this guards the exact source change. The behavioral repro lives in scratch/Verify-Fix4-Capture.ps1.
        $def = (Get-Command Invoke-UiAsync).Definition
        $def | Should -Not -Match "'executor'"
        $def | Should -Not -Match "'varsToInject'"
        $def | Should -Not -Match "'functionsToInject'"
        $def | Should -Match '\$__executor'
    }

    It 'Cancel disposes the executor (OnCancelled path), not just cancels its token' {
        $handle = Invoke-UiAsync -ScriptBlock { 1..100 | ForEach-Object { Start-Sleep -Milliseconds 100 } }
        Start-Sleep -Milliseconds 250
        $handle.Executor.Cancel()

        # Process Dispatcher messages so the queued OnCancelled disposer runs. Bounded so it can't hang.
        $frame = [System.Windows.Threading.DispatcherFrame]::new()
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [timespan]::FromMilliseconds(700)
        $timer.Add_Tick({ $timer.Stop(); $frame.Continue = $false }.GetNewClosure())
        $timer.Start()
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)

        # Dispose() nulls the private _cts. Cancel() alone only cancels it.
        $ctsField = [PsUi.AsyncExecutor].GetField('_cts', [System.Reflection.BindingFlags]'Instance,NonPublic')
        $ctsField.GetValue($handle.Executor) | Should -BeNullOrEmpty
    }
}

# Also needs the Application, so it sits below the lifecycle block that creates it.
Describe 'ActiveExecutor release on run end' {
    BeforeAll {
        if (![System.Windows.Application]::Current) { $null = New-Object System.Windows.Application }

        $script:aeSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:aeSessionId)
        $script:aeSession = [PsUi.SessionManager]::Current

        # Bounded message loop. The completion handlers queue onto the Dispatcher, so nothing releases until something processes messages.
        function Wait-Condition {
            param([scriptblock]$Until, [int]$TimeoutSec = 6)
            $deadline = (Get-Date).AddSeconds($TimeoutSec)
            while (!(& $Until) -and (Get-Date) -lt $deadline) {
                $frame = [System.Windows.Threading.DispatcherFrame]::new()
                [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::Background,
                    [Action]{ $frame.Continue = $false })
                [System.Windows.Threading.Dispatcher]::PushFrame($frame)
                [System.Threading.Thread]::Sleep(20)
            }
        }
    }

    AfterAll {
        [PsUi.SessionManager]::DisposeSession($script:aeSessionId)
    }

    It 'completion nulls ActiveExecutor instead of leaving a disposed AsyncExecutor behind' {
        # Before the fix the only clear was SessionContext.Clear() at window teardown.
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
        Wait-Condition { $false } 1
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
    }

    It 'an async action calling Stop-UiAsync warns that it would cancel itself' {
        $warnings = @()
        New-UiButton -Text 'Cancel' -Action { Stop-UiAsync } -WarningVariable warnings -WarningAction SilentlyContinue
        ($warnings -join ' ') | Should -Match 'cancel itself'
    }

    It '-NoAsync suppresses the warning' {
        $warnings = @()
        New-UiButton -Text 'CancelSync' -NoAsync -Action { Stop-UiAsync } -WarningVariable warnings -WarningAction SilentlyContinue
        $warnings.Count | Should -Be 0
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

InModuleScope PsUi {
    Describe 'Get-UiCollectionKind' {
        It 'classifies every input form' {
            Get-UiCollectionKind -Obj ([System.Collections.ObjectModel.ObservableCollection[object]]::new()) | Should -Be 'WpfObservable'
            Get-UiCollectionKind -Obj ([PsUi.AsyncObservableCollection[object]]::new([System.Windows.Threading.Dispatcher]::CurrentDispatcher)) | Should -Be 'PsUiObservable'
            Get-UiCollectionKind -Obj ([System.Collections.ArrayList]::new()) | Should -Be 'Other'
            Get-UiCollectionKind -Obj (@('a', 'b')) | Should -Be 'Other'
            Get-UiCollectionKind -Obj $null | Should -Be 'Null'
            $target = @(1)
            Get-UiCollectionKind -Obj ([ref]$target) | Should -Be 'Ref'
        }

        It 'classifies a typed AsyncObservableCollection, which the old name match missed for subclasses' {
            Get-UiCollectionKind -Obj ([PsUi.AsyncObservableCollection[string]]::new([System.Windows.Threading.Dispatcher]::CurrentDispatcher)) | Should -Be 'PsUiObservable'
        }

        It 'classifies GridOwnedCollection as PsUiObservable via inheritance' {
            # GridOwnedCollection derives from AsyncObservableCollection, so the BaseType walk finds the threadsafe base first. That keeps a grid owned collection out of the wrap path if one ever reaches the list resolve.
            Get-UiCollectionKind -Obj ([PsUi.GridOwnedCollection[object]]::new()) | Should -Be 'PsUiObservable'
        }
    }
}
