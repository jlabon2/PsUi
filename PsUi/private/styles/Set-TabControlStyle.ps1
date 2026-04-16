<#
.SYNOPSIS
    Applies themed styling to a TabControl with fixed tab row positions.
#>
function Set-TabControlStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.TabControl]$TabControl
    )

    # Custom TabControl template that uses WrapPanel instead of TabPanel
    # WrapPanel doesn't reorder rows when a tab is selected
    # Uses DynamicResource for theme-aware colors
    $xaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="TabControl">
    <Grid KeyboardNavigation.TabNavigation="Local">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Tab header area using WrapPanel for stable row positions -->
        <Border Grid.Row="0"
                BorderBrush="{DynamicResource BorderBrush}"
                BorderThickness="0,0,0,1"
                Background="Transparent">
            <WrapPanel x:Name="HeaderPanel"
                       IsItemsHost="True"
                       HorizontalAlignment="Left"
                       Margin="8,0,0,0"
                       KeyboardNavigation.TabIndex="1"/>
        </Border>

        <!-- Content area -->
        <Border x:Name="ContentPanel"
                Grid.Row="1"
                Background="{DynamicResource WindowBackgroundBrush}"
                BorderBrush="{DynamicResource BorderBrush}"
                BorderThickness="0"
                KeyboardNavigation.TabNavigation="Local"
                KeyboardNavigation.DirectionalNavigation="Contained"
                KeyboardNavigation.TabIndex="2">
            <ContentPresenter x:Name="PART_SelectedContentHost"
                              ContentSource="SelectedContent"
                              Margin="0"/>
        </Border>
    </Grid>
</ControlTemplate>
"@

    try {
        $TabControl.Template = [System.Windows.Markup.XamlReader]::Parse($xaml)
    }
    catch {
        Write-Verbose "Failed to apply TabControl template: $_"
    }
}
