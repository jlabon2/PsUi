function Show-UiOuPicker {
    <#
    .SYNOPSIS
        Shows the native Windows OU/container browser dialog.
    .DESCRIPTION
        Wraps DsBrowseForContainerW (dsuiext.dll) - the same OU picker that ADUC,
        Group Policy Management, and every other Microsoft AD tool uses. Returns a
        PSCustomObject with Name, DistinguishedName, and AdsPath. Returns $null
        if the user cancels.
    .PARAMETER Title
        Caption shown in the dialog title bar.
    .PARAMETER Prompt
        Instruction text shown above the tree.
    .PARAMETER Root
        Distinguished name or ADsPath of the container to use as the tree root.
        Accepts either 'OU=Servers,DC=corp,DC=local' or 'LDAP://corp.local/...'.
        Defaults to the current domain.
    .PARAMETER Server
        Domain controller or DNS name to target. Useful when the local machine
        isn't joined to the target domain.
    .PARAMETER IncludeEntireDirectory
        Browse the full forest, not just the local domain.
    .PARAMETER IncludeHidden
        Include hidden containers (CN=System, CN=Configuration, etc.).
    .PARAMETER NoButtons
        Hide the expand/collapse buttons.
    .PARAMETER IgnoreTreatAsLeaf
        Makes the dialog ignore treatAsLeaf display specifiers, so containers they mark
        as leaf objects still expand. Worth trying when a custom -Root or -Server leaves
        the tree refusing to expand things that clearly have children.
    .PARAMETER ParentWindow
        WPF window to use as the modal parent. Falls back to the active session window.
    .PARAMETER Credential
        Alternate credentials for accessing a directory the local machine is not
        joined to. Handed to the native dialog's own credential fields. No
        impersonation involved, no special privileges required.
    .EXAMPLE
        $ou = Show-UiOuPicker -Title 'Pick a target OU'
        if ($ou) { New-ADUser -Path $ou.DistinguishedName -Name 'jdoe' }
    .EXAMPLE
        Show-UiOuPicker -Server 'dc01.corp.local' -Root 'OU=Servers,DC=corp,DC=local'
    .EXAMPLE
        $cred = Get-Credential 'CORP\admin'
        $ou = Show-UiOuPicker -Credential $cred -Server 'dc01.corp.local'
    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding()]
    param(
        [string]$Title  = 'Select an organizational unit',
        [string]$Prompt = 'Select an organizational unit:',
        [string]$Root,
        [string]$Server,
        [switch]$IncludeEntireDirectory,
        [switch]$IncludeHidden,
        [switch]$NoButtons,
        # Maps to DSBI_IGNORETREATASLEAF. Display specifiers lie with a non-null root. This makes containers they mark as leaves expand anyway.
        [switch]$IgnoreTreatAsLeaf,
        [System.Windows.Window]$ParentWindow,

        # Alternate credentials for accessing a domain the machine isn't joined to.
        # These go through the native struct's pUserName/pPassword fields (DSBI_HASCREDENTIALS), not impersonation.
        [PSCredential]$Credential
    )

    Write-Debug "Title='$Title' Root='$Root' Server='$Server'"

    # Pull creds early - the RootDSE query and the up-front bind check need them before the dialog even opens.
    $credUser = $null; $credPass = $null
    if ($Credential) {
        $credUser = $Credential.UserName
        $credPass = $Credential.GetNetworkCredential().Password

        # Probe the bind now to surface a real error instead of an empty tree.
        if ($Server) {
            try {
                $testEntry = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/RootDSE", $credUser, $credPass)
                $null = $testEntry.NativeObject
                $testEntry.Dispose()
            }
            catch {
                throw "Credential validation failed against $Server. Verify the username (use DOMAIN\\user format), password, and server reachability. Error: $_"
            }
        }
    }

    # Factory for DirectoryEntry - passes creds when present, skips when not.
    # The workgroup check below only fires without -Server, where creds aren't
    # relevant anyway.
    $newEntry = {
        param($path)
        if ($credUser) {
            return [System.DirectoryServices.DirectoryEntry]::new($path, $credUser, $credPass)
        }
        return [System.DirectoryServices.DirectoryEntry]::new($path)
    }

    # No -Server means the dialog uses the logon domain. Bail on workgroup
    # machines now instead of showing a broken tree.
    if (!$Server) {
        try {
            [void][System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        }
        catch {
            throw "Show-UiOuPicker requires Active Directory domain membership unless -Server is supplied. Error: $_"
        }
    }

    # Build the root ADsPath. The API only accepts LDAP:// prefixed paths; bare DNs
    # need wrapping. We leave $rootAds $null when the caller didn't specify a root:
    # pszRoot=NULL triggers the picker's built-in domain browser, which uses
    # objectClass-based detection (like ADUC does). A non-null pszRoot breaks that
    # and you get the treatAsLeaf expansion issue. That's the API, not us.
    $rootAds = $null
    if ($Root) {
        if ($Root -like 'LDAP://*' -or $Root -like 'GC://*') { $rootAds = $Root }
        elseif ($Server) { $rootAds = "LDAP://$Server/$Root" }
        else             { $rootAds = "LDAP://$Root" }
    }
    elseif ($Server) {
        # Server without a root - point at its defaultNamingContext so the picker
        # targets that DC. There's no way to say "default domain on this specific
        # server" with pszRoot=NULL, so the treatAsLeaf trade-off applies here.
        # If RootDSE is unreachable (firewall, permissions, etc.), fall back to
        # pszRoot=NULL and let the dialog auto-discover.
        try {
            $rootDse = & $newEntry "LDAP://$Server/RootDSE"
            $ncProp  = $rootDse.Properties['defaultNamingContext']
            if ($ncProp -and $ncProp.Value) {
                $rootAds = "LDAP://$Server/$($ncProp.Value)"
            }
            $rootDse.Dispose()
        }
        catch {
            Write-Verbose "Show-UiOuPicker: RootDSE query against '$Server' failed - falling back to auto-discovery. Error: $_"
        }
    }
    # else: $rootAds stays $null - the dialog auto-discovers and expands correctly.

    # Probe the resolved root. dsuiext returns -1 with no LastError when it
    # can't bind - useless. Failing here gives a real .NET exception instead.
    if ($rootAds) {
        try {
            $probe = & $newEntry $rootAds
            $null  = $probe.NativeObject  # forces the bind
            $probe.Dispose()
        }
        catch {
            throw "Show-UiOuPicker could not bind to root '$rootAds'. Verify the server, DN, and your access. Error: $_"
        }
    }

    Write-Debug "Resolved rootAds='$rootAds'"

    # Get a parent HWND or the dialog shows up behind everything.
    # IntPtr.Zero works but the UX is bad.
    $hwnd      = [IntPtr]::Zero
    $session   = Get-UiSession -ErrorAction SilentlyContinue
    $candidate = $ParentWindow
    if (!$candidate -and $session -and $session.Window) { $candidate = $session.Window }
    if (!$candidate) {
        $app = [System.Windows.Application]::Current
        if ($app -and $app.MainWindow -and $app.MainWindow.IsVisible) { $candidate = $app.MainWindow }
    }
    if ($candidate) {
        try {
            $helper = [System.Windows.Interop.WindowInteropHelper]::new($candidate)
            if ($helper.Handle -ne [IntPtr]::Zero -and $candidate.IsVisible) { $hwnd = $helper.Handle }
        }
        catch { $hwnd = [IntPtr]::Zero }
    }

    # When called from a button action, the caller is on a background MTA thread. Route through
    # the session dispatcher so the dialog has a proper parent thread context.
    $ignoreTreatAsLeaf = $IgnoreTreatAsLeaf.IsPresent

    # $hwnd must be IntPtr, never $null. The API handles Zero fine but
    # PowerShell's type system chokes on null.
    if ($null -eq $hwnd) { $hwnd = [IntPtr]::Zero }

    if ($session -and $session.Window -and !$session.Window.Dispatcher.CheckAccess()) {
        $raw = $session.Window.Dispatcher.Invoke([Func[object]]{
            [PsUi.OuPicker]::Show($hwnd, $Title, $Prompt, $rootAds,
                $IncludeEntireDirectory.IsPresent, $IncludeHidden.IsPresent, $NoButtons.IsPresent,
                $ignoreTreatAsLeaf, $credUser, $credPass)
        }.GetNewClosure())
    }
    else {
        # No session, or already on UI thread. OuPicker.cs runs its own STA thread internally.
        $raw = [PsUi.OuPicker]::Show($hwnd, $Title, $Prompt, $rootAds,
            $IncludeEntireDirectory.IsPresent, $IncludeHidden.IsPresent, $NoButtons.IsPresent,
            $ignoreTreatAsLeaf, $credUser, $credPass)
    }

    # Clear the plaintext string reference so GC can collect it sooner
    $credPass = $null

    if (!$raw) { return $null }

    # API returns "LDAP://server/CN=...,DC=corp,DC=local". Strip the prefix
    # so callers get the plain DN.
    $adsPath = [string]$raw
    $dn      = $adsPath
    if ($dn -match '^LDAP://(?:[^/]+/)?(.+)$') { $dn = $matches[1] }

    # Leaf RDN value is the human-readable name (OU=Servers becomes Servers)
    $name = $dn
    if ($dn -match '^[A-Za-z]+=([^,]+)') { $name = $matches[1] }

    [pscustomobject]@{
        Name              = $name
        DistinguishedName = $dn
        AdsPath           = $adsPath
    }
}
