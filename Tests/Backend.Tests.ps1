#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# The C# under the DSL. Converters, the script builder, the proxy and hydration.
. (Join-Path $PSScriptRoot '_Setup.ps1')

BeforeAll { . (Join-Path $PSScriptRoot '_Setup.ps1') }

Describe 'Constants - IsReservedVariable' {
    # These guard against clobbering PS builtins during hydration
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
        # Variable names land inside generated script text, so injection patterns get rejected
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

# Arrays land in a cell as '[3 items]'.
Describe 'ArrayDisplayConverter' {
    BeforeAll { $script:converter = [PsUi.ArrayDisplayConverter]::new() }

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
        $preview    = [PsUi.ArrayDisplayConverter]::GetTooltipPreview(@($longString), 10)
        $preview | Should -Match '\.\.\.'
        $preview.Length | Should -BeLessThan 60
    }

    It 'Shows overflow count in tooltip' {
        $items   = 1..20
        $preview = [PsUi.ArrayDisplayConverter]::GetTooltipPreview($items, 5)
        $preview | Should -Match 'and 15 more'
    }
}

Describe 'ExpandableValueTooltipConverter' {
    BeforeAll { $script:converter = [PsUi.ExpandableValueTooltipConverter]::new() }

    It 'Formats hashtable tooltips with key count' {
        $ht     = @{ Name = 'Alice'; Age = 30 }
        $result = $script:converter.Convert($ht, [string], $null, $null)
        $result | Should -Match 'Click to expand \(2 keys\)'
    }

    It 'Shows null values as $null in dict preview' {
        $ht     = @{ Missing = $null }
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

Describe 'ScriptBuilder' {
    It 'Generates session propagation code from valid GUID' {
        $guid = [guid]::NewGuid()
        $code = [PsUi.ScriptBuilder]::BuildSessionPropagation($guid)
        $code | Should -Match 'PsUiSessionId'
        $code | Should -Match 'SetCurrentSession'
        # Match the id itself. A wrong format argument writes Guid.Empty and both assertions above still pass.
        $code | Should -Match $guid.ToString()
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
        $code | Should -Match 'serverName'
        # Emitting ${userName} = ${userName} instead kills every hydrated value in a button action.
        $code | Should -Match '\$\{userName\} = \$\{Global:userName\}'
    }

    It 'BuildLocalizer skips invalid variable names' {
        # Names get emitted into generated code, so anything that isn't an identifier is filtered out
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

        # The localizer emits Global:outputPath too, on the other side. Only the assignment tells them apart.
        $code | Should -Match '\$\{Global:outputPath\} = \$\{outputPath\}'
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

# All on the test thread, so nothing here exercises the cross thread hop the proxy exists for.
Describe 'ThreadSafeControlProxy' {
    It 'Should wrap TextBox and provide Text property' {
        $textBox = [System.Windows.Controls.TextBox]@{ Text = 'InitialText' }
        $proxy   = [PsUi.ThreadSafeControlProxy]::new($textBox, 'testProxy')

        $proxy.Text | Should -Be 'InitialText'

        $proxy.Text = 'UpdatedText'
        $textBox.Text | Should -Be 'UpdatedText'
    }

    It 'Should wrap CheckBox and provide IsChecked property' {
        # Start it checked. A null getter passes Should -BeFalse, and a missed ToggleButton cast returns null.
        $checkBox = [System.Windows.Controls.CheckBox]@{ IsChecked = $true }
        $proxy    = [PsUi.ThreadSafeControlProxy]::new($checkBox, 'checkProxy')

        $proxy.IsChecked | Should -BeTrue

        $proxy.IsChecked = $false
        $proxy.IsChecked    | Should -Be $false
        $checkBox.IsChecked | Should -Be $false
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

        $proxy.Control.Value = 75
        $slider.Value | Should -Be 75
    }

    It 'Should provide IsEnabled property for any control' {
        $button = [System.Windows.Controls.Button]@{ IsEnabled = $true }
        $proxy  = [PsUi.ThreadSafeControlProxy]::new($button, 'buttonProxy')

        $proxy.IsEnabled | Should -BeTrue

        $proxy.IsEnabled = $false
        $button.IsEnabled | Should -BeFalse
    }

    It 'Should throw on null control' {
        { [PsUi.ThreadSafeControlProxy]::new($null, 'nullProxy') } | Should -Throw
    }
}

Describe 'ControlValueExtractor' {
    It 'Extracts Text from TextBox' {
        $tb  = [System.Windows.Controls.TextBox]@{ Text = 'extracted' }
        $val = [PsUi.ControlValueExtractor]::ExtractValue($tb)
        $val | Should -Be 'extracted'
    }

    It 'Extracts Text from TextBlock' {
        $tb  = [System.Windows.Controls.TextBlock]@{ Text = 'readonly label' }
        $val = [PsUi.ControlValueExtractor]::ExtractValue($tb)
        $val | Should -Be 'readonly label'
    }

    It 'Extracts IsChecked from CheckBox' {
        $cb  = [System.Windows.Controls.CheckBox]@{ IsChecked = $true }
        $val = [PsUi.ControlValueExtractor]::ExtractValue($cb)
        $val | Should -BeTrue
    }

    It 'Extracts SelectedItem from ComboBox' {
        $combo = [System.Windows.Controls.ComboBox]::new()
        $combo.Items.Add('A')
        $combo.Items.Add('B')
        $combo.SelectedIndex = 1
        $val                 = [PsUi.ControlValueExtractor]::ExtractValue($combo)
        $val | Should -Be 'B'
    }

    It 'Extracts Value from Slider' {
        $slider = [System.Windows.Controls.Slider]@{ Maximum = 100; Value = 42.5 }
        $val    = [PsUi.ControlValueExtractor]::ExtractValue($slider)
        $val | Should -Be 42.5
    }

    It 'Extracts Value from ProgressBar' {
        $pb  = [System.Windows.Controls.ProgressBar]@{ Value = 80 }
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

# What lets a button action read $userName without digging through session context
# A session per test, never a shared pool. Hydration injects ${Global:name} and never removes it, so a pool would carry those names into every test after.
Describe 'StateHydrationEngine' {
    BeforeEach {
        $script:testSessionId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($script:testSessionId)
        $script:session = [PsUi.SessionManager]::Current
        $script:session.CurrentParent = [System.Windows.Controls.StackPanel]::new()
    }

    AfterEach { [PsUi.SessionManager]::DisposeSession($script:testSessionId) }

    It 'Should extract value from TextBox control' {
        $textBox = [System.Windows.Controls.TextBox]@{ Text = 'TestValue123' }
        $script:session.AddControlSafe('userName', $textBox)

        $ps = [PowerShell]::Create()

        try {
            $initialValues = [PsUi.StateHydrationEngine]::HydrateViaScript($ps, $null)

            $initialValues.ContainsKey('userName') | Should -BeTrue
            $initialValues['userName'] | Should -Be 'TestValue123'
        }
        finally { $ps.Dispose() }
    }

    It 'Should extract value from CheckBox control' {
        $checkBox = [System.Windows.Controls.CheckBox]@{ IsChecked = $true }
        $script:session.AddControlSafe('enableFeature', $checkBox)

        $ps = [PowerShell]::Create()

        try {
            $initialValues = [PsUi.StateHydrationEngine]::HydrateViaScript($ps, $null)

            $initialValues.ContainsKey('enableFeature') | Should -BeTrue
            $initialValues['enableFeature'] | Should -BeTrue
        }
        finally { $ps.Dispose() }
    }

    It 'Should extract selected item from ComboBox' {
        $comboBox = [System.Windows.Controls.ComboBox]::new()
        $comboBox.Items.Add('Option1')
        $comboBox.Items.Add('Option2')
        $comboBox.Items.Add('Option3')
        $comboBox.SelectedIndex = 1
        $script:session.AddControlSafe('selectedOption', $comboBox)

        $ps = [PowerShell]::Create()

        try {
            $initialValues = [PsUi.StateHydrationEngine]::HydrateViaScript($ps, $null)

            $initialValues.ContainsKey('selectedOption') | Should -BeTrue
            $initialValues['selectedOption'] | Should -Be 'Option2'
        }
        finally { $ps.Dispose() }
    }

    It 'Should skip variables already defined (collision detection)' {
        # Vars already in the calling scope take precedence over controls
        $textBox = [System.Windows.Controls.TextBox]@{ Text = 'ControlValue' }
        $script:session.AddControlSafe('myVar', $textBox)

        $alreadyDefined = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $alreadyDefined.Add('myVar') | Out-Null

        $ps = [PowerShell]::Create()

        try {
            $initialValues = [PsUi.StateHydrationEngine]::HydrateViaScript($ps, $alreadyDefined)

            $initialValues.ContainsKey('myVar') | Should -BeFalse
        }
        finally { $ps.Dispose() }
    }

    It 'Should extract value from Slider control' {
        $slider = [System.Windows.Controls.Slider]@{
            Minimum = 0
            Maximum = 100
            Value   = 75
        }
        $script:session.AddControlSafe('volumeLevel', $slider)

        $ps = [PowerShell]::Create()

        try {
            $initialValues = [PsUi.StateHydrationEngine]::HydrateViaScript($ps, $null)

            $initialValues.ContainsKey('volumeLevel') | Should -BeTrue
            $initialValues['volumeLevel'] | Should -Be 75
        }
        finally { $ps.Dispose() }
    }
}

# Same reserved names as the IsReservedVariable block, this time registered as controls and pushed through HydrateViaScript.
Describe 'Reserved Variables' {
    It 'Should reserve every common automatic variable' {
        $mustBeReserved = @(
            'Host', 'Error', 'PSVersionTable', 'true', 'false', 'null',
            'PSCmdlet', 'PSBoundParameters', 'ErrorActionPreference'
        )

        $testId = [PsUi.SessionManager]::CreateSession()
        [PsUi.SessionManager]::SetCurrentSession($testId)
        $session = [PsUi.SessionManager]::Current

        try {
            foreach ($varName in $mustBeReserved) {
                $textBox = [System.Windows.Controls.TextBox]@{ Text = 'ShouldNotAppear' }
                $session.AddControlSafe($varName, $textBox)
            }

            $ps = [PowerShell]::Create()

            try {
                $initialValues = [PsUi.StateHydrationEngine]::HydrateViaScript($ps, $null)

                foreach ($varName in $mustBeReserved) {
                    $initialValues.ContainsKey($varName) | Should -BeFalse -Because "$varName is reserved"
                }
            }
            finally { $ps.Dispose() }
        }
        finally { [PsUi.SessionManager]::DisposeSession($testId) }
    }
}
