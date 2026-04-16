function Show-UiPathPicker {
    <#
    .SYNOPSIS
        Shows a file or folder picker dialog and returns the selected path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('File', 'Folder', 'SaveFile')]
        [string]$Mode,
        
        [string]$Title,
        
        [string]$Filter = 'All Files (*.*)|*.*',
        
        [string]$InitialDirectory
    )
    
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    
    $result = $null
    
    switch ($Mode) {
        'File' {
            $dialog = [System.Windows.Forms.OpenFileDialog]::new()
            $dialog.Filter = $Filter
            $dialog.Multiselect = $false
            if ($Title) { $dialog.Title = $Title }
            if ($InitialDirectory -and (Test-Path $InitialDirectory)) {
                $dialog.InitialDirectory = $InitialDirectory
            }
            
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $result = $dialog.FileName
            }
            $dialog.Dispose()
        }
        
        'SaveFile' {
            $dialog = [System.Windows.Forms.SaveFileDialog]::new()
            $dialog.Filter = $Filter
            if ($Title) { $dialog.Title = $Title }
            if ($InitialDirectory -and (Test-Path $InitialDirectory)) {
                $dialog.InitialDirectory = $InitialDirectory
            }
            
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $result = $dialog.FileName
            }
            $dialog.Dispose()
        }
        
        'Folder' {
            $result = Show-ModernFolderPicker -Title $Title -InitialDirectory $InitialDirectory
        }
    }
    
    return $result
}
