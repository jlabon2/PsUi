function Add-InputProviders {
    <#
    .SYNOPSIS
        Configures all input providers for AsyncExecutor.
        InputProvders map legacy console input (Read-Host, Get-Credential, PromptForChoice)
        to WPF dialog equivalents.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Executor,

        [System.Windows.Window]$Window,

        [scriptblock]$ClearHostAction,

        [switch]$DebugEnabled
    )

    $isDebug = $DebugEnabled

    # Input Provider for Read-Host
    $Executor.InputProvider = {
        param($PromptText)
        if ($isDebug) { [Console]::WriteLine("[DEBUG] Read-Host invoked - Prompt='$PromptText'") }

        # Suspend topmost so the dialog isn't trapped behind a pinned output window
        $wasPinned = $Window -and $Window.Topmost
        if ($wasPinned) {
            $Window.Topmost = $false
            # Brief delay lets pending UI work flush before the modal dialog takes over
            Start-Sleep -Milliseconds 500
        }

        # Detect native Pause command (calls Read-Host with this exact prompt)
        $isPause = $PromptText -eq 'Press Enter to continue...' -or $PromptText -eq 'Press any key to continue . . .'
        if ($isPause) {
            if ($isDebug) { [Console]::WriteLine('[DEBUG] Detected Pause pattern') }
            Show-UiMessageDialog -Title 'Paused' -Message 'Press OK to continue...' -Buttons OK -Icon Info | Out-Null
            if ($wasPinned) { $Window.Topmost = $true }
            return ''
        }

        $msg    = if (![string]::IsNullOrWhiteSpace($PromptText)) { $PromptText } else { 'The running script is requesting input.' }
        $result = Show-UiInputDialog -Title 'Script Input Required' -Prompt $msg
        if ($isDebug) { [Console]::WriteLine("[DEBUG] Read-Host returned: $(if ($result) { '<value>' } else { '<empty>' })") }
        if ($wasPinned) { $Window.Topmost = $true }
        return $result
    }.GetNewClosure()

    # Secure Input Provider for Get-Credential password prompts
    $Executor.SecureInputProvider = {
        param($PromptText)
        if ($isDebug) { [Console]::WriteLine("[DEBUG] Read-Host -AsSecureString - Prompt='$PromptText'") }

        $wasPinned = $Window -and $Window.Topmost
        if ($wasPinned) {
            $Window.Topmost = $false
            Start-Sleep -Milliseconds 500
        }

        $msg          = if (![string]::IsNullOrWhiteSpace($PromptText)) { $PromptText } else { 'Script is requesting a password.' }
        $secureInput  = Show-UiInputDialog -Title 'Secure Input Required' -Prompt $msg -Password
        if ($wasPinned) { $Window.Topmost = $true }

        if ($secureInput) {
            if ($isDebug) { [Console]::WriteLine('[DEBUG] Secure input received') }
            # -Password now returns SecureString directly
            if ($secureInput -is [System.Security.SecureString]) { return $secureInput }
            return ConvertTo-SecureString $secureInput -AsPlainText -Force
        }

        if ($isDebug) { [Console]::WriteLine('[DEBUG] Secure input cancelled/empty') }
        return [System.Security.SecureString]::new()
    }.GetNewClosure()

    # Choice Provider for -Confirm prompts and ShouldProces
    $Executor.ChoiceProvider = {
        param($Caption, $Message, $Choices, $DefaultChoice)
        if ($isDebug) { [Console]::WriteLine("[DEBUG] PromptForChoice invoked - Caption='$Caption', Choices=$($Choices.Count), Default=$DefaultChoice") }

        $wasPinned = $Window -and $Window.Topmost
        if ($wasPinned) {
            $Window.Topmost = $false
            Start-Sleep -Milliseconds 500
        }

        $result = Show-UiChoiceDialog -Caption $Caption -Message $Message -Choices $Choices -DefaultChoice $DefaultChoice
        if ($isDebug) { [Console]::WriteLine("[DEBUG] PromptForChoice returned: $result") }
        if ($wasPinned) { $Window.Topmost = $true }
        return $result
    }.GetNewClosure()

    # Credential Provider for Get-Credential
    $Executor.CredentialProvider = {
        param($Caption, $Message, $UserName, $TargetName)
        if ($isDebug) { [Console]::WriteLine("[DEBUG] Get-Credential invoked - UserName='$UserName', Target='$TargetName'") }

        $wasPinned = $Window -and $Window.Topmost
        if ($wasPinned) {
            $Window.Topmost = $false
            Start-Sleep -Milliseconds 500
        }

        $result = Show-UiCredentialDialog -Caption $Caption -Message $Message -UserName $UserName -TargetName $TargetName
        if ($isDebug) { [Console]::WriteLine("[DEBUG] Get-Credential returned: $(if ($result) { 'PSCredential' } else { '<cancelled>' })") }
        if ($wasPinned) { $Window.Topmost = $true }
        return $result
    }.GetNewClosure()

    # Prompt Provider for multi-field prompts
    $Executor.PromptProvider = {
        param($Caption, $Message, $Descriptions)
        if ($isDebug) { [Console]::WriteLine("[DEBUG] Prompt invoked - Caption='$Caption', Fields=$($Descriptions.Count)") }

        $wasPinned = $Window -and $Window.Topmost
        if ($wasPinned) {
            $Window.Topmost = $false
            Start-Sleep -Milliseconds 500
        }

        $result = Show-UiPromptDialog -Caption $Caption -Message $Message -Descriptions $Descriptions
        if ($isDebug) { [Console]::WriteLine("[DEBUG] Prompt returned: $(if ($result) { "$($result.Count) values" } else { '<cancelled>' })") }
        if ($wasPinned) { $Window.Topmost = $true }
        return $result
    }.GetNewClosure()

    # ReadKey Provider for "Press any key to continue" patterns
    $Executor.ReadKeyProvider = {
        param($Options)
        if ($isDebug) { [Console]::WriteLine('[DEBUG] ReadKey invoked') }

        $wasPinned = $Window -and $Window.Topmost
        if ($wasPinned) {
            $Window.Topmost = $false
            Start-Sleep -Milliseconds 500
        }

        Show-UiMessageDialog -Title 'Continue' -Message 'Press OK to continue...' -Buttons OK -Icon Info
        if ($isDebug) { [Console]::WriteLine('[DEBUG] ReadKey acknowledged') }
        if ($wasPinned) { $Window.Topmost = $true }
    }.GetNewClosure()

    # ClearHost Provider for Clear-Host cmdlet
    if ($ClearHostAction) {
        $Executor.ClearHostProvider = {
            if ($isDebug) { [Console]::WriteLine('[DEBUG] Clear-Host invoked') }
            & $ClearHostAction
        }.GetNewClosure()
    }
    else { $Executor.ClearHostProvider = { }.GetNewClosure() }
}