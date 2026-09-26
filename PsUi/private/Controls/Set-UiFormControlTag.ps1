function Set-UiFormControlTag {
    <#
    .SYNOPSIS
        Tags a wrapper panel with label and control references for FormLayout grid unwrapping.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Panel]$Wrapper,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBlock]$Label,

        [Parameter(Mandatory)]
        [System.Windows.UIElement]$Control
    )

    # Tag enables New-UiGrid FormLayout to unwrap and position label/control separately
    $Wrapper.Tag = @{
        FormControl = $true
        Label       = $Label
        Control     = $Control
    }

    # New-UiWindow builds its content panel in C#. A labeled control directly within it get the row alignment from here
    $alignRows    = ${function:Set-UiRowAlignment}
    $hook         = @{}
    $hook.Handler = [System.Windows.RoutedEventHandler]{
        param($sender, $loadedArgs)
        trap { Write-Debug "Set-UiFormControlTag row alignment: $_"; continue }

        # Loaded fires again on every tab switch with the old handlers still on
        $sender.Remove_Loaded($hook.Handler)
        if ($sender.Parent -is [System.Windows.Controls.Panel]) { & $alignRows -Panel $sender.Parent }
    }.GetNewClosure()
    $Wrapper.Add_Loaded($hook.Handler)
}
