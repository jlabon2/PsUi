function Get-UiDataGridCheckBoxStyle {
    <#
    .SYNOPSIS
        Themed CheckBox style for DataGrid bool cells, centred in the cell.
    #>
    [CmdletBinding()]
    param()

    $iconFontName = [PsUi.ModuleContext]::ActiveIconFontName

    if ($null -eq $script:_CheckBoxStyleCache) { $script:_CheckBoxStyleCache = @{} }
    if ($script:_CheckBoxStyleCache.ContainsKey($iconFontName)) { return $script:_CheckBoxStyleCache[$iconFontName] }

    $xaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="CheckBox">
    <Border x:Name="checkBoxBorder"
            Width="18"
            Height="18"
            Background="{DynamicResource ControlBackgroundBrush}"
            BorderBrush="{DynamicResource BorderBrush}"
            BorderThickness="1.5"
            CornerRadius="3"
            HorizontalAlignment="Center"
            VerticalAlignment="Center">
        <Grid>
            <TextBlock x:Name="checkMark"
                       Text="&#xE73E;"
                       FontFamily="$iconFontName"
                       FontSize="9"
                       Margin="-2,0,0,0"
                       Foreground="{DynamicResource AccentBrush}"
                       HorizontalAlignment="Center"
                       VerticalAlignment="Center"
                       Visibility="Collapsed"/>
            <Border x:Name="indeterminateMark"
                    Width="8"
                    Height="8"
                    Background="{DynamicResource AccentBrush}"
                    CornerRadius="1"
                    HorizontalAlignment="Center"
                    VerticalAlignment="Center"
                    Visibility="Collapsed"/>
        </Grid>
    </Border>

    <ControlTemplate.Triggers>
        <Trigger Property="IsChecked" Value="True">
            <Setter TargetName="checkMark" Property="Visibility" Value="Visible"/>
            <Setter TargetName="checkBoxBorder" Property="Background" Value="{DynamicResource AccentBrush}"/>
            <Setter TargetName="checkBoxBorder" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
            <Setter TargetName="checkMark" Property="Foreground" Value="{DynamicResource AccentHeaderForegroundBrush}"/>
        </Trigger>
        <Trigger Property="IsChecked" Value="False">
            <Setter TargetName="checkMark" Property="Visibility" Value="Collapsed"/>
            <Setter TargetName="checkBoxBorder" Property="Background" Value="{DynamicResource ControlBackgroundBrush}"/>
            <Setter TargetName="checkBoxBorder" Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
        </Trigger>
        <Trigger Property="IsChecked" Value="{x:Null}">
            <Setter TargetName="checkMark" Property="Visibility" Value="Collapsed"/>
            <Setter TargetName="indeterminateMark" Property="Visibility" Value="Visible"/>
        </Trigger>

        <DataTrigger Binding="{Binding RelativeSource={RelativeSource AncestorType={x:Type DataGridRow}, AncestorLevel=1}, Path=IsSelected, FallbackValue=False}" Value="True">
            <Setter TargetName="checkBoxBorder" Property="BorderBrush" Value="{DynamicResource SelectionTextBrush}"/>
        </DataTrigger>
        <MultiDataTrigger>
            <MultiDataTrigger.Conditions>
                <Condition Binding="{Binding RelativeSource={RelativeSource AncestorType={x:Type DataGridRow}, AncestorLevel=1}, Path=IsSelected, FallbackValue=False}" Value="True"/>
                <Condition Binding="{Binding RelativeSource={RelativeSource Self}, Path=IsChecked}" Value="True"/>
            </MultiDataTrigger.Conditions>
            <Setter TargetName="checkBoxBorder" Property="Background" Value="{DynamicResource SelectionTextBrush}"/>
            <Setter TargetName="checkMark" Property="Foreground" Value="{DynamicResource AccentBrush}"/>
        </MultiDataTrigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@

    $template = [System.Windows.Markup.XamlReader]::Parse($xaml)

    $style = [System.Windows.Style]::new([System.Windows.Controls.CheckBox])
    [void]$style.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.CheckBox]::TemplateProperty, $template))
    [void]$style.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.CheckBox]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center))
    [void]$style.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.CheckBox]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center))
    [void]$style.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.CheckBox]::FontFamilyProperty, [System.Windows.Media.FontFamily]::new('Segoe UI')))
    [void]$style.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.CheckBox]::FontSizeProperty, [double]12))
    [void]$style.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.CheckBox]::CursorProperty, [System.Windows.Input.Cursors]::Hand))

    $script:_CheckBoxStyleCache[$iconFontName] = $style
    return $style
}
