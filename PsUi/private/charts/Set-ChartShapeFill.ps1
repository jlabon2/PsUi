function Set-ChartShapeFill {
    <#
    .SYNOPSIS
        Applies fill to a shape using resource binding when available.
    #>
    param($Shape, $PaletteEntry)

    if ($PaletteEntry.ResourceKey) {
        # Use resource binding for dynamic theme updates
        $Shape.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $PaletteEntry.ResourceKey)
    }
    else {
        # Fallback to static color
        $Shape.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFrom($PaletteEntry.Fallback)
    }
}
