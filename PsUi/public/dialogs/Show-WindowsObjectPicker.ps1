function Show-WindowsObjectPicker {
    <#
    .SYNOPSIS
        Shows the native Windows Object Picker dialog.
    .DESCRIPTION
        Wraps the Windows DSObjectPicker COM component to display the standard
        "Select Users, Computers, or Groups" dialog. Computer selection requires
        domain membership.
    .PARAMETER ObjectType
        The type(s) of object to select. Can be one or more of: Computer, User, Group.
        Use array to allow multiple types, e.g., @('User', 'Group')
    .PARAMETER MultiSelect
        Allow selecting multiple objects. Returns array when enabled.
    .PARAMETER ParentWindow
        Optional WPF window to use as the dialog parent.
    .EXAMPLE
        Show-WindowsObjectPicker -ObjectType User
        # Opens the user picker, returns selected username
    .EXAMPLE
        Show-WindowsObjectPicker -ObjectType User, Group -MultiSelect
        # Opens picker for users and groups with multi-select
    .EXAMPLE
        Show-WindowsObjectPicker -ObjectType Computer -MultiSelect
        # Opens computer picker with multi-select on a domain-joined machine
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Computer', 'User', 'Group')]
        [string[]]$ObjectType,
        
        [switch]$MultiSelect,
        
        [System.Windows.Window]$ParentWindow
    )
    
    # Computer picker requires domain membership
    if ($ObjectType -contains 'Computer') {
        try {
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            if (!$cs.PartOfDomain) {
                throw "Computer selection requires domain membership. This machine is not joined to a domain."
            }
        }
        catch [Microsoft.Management.Infrastructure.CimException] {
            throw "Unable to determine domain membership: $_"
        }
    }
    
    # DSObjectPicker is picky about parent handles - different thread or closed window = IntPtr.Zero
    $hwnd = [IntPtr]::Zero
    if ($ParentWindow) {
        try {
            $helper = [System.Windows.Interop.WindowInteropHelper]::new($ParentWindow)
            if ($helper.Handle -ne [IntPtr]::Zero -and $ParentWindow.IsVisible) {
                $hwnd = $helper.Handle
            }
        }
        catch {
            # Window may be disposed or on wrong thread - use no parent
            $hwnd = [IntPtr]::Zero
        }
    }
    else {
        # Try current application window only if it's valid and visible
        $app = [System.Windows.Application]::Current
        if ($app -and $app.MainWindow -and $app.MainWindow.IsVisible) {
            try {
                $helper = [System.Windows.Interop.WindowInteropHelper]::new($app.MainWindow)
                $hwnd = $helper.Handle
            }
            catch {
                $hwnd = [IntPtr]::Zero
            }
        }
    }
    
    # Build the object types flags
    $flags = [PsUi.ObjectPicker+ObjectTypes]::None
    foreach ($type in $ObjectType) {
        switch ($type) {
            'Computer' { $flags = $flags -bor [PsUi.ObjectPicker+ObjectTypes]::Computers }
            'User'     { $flags = $flags -bor [PsUi.ObjectPicker+ObjectTypes]::Users }
            'Group'    { $flags = $flags -bor [PsUi.ObjectPicker+ObjectTypes]::Groups }
        }
    }
    
    # Call the generic picker with combined flags
    $results = [PsUi.ObjectPicker]::ShowObjectPicker($hwnd, $flags, $MultiSelect.IsPresent)
    
    # Check for errors from the native picker
    if ($results -and $results.Count -gt 0 -and $results[0] -like 'ERROR:*') {
        throw "Windows Object Picker failed: $($results[0])"
    }
    
    # Return null if cancelled
    if (!$results -or $results.Count -eq 0) {
        return $null
    }
    
    # Parse results into structured objects for pipeline friendliness
    function ConvertTo-ObjectPickerResult {
        param(
            [string]$RawValue,
            [string[]]$ObjectTypes
        )
        
        $domain = $null
        $name   = $RawValue
        $upn    = $null
        
        # Parse DOMAIN\Name format
        if ($RawValue -match '^([^\\]+)\\(.+)$') {
            $domain = $matches[1]
            $name   = $matches[2]
        }
        
        # Infer type from context (best effort since native picker doesn't always tell us)
        $type = 'Unknown'
        if ($ObjectTypes.Count -eq 1) {
            $type = $ObjectTypes[0]
        }
        elseif ($name -match '\$$') {
            # Computer accounts end with $
            $type = 'Computer'
            $name = $name.TrimEnd('$')
        }
        
        # Build UPN if we have domain info (for users)
        if ($domain -and $type -eq 'User') {
            try {
                $dnsRoot = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
                $upn = "$name@$dnsRoot"
            }
            catch {
                $upn = "$name@$domain"
            }
        }
        
        return [PSCustomObject]@{
            Name     = $name
            Domain   = $domain
            Type     = $type
            UPN      = $upn
            RawValue = $RawValue
        }
    }

    $parsed = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($item in $results) {
        $obj = ConvertTo-ObjectPickerResult -RawValue $item -ObjectTypes $ObjectType
        $parsed.Add($obj)
    }
    
    # Return single object or array based on selection mode
    if ($MultiSelect) {
        return $parsed
    }
    else {
        return $parsed[0]
    }
}
