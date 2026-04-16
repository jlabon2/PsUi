function New-FilterBoxWithClear {
    <#
    .SYNOPSIS
        Creates a filter/search text box with an integrated clear button.
    #>
    [CmdletBinding()]
    param(
        [int]$Width = 200,

        [int]$Height = 28,

        [switch]$IncludeIcon,

        [hashtable]$AdditionalTagData
    )

    $colors = Get-ThemeColors
    $result = @{}

    if ($IncludeIcon) {
        $result.Icon = [System.Windows.Controls.TextBlock]@{
            Text              = [PsUi.ModuleContext]::GetIcon('Search')
            FontFamily        = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            FontSize          = 14
            VerticalAlignment = 'Center'
            Foreground        = ConvertTo-UiBrush $colors.ControlFg
            Margin            = [System.Windows.Thickness]::new(0, 0, 6, 0)
        }
    }

    $container = [System.Windows.Controls.Grid]@{
        Width             = $Width
        Height            = $Height
        VerticalAlignment = 'Center'
    }

    $textBox = [System.Windows.Controls.TextBox]@{
        Height                   = $Height
        VerticalAlignment        = 'Center'
        VerticalContentAlignment = 'Center'
        Padding                  = [System.Windows.Thickness]::new(2, 0, 20, 0)
    }
    Set-TextBoxStyle -TextBox $textBox
    [void]$container.Children.Add($textBox)

    $watermark = [System.Windows.Controls.TextBlock]@{
        Text                = 'Filter...'
        FontStyle           = 'Italic'
        Foreground          = ConvertTo-UiBrush $colors.SecondaryText
        VerticalAlignment   = 'Center'
        HorizontalAlignment = 'Left'
        Margin              = [System.Windows.Thickness]::new(6, 0, 0, 0)
        IsHitTestVisible    = $false
    }
    [void]$container.Children.Add($watermark)

    $clearBtn = [System.Windows.Controls.Button]@{
        Content             = [PsUi.ModuleContext]::GetIcon('Cancel')
        FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize            = 10
        Width               = 16
        Height              = 16
        Padding             = [System.Windows.Thickness]::new(0)
        Margin              = [System.Windows.Thickness]::new(0, 0, 6, 0)
        HorizontalAlignment = 'Right'
        VerticalAlignment   = 'Center'
        Background          = [System.Windows.Media.Brushes]::Transparent
        BorderThickness     = [System.Windows.Thickness]::new(0)
        Foreground          = ConvertTo-UiBrush $colors.SecondaryText
        Cursor              = [System.Windows.Input.Cursors]::Hand
        Visibility          = 'Collapsed'
        ToolTip             = 'Clear'
    }
    $clearBtn.Tag = $textBox
    $clearBtn.Add_Click({
        param($sender, $eventArgs)
        $sender.Tag.Text = ''
        $sender.Tag.Focus()
    }.GetNewClosure())
    [void]$container.Children.Add($clearBtn)

    $tagData = @{ ClearButton = $clearBtn; Watermark = $watermark }
    if ($AdditionalTagData) {
        foreach ($key in $AdditionalTagData.Keys) {
            $tagData[$key] = $AdditionalTagData[$key]
        }
    }
    $textBox.Tag = $tagData

    $textBox.Add_TextChanged({
        $tagData = $this.Tag
        $isEmpty = [string]::IsNullOrEmpty($this.Text)
        if ($tagData.ClearButton) {
            $tagData.ClearButton.Visibility = if ($isEmpty) { 'Collapsed' } else { 'Visible' }
        }
        if ($tagData.Watermark) {
            $tagData.Watermark.Visibility = if ($isEmpty) { 'Visible' } else { 'Collapsed' }
        }
    }.GetNewClosure())

    $result.Container = $container
    $result.TextBox   = $textBox
    $result.ClearBtn  = $clearBtn
    $result.Watermark = $watermark

    return $result
}
