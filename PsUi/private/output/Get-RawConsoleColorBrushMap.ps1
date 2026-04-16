function Get-RawConsoleColorBrushMap {
    <#
    .SYNOPSIS
        Returns true console colors as WPF brushes (no dark-bg adjustment).
    .DESCRIPTION
        Unlike Get-ConsoleColorBrushMap, this returns actual console colors without
        contrast adjustment. Used when -BackgroundColor is explicitly set.
    #>
    [CmdletBinding()]
    param()

    return @{
        [System.ConsoleColor]::Black       = [System.Windows.Media.Brushes]::Black
        [System.ConsoleColor]::DarkBlue    = [System.Windows.Media.Brushes]::DarkBlue
        [System.ConsoleColor]::DarkGreen   = [System.Windows.Media.Brushes]::DarkGreen
        [System.ConsoleColor]::DarkCyan    = [System.Windows.Media.Brushes]::DarkCyan
        [System.ConsoleColor]::DarkRed     = [System.Windows.Media.Brushes]::DarkRed
        [System.ConsoleColor]::DarkMagenta = [System.Windows.Media.Brushes]::DarkMagenta
        [System.ConsoleColor]::DarkYellow  = [System.Windows.Media.Brushes]::DarkGoldenrod
        [System.ConsoleColor]::Gray        = [System.Windows.Media.Brushes]::Gray
        [System.ConsoleColor]::DarkGray    = [System.Windows.Media.Brushes]::DarkGray
        [System.ConsoleColor]::Blue        = [System.Windows.Media.Brushes]::Blue
        [System.ConsoleColor]::Green       = [System.Windows.Media.Brushes]::LimeGreen
        [System.ConsoleColor]::Cyan        = [System.Windows.Media.Brushes]::Cyan
        [System.ConsoleColor]::Red         = [System.Windows.Media.Brushes]::Red
        [System.ConsoleColor]::Magenta     = [System.Windows.Media.Brushes]::Magenta
        [System.ConsoleColor]::Yellow      = [System.Windows.Media.Brushes]::Yellow
        [System.ConsoleColor]::White       = [System.Windows.Media.Brushes]::White
    }
}
