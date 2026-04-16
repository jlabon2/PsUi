function New-WindowIcon {
    <#
    .SYNOPSIS
        Creates a themed window icon with a terminal prompt symbol (>_).
        # This is kind of a placeholder for now until we have better icons. But it works decently.
    #>
    param(
        [hashtable]$Colors
    )

    try {
        $iconVisual = [System.Windows.Media.DrawingVisual]::new()
        $dc         = $iconVisual.RenderOpen()

        # Parse accent color for icon background
        $bgBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(71, 85, 105))
        if ($Colors.Accent -match '#([0-9A-Fa-f]{6})') {
            $red     = [Convert]::ToByte($matches[1].Substring(0, 2), 16)
            $green   = [Convert]::ToByte($matches[1].Substring(2, 2), 16)
            $blue    = [Convert]::ToByte($matches[1].Substring(4, 2), 16)
            $bgBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb($red, $green, $blue))
        }

        # Calculate optimal contrast color for the chevron
        $fgBrush     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Colors]::White)
        $contrastHex = Get-ContrastColor -HexColor $Colors.Accent
        if ($contrastHex -match '#([0-9A-Fa-f]{6})') {
            $red     = [Convert]::ToByte($matches[1].Substring(0, 2), 16)
            $green   = [Convert]::ToByte($matches[1].Substring(2, 2), 16)
            $blue    = [Convert]::ToByte($matches[1].Substring(4, 2), 16)
            $fgBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb($red, $green, $blue))
        }

        # Draw main rounded rectangle background
        $iconRect = [System.Windows.Rect]::new(0, 0, 32, 32)
        $dc.DrawRoundedRectangle($bgBrush, $null, $iconRect, 5, 5)

        # Draw chevron ">" - shifted left to make room for underscore
        $chevronGeometry = [System.Windows.Media.Geometry]::Parse('M 7,6 L 18,14 L 7,22 Z')
        $dc.DrawGeometry($fgBrush, $null, $chevronGeometry)

        # Draw underscore "_" as a horizontal bar
        $underscoreRect = [System.Windows.Rect]::new(18, 20, 9, 3)
        $dc.DrawRectangle($fgBrush, $null, $underscoreRect)
        $dc.Close()

        # Render to 256x256 for crisp taskbar display, WPF scales as needed
        $renderTarget = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
            256, 256, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32
        )

        # Scale the 32x32 visual to fill 256x256
        $drawingVisual = [System.Windows.Media.DrawingVisual]::new()
        $dc2 = $drawingVisual.RenderOpen()
        $dc2.PushTransform([System.Windows.Media.ScaleTransform]::new(8, 8))
        $dc2.DrawDrawing($iconVisual.Drawing)
        $dc2.Pop()
        $dc2.Close()

        $renderTarget.Render($drawingVisual)
        $renderTarget.Freeze()
        return $renderTarget
    }
    catch { return $null }
}