function Resolve-HelperOptionValue {
    <#
    .SYNOPSIS
        Resolves one HelperOptions value: control-name lookup if the value matches a registered Variable, literal otherwise.
    #>
    [CmdletBinding()]
    param(
        [object]$Value
    )

    if ($null -eq $Value) { return $null }

    # Strings might be lookup keys. Ints, creds, anything else - the user meant it literally.
    if ($Value -isnot [string]) { return $Value }
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    $session = Get-UiSession
    if (!$session) { return $Value }

    if ($session.Variables.ContainsKey($Value)) {
        $entry = $session.Variables[$Value]

        # CredentialControl is a PSCustomObject wraper - not a FrameworkElement, can't go through the extractor.
        if ($entry.PSTypeNames -contains 'PsUi.CredentialControl') {
            if (!$entry.UsernameBox -or !$entry.PasswordBox) { return $null }
            $user = $entry.UsernameBox.Text
            $pass = $entry.PasswordBox.SecurePassword
            if (!$user -or !$pass -or $pass.Length -eq 0) {
                if ($pass) { try { $pass.Dispose() } catch { } }
                return $null
            }
            # $pass is a fresh copy from WPF (new one per .SecurePassword read). Copy it for the credential, dispose the spare.
            $copy = $pass.Copy()
            $copy.MakeReadOnly()
            try { $pass.Dispose() } catch { }
            return [System.Management.Automation.PSCredential]::new($user, $copy)
        }

        # ExtractValue knows the per-control quirks - SelectedItem for ComboBox, SelectedDate for DatePicker, etc.
        if ($entry -is [System.Windows.FrameworkElement]) {
            $raw = [PsUi.ControlValueExtractor]::ExtractValue($entry)
            if ($null -ne $raw -and "$raw" -ne '') { return $raw }
            return $null
        }
    }

    return $Value
}
