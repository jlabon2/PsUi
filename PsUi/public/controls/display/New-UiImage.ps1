function New-UiImage {
    <#
    .SYNOPSIS
        Displays an image from file or base64.
    .DESCRIPTION
        Shows an image from a file path or a base64 string. Aspect ratio is always preserved:
        give one dimension and the other follows, give both and the image fits inside the box.
    .PARAMETER Path
        File path to the image.
    .PARAMETER Base64
        Base64 encoded image data.
    .PARAMETER Width
        Image width (maintains aspect ratio).
    .PARAMETER Height
        Image height in pixels. With Width also set, the image fits the box without stretching.
    .PARAMETER WPFProperties
        Hashtable of additional WPF properties to set on the control.
        Allows setting any valid WPF property not explicitly exposed as a parameter.
        Bad values warn and get skipped. A property name that does not exist on the control is
        skipped silently (-Verbose shows it). Nothing stops execution.
        Supports attached properties using dot notation (e.g., "Grid.Row").
    .EXAMPLE
        New-UiImage -Path 'C:\Photos\logo.png' -Width 200
    .EXAMPLE
        New-UiImage -Base64 $encodedString -Width 64 -Height 64
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory, ParameterSetName = 'Base64')]
        [string]$Base64,
        
        [int]$Width,
        
        [int]$Height,
        
        [Parameter()]
        [hashtable]$WPFProperties
    )

    $session = Assert-UiSession -CallerName 'New-UiImage'
    $parent  = $session.CurrentParent
    Write-Debug "Path='$Path', Width=$Width, Height=$Height, Parent: $($parent.GetType().Name)"

    $image = [System.Windows.Controls.Image]::new()
    $image.Stretch = [System.Windows.Media.Stretch]::Uniform
    $image.Margin = [System.Windows.Thickness]::new(4)

    if ($Width) { $image.Width = $Width }
    if ($Height) { $image.Height = $Height }

    try {
        $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
        $bitmap.BeginInit()

        if ($Path -and (Test-Path $Path)) {
            $bitmap.UriSource = [Uri]::new($Path)
        }
        elseif ($Base64) {
            $bytes = [Convert]::FromBase64String($Base64)
            $stream = [System.IO.MemoryStream]::new($bytes)
            $bitmap.StreamSource = $stream
        }
        else {
            Write-Error 'Provide either -Path or -Base64'
            return
        }

        $bitmap.EndInit()
        $bitmap.Freeze()
        $image.Source = $bitmap
    }
    catch {
        Write-Error "Failed to load image: $_"
        return
    }

    # Apply custom WPF properties if specified
    if ($WPFProperties) {
        Set-UiProperties -Control $image -Properties $WPFProperties
    }

    Write-Debug "Adding image to parent"
    [void]$parent.Children.Add($image)
}
