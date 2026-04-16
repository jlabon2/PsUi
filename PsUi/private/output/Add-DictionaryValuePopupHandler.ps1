function Add-DictionaryValuePopupHandler {
    <#
    .SYNOPSIS
        Adds click handler to DataGrid for expanding nested hashtable/array values in a popup.
        Shows items in a scrollable popup instead of the raw object string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$DataGrid
    )

    # Click handler for expanding values - checks Tag for complex types
    $DataGrid.Add_PreviewMouseLeftButtonDown({
        param($sender, $eventArgs)

        if ($script:currentDictPopup -and $script:currentDictPopup.IsOpen) {
            $script:currentDictPopup.IsOpen = $false
            $script:currentDictPopup = $null
        }

        # Only TextBlocks with complex values in their Tag get popups
        $source = $eventArgs.OriginalSource
        if ($source -isnot [System.Windows.Controls.TextBlock]) { return }

        $textBlock = $source
        $rawValue  = $textBlock.Tag
        if ($null -eq $rawValue) { return }

        # Only show popup for complex types
        $isExpandable = ($rawValue -is [System.Collections.IDictionary]) -or
                        ($rawValue -is [array] -and $rawValue.Count -gt 0)
        if (!$isExpandable) { return }

        $popupColors = Get-ThemeColors

        # Build popup at mouse position with offset so mouse is inside
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
            MaxWidth        = 450
            MaxHeight       = 350
        }

        # Close popup when mouse leaves
        $popupBorder.Add_MouseLeave({
            param($sender, $eventArgs)
            if ($script:currentDictPopup) {
                $script:currentDictPopup.IsOpen = $false
                $script:currentDictPopup = $null
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

        # Header showing type info
        $header = [System.Windows.Controls.TextBlock]@{
            FontWeight = 'SemiBold'
            Margin     = [System.Windows.Thickness]::new(0, 0, 0, 8)
            Foreground = ConvertTo-UiBrush $popupColors.ControlFg
        }

        if ($rawValue -is [System.Collections.IDictionary]) {
            $keyCount    = $rawValue.get_Count()
            $header.Text = "Hashtable ($keyCount keys):"
            [void]$stackPanel.Children.Add($header)

            # Render each key-value pair - format values based on type
            foreach ($key in $rawValue.Keys) {
                $val = $rawValue[$key]
                $displayVal = switch ($val) {
                    { $_ -is [System.Collections.IDictionary] } { "@{...} ($($_.get_Count()) keys)" }
                    { $_ -is [array] }  { "[$($_.Count) items]" }
                    { $_ -is [bool] }   { "`$$_" }
                    { $_ -is [string] } { "'$_'" }
                    default { "$_" }
                }

                $kvPanel = [System.Windows.Controls.StackPanel]@{
                    Orientation = 'Horizontal'
                    Margin      = [System.Windows.Thickness]::new(0, 2, 0, 2)
                }

                $keyText = [System.Windows.Controls.TextBlock]@{
                    Text       = "$key = "
                    FontWeight = 'SemiBold'
                    Foreground = ConvertTo-UiBrush $popupColors.ControlFg
                }
                [void]$kvPanel.Children.Add($keyText)

                $valText = [System.Windows.Controls.TextBlock]@{
                    Text        = $displayVal
                    TextWrapping = 'Wrap'
                    Foreground  = ConvertTo-UiBrush $popupColors.SecondaryText
                }
                [void]$kvPanel.Children.Add($valText)
                [void]$stackPanel.Children.Add($kvPanel)
            }
        }
        elseif ($rawValue -is [array]) {
            $header.Text = "Array ($($rawValue.Count) items):"
            [void]$stackPanel.Children.Add($header)

            foreach ($item2 in $rawValue) {
                $itemText = [System.Windows.Controls.TextBlock]@{
                    Text        = if ($null -eq $item2) { '(null)' } else { $item2.ToString() }
                    TextWrapping = 'Wrap'
                    Margin      = [System.Windows.Thickness]::new(0, 2, 0, 2)
                    Foreground  = ConvertTo-UiBrush $popupColors.ControlFg
                }
                [void]$stackPanel.Children.Add($itemText)
            }
        }

        $scrollViewer.Content = $stackPanel
        $popupBorder.Child    = $scrollViewer
        $popup.Child          = $popupBorder

        $script:currentDictPopup = $popup
        $popup.IsOpen            = $true
    }.GetNewClosure())

    # Close popup when clicking elsewhere
    $DataGrid.Add_PreviewMouseRightButtonDown({
        if ($script:currentDictPopup -and $script:currentDictPopup.IsOpen) {
            $script:currentDictPopup.IsOpen = $false
            $script:currentDictPopup = $null
        }
    })
}
