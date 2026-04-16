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
}
