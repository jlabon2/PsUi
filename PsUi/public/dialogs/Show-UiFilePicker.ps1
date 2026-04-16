function Show-UiFilePicker {
    <#
    .SYNOPSIS
        Shows a file open dialog.
    .PARAMETER Title
        Dialog title.
    .PARAMETER Filter
        File type filter.
    .PARAMETER MultiSelect
        Allow multiple file selection.
    .PARAMETER InitialDirectory
        Starting folder path when the dialog opens.
    .EXAMPLE
        $file = Show-UiFilePicker -Filter 'Text files|*.txt|All files|*.*'
    #>
    [CmdletBinding()]
    param(
        [string]$Title = 'Select File',
        
        [string]$Filter = 'All files|*.*',
        
        [string]$InitialDirectory,
        
        [switch]$MultiSelect
    )

    Write-Debug "Title='$Title' Filter='$Filter' MultiSelect=$MultiSelect"

    # If we're inside a PsUi window, use its dispatcher to show the dialog
    $session = Get-UiSession -ErrorAction SilentlyContinue
    if ($session -and $session.Window) {
        # We have a window, use its dispatcher
        return $session.Window.Dispatcher.Invoke([Func[object]]{
            $dialog = [Microsoft.Win32.OpenFileDialog]::new()
            $dialog.Title = $Title
            $dialog.Filter = $Filter
            $dialog.Multiselect = $MultiSelect.IsPresent
            if ($InitialDirectory -and (Test-Path $InitialDirectory)) { 
                $dialog.InitialDirectory = $InitialDirectory 
            }
            $result = $dialog.ShowDialog($session.Window)
            if ($result -eq $true) {
                if ($MultiSelect) { return $dialog.FileNames }
                return $dialog.FileName
            }
            return $null
        })
    }

    # No UI context - run in STA runspace
    $showDialog = {
        param($dialogTitle, $dialogFilter, $initialDir, $multiSel)
        
        Add-Type -AssemblyName PresentationFramework
        
        $dialog = [Microsoft.Win32.OpenFileDialog]::new()
        $dialog.Title = $dialogTitle
        $dialog.Filter = $dialogFilter
        $dialog.Multiselect = $multiSel

        if ($initialDir -and (Test-Path $initialDir)) {
            $dialog.InitialDirectory = $initialDir
        }

        $result = $dialog.ShowDialog()

        if ($result -eq $true) {
            if ($multiSel) { return $dialog.FileNames }
            return $dialog.FileName
        }
        return $null
    }

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($showDialog)
    [void]$ps.AddArgument($Title)
    [void]$ps.AddArgument($Filter)
    [void]$ps.AddArgument($InitialDirectory)
    [void]$ps.AddArgument($MultiSelect.IsPresent)

    try {
        $result = $ps.Invoke()
        Write-Debug "Result: $result"
        return $result
    }
    finally {
        $ps.Dispose()
        $runspace.Dispose()
    }
}
