function Set-UiProgress {
    <#
    .SYNOPSIS
        Updates a progress bar value.
    .PARAMETER Variable
        Name of the progress bar control to update.
    .PARAMETER Value
        Percentage value between 0 and 100.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Variable,
        
        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$Value
    )

    Write-Debug "Setting '$Variable' to $Value%"

    $session = Get-UiSession
    $progress = $session.Variables[$Variable]
    
    if ($progress) {
        Invoke-OnUIThread { $progress.Value = $Value }
        Write-Debug "Progress updated"
    }
    else {
        Write-Debug "Control '$Variable' not found in session"
    }
}
