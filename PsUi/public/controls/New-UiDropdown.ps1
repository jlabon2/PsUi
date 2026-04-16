function New-UiDropdown {
    <#
    .SYNOPSIS
        Creates a dropdown selection control.
    .DESCRIPTION
        Creates a labeled ComboBox for selecting from a list of items.
    .PARAMETER Label
        Label text displayed above the dropdown.
    .PARAMETER Variable
        Variable name to store selection.
    .PARAMETER Items
        Array of selectable items.
    .PARAMETER Default
        Initially selected item.
    .PARAMETER FullWidth
        Forces the control to take full width in WrapPanel layouts.
    .PARAMETER EnabledWhen
        Conditional enabling based on another control's state. Accepts either:
        - A control proxy (e.g., $toggleControl) - enables when that control is truthy
        - A scriptblock (e.g., { $toggle -and $userName }) - enables when expression is true
        Truthy values: CheckBox=checked, TextBox=non-empty, ComboBox=has selection.
    .PARAMETER ClearIfDisabled
        When used with -EnabledWhen, resets the dropdown selection when it becomes disabled.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
        Allows setting any valid WPF property not explicitly exposed as a parameter.
        Invalid properties will generate warnings but not stop execution.
        Supports attached properties using dot notation (e.g., "Grid.Row").
    .EXAMPLE
        New-UiDropdown -Label "Color" -Variable "color" -Items @('Red','Green','Blue') -WPFProperties @{ ToolTip = "Pick a color" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$Variable,

        [Parameter(Mandatory)]
        [string[]]$Items,

        [string]$Default,

        [switch]$FullWidth,

        [Parameter()]
        [object]$EnabledWhen,

        [Parameter()]
        [switch]$ClearIfDisabled,
        
        [Parameter()]
        [hashtable]$WPFProperties
    )

    try {
        $session = Assert-UiSession -CallerName 'New-UiDropdown'
        Write-Debug "Label='$Label', Variable='$Variable', Items=$($Items.Count)"

        $colors  = Get-ThemeColors
        $parent  = $session.CurrentParent
        Write-Debug "Parent: $($parent.GetType().Name)"

        $stack = [System.Windows.Controls.StackPanel]@{
            Margin = [System.Windows.Thickness]::new(4, 4, 4, 8)
        }

        $labelBlock = [System.Windows.Controls.TextBlock]@{
            Text       = $Label
            FontSize   = 12
            Foreground = ConvertTo-UiBrush $colors.ControlFg
            Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
            Tag        = 'ControlFgBrush'
        }
        [PsUi.ThemeEngine]::RegisterElement($labelBlock)
        [void]$stack.Children.Add($labelBlock)

        $combo = [System.Windows.Controls.ComboBox]@{
            Height = 28
        }
        Set-ComboBoxStyle -ComboBox $combo

        foreach ($item in $Items) {
            [void]$combo.Items.Add($item)
        }

        if ($Default -and $Items -contains $Default) {
            $combo.SelectedItem = $Default
        }
        elseif ($Items.Count -gt 0) {
            $combo.SelectedIndex = 0
        }

        [void]$stack.Children.Add($combo)

        # Tag wrapper for FormLayout unwrapping in New-UiGrid
        Set-UiFormControlTag -Wrapper $stack -Label $labelBlock -Control $combo
        
        # FullWidth in WrapPanel contexts
        Set-FullWidthConstraint -Control $stack -Parent $parent -FullWidth:$FullWidth
        
        # Apply custom WPF properties if specified
        if ($WPFProperties) {
            Set-UiProperties -Control $stack -Properties $WPFProperties
        }
        
        Write-Debug "Adding to $($parent.GetType().Name)"
        [void]$parent.Children.Add($stack)

        # Register control in all session registries
        Register-UiControlComplete -Name $Variable -Control $combo -InitialValue $combo.SelectedItem

        # Wire up conditional enabling if specified
        if ($EnabledWhen) {
            Register-UiCondition -TargetControl $combo -Condition $EnabledWhen -ClearIfDisabled:$ClearIfDisabled
        }
    }
    catch {
        Write-Debug "ERROR: $($_.Exception.Message)"
        Write-Debug "STACK: $($_.ScriptStackTrace)"
        throw
    }
}
