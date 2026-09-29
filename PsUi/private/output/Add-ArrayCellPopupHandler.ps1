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
        # Dictionaries have their own popup
        if ($arrayValue -is [string] -or $arrayValue -is [System.Collections.IDictionary]) { return }

        # Refuses a one pass reader without reading it, and an empty list, whose popup would be a header and a copy button over just an empty string
        if (![PsUi.ValueKind]::IsExpandable($arrayValue)) { return }

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

        # With Auto the panel measures at infinite width, and the TextWrapping on every line below never gets a width to wrap at
        $scrollViewer = [System.Windows.Controls.ScrollViewer]@{
            VerticalScrollBarVisibility   = 'Auto'
            HorizontalScrollBarVisibility = 'Disabled'
        }

        $stackPanel = [System.Windows.Controls.StackPanel]::new()

        $copyHeader = New-UiPopupCopyHeader -Colors $popupColors
        $headerRow  = $copyHeader.Panel
        $header     = $copyHeader.Title
        $copyState  = $copyHeader.State

        $items       = @($arrayValue)
        $header.Text = if ($items.Count -eq 1) { '1 item:' } else { "$($items.Count) items:" }
        [void]$stackPanel.Children.Add($headerRow)

        $copyLines = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $items) {
            # Each line reads the way a cell would show it, so a list of hashtables lists @{a=1} rather than a type name per line.
            $line = "$(ConvertTo-DisplayValue -Value $item)"
            $copyLines.Add($line)

            $itemText = [System.Windows.Controls.TextBlock]@{
                Text         = $line
                TextWrapping = 'Wrap'
                Margin       = [System.Windows.Thickness]::new(0, 2, 0, 2)
                Foreground   = ConvertTo-UiBrush $popupColors.ControlFg
            }
            [void]$stackPanel.Children.Add($itemText)
        }
        $copyState.Text = $copyLines -join [Environment]::NewLine

        $scrollViewer.Content = $stackPanel
        $popupBorder.Child    = $scrollViewer
        $popup.Child          = $popupBorder

        $script:currentArrayPopup = $popup
        $popup.IsOpen             = $true
    }.GetNewClosure())
}
