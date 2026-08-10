<#
.SYNOPSIS
    Styles a CheckBox with accent-colored checkmark.
#>
function Set-CheckBoxStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.CheckBox]$CheckBox
    )

    # Set basic non-color properties only
    $CheckBox.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
    $CheckBox.FontSize = 12
    $CheckBox.VerticalContentAlignment = 'Center'
    $CheckBox.Cursor = [System.Windows.Input.Cursors]::Hand

    # Substitute the active icon font into the XAML template
    $iconFontName = [PsUi.ModuleContext]::ActiveIconFontName

    $xaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="CheckBox">
    <Grid Background="Transparent">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="20"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border x:Name="checkBoxBorder"
                Grid.Column="0"
                Width="18"
                Height="18"
                Background="{DynamicResource ControlBackgroundBrush}"
                BorderBrush="{DynamicResource BorderBrush}"
                BorderThickness="1.5"
                CornerRadius="3"
                VerticalAlignment="Center"
                HorizontalAlignment="Center">
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

        <ContentPresenter Grid.Column="1"
                          Margin="6,2,0,0"
                          VerticalAlignment="Center"
                          HorizontalAlignment="Left"
                          RecognizesAccessKey="True"
                          TextElement.Foreground="{TemplateBinding Foreground}"/>
    </Grid>

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

        <!-- Inside a selected DataGridRow the accent selection brush matches the checked fill -
             swap to SelectionTextBrush so the box stays visible against the row highlight. -->
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

    try {
        # Re-parse if icon font changed since last cache
        if (!$script:_checkBoxTemplate -or $script:_checkBoxTemplateFontName -ne $iconFontName) {
            $script:_checkBoxTemplate = [System.Windows.Markup.XamlReader]::Parse($xaml)
            $script:_checkBoxTemplateFontName = $iconFontName
        }
        $CheckBox.Template = $script:_checkBoxTemplate
        
        # Clear local values so DynamicResource in template works
        $CheckBox.ClearValue([System.Windows.Controls.Control]::ForegroundProperty)
        $CheckBox.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
        $CheckBox.ClearValue([System.Windows.Controls.Control]::BorderBrushProperty)
    }
    catch {
        Write-Verbose "Failed to parse checkbox template XAML: $($_.Exception.Message)"
    }

    try {
        [PsUi.ThemeEngine]::RegisterElement($CheckBox)
    }
    catch {
        Write-Verbose "Failed to register CheckBox with ThemeEngine: $_"
    }
}
