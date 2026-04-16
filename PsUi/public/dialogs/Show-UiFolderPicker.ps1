function Show-UiFolderPicker {
    <#
    .SYNOPSIS
        Shows a folder selection dialog.
    .DESCRIPTION
        Displays a modern Windows folder picker dialog. By default uses the Vista-style file dialog
        configured for folder selection, which provides a better user experience with navigation pane,
        breadcrumb bar, and search. Use -Simple for the legacy tree-view style picker.
    .PARAMETER Title
        Dialog title shown in the title bar.
    .PARAMETER Description
        Alias for Title.
    .PARAMETER InitialDirectory
        Starting folder path.
    .PARAMETER Simple
        Use the legacy FolderBrowserDialog (XP-style tree view) instead of the modern picker.
    .PARAMETER Multiselect
        Allow selection of multiple folders. Only works with the modern picker (ignored with -Simple).
    .EXAMPLE
        $folder = Show-UiFolderPicker -Title 'Select Output Folder'
    .EXAMPLE
        $folders = Show-UiFolderPicker -Title 'Select Source Folders' -Multiselect
    #>
    [CmdletBinding()]
    param(
        [Alias('Description')]
        [string]$Title = 'Select a folder',
        
        [string]$InitialDirectory,
        
        [switch]$Simple,
        
        [switch]$Multiselect
    )

    Write-Debug "Title='$Title' Simple=$Simple Multiselect=$Multiselect"

    if ($Simple) {
        return Show-SimpleFolderPicker -Title $Title -InitialDirectory $InitialDirectory
    }
    
    return Show-ModernFolderPicker -Title $Title -InitialDirectory $InitialDirectory -Multiselect:$Multiselect
}
