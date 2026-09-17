function Add-UiControlToParent {
    <#
    .SYNOPSIS
        Puts a finished control into the current parent, regardless of the parent's type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Control,

        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Parent
    )

    # Three containers'll hold a child at three different places
    if ($Parent -is [System.Windows.Controls.Panel]) { [void]$Parent.Children.Add($Control) }
    elseif ($Parent -is [System.Windows.Controls.ItemsControl]) {

        # WPF throws on Items the moment ItemsSource is set, and its message implies its the list when the problem is actually the layout.
        if ($null -ne $Parent.ItemsSource) { Write-Warning "Add-UiControlToParent: $($Parent.GetType().Name) is driven by ItemsSource, so the $($Control.GetType().Name) was left out. Put the control somewhere that is not bound to a list, or add it to that list's source instead." }
        else { [void]$Parent.Items.Add($Control) }
    }
    elseif ($Parent -is [System.Windows.Controls.ContentControl]) { $Parent.Content = $Control }

    # A parent with no method to add a child gets a warning rather so it'll still build but will notify it wasn't added
    else { Write-Warning "Add-UiControlToParent: a $($Parent.GetType().Name) parent does not hold child controls, so the $($Control.GetType().Name) was built and never placed. Build it inside a panel instead." }
}
