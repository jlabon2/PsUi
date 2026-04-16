function Get-ChartPalette {
    <#
    .SYNOPSIS
        Returns resource key names for theme-aware chart colors.
    #>

    # Return brush resource keys that the ThemeEngine creates
    # First 4 are theme semantic colors, rest are fallback hex values
    return @(
        @{ ResourceKey = 'AccentBrush';  Fallback = '#0078D4' }
        @{ ResourceKey = 'SuccessBrush'; Fallback = '#50A14F' }
        @{ ResourceKey = 'WarningBrush'; Fallback = '#C18401' }
        @{ ResourceKey = 'ErrorBrush';   Fallback = '#E45649' }
        @{ ResourceKey = $null; Fallback = '#9B59B6' }
        @{ ResourceKey = $null; Fallback = '#1ABC9C' }
        @{ ResourceKey = $null; Fallback = '#E67E22' }
        @{ ResourceKey = $null; Fallback = '#34495E' }
    )
}
