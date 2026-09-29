function Add-UiStyleHandler {
    <#
    .SYNOPSIS
        Attaches a handler the first time a style function runs and skips it on every pass after.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Control,

        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [scriptblock]$Attach
    )

    # Every Set-*Style runs again on a theme switch, so a raw Add_ in one of them stacks another handler each pass.
    # $Attach gets the element as its argument.
    if ($Control.Resources.Contains($Key)) { return }
    $Control.Resources[$Key] = $true
    & $Attach $Control
}
