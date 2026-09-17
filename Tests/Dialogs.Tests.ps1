#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Native dialogs, checked at the parameter surface. The modal half needs a person.
. (Join-Path $PSScriptRoot '_Setup.ps1')

BeforeAll { . (Join-Path $PSScriptRoot '_Setup.ps1') }

# What is left to pin is the exports and the parameter surface.
Describe 'Native Dialogs - API surface' {

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

# The same functions from a background runspace, the way an action card runs them.
Describe 'Native Dialogs - Runspace and action card paths' {
    BeforeAll {
        $script:modulePath = (Resolve-Path (Join-Path $PSScriptRoot '..\PsUi\PsUi.psd1')).Path
    }

    It 'Show-UiOuPicker throws a descriptive error when not domain-joined' -Skip:(
        # Skip on domain joined machines, where the function would succeed
        (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain -eq $true
    ) {
        # The raw GetCurrentDomain failure carries the word domain too, so a wildcard always passes.
        { Show-UiOuPicker } | Should -Throw -ExpectedMessage '*requires Active Directory domain membership unless -Server*'
    }

    It 'Show-WindowsObjectPicker ObjectType validation fires from a background runspace' {
        $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $runspace.Open()
        $psInstance = $null
        try {
            $psInstance          = [System.Management.Automation.PowerShell]::Create()
            $psInstance.Runspace = $runspace
            [void]$psInstance.AddScript("Import-Module '$($script:modulePath)' -Force")
            [void]$psInstance.AddScript("Show-WindowsObjectPicker -ObjectType 'NotAType'")
            $psInstance.Invoke()
            $firstError = $psInstance.Streams.Error | Select-Object -First 1
            $firstError | Should -Not -BeNullOrEmpty
            $firstError.Exception.Message | Should -Not -Match 'NullReference|ObjectReference'
            # A dropped export gives CommandNotFound, which is not empty and not an NRE.
            $firstError.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
        }
        finally {
            if ($psInstance) { $psInstance.Dispose() }
            $runspace.Close()
        }
    }
}

# Modal - can't invoke it under Pester, so pin the binding surface the builders rely on.
Describe 'Show-UiMessageDialog -CustomButtons surface' {
    It '-CustomButtons is untyped so a New-UiDialogButton definition block binds' {
        (Get-Command Show-UiMessageDialog).Parameters['CustomButtons'].ParameterType | Should -Be ([object])
    }
}
