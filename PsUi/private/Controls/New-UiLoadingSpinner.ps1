function New-UiLoadingSpinner {
    <#
    .SYNOPSIS
        Creates a spinning circle animation for loading states.
    #>
    [CmdletBinding()]
    param(
        [int]$Size = 16,
        [string]$Color = '#FFFFFF'
    )
    
    # Oroginally used a MDL2 glyph for spinner, but not all Win10 versions have the glyph
    # Use drawn arc instead of font glyph for universal Windows 10 compatibility - doesn't look ad good, but works
    $spinner = [System.Windows.Shapes.Path]@{
        Stroke                = ConvertTo-UiBrush $Color
        StrokeThickness       = [Math]::Max(1.5, $Size / 8)
        Width                 = $Size
        Height                = $Size
        HorizontalAlignment   = 'Center'
        VerticalAlignment     = 'Center'
        RenderTransformOrigin = '0.5,0.5'
    }
    
    # Create arc geometry (3/4 circle)
    $radius    = $Size / 2
    $geometry  = [System.Windows.Media.PathGeometry]::new()
    $figure    = [System.Windows.Media.PathFigure]::new()
    $figure.StartPoint = [System.Windows.Point]::new($radius, 0)
    $arc       = [System.Windows.Media.ArcSegment]::new()
    $arc.Point = [System.Windows.Point]::new($radius, $Size)
    $arc.Size  = [System.Windows.Size]::new($radius, $radius)
    $arc.SweepDirection = [System.Windows.Media.SweepDirection]::Clockwise
    $arc.IsLargeArc = $true
    [void]$figure.Segments.Add($arc)
    [void]$geometry.Figures.Add($figure)
    $spinner.Data = $geometry
    
    $rotateTransform = [System.Windows.Media.RotateTransform]::new()
    $spinner.RenderTransform = $rotateTransform
    
    $animation = [System.Windows.Media.Animation.DoubleAnimation]@{
        From           = 0
        To             = 360
        Duration       = [System.Windows.Duration]::new([TimeSpan]::FromSeconds(1.2))
        RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    }
    
    $rotateTransform.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $animation)
    
    return $spinner
}