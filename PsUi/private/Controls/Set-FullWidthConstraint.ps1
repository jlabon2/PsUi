function Set-FullWidthConstraint {
    <#
    .SYNOPSIS
        Applies full-width constraint to a control in WrapPanel contexts.
        This is used with Set-ResponsiveConstraints to enforce full-width behavior.
        A bit hacky but works within WPF's layout system.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Control,
        
        [Parameter(Mandatory)]
        [System.Windows.Controls.Panel]$Parent,
        
        [switch]$FullWidth
    )
    
    # Only apply if FullWidth is requested and parent is a WrapPanel
    if (!$FullWidth) { return }
    if ($Parent -isnot [System.Windows.Controls.WrapPanel]) { return }
    
    # Force the control to take full width
    $Parent.Add_SizeChanged({
        param($sender, $eventArgs)
        # Padding buffer accounts for WrapPanel internal spacing (18px matches Set-ResponsiveConstraints)
        $paddingBuffer = 18
        $availableWidth = $sender.ActualWidth - $paddingBuffer
        if ($availableWidth -gt 0) {
            $Control.Width = $availableWidth
        }
    }.GetNewClosure())
    
    # Add standard 8px margins if none are set
    $defaultMargin = 8
    if ($Control.Margin.Left -eq 0 -and $Control.Margin.Right -eq 0) {
        $Control.Margin = [System.Windows.Thickness]::new($defaultMargin)
    }
}
