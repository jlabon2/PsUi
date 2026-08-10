function Write-Status {
    <#
    .SYNOPSIS
        Writes a status message to a PsUi status bar from any thread.
    .DESCRIPTION
        Forwards to Set-UiStatusBar with a positional -Message. If no bar is
        found, Set-UiStatusBar emits a warning and the message is dropped.
    .PARAMETER Message
        The status text. Positional, so 'Write-Status "Working..."' works.
        Pass an empty string to clear.
    .PARAMETER Severity
        Info, Success, Warning, or Error. Auto-resets after 5 seconds unless
        -Timeout 0 is also passed.
    .PARAMETER Timeout
        Seconds before severity auto-resets. Pass 0 to keep the tint until the
        next manual change.
    .PARAMETER Bar
        Session name of the target bar. Resolves the active bar when omitted.
    .EXAMPLE
        Write-Status 'Processing...'
    .EXAMPLE
        Write-Status 'Failed' -Severity Error
    .EXAMPLE
        Write-Status 'Saved' -Severity Success -Bar 'mainBar'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Severity,

        [int]$Timeout,

        [string]$Bar
    )

    $params = @{ Text = $Message }
    if ($PSBoundParameters.ContainsKey('Severity')) { $params.Severity = $Severity }
    if ($PSBoundParameters.ContainsKey('Timeout'))  { $params.Timeout  = $Timeout }
    if ($PSBoundParameters.ContainsKey('Bar'))       { $params.Variable = $Bar }

    # Forward unconditionally - Set-UiStatusBar resolves on the UI thread and warns if no bar
    # exists. Safer than probing WPF controls from a background thread for a fallback path.
    Set-UiStatusBar @params
}
