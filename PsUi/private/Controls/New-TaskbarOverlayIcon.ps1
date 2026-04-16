function New-TaskbarOverlayIcon {
    <#
    .SYNOPSIS
        Creates a small circular overlay icon from a glyph character for taskbar badge display.
        This is useful for showing status on the taskbar button and over dialogs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [char]$GlyphChar,

        [Parameter(Mandatory)]
        [string]$Color,

        [string]$BackgroundColor = '#FFFFFF',

        [int]$Size = 16
    )

    try {
        $iconVisual = [System.Windows.Media.DrawingVisual]::new()
        $dc         = $iconVisual.RenderOpen()

        # Parse foreground color for the glyph
        $fgBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Colors]::White)
        if ($Color -match '#([0-9A-Fa-f]{6})') {
            $red     = [Convert]::ToByte($matches[1].Substring(0, 2), 16)
            $green   = [Convert]::ToByte($matches[1].Substring(2, 2), 16)
            $blue    = [Convert]::ToByte($matches[1].Substring(4, 2), 16)
            $fgBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb($red, $green, $blue))
        }

        # Parse background color (defaults to white for taskbar visibility)
        $bgBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Colors]::White)
        if ($BackgroundColor -match '#([0-9A-Fa-f]{6})') {
            $red     = [Convert]::ToByte($matches[1].Substring(0, 2), 16)
            $green   = [Convert]::ToByte($matches[1].Substring(2, 2), 16)
            $blue    = [Convert]::ToByte($matches[1].Substring(4, 2), 16)
            $bgBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb($red, $green, $blue))
        }

        # Draw shadow ring for contrast against any taskbar color
        $center    = [System.Windows.Point]::new($Size / 2, $Size / 2)
        $radius    = ($Size / 2) - 0.5
        $shadowPen = [System.Windows.Media.Pen]::new(
            [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(100, 0, 0, 0)), 1.0
        )
        $dc.DrawEllipse($null, $shadowPen, $center, $radius, $radius)

        # Draw the filled background circle
        $innerRadius = $radius - 0.5
        $dc.DrawEllipse($bgBrush, $null, $center, $innerRadius, $innerRadius)

        # Create typeface for glyph rendering
        $typeface = [System.Windows.Media.Typeface]::new(
            [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets'),
            [System.Windows.FontStyles]::Normal,
            [System.Windows.FontWeights]::Normal,
            [System.Windows.FontStretches]::Normal
        )

        # Create formatted text sized to fit within the circle
        $fontSize      = $Size * 0.60
        $formattedText = [System.Windows.Media.FormattedText]::new(
            [string]$GlyphChar,
            [System.Globalization.CultureInfo]::CurrentCulture,
            [System.Windows.FlowDirection]::LeftToRight,
            $typeface,
            $fontSize,
            $fgBrush,
            96
        )

        # Center the glyph in the icon
        $x = ($Size - $formattedText.Width) / 2
        $y = ($Size - $formattedText.Height) / 2
        $dc.DrawText($formattedText, [System.Windows.Point]::new($x, $y))
        $dc.Close()

        # Render to bitmap and freeze for thread safety
        $renderTarget = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
            $Size, $Size, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32
        )
        $renderTarget.Render($iconVisual)
        $renderTarget.Freeze()

        return $renderTarget
    }
    catch {
        Write-Verbose "Failed to create overlay icon: $_"
        return $null
    }
}
