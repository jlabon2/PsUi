function Reset-StatusBarBadges {
    <#
    .SYNOPSIS
        Zeros all intercept badges, clears message lists, and closes popups.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Meta
    )

    # Flush the backing message lists
    if ($null -ne $Meta.WarningMessages) { $Meta.WarningMessages.Clear() }
    if ($null -ne $Meta.ErrorMessages)   { $Meta.ErrorMessages.Clear() }
    if ($null -ne $Meta.HostMessages)    { $Meta.HostMessages.Clear() }
    if ($null -ne $Meta.VerboseMessages) { $Meta.VerboseMessages.Clear() }
    if ($null -ne $Meta.DebugMessages)   { $Meta.DebugMessages.Clear() }

    # Badges back to visible-but-dimmed
    if ($Meta.WarningBadge) {
        $Meta.WarningBadge.CountText.Text = '0'
        $Meta.WarningBadge.Badge.Opacity  = 0.35
        $Meta.WarningBadge.Badge.ToolTip  = '0 Warnings'
    }
    if ($Meta.ErrorBadge) {
        $Meta.ErrorBadge.CountText.Text = '0'
        $Meta.ErrorBadge.Badge.Opacity  = 0.35
        $Meta.ErrorBadge.Badge.ToolTip  = '0 Errors'
    }
    if ($Meta.HostBadge) {
        $Meta.HostBadge.CountText.Text = '0'
        $Meta.HostBadge.Badge.Opacity  = 0.35
        $Meta.HostBadge.Badge.ToolTip  = '0 Messages'
    }
    if ($Meta.VerboseBadge) {
        $Meta.VerboseBadge.CountText.Text = '0'
        $Meta.VerboseBadge.Badge.Opacity  = 0.35
        $Meta.VerboseBadge.Badge.ToolTip  = '0 Verbose lines'
    }
    if ($Meta.DebugBadge) {
        $Meta.DebugBadge.CountText.Text = '0'
        $Meta.DebugBadge.Badge.Opacity  = 0.35
        $Meta.DebugBadge.Badge.ToolTip  = '0 Debug lines'
    }

    # Close popups and clear their content
    if ($Meta.WarningPopup) {
        $Meta.WarningPopup.MessagePanel.Children.Clear()
        $Meta.WarningPopup.HeaderText.Text = '0 Warnings'
        $Meta.WarningPopup.Popup.IsOpen    = $false
    }
    if ($Meta.ErrorPopup) {
        $Meta.ErrorPopup.MessagePanel.Children.Clear()
        $Meta.ErrorPopup.HeaderText.Text = '0 Errors'
        $Meta.ErrorPopup.Popup.IsOpen    = $false
    }
    if ($Meta.HostPopup) {
        $Meta.HostPopup.MessagePanel.Children.Clear()
        $Meta.HostPopup.HeaderText.Text = '0 Messages'
        $Meta.HostPopup.Popup.IsOpen    = $false
    }
    if ($Meta.VerbosePopup) {
        $Meta.VerbosePopup.MessagePanel.Children.Clear()
        $Meta.VerbosePopup.HeaderText.Text = '0 Verbose lines'
        $Meta.VerbosePopup.Popup.IsOpen    = $false
    }
    if ($Meta.DebugPopup) {
        $Meta.DebugPopup.MessagePanel.Children.Clear()
        $Meta.DebugPopup.HeaderText.Text = '0 Debug lines'
        $Meta.DebugPopup.Popup.IsOpen    = $false
    }
}
