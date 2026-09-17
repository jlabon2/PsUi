#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# The status bar, the badge and popup stuff.
. (Join-Path $PSScriptRoot '_Setup.ps1')

BeforeAll { . (Join-Path $PSScriptRoot '_Setup.ps1') }

# StatusBar - freeform content bar docked to parent container.
Describe 'New-UiStatusBar' {
    It 'Has the documented parameter surface' {
        $params = (Get-Command New-UiStatusBar -Module PsUi).Parameters.Keys
        foreach ($paramName in @('Content', 'DefaultText', 'Variable', 'Location', 'WPFProperties',
                         'AutoProgress', 'AutoCancel', 'Inline', 'Intercept', 'CaptureHost',
                         'NoOutputOnly', 'Persist', 'MaxMessages')) {
            $params | Should -Contain $paramName -Because "$paramName is documented"
        }
    }

    It 'Has optional -Content scriptblock parameter' {
        $cmd = Get-Command New-UiStatusBar -Module PsUi
        $cmd.Parameters['Content'].ParameterType | Should -Be ([scriptblock])
        $cmd.Parameters['Content'].Attributes.Mandatory | Should -Not -Contain $true
    }

    It 'Has -Location parameter with Top/Bottom' {
        $cmd         = Get-Command New-UiStatusBar -Module PsUi
        $validateSet = $cmd.Parameters['Location'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validateSet.ValidValues | Should -Contain 'Top'
        $validateSet.ValidValues | Should -Contain 'Bottom'
    }

}

Describe 'Write-Status' {
    It 'Has the documented parameter surface' {
        $params = (Get-Command Write-Status -Module PsUi).Parameters.Keys
        foreach ($paramName in @('Message', 'Severity', 'Timeout', 'Bar')) {
            $params | Should -Contain $paramName -Because "$paramName is documented"
        }
    }

    It 'Has mandatory positional -Message parameter' {
        $cmd = Get-Command Write-Status -Module PsUi
        $cmd.Parameters['Message'].ParameterType | Should -Be ([string])
        $cmd.Parameters['Message'].Attributes.Mandatory | Should -Contain $true
    }

}

Describe 'Set-UiStatusBar' {
    It 'Has the documented parameter surface' {
        $params = (Get-Command Set-UiStatusBar -Module PsUi).Parameters.Keys
        foreach ($paramName in @('Text', 'Progress', 'Increment', 'Severity', 'Indeterminate', 'Variable')) {
            $params | Should -Contain $paramName -Because "$paramName is documented"
        }
    }

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

# Private functions aren't exported, so they need module scope to reach.
InModuleScope PsUi {
    Describe 'New-StatusBarBadge' {
        BeforeAll {
            $script:warnBadge = New-StatusBarBadge -Severity Warning
            $script:errBadge  = New-StatusBarBadge -Severity Error
        }

        It 'Warning/Error badges start visible but dimmed' {
            $script:warnBadge.Badge.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
            $script:warnBadge.Badge.Opacity | Should -Be 0.35
            $script:errBadge.Badge.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
            $script:errBadge.Badge.Opacity | Should -Be 0.35
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
            # -Match on either name also accepts a hardcoded literal, which is the regression this is named for.
            $script:warnBadge.GlyphText.FontFamily.Source |
                Should -Be ([PsUi.ModuleContext]::ActiveIconFontFamily.Source)
        }

        It 'Pill Tag carries IsBadgePill flag' {
            $script:warnBadge.Badge.Tag.IsBadgePill | Should -BeTrue
        }
    }

    Describe 'New-StatusBarMessagePopup' {
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

        It 'Hands back all four pieces the status bar hooks together' {
            # The tests below reach into these by name, so a factory quietly dropping one would read as a null reference somewhere else entirely.
            foreach ($key in 'Popup', 'MessagePanel', 'HeaderText', 'ClearButton') {
                $script:popup.Keys | Should -Contain $key
            }
        }

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
            $script:badge.Badge.Opacity    = 1.0
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
            # The BeforeAll lights it to 1.0 first, or this only restates New-StatusBarBadge's default.
            $script:badge.Badge.Opacity | Should -Be 0.35
            $script:badge.Badge.ToolTip | Should -Be '0 Warnings'
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
