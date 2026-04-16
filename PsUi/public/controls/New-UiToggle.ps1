function New-UiToggle {
    <#
    .SYNOPSIS
        Creates a checkbox/toggle control.
    .DESCRIPTION
        Creates a themed CheckBox control with a label.
    .PARAMETER Label
        Text shown next to the toggle.
    .PARAMETER Variable
        Variable name to store state.
    .PARAMETER Checked
        Initial checked state.
    .PARAMETER FullWidth
        Forces the control to take full width in WrapPanel layouts.
    .PARAMETER EnabledWhen
        Conditional enabling based on another control's state. Accepts either:
        - A control proxy (e.g., $toggleControl) - enables when that control is truthy
        - A scriptblock (e.g., { $toggle -and $userName }) - enables when expression is true
        Truthy values: CheckBox=checked, TextBox=non-empty, ComboBox=has selection.
    .PARAMETER ClearIfDisabled
        When used with -EnabledWhen, unchecks the toggle when it becomes disabled.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
        Allows setting any valid WPF property not explicitly exposed as a parameter.
        Invalid properties will generate warnings but not stop execution.
        Supports attached properties using dot notation (e.g., "Grid.Row").
    .EXAMPLE
        New-UiToggle -Label "Enable" -Variable "enabled" -WPFProperties @{ ToolTip = "Toggle feature" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$Variable,

        [switch]$Checked,

        [switch]$FullWidth,

        [Parameter()]
        [object]$EnabledWhen,

        [Parameter()]
        [switch]$ClearIfDisabled,
        
        [Parameter()]
        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiToggle'
    Write-Debug "Label='$Label', Variable='$Variable', Checked=$($Checked.IsPresent)"

    $parent  = $session.CurrentParent
    Write-Debug "Parent: $($parent.GetType().Name)"

    $checkBox = [System.Windows.Controls.CheckBox]@{
        Content   = $Label
        IsChecked = $Checked.IsPresent
        Margin    = [System.Windows.Thickness]::new(4, 4, 4, 8)
    }
    Set-CheckBoxStyle -CheckBox $checkBox

    # Complete setup: constraints, properties, add to parent
    Write-Debug "Adding to $($parent.GetType().Name)"
    Complete-UiControlSetup -Control $checkBox -Parent $parent -FullWidth:$FullWidth -WPFProperties $WPFProperties

    # Register control in all session registries
    Register-UiControlComplete -Name $Variable -Control $checkBox -InitialValue $Checked.IsPresent

    # Wire up conditional enabling if specified
    if ($EnabledWhen) {
        Register-UiCondition -TargetControl $checkBox -Condition $EnabledWhen -ClearIfDisabled:$ClearIfDisabled
    }
}
