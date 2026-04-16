function Complete-UiControlSetup {
    <#
    .SYNOPSIS
        Completes control setup by applying constraints, properties, and adding to parent.
        TODO: Eval whether we can use this more widely across PsUi.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Control,

        [Parameter(Mandatory)]
        [System.Windows.Controls.Panel]$Parent,

        [switch]$FullWidth,

        [hashtable]$WPFProperties
    )

    Set-FullWidthConstraint -Control $Control -Parent $Parent -FullWidth:$FullWidth
    if ($WPFProperties) { Set-UiProperties -Control $Control -Properties $WPFProperties }
    [void]$Parent.Children.Add($Control)
}
