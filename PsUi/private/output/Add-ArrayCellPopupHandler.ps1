function Add-ArrayCellPopupHandler {
    <#
    .SYNOPSIS
        Adds click handler to DataGrid for expanding array cells in a popup.
        Shows items in a scrollable list instead of the raw type string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid
    )

    $DataGrid.Add_PreviewMouseLeftButtonDown({
        param($sender, $eventArgs)

        if ($script:currentArrayPopup -and $script:currentArrayPopup.IsOpen) {
            $script:currentArrayPopup.IsOpen = $false
            $script:currentArrayPopup = $null
        }

        # Only italic TextBlocks with array data in Tag get popups
        $source = $eventArgs.OriginalSource
        if ($source -isnot [System.Windows.Controls.TextBlock]) { return }

        $textBlock = $source
        if ($textBlock.FontStyle -ne [System.Windows.FontStyles]::Italic) { return }
        if ($null -eq $textBlock.Tag) { return }

        $arrayValue = $textBlock.Tag
        if ($arrayValue -is [string]) { return }

        $popupColors = Get-ThemeColors

        $popup = [System.Windows.Controls.Primitives.Popup]@{
            StaysOpen         = $false
            AllowsTransparency = $true
            Placement         = 'Mouse'
            VerticalOffset    = -20
            HorizontalOffset  = -10
        }

        $popupBorder = [System.Windows.Controls.Border]@{
            Background      = ConvertTo-UiBrush $popupColors.ControlBg
            BorderBrush     = ConvertTo-UiBrush $popupColors.Border
            BorderThickness = [System.Windows.Thickness]::new(1)
            CornerRadius    = [System.Windows.CornerRadius]::new(4)
            Padding         = [System.Windows.Thickness]::new(12)
            MaxWidth        = 400
            MaxHeight       = 300
        }

        # Close popup when mouse leaves
        $popupBorder.Add_MouseLeave({
            param($sender, $eventArgs)
            if ($script:currentArrayPopup) {
                $script:currentArrayPopup.IsOpen = $false
                $script:currentArrayPopup = $null
            }
        })

        $shadow = [System.Windows.Media.Effects.DropShadowEffect]@{
            BlurRadius  = 10
            ShadowDepth = 3
            Opacity     = 0.3
        }
        $popupBorder.Effect = $shadow

        $scrollViewer = [System.Windows.Controls.ScrollViewer]@{
            VerticalScrollBarVisibility   = 'Auto'
            HorizontalScrollBarVisibility = 'Auto'
        }

        $stackPanel = [System.Windows.Controls.StackPanel]::new()

        $header = [System.Windows.Controls.TextBlock]@{
            FontWeight = 'SemiBold'
            Margin     = [System.Windows.Thickness]::new(0, 0, 0, 8)
            Foreground = ConvertTo-UiBrush $popupColors.ControlFg
        }

        $items       = @($arrayValue)
        $header.Text = "$($items.Count) item(s):"
        [void]$stackPanel.Children.Add($header)

        foreach ($item in $items) {
            $itemText = [System.Windows.Controls.TextBlock]@{
                Text        = if ($null -eq $item) { '(null)' } else { $item.ToString() }
                TextWrapping = 'Wrap'
                Margin      = [System.Windows.Thickness]::new(0, 2, 0, 2)
                Foreground  = ConvertTo-UiBrush $popupColors.ControlFg
            }
            [void]$stackPanel.Children.Add($itemText)
        }

        $scrollViewer.Content = $stackPanel
        $popupBorder.Child    = $scrollViewer
        $popup.Child          = $popupBorder

        $script:currentArrayPopup = $popup
        $popup.IsOpen             = $true
    }.GetNewClosure())
}
