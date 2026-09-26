<#
.SYNOPSIS
    Executes the command for New-UiTool with validated parameters.
#>
function Invoke-UiToolAction {
    [CmdletBinding()]
    param(
        [string]$CommandName,

        [string]$CommandDisplayName,

        [string]$CommandDefinition,

        [string]$FunctionFile
    )

    $session = Get-UiSession
    $def = $session.PSBase.CurrentDefinition

    if (!$CommandName -and $def) {
        $CommandName = $def.CommandName
        $CommandDisplayName = $def.DisplayName
        $CommandDefinition = $def.CommandDefinition
        $FunctionFile = $def.FunctionFile
    }

    if (!$CommandName) {
        Write-Error "No command specified and no CurrentDefinition found in session $([PsUi.SessionManager]::CurrentSessionId). Definition is null: $($null -eq $def)"
        return
    }

    # Local functions come over as text, while one out of a .ps1 gets its whole file dot sourced so the helpers beside it are also available
    if ($FunctionFile) { . $FunctionFile }
    elseif ($CommandDefinition) {
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
        if ($_.Value -is [switch]) { "-$($_.Key)$(if (!$_.Value) { ':$false' })" }
        else { "-$($_.Key) $val" }
    }) -join ' '

    $displayName = if ($CommandDisplayName) { $CommandDisplayName } else { $CommandName }
    Write-Host "> $displayName $paramDisplay" -ForegroundColor Cyan
    Write-Host ""

    & $CommandName @paramHash
}
