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

        # Detect stub help (PS 7+ doesn't ship help files - Description will be empty)
        $hasRealHelp = $help -and $help.Description

        # Try to get online help URI from the definition or the command itself
        $onlineUri = $null
        if ($def -and $def.HelpUri) { $onlineUri = $def.HelpUri }
        else {
            try {
                $cmdObj = Get-Command $CommandName -ErrorAction SilentlyContinue
                if ($cmdObj.HelpUri) { $onlineUri = $cmdObj.HelpUri }
            } catch { Write-Debug "Could not resolve HelpUri for ${CommandName}: $_" }
        }

        if (!$hasRealHelp) {
            Write-Host "Help files not installed for this command." -ForegroundColor Yellow
            Write-Host "Run " -NoNewline -ForegroundColor Gray
            Write-Host "Update-Help" -NoNewline -ForegroundColor Cyan
            Write-Host " to enable full offline help." -ForegroundColor Gray
            Write-Host ""
            
            # Show parameter names/types as a quick reference
            if ($help.parameters.parameter) {
                Write-Host "PARAMETERS:" -ForegroundColor Yellow
                $help.parameters.parameter | ForEach-Object {
                    Write-Host "  -$($_.Name) <$($_.Type.Name)>" -ForegroundColor Green
                    if ($_.Required -eq 'true') {
                        Write-Host "    Required: Yes" -ForegroundColor Gray
                    }
                }
                Write-Host ""
            }

            # Offer to open online help if a URI is available
            if ($onlineUri) {
                $choices = @(
                    [System.Management.Automation.Host.ChoiceDescription]::new('&Open Online Help', 'Opens the documentation in your default browser')
                    [System.Management.Automation.Host.ChoiceDescription]::new('&Close', 'Dismiss')
                )
                $result = $host.UI.PromptForChoice('Online Help Available', "Open documentation for $displayName in your browser?", $choices, 0)
                if ($result -eq 0) {
                    try { Start-Process $onlineUri }
                    catch { Write-Host "Could not open browser: $_" -ForegroundColor Red }
                }
            }
        }
        else {
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
    }
}
