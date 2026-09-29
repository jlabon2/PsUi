function Get-UiValueKind {
    <#
    .SYNOPSIS
        Returns what kind of value is being passed in, as a PsUi.ValueKind enum.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Untyped so a PSObject arrives as itself rather than as whatever it wraps.
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        $Value
    )

    # The C# side determines the value kind, so the converters and this answer the same. Kept as a function so the display code reads as PowerShell.
    [PsUi.ValueKind]::Of($Value)
}
