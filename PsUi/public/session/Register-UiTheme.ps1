function Register-UiTheme {
    <#
    .SYNOPSIS
        Registers a custom theme for use in PsUi windows.
    .DESCRIPTION
        Adds a user-defined theme to the available themes collection. Once registered,
        the theme can be activated with Set-ActiveTheme or selected from the theme picker.
        
        Themes are hashtables mapping color keys to hex color values. At minimum, provide
        Type (Light/Dark), WindowBg, WindowFg, ControlBg, ControlFg, Accent, and Border.
        Missing colors will fall back to the base Light or Dark theme.
    .PARAMETER Name
        The display name for the theme. Used in theme picker menus.
    .PARAMETER Colors
        Hashtable of color definitions. See Get-UiThemeTemplate for required keys.
    .PARAMETER BasedOn
        Optional theme name to inherit missing values from. Defaults to 'Light'.
    .PARAMETER Force
        Overwrite an existing theme with the same name.
    .EXAMPLE
        $myTheme = @{
            Type       = 'Dark'
            WindowBg   = '#1E1E2E'
            WindowFg   = '#CDD6F4'
            ControlBg  = '#313244'
            ControlFg  = '#CDD6F4'
            ButtonBg   = '#45475A'
            ButtonFg   = '#CDD6F4'
            Accent     = '#89B4FA'
            Border     = '#585B70'
        }
        Register-UiTheme -Name 'Catppuccin' -Colors $myTheme -BasedOn 'Dark'
    .EXAMPLE
        # Create a corporate theme based on Light
        Register-UiTheme -Name 'Corporate' -Colors @{
            Type   = 'Light'
            Accent = '#0078D4'
            HeaderBackground = '#004E8C'
            HeaderForeground = '#FFFFFF'
        } -BasedOn 'Light'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [hashtable]$Colors,

        [string]$BasedOn = 'Light',

        [switch]$Force
    )

    $themes = [PsUi.ModuleContext]::Themes
    if (!$themes) {
        Write-Error 'Theme system not initialized. Import the PsUi module first.'
        return
    }

    # Check for existing theme
    if ($themes.ContainsKey($Name) -and !$Force) {
        Write-Error "Theme '$Name' already exists. Use -Force to overwrite."
        return
    }

    # Validate we have a base theme to inherit from
    if (!$themes.ContainsKey($BasedOn)) {
        Write-Warning "Base theme '$BasedOn' not found. Using 'Light' as fallback."
        $BasedOn = 'Light'
    }

    # Start with a copy of the base theme
    $baseColors = $themes[$BasedOn]
    $mergedTheme = @{}
    foreach ($key in $baseColors.Keys) {
        $mergedTheme[$key] = $baseColors[$key]
    }

    # Overlay user-provided colors
    foreach ($key in $Colors.Keys) {
        $mergedTheme[$key] = $Colors[$key]
    }

    # Ensure Type is set correctly based on user input or base
    if ($Colors.ContainsKey('Type')) {
        $mergedTheme['Type'] = $Colors['Type']
    }

    # Sanity check — warn if core keys are missing from the merged result
    $requiredKeys = @('WindowBg', 'WindowFg', 'ControlBg', 'ControlFg', 'ButtonBg', 'ButtonFg', 'Accent', 'Border')
    $missingKeys  = $requiredKeys | Where-Object { !$mergedTheme.ContainsKey($_) }
    if ($missingKeys) {
        Write-Warning "Theme '$Name' is missing required color keys after merge: $($missingKeys -join ', '). This may cause runtime errors."
    }

    $themes[$Name] = $mergedTheme

    Write-Verbose "Registered theme '$Name' (based on '$BasedOn')"
}
