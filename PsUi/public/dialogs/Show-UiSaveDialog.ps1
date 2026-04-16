function Show-UiSaveDialog {
    <#
    .SYNOPSIS
        Shows a file save dialog.
    .PARAMETER Title
        Dialog title.
    .PARAMETER Filter
        File type filter.
    .PARAMETER DefaultName
        Default file name.
    .PARAMETER InitialDirectory
        Starting folder path when the dialog opens.
    .EXAMPLE
        $path = Show-UiSaveDialog -Filter 'CSV files|*.csv' -DefaultName 'export.csv'
    #>
    [CmdletBinding()]
    param(
        [string]$Title = 'Save File',
        
        [string]$Filter = 'All files|*.*',
        
        [string]$DefaultName,
        
        [string]$InitialDirectory
    )

    Write-Debug "Title='$Title' Filter='$Filter' DefaultName='$DefaultName'"

    # The dialog needs to run on an STA thread with a message pump
    $showDialog = {
        param($dialogTitle, $dialogFilter, $defaultFileName, $initialDir)
        
        Add-Type -AssemblyName PresentationFramework
        
        $dialog = [Microsoft.Win32.SaveFileDialog]::new()
        $dialog.Title = $dialogTitle
        $dialog.Filter = $dialogFilter

        if ($defaultFileName) {
            $dialog.FileName = $defaultFileName
        }

        if ($initialDir -and (Test-Path $initialDir)) {
            $dialog.InitialDirectory = $initialDir
        }

        $result = $dialog.ShowDialog()

        if ($result -eq $true) {
            return $dialog.FileName
        }
        return $null
    }

    # If we're inside a PsUi window, use its dispatcher to show the dialog
    $session = Get-UiSession -ErrorAction SilentlyContinue
    if ($session -and $session.Window) {
        # We have a window, use its dispatcher
        return $session.Window.Dispatcher.Invoke([Func[object]]{
            $dialog = [Microsoft.Win32.SaveFileDialog]::new()
            $dialog.Title = $Title
            $dialog.Filter = $Filter
            if ($DefaultName) { $dialog.FileName = $DefaultName }
            if ($InitialDirectory -and (Test-Path $InitialDirectory)) { 
                $dialog.InitialDirectory = $InitialDirectory 
            }
            $result = $dialog.ShowDialog($session.Window)
            if ($result -eq $true) { return $dialog.FileName }
            return $null
        })
    }

    # No UI context - run in STA runspace
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($showDialog)
    [void]$ps.AddArgument($Title)
    [void]$ps.AddArgument($Filter)
    [void]$ps.AddArgument($DefaultName)
    [void]$ps.AddArgument($InitialDirectory)

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
