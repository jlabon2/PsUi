function Register-UiHotkey {
    <#
    .SYNOPSIS
        Registers a keyboard shortcut to trigger an action.
    .DESCRIPTION
        Binds a key combination (like Ctrl+S or F5) to a ScriptBlock.
        The shortcut works anywhere in the window, with one carve-out: plain keys
        (no Ctrl or Alt in the combination) don't fire while an editable text box
        has focus, so typing never triggers them.
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
    .EXAMPLE
        Register-UiHotkey -Key 'Escape' -Action { (Get-UiSession).Window.Close() } -NoAsync
        # Closing the window is UI work, so -NoAsync
    .EXAMPLE
        Register-UiHotkey -Key 'F5' -Action { Invoke-Refresh } -NoAsync
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
