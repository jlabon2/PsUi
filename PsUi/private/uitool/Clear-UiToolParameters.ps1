<#
.SYNOPSIS
    Clears all parameter controls for New-UiTool.
#>
function Clear-UiToolParameters {
    [CmdletBinding()]
    param(
        [string[]]$ParameterNames
    )

    if (!$ParameterNames -or $ParameterNames.Count -eq 0) {
        $session = Get-UiSession
        $def = $session.PSBase.CurrentDefinition
        if ($def -and $def.Parameters) {
            $ParameterNames = $def.Parameters | ForEach-Object { $_.Name }
        }
    }

    if (!$ParameterNames) {
        Write-Host "No parameters to clear." -ForegroundColor Gray
        return
    }

    $session = Get-UiSession

    foreach ($pName in $ParameterNames) {
        $varName = "param_$pName"
        
        # Check for credential wrapper in session.Variables first
        $credWrapper = $session.Variables[$varName]
        if ($credWrapper -and $credWrapper.PSObject.TypeNames -contains 'PsUi.CredentialControl') {
            $credWrapper.UsernameBox.Text = ''
            $credWrapper.PasswordBox.Clear()
            continue
        }
        
        # Standard controls use SafeVariables proxy
        $proxy = [PsUi.SessionManager]::Current.GetSafeVariable($varName)
        if ($proxy) { $proxy.Clear() }
    }

    Write-Host "Parameters cleared." -ForegroundColor Gray
}
