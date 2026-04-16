function Close-UiParentWindow {
    <#
    .SYNOPSIS
        Finds and closes the parent window of a given control.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.DependencyObject]$Control
    )
    
    # Close any open ReadKey dialog first to prevent freeze
    [PsUi.KeyCaptureDialog]::CloseCurrentDialog()
    
    $parent = $Control
    while ($parent -and $parent -isnot [System.Windows.Window]) {
        $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($parent)
    }
    
    if ($parent) { $parent.Close() }
}
