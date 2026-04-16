function Show-SimpleFolderPicker {
    <#
    .SYNOPSIS
        Legacy FolderBrowserDialog implementation (tree-view style).
    #>
    param(
        [string]$Title,
        [string]$InitialDirectory
    )

    # If we're inside a PsUi window, use its dispatcher to show the dialog
    $session = Get-UiSession -ErrorAction SilentlyContinue
    if ($session -and $session.Window) {
        return $session.Window.Dispatcher.Invoke([Func[object]]{
            Add-Type -AssemblyName System.Windows.Forms
            $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
            $dialog.Description = $Title
            $dialog.ShowNewFolderButton = $true
            if ($InitialDirectory -and (Test-Path $InitialDirectory)) {
                $dialog.SelectedPath = $InitialDirectory
            }
            $result = $dialog.ShowDialog()
            if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
                return $dialog.SelectedPath
            }
            return $null
        })
    }

    # No UI context - run in STA runspace
    $showDialog = {
        param($dialogTitle, $initialDir)

        Add-Type -AssemblyName System.Windows.Forms

        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dialog.Description = $dialogTitle
        $dialog.ShowNewFolderButton = $true

        if ($initialDir -and (Test-Path $initialDir)) {
            $dialog.SelectedPath = $initialDir
        }

        $result = $dialog.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
        return $null
    }

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions  = 'ReuseThread'
    $runspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($showDialog)
    [void]$ps.AddArgument($Title)
    [void]$ps.AddArgument($InitialDirectory)

    try {
        return $ps.Invoke()
    }
    finally {
        $ps.Dispose()
        $runspace.Dispose()
    }
}
