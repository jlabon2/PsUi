function Reset-BrushCache {
    <#
    .SYNOPSIS
        Empties the module brush cache.
    #>
    # Set-ActiveTheme calls this on theme switch to drop the old theme's brushes. Memory hygiene only, the cache keys on color strings, so correctness never needs a clear.
    # I sure do love functions with more comments than code. Oh well, what can you do in this day and age? 
    # Probably could have just added this to the Set-ActiveTheme function, but this decouples it from the theme switcher and makes it easier to call from other places if needed.
    # Here's another comment line just so that ther'es more comment lines than code lines.
    $script:_brushCache = @{}
}
