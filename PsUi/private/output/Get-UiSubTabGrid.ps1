function Get-UiSubTabGrid {
    <#
    .SYNOPSIS
        The DataGrid inside a results subtab. Null for a tab holding anything else.
    #>
    [CmdletBinding()]
    param(
        [object]$Tab
    )

    if (!$Tab) { return $null }

    # The empty overlay sets the grid inside a Panel. A text tab holds a RichTextBox (null here).
    $content = $Tab.Content
    if ($content -is [System.Windows.Controls.DataGrid]) { return $content }

    if ($content -is [System.Windows.Controls.Panel]) {
        foreach ($child in $content.Children) {
            if ($child -is [System.Windows.Controls.DataGrid]) { return $child }
        }
    }

    return $null
}
