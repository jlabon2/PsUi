function Get-OutputPresenter {
    <#
    .SYNOPSIS
        Empty, Text or Collection for the array that Invoke-OnCompleteHandler receives. The kind of value sets which way its shown.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Data
    )

    if ($null -eq $Data) { return 'Empty' }

    $dataArray = @($Data)
    if ($dataArray.Count -eq 0) { return 'Empty' }

    # Only the first ten are eval'd, so an object past them prints as its ToString.
    $sampleSize = [Math]::Min(10, $dataArray.Count)
    for ($i = 0; $i -lt $sampleSize; $i++) {
        if ($dataArray[$i] -isnot [string]) { return 'Collection' }
    }

    return 'Text'
}
