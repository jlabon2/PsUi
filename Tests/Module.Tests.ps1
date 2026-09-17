#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Module surface. Themes, the icon list, the icon font switch, the manifest.
. (Join-Path $PSScriptRoot '_Setup.ps1')

BeforeAll { . (Join-Path $PSScriptRoot '_Setup.ps1') }

# Theme engine is static, loaded once at module import
Describe 'Theme System' {
    It 'Should return available themes' {
        $themes = [PsUi.ThemeEngine]::GetAvailableThemes()
        $themes | Should -Contain 'Light'
        $themes | Should -Contain 'Dark'
        # Light and Dark are also the hardcoded fallback. Only Monokai proves the real list loaded.
        $themes | Should -Contain 'Monokai'
    }

    It 'Takes a Border tagged as a status bar without throwing' {
        # The theming code reads IsStatusBar off the Tag and hands the border its own brushes, and nothing else covers that branch.
        $border     = [System.Windows.Controls.Border]::new()
        $border.Tag = @{ IsStatusBar = $true }
        { [PsUi.ThemeEngine]::RegisterElement($border) } | Should -Not -Throw
    }
}

# Icons come from CharList.json, the unicode mappings for MDL2 and Fluent
Describe 'Icon System' {

    It 'Should have 100+ icons available' {
        $icons = [PsUi.ModuleContext]::Icons
        $icons | Should -Not -BeNullOrEmpty
        $icons.Count | Should -BeGreaterThan 100
    }

    It 'Finished loading them at import' {
        # The count above passes off a partly built list too. This is the flag the module sets once it is actually done.
        [PsUi.ModuleContext]::IsInitialized | Should -BeTrue
    }
}

Describe 'Exported surface' {
    It 'Exports the controls a script reaches for first' {
        # The manifest checks below prove every name resolves. This one catches the ones that would be missed.
        $exported = (Get-Module PsUi).ExportedFunctions.Keys
        foreach ($name in 'New-UiButton', 'New-UiInput', 'New-UiTool', 'New-UiLabel') {
            $exported | Should -Contain $name
        }
    }
}

# Snapshot and restore the global icon font state, or a mutation leaks into later tests.
Describe 'Icon Font - ModuleContext static API' {
    BeforeAll { $script:savedIconFontSnap = [PsUi.ModuleContext]::SnapshotIconFontState() }
    AfterAll { [PsUi.ModuleContext]::RestoreIconFontState($script:savedIconFontSnap) }

    It 'DetectDefaultIconFont picks Fluent when it is installed' {
        # The method can only return those two names, so asserting it returns one of them cannot fail.
        $detected = [PsUi.ModuleContext]::DetectDefaultIconFont()
        if ([PsUi.ModuleContext]::IsFontInstalled([PsUi.ModuleContext]::FontNameFluent)) {
            $detected | Should -Be ([PsUi.ModuleContext]::FontNameFluent)
        }
        else { $detected | Should -Be ([PsUi.ModuleContext]::FontNameMDL2) }
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

    It 'IsGlyphAvailable returns true for a common glyph' {
        if ([PsUi.ModuleContext]::NoIconFontInstalled) {
            Set-ItResult -Skipped -Because 'no Segoe icon font on this box, so every glyph reports unavailable'
            return
        }
        [PsUi.ModuleContext]::IsGlyphAvailable('Save') | Should -BeTrue
    }

    It 'IsGlyphAvailable returns false for an unknown glyph name' {
        [PsUi.ModuleContext]::IsGlyphAvailable('DefinitelyNotAGlyphName__xyz') | Should -BeFalse
    }

    It 'Snapshot + Restore round-trips state' {
        $originalName     = [PsUi.ModuleContext]::ActiveIconFontName
        $originalFallback = [PsUi.ModuleContext]::IconFontNoFallback
        $snap             = [PsUi.ModuleContext]::SnapshotIconFontState()

        # The name only moves on a box with both fonts. The fallback flag moves either way, since SetIconFont writes it even when the name it was given does not take.
        # Without that second axis this asserted the starting values against themselves on a one font box, which is every check it had.
        $other = if ($originalName -eq [PsUi.ModuleContext]::FontNameMDL2) {
            [PsUi.ModuleContext]::FontNameFluent
        }
        else { [PsUi.ModuleContext]::FontNameMDL2 }

        [PsUi.ModuleContext]::SetIconFont($other, !$originalFallback)
        [PsUi.ModuleContext]::IconFontNoFallback | Should -Be (!$originalFallback)
        if ([PsUi.ModuleContext]::IsFontInstalled($other)) {
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
        # The chain form is "Primary, Secondary"
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
    BeforeAll { $script:savedIconFontSnap2 = [PsUi.ModuleContext]::SnapshotIconFontState() }
    AfterAll { [PsUi.ModuleContext]::RestoreIconFontState($script:savedIconFontSnap2) }

    It 'Get-PsUiIconFont hands back the active font name as a string' {
        $name = Get-PsUiIconFont
        $name | Should -Not -BeNullOrEmpty
        $name | Should -Match 'Segoe (MDL2 Assets|Fluent Icons)'
    }

    It 'Test-PsUiIcon -Font Either answers for a name both fonts carry' {
        Test-PsUiIcon -Name 'Save' -Font Either | Should -BeTrue
    }

    It 'Set-PsUiIconFont Auto sets the active font to a known name' {
        Set-PsUiIconFont -FontName Auto
        # Auto only calls DetectDefaultIconFont, so checking the answer is one of two names checks nothing.
        Get-PsUiIconFont | Should -Be ([PsUi.ModuleContext]::DetectDefaultIconFont())
    }

    It 'Set-PsUiIconFont SegoeFluentIcons (when installed) sets Fluent' {
        if (![PsUi.ModuleContext]::IsFontInstalled('Segoe Fluent Icons')) {
            Set-ItResult -Skipped -Because 'Segoe Fluent Icons not installed on this box'
            return
        }
        # Park it on MDL2 first. On a Fluent box the active font already is Fluent, so the Set proves nothing.
        if ([PsUi.ModuleContext]::IsFontInstalled('Segoe MDL2 Assets')) { Set-PsUiIconFont -FontName SegoeMDL2 }
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
        if ([PsUi.ModuleContext]::NoIconFontInstalled) {
            Set-ItResult -Skipped -Because 'no Segoe icon font on this box, so every glyph reports unavailable'
            return
        }
        Test-PsUiIcon -Name 'Save' | Should -BeTrue
    }

    It 'Test-PsUiIcon returns false for an unknown name' {
        Test-PsUiIcon -Name 'DefinitelyNotAGlyphName__xyz' | Should -BeFalse
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
        # 'Blocked' is one of the Fluent modern names, and its codepoint sits outside the MDL2 range.
        Test-PsUiIcon -Name 'Blocked' -Font MDL2 | Should -BeFalse
    }
}

Describe 'Icon Font - Out-* parameter surface' {
    It 'Every Out-* command takes the same IconFont ValidateSet' {
        foreach ($command in 'Out-Datagrid', 'Out-CSVDataGrid', 'Out-TextEditor') {
            $param = (Get-Command $command).Parameters['IconFont']
            $param | Should -Not -BeNullOrEmpty -Because "$command should expose -IconFont"
            $set = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            foreach ($value in 'Inherit', 'Auto', 'SegoeMDL2', 'SegoeFluentIcons') {
                $set.ValidValues | Should -Contain $value -Because "$command should accept -IconFont $value"
            }
        }
    }
}

# A control that adds itself to the open panel has to go through Assert-UiSession, or it cannot start an implicit window.
Describe 'Controls reach the session through Assert-UiSession' {
    It 'Every control that adds to CurrentParent asks Assert-UiSession for it' {
        # A window maker sets CurrentParent rather than adding to it, and Get-UiSession only mentions it in help.
        $makesItsOwn = 'New-UiWindow', 'New-UiChildWindow', 'New-UiTool', 'Out-Datagrid', 'Out-CSVDataGrid', 'Out-TextEditor', 'Get-UiSession'

        $root     = Join-Path $PSScriptRoot '..\PsUi\public'
        $wrong    = foreach ($file in Get-ChildItem $root -Recurse -Filter '*.ps1') {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            if ($name -in $makesItsOwn -or $name -like 'Show-Ui*') { continue }
            $text = Get-Content $file.FullName -Raw
            if ($text -notmatch 'CurrentParent') { continue }
            if ($text -match 'Assert-UiSession') { continue }
            $name
        }

        # New-UiChart, New-UiWebView, New-UiDropdownButton and New-UiSpacer each sat on this list, and a script opening with one lost that control without a word.
        @($wrong) -join ', ' | Should -BeNullOrEmpty
    }
}

# Catches an export that no longer resolves, and a GUID somebody regenerated.
Describe 'Module Manifest' {
    BeforeAll {
        $script:manifest = Test-ModuleManifest (Join-Path $PSScriptRoot '..\PsUi\PsUi.psd1')
    }

    It 'Requires PowerShell 5.1+' {
        $script:manifest.PowerShellVersion | Should -Be '5.1'
    }

    It 'Supports Desktop and Core editions' {
        $script:manifest.CompatiblePSEditions | Should -Contain 'Desktop'
        $script:manifest.CompatiblePSEditions | Should -Contain 'Core'
    }

    It 'Exports zero aliases' {
        $script:manifest.ExportedAliases.Count | Should -Be 0
    }

    It 'Exports 60 or more functions' {
        # The exact count moves with every feature. This only catches the export list emptying out.
        $script:manifest.ExportedFunctions.Count | Should -BeGreaterOrEqual 60
    }

    It 'Exports exactly one cmdlet (New-UiWindow)' {
        $script:manifest.ExportedCmdlets.Keys | Should -Contain 'New-UiWindow'
        $script:manifest.ExportedCmdlets.Count | Should -Be 1
    }

    It 'Every exported function actually exists' {
        # One Get-Command for the whole module. Asking per name costs about 200ms across the eighty odd exports.
        $live = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]@(Get-Command -Module PsUi | ForEach-Object { $_.Name }),
            [StringComparer]::OrdinalIgnoreCase)

        foreach ($funcName in $script:manifest.ExportedFunctions.Keys) {
            $live.Contains($funcName) | Should -BeTrue -Because "$funcName is listed in manifest"
        }
    }

    It 'Has a GUID that wont change accidentally' {
        # If this changes, anyone who installed via PSGallery gets a different module identity
        $script:manifest.Guid.ToString() | Should -Be '205560a1-3780-4ce1-9ff3-480141781fe4'
    }

    It 'Carries the version the CHANGELOG calls newest' {
        # Two places to bump and one of them always gets forgotten.
        $heading = Select-String -Path (Join-Path $PSScriptRoot '..\CHANGELOG.md') -Pattern '^## \[(\d+\.\d+\.\d+)\]' | Select-Object -First 1
        $script:manifest.Version.ToString() | Should -Be $heading.Matches[0].Groups[1].Value
    }
}

# CI runs both editions now, and this catches the case neither of them would: an API that only the net452 build lacks, on a box nobody tests.
Describe 'Windows PowerShell guard' {
    It 'Never reaches for [Math]::Clamp' {
        $hits = Get-ChildItem (Join-Path $PSScriptRoot '..\PsUi') -Recurse -Include *.ps1, *.psm1 | Select-String -Pattern 'Math\]::Clamp' -List
        @($hits | ForEach-Object { $_.Path }) | Should -BeNullOrEmpty
    }

    It 'Never splats a parameter table by wrapping it in an array' {
        # & $action @($table) reads as one positional argument holding the whole table, so no key in it ever reaches a parameter. The async path got these onto their parameters and the sync one silently did not.
        # Only a name ending in Parameters counts. An array literal in that position is a real thing to write, and Invoke-UiAsync uses one to fan results into a callback that takes a single argument.
        $hits = Get-ChildItem (Join-Path $PSScriptRoot '..\PsUi') -Recurse -Include *.ps1, *.psm1 | Select-String -Pattern '&\s+\$\w+(\.\w+)*\s+@\(\$\w+(\.\w+)*Parameters\)' -List
        @($hits | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }) | Should -BeNullOrEmpty
    }
}

# Private functions aren't exported, so they need module scope to reach.
InModuleScope PsUi {
    Describe 'Push-UiIconFontOverride' {
        BeforeAll { $script:savedPushSnap = [PsUi.ModuleContext]::SnapshotIconFontState() }
        AfterAll {
            [PsUi.ModuleContext]::RestoreIconFontState($script:savedPushSnap)
            Remove-Variable -Name savedPushSnap -Scope Script -ErrorAction SilentlyContinue
        }

        It 'Returns $null when IsStandalone is $false (parent context wins, mirrors -Theme)' {
            $pushSplat = @{
                IsStandalone       = $false
                BoundParameters    = @{ IconFont = 'SegoeMDL2' }
                IconFont           = 'SegoeMDL2'
                NoIconFontFallback = $false
            }
            Push-UiIconFontOverride @pushSplat | Should -BeNullOrEmpty
        }

        It 'Returns $null when no override params are bound' {
            $pushSplat = @{
                IsStandalone       = $true
                BoundParameters    = @{}
                IconFont           = 'Inherit'
                NoIconFontFallback = $false
            }
            Push-UiIconFontOverride @pushSplat | Should -BeNullOrEmpty
        }

        It 'Treats explicit -IconFont Inherit as not-bound (returns $null, no mutation)' {
            $before    = [PsUi.ModuleContext]::ActiveIconFontName
            $pushSplat = @{
                IsStandalone       = $true
                BoundParameters    = @{ IconFont = 'Inherit' }
                IconFont           = 'Inherit'
                NoIconFontFallback = $false
            }
            Push-UiIconFontOverride @pushSplat | Should -BeNullOrEmpty
            [PsUi.ModuleContext]::ActiveIconFontName | Should -Be $before
        }

        It 'Returns a snapshot capturing pre-mutation state when -IconFont Auto is bound' {
            # Move the active font off Detect() first, or before and after look the same either way.
            $other = if ([PsUi.ModuleContext]::ActiveIconFontName -eq [PsUi.ModuleContext]::FontNameMDL2) {
                [PsUi.ModuleContext]::FontNameFluent
            }
            else { [PsUi.ModuleContext]::FontNameMDL2 }
            if ([PsUi.ModuleContext]::IsFontInstalled($other)) { [PsUi.ModuleContext]::SetIconFont($other, $false) }

            $origName     = [PsUi.ModuleContext]::ActiveIconFontName
            $origFallback = [PsUi.ModuleContext]::IconFontNoFallback
            $pushSplat    = @{
                IsStandalone       = $true
                BoundParameters    = @{ IconFont = 'Auto' }
                IconFont           = 'Auto'
                NoIconFontFallback = $false
            }
            $snap = Push-UiIconFontOverride @pushSplat
            try {
                $snap            | Should -Not -BeNullOrEmpty
                $snap.FontName   | Should -Be $origName
                $snap.NoFallback | Should -Be $origFallback
                [PsUi.ModuleContext]::ActiveIconFontName |
                    Should -Be ([PsUi.ModuleContext]::DetectDefaultIconFont())
            }
            finally { [PsUi.ModuleContext]::RestoreIconFontState($snap) }
        }

        It 'Toggles only fallback when only -NoIconFontFallback is bound (font name unchanged)' {
            $origName  = [PsUi.ModuleContext]::ActiveIconFontName
            $pushSplat = @{
                IsStandalone       = $true
                BoundParameters    = @{ NoIconFontFallback = $true }
                IconFont           = 'Inherit'
                NoIconFontFallback = $true
            }
            $snap = Push-UiIconFontOverride @pushSplat
            try {
                $snap | Should -Not -BeNullOrEmpty
                [PsUi.ModuleContext]::IconFontNoFallback | Should -BeTrue
                [PsUi.ModuleContext]::ActiveIconFontName | Should -Be $origName
            }
            finally { [PsUi.ModuleContext]::RestoreIconFontState($snap) }
        }
    }
}
