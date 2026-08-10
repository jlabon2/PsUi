function Get-UiGridFloodWarning {
    <#
    .SYNOPSIS
        Shared wide grid flood policy. Cell threshold and the common warning clause.
    #>
    @{
        CellThreshold = 10000
        Clause        = 'Wide grids get sluggish past ~10k cells.'
    }
}
