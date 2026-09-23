function New-UiLoadingSpinner {
    <#
    .SYNOPSIS
        Spinning animation for loading states, handed back as its host Grid so Visibility drives it.
    #>
    [CmdletBinding()]
    [OutputType([System.Windows.Controls.Grid])]
    param(
        [int]$Size = 16,

        [string]$Color = '#FFFFFF',

        # Takes a theme key instead of a fixed color, for a spinner that lives past a theme switch.
        [string]$BrushKey
    )

    $thickness = [Math]::Max(1.5, $Size / 8)
    $centre    = $Size / 2
    $brush     = ConvertTo-UiBrush $Color
    $stroke    = [System.Windows.Shapes.Shape]::StrokeProperty

    # Inset by half a stroke or the host clips the fat end of the spiral
    $radius = ($Size - $thickness) / 2

    # The slices depend only on Size, and a button builds a spinner on every click, so they get cut once per size
    if (!$script:_spinnerSlices) { $script:_spinnerSlices = @{} }
    if ($script:_spinnerSlices.Count -ge 8) { $script:_spinnerSlices.Clear() }
    if (!$script:_spinnerSlices.ContainsKey($Size)) {
        $cut    = [System.Collections.Generic.List[object]]::new()
        $slices = 48
        $step   = 265 / $slices

        # WPF has no gradient for conic, so the fade is slices stepping down in opacity and width, each running 0.6 degrees into the next because antialiasing opens a hairline at every join.
        # The fade is squared off, or the far tail stays bright enough to close the ring up again.
        for ($i = 0; $i -lt $slices; $i++) {
            $fromRad = (($i * $step) - 90) * [Math]::PI / 180
            $toRad   = (($i * $step) + $step + 0.6 - 90) * [Math]::PI / 180

            $figure = [System.Windows.Media.PathFigure]::new()
            $figure.StartPoint = [System.Windows.Point]::new(
                $centre + $radius * [Math]::Cos($fromRad),
                $centre + $radius * [Math]::Sin($fromRad))

            $arc = [System.Windows.Media.ArcSegment]::new()
            $arc.Point          = [System.Windows.Point]::new(
                $centre + $radius * [Math]::Cos($toRad),
                $centre + $radius * [Math]::Sin($toRad))
            $arc.Size           = [System.Windows.Size]::new($radius, $radius)
            $arc.SweepDirection = [System.Windows.Media.SweepDirection]::Clockwise
            $arc.IsLargeArc     = ($step + 0.6) -gt 180
            [void]$figure.Segments.Add($arc)

            $geometry = [System.Windows.Media.PathGeometry]::new()
            [void]$geometry.Figures.Add($figure)
            $geometry.Freeze()

            $toward = ($i + 1) / $slices
            $cut.Add([pscustomobject]@{
                Geometry = $geometry
                Width    = $thickness * (0.45 + 0.55 * $toward)
                Fade     = [Math]::Pow($toward, 1.7)
                IsHead   = $i -eq ($slices - 1)
            })
        }
        $script:_spinnerSlices[$Size] = $cut
    }

    # The fixed ring behind the comet gives the eye something still to track the motion against. Flat caps on the slices so they butt together without a bump, and only the head is round.
    $track = [System.Windows.Shapes.Ellipse]@{
        Width               = $radius * 2
        Height              = $radius * 2
        StrokeThickness     = $thickness * 0.5
        Opacity             = 0.1
        HorizontalAlignment = 'Center'
        VerticalAlignment   = 'Center'
    }
    if ($BrushKey) { $track.SetResourceReference($stroke, $BrushKey) } else { $track.Stroke = $brush }

    # Canvas, so the arcs keep the coordinates they were built in, where a Grid would recenter each one on its own bounds.
    $rotor = [System.Windows.Controls.Canvas]@{ Width = $Size; Height = $Size }
    $rotor.CacheMode = [System.Windows.Media.BitmapCache]@{ RenderAtScale = 3 }

    foreach ($slice in $script:_spinnerSlices[$Size]) {
        $endCap = if ($slice.IsHead) { [System.Windows.Media.PenLineCap]::Round } else { [System.Windows.Media.PenLineCap]::Flat }
        $path   = [System.Windows.Shapes.Path]@{
            Data             = $slice.Geometry
            StrokeThickness  = $slice.Width
            StrokeEndLineCap = $endCap
            Opacity          = $slice.Fade
        }
        if ($BrushKey) { $path.SetResourceReference($stroke, $BrushKey) } else { $path.Stroke = $brush }
        [void]$rotor.Children.Add($path)
    }

    # CenterX and CenterY, as RenderTransformOrigin is a fraction of whatever size layout decides on and the comet wobbles when that isn't square
    $spin         = [System.Windows.Media.RotateTransform]::new()
    $spin.CenterX = $centre
    $spin.CenterY = $centre
    $rotor.RenderTransform = $spin

    $animation = [System.Windows.Media.Animation.DoubleAnimation]@{
        From           = 0
        To             = 360
        Duration       = [System.Windows.Duration]::new([TimeSpan]::FromSeconds(1.1))
        RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    }
    [System.Windows.Media.Animation.Timeline]::SetDesiredFrameRate($animation, 60)
    $spin.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $animation)

    $spinner = [System.Windows.Controls.Grid]@{
        Width               = $Size
        Height              = $Size
        HorizontalAlignment = 'Center'
        VerticalAlignment   = 'Center'
    }
    [void]$spinner.Children.Add($track)
    [void]$spinner.Children.Add($rotor)

    return $spinner
}
