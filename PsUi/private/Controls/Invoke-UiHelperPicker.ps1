function Invoke-UiHelperPicker {
    <#
    .SYNOPSIS
        Routes a helper-button click to the matching Show-* picker, splatting resolved HelperOptions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Mode,

        [hashtable]$Options,

        [switch]$MultiSelect
    )

    $resolved = Resolve-HelperOptions $Options

    # MultiSelect is passed explicitly below. If it's also in the splat, parameter binding throws on the duplicate.
    if ($resolved.ContainsKey('MultiSelect')) {
        $MultiSelect = [bool]$resolved.MultiSelect
        [void]$resolved.Remove('MultiSelect')
    }

    switch ($Mode) {
        { $_ -in 'File', 'FilePicker' } { return Show-UiPathPicker -Mode 'File' @resolved }
        'Folder'               { return Show-UiPathPicker -Mode 'Folder' @resolved }
        'FolderPicker'         { return Show-UiFolderPicker -Simple @resolved }
        'AdvancedFolderPicker' { return Show-UiFolderPicker @resolved }
        { $_ -in 'Computer', 'ComputerPicker' } {
            $resolved.ObjectType  = 'Computer'
            $resolved.MultiSelect = $MultiSelect
            return Format-PickerObjectResult (Show-WindowsObjectPicker @resolved)
        }
        { $_ -in 'User', 'UserPicker' } {
            $resolved.ObjectType  = 'User'
            $resolved.MultiSelect = $MultiSelect
            return Format-PickerObjectResult (Show-WindowsObjectPicker @resolved)
        }
        { $_ -in 'Group', 'GroupPicker' } {
            $resolved.ObjectType  = 'Group'
            $resolved.MultiSelect = $MultiSelect
            return Format-PickerObjectResult (Show-WindowsObjectPicker @resolved)
        }
        { $_ -in 'Member', 'UserGroupPicker' } {
            $resolved.ObjectType  = @('User', 'Group')
            $resolved.MultiSelect = $MultiSelect
            return Format-PickerObjectResult (Show-WindowsObjectPicker @resolved)
        }
        { $_ -in 'OU', 'OUPicker' } {
            return Invoke-UiOuPickerOrPrompt -Resolved $resolved.Clone()
        }
    }
}
