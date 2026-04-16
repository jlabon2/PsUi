<#
.SYNOPSIS
    Displays help for a command in New-UiTool output panel.
#>
function Show-UiToolHelp {
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
        Write-Host "No command specified." -ForegroundColor Red
        return
    }

    $displayName = if ($CommandDisplayName) { $CommandDisplayName } else { $CommandName }

    Write-Host "=== $displayName ===" -ForegroundColor Cyan
    Write-Host ""

    # For local functions with embedded definition, try to extract help
    if ($CommandDefinition) {
        $help = $null
        try {
            $funcBlock = [scriptblock]::Create("function $CommandName {`n$CommandDefinition`n}")
            . $funcBlock
            $help = Get-Help $CommandName -Full -ErrorAction SilentlyContinue
        }
        catch { Write-Debug "Help retrieval failed: $_" }

        if ($help -and $help.Description) {
            if ($help.Synopsis) {
                Write-Host "SYNOPSIS:" -ForegroundColor Yellow
                Write-Host "  $($help.Synopsis)"
                Write-Host ""
            }
            if ($help.Description) {
                Write-Host "DESCRIPTION:" -ForegroundColor Yellow
                $help.Description | ForEach-Object { Write-Host "  $($_.Text)" }
                Write-Host ""
            }
            if ($help.parameters.parameter) {
                Write-Host "PARAMETERS:" -ForegroundColor Yellow
                $help.parameters.parameter | ForEach-Object {
                    Write-Host "  -$($_.Name) <$($_.Type.Name)>" -ForegroundColor Green
                    if ($_.Description) {
                        $_.Description | ForEach-Object { Write-Host "    $($_.Text)" }
                    }
                    Write-Host ""
                }
            }
        }
        else {
            Write-Host "This is a locally-defined function." -ForegroundColor Gray
            Write-Host ""
            Write-Host "DEFINITION:" -ForegroundColor Yellow
            Write-Host ""
            $CommandDefinition.Split([char[]]@("`r","`n"), [StringSplitOptions]::RemoveEmptyEntries) |
                ForEach-Object { Write-Host "  $_" }
        }
    }
    else {
        # Global command - use standard Get-Help
        $help = Get-Help $CommandName -Full -ErrorAction SilentlyContinue

        if ($help) {
            if ($help.Synopsis) {
                Write-Host "SYNOPSIS:" -ForegroundColor Yellow
                Write-Host "  $($help.Synopsis)"
                Write-Host ""
            }
            if ($help.Description) {
                Write-Host "DESCRIPTION:" -ForegroundColor Yellow
                $help.Description | ForEach-Object { Write-Host "  $($_.Text)" }
                Write-Host ""
            }
            if ($help.parameters.parameter) {
                Write-Host "PARAMETERS:" -ForegroundColor Yellow
                $help.parameters.parameter | ForEach-Object {
                    Write-Host "  -$($_.Name) <$($_.Type.Name)>" -ForegroundColor Green
                    if ($_.Description) {
                        $_.Description | ForEach-Object { Write-Host "    $($_.Text)" }
                    }
                    if ($_.Required -eq 'true') {
                        Write-Host "    Required: Yes" -ForegroundColor Gray
                    }
                    Write-Host ""
                }
            }
            if ($help.Examples.Example) {
                Write-Host "EXAMPLES:" -ForegroundColor Yellow
                $help.Examples.Example | ForEach-Object {
                    Write-Host "  $($_.Title)" -ForegroundColor Cyan
                    Write-Host "  $($_.Code)" -ForegroundColor Green
                    if ($_.Remarks) {
                        $_.Remarks | ForEach-Object { Write-Host "    $($_.Text)" }
                    }
                    Write-Host ""
                }
            }
        }
        else {
            Write-Host "No help available for $displayName" -ForegroundColor Yellow
        }
    }
}
