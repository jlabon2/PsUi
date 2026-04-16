function Get-ControlChildren {
    <#
    .SYNOPSIS
        Returns child elements to traverse for theme updates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Control
    )

    # Return children based on container type (layout containers only, not control internals)
    if ($Control -is [System.Windows.Controls.Panel]) {
        return @($Control.Children)
    }
    elseif ($Control -is [System.Windows.Controls.TabControl]) {
        # Return TabItems only
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Control.Items) {
            if ($item -is [System.Windows.Controls.TabItem]) {
                $items.Add($item)
            }
        }
        return $items
    }
    elseif ($Control -is [System.Windows.Controls.TabItem]) {
        if ($Control.Content -is [System.Windows.UIElement]) {
            return @($Control.Content)
        }
    }
    elseif ($Control -is [System.Windows.Controls.Border]) {
        if ($Control.Child -is [System.Windows.UIElement]) {
            return @($Control.Child)
        }
    }
    elseif ($Control -is [System.Windows.Controls.Decorator]) {
        if ($Control.Child -is [System.Windows.UIElement]) {
            return @($Control.Child)
        }
    }
    elseif ($Control -is [System.Windows.Controls.ScrollViewer]) {
        if ($Control.Content -is [System.Windows.UIElement]) {
            return @($Control.Content)
        }
    }
    elseif ($Control -is [System.Windows.Window]) {
        if ($Control.Content -is [System.Windows.UIElement]) {
            return @($Control.Content)
        }
    }
    elseif ($Control -is [System.Windows.Controls.GroupBox]) {
        if ($Control.Content -is [System.Windows.UIElement]) {
            return @($Control.Content)
        }
    }

    # Leaf controls (Button, Label, CheckBox, etc.) have no traversable children
    return @()
}
