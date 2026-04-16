function Write-UiHostDirect {
    <#
    .SYNOPSIS
        Writes directly to the console bypassing PsUi's Write-Host proxy.
    .DESCRIPTION
        In async button actions, PsUi intercepts Write-Host to route output to the UI.
        Call this when you need actual console output - for example,
        when logging outside the UI or writing to a console window.
        
        Uses [Console]::WriteLine to bypass both the PSHost proxy and runspace boundaries.
        Note: Color support is limited compared to Write-Host since we use Console APIs directly.
    .PARAMETER Object
        The object to write.
    .PARAMETER ForegroundColor
        Text foreground color.
    .PARAMETER BackgroundColor
        Text background color.
    .PARAMETER NoNewline
        Don't append a newline.
    .PARAMETER Separator
        Separator between multiple objects.
    .EXAMPLE
        Write-UiHostDirect "This goes to console, not the UI panel"
    .EXAMPLE
        # Inside a button action
        New-UiButton -Text 'Log' -Action {
            Write-Host "This appears in UI output panel"
            Write-UiHostDirect "This goes to PowerShell console"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [object]$Object,

        [System.ConsoleColor]$ForegroundColor,
        [System.ConsoleColor]$BackgroundColor,
        [switch]$NoNewline,
        [object]$Separator = ' '
    )

    process {
        # Build output string
        $text = if ($null -eq $Object) { '' } else { $Object.ToString() }

        # Save current colors if we need to change them
        $restoreFg = $false
        $restoreBg = $false
        $originalFg = [Console]::ForegroundColor
        $originalBg = [Console]::BackgroundColor

        try {
            if ($PSBoundParameters.ContainsKey('ForegroundColor')) {
                [Console]::ForegroundColor = $ForegroundColor
                $restoreFg = $true
            }
            if ($PSBoundParameters.ContainsKey('BackgroundColor')) {
                [Console]::BackgroundColor = $BackgroundColor
                $restoreBg = $true
            }

            if ($NoNewline) {
                [Console]::Write($text)
            }
            else {
                [Console]::WriteLine($text)
            }
        }
        finally {
            # Restore original colors
            if ($restoreFg) { [Console]::ForegroundColor = $originalFg }
            if ($restoreBg) { [Console]::BackgroundColor = $originalBg }
        }
    }
}
