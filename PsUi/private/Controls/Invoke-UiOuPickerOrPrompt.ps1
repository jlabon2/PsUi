function Invoke-UiOuPickerOrPrompt {
    <#
    .SYNOPSIS
        Runs the OU picker. On a non-domain box with no Server in HelperOptions, prompts for a DC and creds instead of throwing.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Resolved
    )

    $picked = $null

    if ($Resolved.ContainsKey('Server')) {
        # Server is known. Only ask for creds if the caller didn't wire one in.
        if (!$Resolved.ContainsKey('Credential')) {
            $credParams = @{
                Caption = 'OU Picker - Remote Connection'
                Message = "Enter credentials with permission to browse OUs on $($Resolved.Server)"
            }
            $Resolved.Credential = Show-UiCredentialDialog @credParams
            if (!$Resolved.Credential) { return $null }
        }
        $picked = Show-UiOuPicker @Resolved
    }
    else {
        # No server hint. Try the local domain; if there is no local domain, prompt.
        try { $picked = Show-UiOuPicker @Resolved }
        catch {
            # Only the no-domain throw triggers the fallback. Anything else (bad bind, bad creds, network) is a real failure - let the click-handler dialog show it.
            if ($_.Exception.Message -notmatch 'requires Active Directory domain membership') { throw }

            $serverParams = @{
                Title  = 'OU Picker - No Domain Detected'
                Prompt = 'This machine is not joined to a domain. Enter a resolvable domain controller hostname or IP to browse organizational units remotely:'
            }
            $Resolved.Server = Show-UiInputDialog @serverParams
            if ($Resolved.Server) {
                $credParams = @{
                    Caption = 'OU Picker - Remote Connection'
                    Message = "Enter credentials with permission to browse OUs on $($Resolved.Server)"
                }
                $Resolved.Credential = Show-UiCredentialDialog @credParams
                if ($Resolved.Credential) { $picked = Show-UiOuPicker @Resolved }
            }
        }
    }

    if ($picked) { return $picked.DistinguishedName }
    return $null
}
