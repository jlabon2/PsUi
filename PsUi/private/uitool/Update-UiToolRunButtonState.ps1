<#
.SYNOPSIS
    Validates mandatory parameter fields and updates Run button state.
#>
function Update-UiToolRunButtonState {
    [CmdletBinding()]
    param()

    $session = Get-UiSession
    if (!$session) { return }

    $runBtn = $session.Variables['_uiTool_runButton']
    if (!$runBtn) { return }

    $paramInfo = $session.Variables['_uiTool_paramInfo']
    if (!$paramInfo) {
        $runBtn.IsEnabled = $true
        return
    }

    $allValid = $true
    foreach ($paramDef in $paramInfo) {
        if (!$paramDef.IsMandatory) { continue }

        # Controls are registered with 'param_' prefix
        $varName = "param_$($paramDef.Name)"
        $value   = $null

        # Check SafeVariables first (registered controls with proxies)
        if ($session.SafeVariables.ContainsKey($varName)) {
            $proxy = $session.SafeVariables[$varName]
            if ($proxy) {
                $ctrl = $proxy.Control
                if ($ctrl -is [System.Windows.Controls.TextBox]) {
                    $value = $ctrl.Text
                }
                elseif ($ctrl -is [System.Windows.Controls.PasswordBox]) {
                    $value = $ctrl.SecurePassword
                    # SecureString with length 0 is empty
                    if ($value -and $value.Length -eq 0) { $value = $null }
                }
                elseif ($ctrl -is [System.Windows.Controls.ComboBox]) {
                    $value = $ctrl.SelectedItem
                }
                elseif ($ctrl -is [System.Windows.Controls.CheckBox]) {
                    # Switches are always "valid" - unchecked is a valid state
                    continue
                }
                elseif ($ctrl -is [System.Windows.Controls.Slider]) {
                    # Sliders always have a value
                    continue
                }
            }
        }

        # Check session.Variables for credential wrappers
        if (!$value -and $session.Variables.ContainsKey($varName)) {
            $wrapper = $session.Variables[$varName]
            if ($wrapper.PSObject.TypeNames -contains 'PsUi.CredentialControl') {
                # Credential is mandatory if either username or password is empty
                $userName = $wrapper.UsernameBox.Text
                $passLen  = $wrapper.PasswordBox.SecurePassword.Length
                if ([string]::IsNullOrWhiteSpace($userName) -or $passLen -eq 0) {
                    $allValid = $false
                    break
                }
                continue
            }
        }

        if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) {
            $allValid = $false
            break
        }
        elseif ($null -eq $value) {
            $allValid = $false
            break
        }
    }

    $runBtn.Dispatcher.Invoke([Action]{
        $runBtn.IsEnabled = $allValid
    })
}
