<#
.SYNOPSIS
    Styles a RadioButton with accent selection indicator.
#>
function Set-RadioButtonStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.RadioButton]$RadioButton
    )

    # Set basic non-color properties only
    $RadioButton.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
    $RadioButton.FontSize = 12
    $RadioButton.VerticalContentAlignment = 'Center'
    $RadioButton.Cursor = [System.Windows.Input.Cursors]::Hand

    $xaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="RadioButton">
    <Grid Background="Transparent">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="20"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border x:Name="radioBorder"
                Grid.Column="0"
                Width="18"
                Height="18"
                Background="{DynamicResource ControlBackgroundBrush}"
                BorderBrush="{DynamicResource BorderBrush}"
                BorderThickness="1"
                CornerRadius="9">
            <Ellipse x:Name="radioMark"
                     Width="8"
                     Height="8"
                     Fill="{DynamicResource AccentBrush}"
                     Opacity="0"
                     HorizontalAlignment="Center"
                     VerticalAlignment="Center"/>
        </Border>

        <ContentPresenter Grid.Column="1"
                          Margin="6,0,0,0"
                          VerticalAlignment="Center"
                          HorizontalAlignment="Left"
                          RecognizesAccessKey="True"
                          TextBlock.Foreground="{DynamicResource ControlForegroundBrush}"/>
    </Grid>
    <ControlTemplate.Triggers>
        <Trigger Property="IsChecked" Value="True">
            <Setter TargetName="radioMark" Property="Opacity" Value="1"/>
            <Setter TargetName="radioBorder" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
        </Trigger>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="radioBorder" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter Property="Opacity" Value="0.5"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@

    $stringReader = $null
    $xmlReader    = $null
    try {
        $stringReader = [System.IO.StringReader]::new($xaml)
        $xmlReader    = [System.Xml.XmlReader]::Create($stringReader)
        $template     = [System.Windows.Markup.XamlReader]::Load($xmlReader)
        $RadioButton.Template = $template
        
        # Clear local values so DynamicResource in template works
        $RadioButton.ClearValue([System.Windows.Controls.Control]::ForegroundProperty)
        $RadioButton.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
        $RadioButton.ClearValue([System.Windows.Controls.Control]::BorderBrushProperty)
    }
    catch {
        Write-Verbose "Failed to apply custom RadioButton template: $_"
    }
    finally {
        if ($xmlReader)    { $xmlReader.Dispose() }
        if ($stringReader) { $stringReader.Dispose() }
    }

    try {
        [PsUi.ThemeEngine]::RegisterElement($RadioButton)
    }
    catch {
        Write-Verbose "Failed to register RadioButton with ThemeEngine: $_"
    }
}
