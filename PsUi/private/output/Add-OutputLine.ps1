function Add-OutputLine {
    <#
    .SYNOPSIS
        Appends a host output record to the console with ANSI stripping and color mapping.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PsUi.HostOutputRecord]$Record,
        
        [Parameter(Mandatory)]
        [scriptblock]$AppendFunc,
        
        [Parameter(Mandatory)]
        [hashtable]$ColorMap,
        
        [hashtable]$RawColorMap,
        
        [Parameter(Mandatory)]
        $State,
        
        [switch]$SkipScroll,
        [switch]$SuppressErrors
    )
    
    $message = $Record.Message
    
    # Build the append call with correct scroll/newline flags
    # We do this so that we only have one place to handle SkipScroll/NoNewLine logic
    $doAppend = {
        param($text, $fgBrush, $bgBrush, $addNewLine)
        if ($SkipScroll -and !$addNewLine) { & $AppendFunc $text $fgBrush $bgBrush -SkipScroll -NoNewLine -State $State }
        elseif ($SkipScroll)               { & $AppendFunc $text $fgBrush $bgBrush -SkipScroll -State $State }
        elseif (!$addNewLine)              { & $AppendFunc $text $fgBrush $bgBrush -NoNewLine -State $State }
        else                               { & $AppendFunc $text $fgBrush $bgBrush -State $State }
    }
    
    # Truly empty = "just add newline". Don't use IsNullOrWhiteSpace - spaces are valid
    # (e.g., character-by-character diff highlighting where spaces have background colors)
    if ([string]::IsNullOrEmpty($message)) {
        if (!$Record.NoNewLine) {
            if ($SuppressErrors) { try { & $doAppend "`n" $null $null $false } catch { <# Suppress UI errors during shutdown #> } }
            else                 { & $doAppend "`n" $null $null $false }
        }
        return $false
    }
    
    # Strip ANSI escape codes and resolve color brushes
    $cleanOutput = $message -replace '\x1b\[[0-9;]*m', ''
    $fgBrush     = $null
    $bgBrush     = $null
    $fgColor     = $Record.ForegroundColor
    $bgColor     = $Record.BackgroundColor
    
    # Explicit background = user handled contrast, so use true colors
    $hasExplicitBackground = $null -ne $bgColor
    $fgMap                 = if ($hasExplicitBackground -and $RawColorMap) { $RawColorMap } else { $ColorMap }
    
    if ($null -ne $fgColor -and $fgMap.ContainsKey($fgColor)) {
        $fgBrush = $fgMap[$fgColor]
    }
    
    # Background always uses raw colors (no adjustment needed)
    $bgMap = if ($RawColorMap) { $RawColorMap } else { $ColorMap }
    if ($null -ne $bgColor -and $bgMap.ContainsKey($bgColor)) {
        $bgBrush = $bgMap[$bgColor]
    }
    
    # Append with error handling if requested
    if ($SuppressErrors) { try { & $doAppend $cleanOutput $fgBrush $bgBrush (!$Record.NoNewLine) } catch { <# Suppress UI errors during shutdown #> } }
    else                 { & $doAppend $cleanOutput $fgBrush $bgBrush (!$Record.NoNewLine) }
    
    return $true
}
