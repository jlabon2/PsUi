function New-UiRadioGroup {
    <#
    .SYNOPSIS
        Creates a group of mutually exclusive radio button options.
    .DESCRIPTION
        Creates a labeled panel containing radio buttons where only one option can be selected at a time.
        The selected value is available as a hydrated variable in -Action blocks.
    .PARAMETER Label
        Label text displayed above the radio button group.
    .PARAMETER Variable
        Variable name to store the selected value.
    .PARAMETER Items
        Array of option labels for the radio buttons.
    .PARAMETER Default
        Initially selected option. If not specified, the first item is selected.
    .PARAMETER Orientation
        Layout orientation for the radio buttons. 'Vertical' (default) or 'Horizontal'.
    .PARAMETER FullWidth
        Stretches the control to fill available width instead of fixed sizing.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the container control.
    .EXAMPLE
        New-UiRadioGroup -Label "Priority" -Variable "priority" -Items @('Low', 'Medium', 'High') -Default 'Medium'
    .EXAMPLE
        New-UiRadioGroup -Label "Size" -Variable "size" -Items @('S', 'M', 'L', 'XL') -Orientation Horizontal
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

        [ValidateSet('Vertical', 'Horizontal')]
        [string]$Orientation = 'Vertical',

        [switch]$FullWidth,

        [Parameter()]
        [object]$EnabledWhen,

        [switch]$ClearIfDisabled,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiRadioGroup'
    Write-Debug "Creating radio group '$Variable' with $($Items.Count) items"
    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent

    $outerStack = [System.Windows.Controls.StackPanel]@{
        Margin = [System.Windows.Thickness]::new(4, 4, 4, 8)
    }

    $labelBlock = [System.Windows.Controls.TextBlock]@{
        Text       = $Label
        FontSize   = 12
        Foreground = ConvertTo-UiBrush $colors.ControlFg
        Margin     = [System.Windows.Thickness]::new(0, 0, 0, 6)
        Tag        = 'ControlFgBrush'
    }
    [PsUi.ThemeEngine]::RegisterElement($labelBlock)
    [void]$outerStack.Children.Add($labelBlock)

    $radioPanel = [System.Windows.Controls.StackPanel]@{
        Orientation = if ($Orientation -eq 'Horizontal') {
            [System.Windows.Controls.Orientation]::Horizontal
        } else {
            [System.Windows.Controls.Orientation]::Vertical
        }
    }

    # Unique group name so only one radio button can be selected at a time
    $groupName = "RadioGroup_${Variable}_$(Get-Random)"

    # Track which item should be selected by default
    $defaultItem = if ($Default -and $Items -contains $Default) { $Default } else { $Items[0] }
    Write-Debug "Default selection: $defaultItem"
    $radioButtons = @{}

    foreach ($item in $Items) {
        $radio = [System.Windows.Controls.RadioButton]@{
            Content   = $item
            GroupName = $groupName
            IsChecked = ($item -eq $defaultItem)
            Margin    = if ($Orientation -eq 'Horizontal') {
                [System.Windows.Thickness]::new(0, 2, 12, 2)
            } else {
                [System.Windows.Thickness]::new(0, 2, 0, 2)
            }
            Tag       = $item  # Store the value in Tag for easy retrieval
        }

        Set-RadioButtonStyle -RadioButton $radio

        $radioButtons[$item] = $radio
        [void]$radioPanel.Children.Add($radio)
    }

    [void]$outerStack.Children.Add($radioPanel)

    # Tag wrapper for FormLayout unwrapping in New-UiGrid
    Set-UiFormControlTag -Wrapper $outerStack -Label $labelBlock -Control $radioPanel

    # FullWidth in WrapPanel contexts
    Set-FullWidthConstraint -Control $outerStack -Parent $parent -FullWidth:$FullWidth

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $outerStack -Properties $WPFProperties
    }

    Write-Debug "Adding to parent and registering as '$Variable'"
    [void]$parent.Children.Add($outerStack)

    # Store the panel and mark it so hydration knows how to extract the value
    $radioPanel.Tag = @{
        ControlType = 'RadioGroup'
        GroupName   = $groupName
    }

    # Register control with session using AddControlSafe for thread-safe access
    $session.AddControlSafe($Variable, $radioPanel)

    if ($EnabledWhen) {
        Register-UiCondition -TargetControl $radioPanel -Condition $EnabledWhen -ClearIfDisabled:$ClearIfDisabled
    }
}
