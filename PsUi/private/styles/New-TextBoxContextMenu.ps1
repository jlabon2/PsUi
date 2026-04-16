<#
.SYNOPSIS
    Creates a themed context menu for TextBox controls.
#>
function New-TextBoxContextMenu {
    [CmdletBinding()]
    param(
        [switch]$ReadOnly
    )

    $menu = [System.Windows.Controls.ContextMenu]::new()

    # Scoped Separator style in menu resources
    $sepStyle = [System.Windows.Style]::new([System.Windows.Controls.Separator])
    $sepStyle.Setters.Add([System.Windows.Setter]::new(
        [System.Windows.FrameworkElement]::MarginProperty,
        [System.Windows.Thickness]::new(0, 4, 0, 4)
    ))
    $sepStyle.Setters.Add([System.Windows.Setter]::new(
        [System.Windows.FrameworkElement]::HorizontalAlignmentProperty,
        [System.Windows.HorizontalAlignment]::Stretch
    ))

    $sepTemplate   = [System.Windows.Controls.ControlTemplate]::new([System.Windows.Controls.Separator])
    $borderFactory = [System.Windows.FrameworkElementFactory]::new([System.Windows.Controls.Border])
    $borderFactory.SetValue([System.Windows.FrameworkElement]::HeightProperty, [double]1)
    $borderFactory.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)
    $borderFactory.SetValue([System.Windows.FrameworkElement]::SnapsToDevicePixelsProperty, $true)
    $borderFactory.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'BorderBrush')

    $sepTemplate.VisualTree = $borderFactory
    $sepStyle.Setters.Add([System.Windows.Setter]::new(
        [System.Windows.Controls.Control]::TemplateProperty,
        $sepTemplate
    ))

    $menu.Resources.Add([System.Windows.Controls.Separator], $sepStyle)

    if ($ReadOnly) {
        # Read-only: only Copy and Select All
        $copy      = [System.Windows.Controls.MenuItem]@{ Header = 'Copy'; Command = [System.Windows.Input.ApplicationCommands]::Copy }
        $selectAll = [System.Windows.Controls.MenuItem]@{ Header = 'Select All'; Command = [System.Windows.Input.ApplicationCommands]::SelectAll }
        $sep       = [System.Windows.Controls.Separator]::new()
        $sep.Style = $sepStyle

        $menu.Items.Add($copy) | Out-Null
        $menu.Items.Add($sep) | Out-Null
        $menu.Items.Add($selectAll) | Out-Null
    }
    else {
        # Editable: Cut, Copy, Paste, Select All
        $cut       = [System.Windows.Controls.MenuItem]@{ Header = 'Cut'; Command = [System.Windows.Input.ApplicationCommands]::Cut }
        $copy      = [System.Windows.Controls.MenuItem]@{ Header = 'Copy'; Command = [System.Windows.Input.ApplicationCommands]::Copy }
        $paste     = [System.Windows.Controls.MenuItem]@{ Header = 'Paste'; Command = [System.Windows.Input.ApplicationCommands]::Paste }
        $selectAll = [System.Windows.Controls.MenuItem]@{ Header = 'Select All'; Command = [System.Windows.Input.ApplicationCommands]::SelectAll }
        $sep       = [System.Windows.Controls.Separator]::new()
        $sep.Style = $sepStyle

        $menu.Items.Add($cut) | Out-Null
        $menu.Items.Add($copy) | Out-Null
        $menu.Items.Add($paste) | Out-Null
        $menu.Items.Add($sep) | Out-Null
        $menu.Items.Add($selectAll) | Out-Null
    }

    Set-ContextMenuStyle -ContextMenu $menu

    return $menu
}
