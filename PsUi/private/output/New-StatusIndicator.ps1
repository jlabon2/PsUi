
function New-StatusIndicator {
    <#
    .SYNOPSIS
        Creates animated status indicator (spinner/checkmark/warning).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Colors
    )

    # Status indicator - small spinner that shows running/complete/warning states
    $statusIndicator = [System.Windows.Controls.Grid]@{
        Width             = 20
        Height            = 20
        Margin            = [System.Windows.Thickness]::new(0, 0, 8, 0)
        VerticalAlignment = 'Center'
        ToolTip           = "Running..."
    }

    # Spinning arc for running state (using Path with ArcSegment)
    $statusSpinner = [System.Windows.Shapes.Path]@{
        Stroke          = ConvertTo-UiBrush $Colors.Accent
        StrokeThickness = 2
        Width           = 16
        Height          = 16
    }

    # Create arc geometry for spinner (3/4 circle)
    $geometry          = [System.Windows.Media.PathGeometry]::new()
    $figure            = [System.Windows.Media.PathFigure]::new()
    $figure.StartPoint = [System.Windows.Point]::new(8, 0)
    $arc               = [System.Windows.Media.ArcSegment]::new()
    $arc.Point         = [System.Windows.Point]::new(8, 16)
    $arc.Size          = [System.Windows.Size]::new(8, 8)
    $arc.SweepDirection = [System.Windows.Media.SweepDirection]::Clockwise
    $arc.IsLargeArc    = $true
    [void]$figure.Segments.Add($arc)
    [void]$geometry.Figures.Add($figure)
    $statusSpinner.Data = $geometry

    # Spinning animation (continuous rotation)
    $rotateTransform           = [System.Windows.Media.RotateTransform]::new()
    $rotateTransform.CenterX   = 8
    $rotateTransform.CenterY   = 8
    $statusSpinner.RenderTransform = $rotateTransform
    $rotateAnimation           = [System.Windows.Media.Animation.DoubleAnimation]@{
        From           = 0
        To             = 360
        Duration       = [System.Windows.Duration]::new([System.TimeSpan]::FromSeconds(1))
        RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    }
    $rotateTransform.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $rotateAnimation)

    [void]$statusIndicator.Children.Add($statusSpinner)

    # Success checkmark icon (hidden initially)
    $statusSuccess = [System.Windows.Controls.TextBlock]@{
        Text                = [PsUi.ModuleContext]::GetIcon('Accept')
        FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize            = 16
        Foreground          = ConvertTo-UiBrush '#107C10'
        HorizontalAlignment = 'Center'
        VerticalAlignment   = 'Center'
        Visibility          = 'Collapsed'
    }
    [void]$statusIndicator.Children.Add($statusSuccess)

    # Warning icon (hidden initially)
    $statusWarning = [System.Windows.Controls.TextBlock]@{
        Text                = [PsUi.ModuleContext]::GetIcon('Warning')
        FontFamily          = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        FontSize            = 16
        Foreground          = ConvertTo-UiBrush '#FFA500'
        HorizontalAlignment = 'Center'
        VerticalAlignment   = 'Center'
        Visibility          = 'Collapsed'
    }
    [void]$statusIndicator.Children.Add($statusWarning)

    return @{
        Container = $statusIndicator
        Spinner   = $statusSpinner
        Success   = $statusSuccess
        Warning   = $statusWarning
    }
}
