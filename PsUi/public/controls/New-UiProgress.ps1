function New-UiProgress {
    <#
    .SYNOPSIS
        Creates a progress bar control.
    .PARAMETER Variable
        Variable name to reference the progress bar.
    .PARAMETER Height
        Bar height in pixels.
    .PARAMETER Indeterminate
        Displays an animated marquee bar instead of a percentage-based fill.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
        Allows setting any valid WPF property not explicitly exposed as a parameter.
        Invalid properties will generate warnings but not stop execution.
        Supports attached properties using dot notation (e.g., "Grid.Row").
    .EXAMPLE
        New-UiProgress -Variable 'progress' -Height 10
    .EXAMPLE
        New-UiProgress -Variable 'loading' -Indeterminate
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Variable,
        
        [int]$Height = 20,
        
        [switch]$Indeterminate,
        
        [Parameter()]
        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiProgress'
    $colors  = Get-ThemeColors
    $parent  = $session.CurrentParent
    Write-Debug "Variable='$Variable', Indeterminate=$($Indeterminate.IsPresent), Parent: $($parent.GetType().Name)"

    $progress = [System.Windows.Controls.ProgressBar]::new()
    $progress.Minimum = 0
    $progress.Maximum = 100
    $progress.Value = 0
    $progress.IsIndeterminate = $Indeterminate.IsPresent
    $progress.Margin = [System.Windows.Thickness]::new(4, 4, 4, 8)
    Set-ProgressBarStyle -ProgressBar $progress
    
    # Override height if explicitly specified (Set-ProgressBarStyle sets it to 6 by default)
    if ($PSBoundParameters.ContainsKey('Height')) {
        $progress.Height = $Height
    }

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $progress -Properties $WPFProperties
    }

    Write-Debug "Adding progress bar '$Variable' to parent"
    [void]$parent.Children.Add($progress)

    # Use Register-UiControlComplete for consistent control registration with hydration support
    Register-UiControlComplete -Name $Variable -Control $progress -InitialValue $progress.Value
}
