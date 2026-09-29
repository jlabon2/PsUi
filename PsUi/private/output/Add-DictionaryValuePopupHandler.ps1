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

    # Opens the popup for a cell whose Tag holds a dictionary.
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

        # Arrays go to the array popup, so the two handlers never open over one cell.
        if ($rawValue -isnot [System.Collections.IDictionary]) { return }
        if (![PsUi.ValueKind]::IsExpandable($rawValue)) { return }

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
            HorizontalScrollBarVisibility = 'Disabled'
        }

        $stackPanel = [System.Windows.Controls.StackPanel]::new()

        $copyHeader = New-UiPopupCopyHeader -Colors $popupColors
        $headerRow  = $copyHeader.Panel
        $header     = $copyHeader.Title
        $copyState  = $copyHeader.State

        $copyLines = [System.Collections.Generic.List[string]]::new()

        $keyCount    = [PsUi.ValueKind]::Count($rawValue)
        $header.Text = if ($keyCount -eq 1) { '1 key:' } else { "$keyCount keys:" }
        [void]$stackPanel.Children.Add($headerRow)

        foreach ($entry in $rawValue.GetEnumerator()) {
            $key = $entry.Key
            $val = $entry.Value
            # Switch on the kind string, not the value, since switch enumerates a list value and runs its clauses per element.
            $displayVal = switch (Get-UiValueKind -Value $val) {
                'Null'       { '(null)' }
                'Bool'       { "`$$val" }
                'Text'       { "'$val'" }
                'Dictionary' { "@{...} ($([PsUi.ValueKind]::Count($val)) keys)" }
                'List'       { "[$([PsUi.ValueKind]::Count($val)) items]" }
                'Sequence'   { '[sequence]' }
                default      { [PsUi.ValueKind]::DisplayText($val) }
            }

            # In a horizontal StackPanel the value gets infinite width and never wraps, so the key docks left and the value takes the rest.
            $kvPanel = [System.Windows.Controls.DockPanel]@{
                Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)
            }

            $keyText = [System.Windows.Controls.TextBlock]@{
                Text              = "$key = "
                FontWeight        = 'SemiBold'
                VerticalAlignment = 'Top'
                Foreground        = ConvertTo-UiBrush $popupColors.ControlFg
            }
            [System.Windows.Controls.DockPanel]::SetDock($keyText, 'Left')
            [void]$kvPanel.Children.Add($keyText)

            $valText = [System.Windows.Controls.TextBlock]@{
                Text         = $displayVal
                TextWrapping = 'Wrap'
                Foreground   = ConvertTo-UiBrush $popupColors.SecondaryText
            }
            [void]$kvPanel.Children.Add($valText)
            [void]$stackPanel.Children.Add($kvPanel)
            $copyLines.Add("$key = $displayVal")
        }

        $copyState.Text = $copyLines -join [Environment]::NewLine

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
