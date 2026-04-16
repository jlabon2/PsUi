function Register-UiHotkey {
    <#
    .SYNOPSIS
        Registers a keyboard shortcut to trigger an action.
    .DESCRIPTION
        Binds a key combination (like Ctrl+S or F5) to a ScriptBlock.
        The shortcut works window-wide; focus can be on any control.
        Actions run asynchronously by default.
    .PARAMETER Key
        Key combination string. Format: "[Ctrl+][Alt+][Shift+]Key"
        Examples: "Ctrl+S", "F5", "Ctrl+Shift+N", "Escape"
    .PARAMETER Action
        ScriptBlock to execute when the hotkey is pressed.
        Runs async by default; use -NoAsync for synchronous execution.
    .PARAMETER NoAsync
        Run the action on the UI thread instead of a background runspace.
    .EXAMPLE
        Register-UiHotkey -Key 'Ctrl+S' -Action { Save-CurrentDocument }
        # Triggers save on Ctrl+S
    .EXAMPLE
        Register-UiHotkey -Key 'Escape' -Action { Close-UiParentWindow }
        # Close window on Escape
    .EXAMPLE
        Register-UiHotkey -Key 'F5' -Action { Invoke-Refresh } -NoAsync
        # Synchronous refresh on F5
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [switch]$NoAsync
    )

    $session = Assert-UiSession -CallerName 'Register-UiHotkey'

    # Normalize key combo for consistent lookup
    $normalizedKey = ConvertTo-NormalizedKeyCombo -KeyCombo $Key
    if (!$normalizedKey) {
        throw "Invalid key combination: '$Key'. Use format like 'Ctrl+S', 'F5', 'Ctrl+Shift+N'"
    }

    # Wrap action for async/sync dispach
    $hotkeyContext = @{
        Action  = $Action
        NoAsync = $NoAsync.IsPresent
    }

    $session.RegisterHotkey($normalizedKey, $hotkeyContext)
    Write-Debug "Registered hotkey: $normalizedKey"
}
