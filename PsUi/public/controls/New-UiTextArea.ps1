function New-UiTextArea {
    <#
    .SYNOPSIS
        Creates a multi-line text input control.
    .DESCRIPTION
        Creates a TextBox configured for multi-line text entry with optional scrollbars.
        Ideal for longer text content like descriptions, notes, or code.
    .PARAMETER Label
        Label text displayed above the text area.
    .PARAMETER Variable
        Variable name to store the text value.
    .PARAMETER Default
        Initial text content.
    .PARAMETER Rows
        Number of visible text rows (controls height). Default is 4.
    .PARAMETER Placeholder
        Placeholder/watermark text shown when the text area is empty.
    .PARAMETER Required
        Mark the field as required with an asterisk.
    .PARAMETER MaxLength
        Maximum number of characters allowed.
    .PARAMETER FullWidth
        Stretches the control to fill available width instead of fixed sizing.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
    .EXAMPLE
        New-UiTextArea -Label "Description" -Variable "description" -Rows 5 -Placeholder "Enter a detailed description..."
    .EXAMPLE
        New-UiTextArea -Label "Notes" -Variable "notes" -Default "Initial notes here..." -Required
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$Variable,

        [string]$Default,

        [int]$Rows = 4,

        [string]$Placeholder,

        [switch]$Required,

        [int]$MaxLength,

        [switch]$FullWidth,

        [Parameter()]
        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiTextArea'
    Write-Debug "Creating text area '$Variable' (Rows=$Rows)"
    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent

    $stack = [System.Windows.Controls.StackPanel]@{
        Margin = [System.Windows.Thickness]::new(4, 4, 4, 8)
    }

    $labelText  = if ($Required) { "$Label *" } else { $Label }
    $labelBlock = [System.Windows.Controls.TextBlock]@{
        Text       = $labelText
        FontSize   = 12
        Foreground = ConvertTo-UiBrush $colors.ControlFg
        Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
        Tag        = 'ControlFgBrush'
    }
    [PsUi.ThemeEngine]::RegisterElement($labelBlock)
    [void]$stack.Children.Add($labelBlock)

    # Calculate height based on rows (approximate line height of 20px)
    $lineHeight = 20
    $padding = 8
    $calculatedHeight = ($Rows * $lineHeight) + $padding

    $textArea = [System.Windows.Controls.TextBox]@{
        AcceptsReturn     = $true
        AcceptsTab        = $true
        TextWrapping      = [System.Windows.TextWrapping]::Wrap
        VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
        HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Disabled
        MinHeight         = $calculatedHeight
        Height            = $calculatedHeight
        VerticalContentAlignment = [System.Windows.VerticalAlignment]::Top
        Padding           = [System.Windows.Thickness]::new(2, 2, 2, 0)
    }

    if ($Default) {
        $textArea.Text = $Default
    }

    if ($MaxLength -gt 0) {
        $textArea.MaxLength = $MaxLength
    }

    Set-TextBoxStyle -TextBox $textArea

    # Placeholder overlay (same pattern as New-UiInput)
    if ($Placeholder) {
        $grid = [System.Windows.Controls.Grid]::new()

        $placeholderBlock = [System.Windows.Controls.TextBlock]@{
            Text              = $Placeholder
            FontSize          = 12
            Foreground        = ConvertTo-UiBrush $colors.SecondaryText
            FontStyle         = [System.Windows.FontStyles]::Italic
            IsHitTestVisible  = $false
            Margin            = [System.Windows.Thickness]::new(6, 4, 0, 0)
            VerticalAlignment = [System.Windows.VerticalAlignment]::Top
        }

        if ([string]::IsNullOrEmpty($textArea.Text)) {
            $placeholderBlock.Visibility = 'Visible'
        }
        else {
            $placeholderBlock.Visibility = 'Collapsed'
        }

        # Update visibility on text change
        $textArea.Add_TextChanged({
            param($sender, $eventArgs)
            if ([string]::IsNullOrEmpty($sender.Text)) {
                $placeholderBlock.Visibility = 'Visible'
            }
            else {
                $placeholderBlock.Visibility = 'Collapsed'
            }
        }.GetNewClosure())

        [void]$grid.Children.Add($textArea)
        [void]$grid.Children.Add($placeholderBlock)
        [void]$stack.Children.Add($grid)
        $controlElement = $grid
    }
    else {
        [void]$stack.Children.Add($textArea)
        $controlElement = $textArea
    }

    # Tag wrapper for FormLayout unwrapping in New-UiGrid
    Set-UiFormControlTag -Wrapper $stack -Label $labelBlock -Control $controlElement

    # FullWidth in WrapPanel contexts
    Set-FullWidthConstraint -Control $stack -Parent $parent -FullWidth:$FullWidth

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $stack -Properties $WPFProperties
    }

    Write-Debug "Adding to parent and registering as '$Variable'"
    [void]$parent.Children.Add($stack)

    # Register control with session using AddControlSafe for thread-safe access
    $session.AddControlSafe($Variable, $textArea)
}
