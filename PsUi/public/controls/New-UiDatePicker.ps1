function New-UiDatePicker {
    <#
    .SYNOPSIS
        Creates a date picker control.
    .PARAMETER Variable
        Variable name to store the date.
    .PARAMETER Label
        Label text.
    .PARAMETER Default
        Initial date value.
    .PARAMETER FullWidth
        Stretches the control to fill available width instead of fixed sizing.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
        Allows setting any valid WPF property not explicitly exposed as a parameter.
        Invalid properties will generate warnings but not stop execution.
        Supports attached properties using dot notation (e.g., "Grid.Row").
    .EXAMPLE
        New-UiDatePicker -Variable 'startDate' -Label 'Start Date'
    .EXAMPLE
        New-UiDatePicker -Variable 'dueDate' -Label 'Due By' -Default (Get-Date).AddDays(30)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Variable,
        
        [string]$Label,
        
        [datetime]$Default = [datetime]::Today,

        [switch]$FullWidth,

        [Parameter()]
        [object]$EnabledWhen,

        [switch]$ClearIfDisabled,
        
        [Parameter()]
        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiDatePicker'
    Write-Debug "Variable='$Variable', Label='$Label', Default=$Default"

    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent
    Write-Debug "Parent: $($parent.GetType().Name)"

    $stack = [System.Windows.Controls.StackPanel]::new()
    $stack.Margin = [System.Windows.Thickness]::new(4, 4, 4, 8)

    if ($Label) {
        $labelBlock = [System.Windows.Controls.TextBlock]@{
            Text       = $Label
            FontSize   = 12
            Foreground = ConvertTo-UiBrush $colors.ControlFg
            Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
            Tag        = 'ControlFgBrush'
        }
        [PsUi.ThemeEngine]::RegisterElement($labelBlock)
        [void]$stack.Children.Add($labelBlock)
    }

    $picker = [System.Windows.Controls.DatePicker]::new()
    $picker.SelectedDate = $Default
    Set-DatePickerStyle -DatePicker $picker
    
    [void]$stack.Children.Add($picker)

    # Tag wrapper for FormLayout unwrapping in New-UiGrid (only if label exists)
    if ($Label) {
        Set-UiFormControlTag -Wrapper $stack -Label $labelBlock -Control $picker
    }
    
    # FullWidth in WrapPanel contexts
    Set-FullWidthConstraint -Control $stack -Parent $parent -FullWidth:$FullWidth
    
    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $stack -Properties $WPFProperties
    }
    
    Write-Debug "Adding to $($parent.GetType().Name)"
    [void]$parent.Children.Add($stack)

    # Register control in all session registries
    Register-UiControlComplete -Name $Variable -Control $picker -InitialValue $picker.SelectedDate

    if ($EnabledWhen) {
        Register-UiCondition -TargetControl $picker -Condition $EnabledWhen -ClearIfDisabled:$ClearIfDisabled
    }
}
