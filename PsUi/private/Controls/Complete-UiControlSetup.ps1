function Complete-UiControlSetup {
    <#
    .SYNOPSIS
        Applies the constraints and properties a control takes and then adds it to the parent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Control,

        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Parent,

        [switch]$FullWidth,

        [hashtable]$WPFProperties
    )

    Set-FullWidthConstraint -Control $Control -Parent $Parent -FullWidth:$FullWidth
    if ($WPFProperties) { Set-UiProperties -Control $Control -Properties $WPFProperties }

    Add-UiControlToParent -Control $Control -Parent $Parent
}
