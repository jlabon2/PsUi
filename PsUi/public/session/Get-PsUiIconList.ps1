function Get-PsUiIconList {
    <#
    .SYNOPSIS
        Lists all available icon names.
    .PARAMETER Filter
        Optional wildcard filter for icon names.
    .EXAMPLE
        Get-PsUiIconList
    .EXAMPLE
        Get-PsUiIconList -Filter '*Arrow*'
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*'
    )

    # Static C# dictionary works from any runspace
    [PsUi.ModuleContext]::Icons.Keys | Where-Object { $_ -like $Filter } | Sort-Object
}
