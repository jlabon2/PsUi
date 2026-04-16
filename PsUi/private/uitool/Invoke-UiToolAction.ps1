<#
.SYNOPSIS
    Executes the command for New-UiTool with validated parameters.
#>
function Invoke-UiToolAction {
    [CmdletBinding()]
    param(
        [string]$CommandName,

        [string]$CommandDisplayName,

        [string]$CommandDefinition
    )

    $session = Get-UiSession
    $def = $session.PSBase.CurrentDefinition

    if (!$CommandName -and $def) {
        $CommandName = $def.CommandName
        $CommandDisplayName = $def.DisplayName
        $CommandDefinition = $def.CommandDefinition
    }

    if (!$CommandName) {
        Write-Error "No command specified and no CurrentDefinition found in session $([PsUi.SessionManager]::CurrentSessionId). Definition is null: $($null -eq $def)"
        return
    }

    # For local functions, inject the definition first
    if ($CommandDefinition) {
        $funcBlock = [scriptblock]::Create("function $CommandName {`n$CommandDefinition`n}")
        . $funcBlock
    }

    $session   = Get-UiSession
    $paramHash = $session.Variables['_uiTool_validatedParams']
    if (!$paramHash) { $paramHash = @{} }

    $paramDisplay = ($paramHash.GetEnumerator() | ForEach-Object {
        $val = if ($_.Value -is [switch]) { '' }
               elseif ($_.Value -is [System.Security.SecureString]) { '***' }
               elseif ($_.Value -is [scriptblock]) { "{$($_.Value)}" }
               elseif ($_.Value -is [array]) { "($($_.Value -join ', '))" }
               else { "'$($_.Value)'" }
        if ($_.Value -is [switch]) { "-$($_.Key)" } else { "-$($_.Key) $val" }
    }) -join ' '

    $displayName = if ($CommandDisplayName) { $CommandDisplayName } else { $CommandName }
    Write-Host "> $displayName $paramDisplay" -ForegroundColor Cyan
    Write-Host ""

    & $CommandName @paramHash
}
