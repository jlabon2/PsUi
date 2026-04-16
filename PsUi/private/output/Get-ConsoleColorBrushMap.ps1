function Get-ConsoleColorBrushMap {
    <#
    .SYNOPSIS
        Returns a hashtable mapping ConsoleColor values to WPF brushes for Write-Host output.
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
        [System.ConsoleColor]::DarkYellow  = [System.Windows.Media.Brushes]::Olive
        [System.ConsoleColor]::Gray        = [System.Windows.Media.Brushes]::Gray
        [System.ConsoleColor]::DarkGray    = [System.Windows.Media.Brushes]::DarkGray
        [System.ConsoleColor]::Blue        = [System.Windows.Media.Brushes]::RoyalBlue
        [System.ConsoleColor]::Green       = [System.Windows.Media.Brushes]::ForestGreen
        [System.ConsoleColor]::Cyan        = [System.Windows.Media.Brushes]::DarkCyan
        [System.ConsoleColor]::Red         = [System.Windows.Media.Brushes]::IndianRed
        [System.ConsoleColor]::Magenta     = [System.Windows.Media.Brushes]::DarkMagenta
        [System.ConsoleColor]::Yellow      = [System.Windows.Media.Brushes]::Olive
        [System.ConsoleColor]::White       = [System.Windows.Media.Brushes]::DimGray
    }
}
