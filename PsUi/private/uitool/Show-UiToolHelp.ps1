<#
.SYNOPSIS
    Displays help for a command in New-UiTool output panel.
#>
function Show-UiToolHelp {
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
        Write-Host "No command specified." -ForegroundColor Red
        return
    }

    $displayName = if ($CommandDisplayName) { $CommandDisplayName } else { $CommandName }

    # Help written in markdown keeps its links and [!NOTE] tags in the Text, and the output window would print them as is
    $writeHelpText = {
        param([string[]]$Text, [string]$Indent)

        $plain = ConvertFrom-UiHelpMarkdown -Text $Text -Plain
        if (!$plain) { return }

        # Installed cmdlet help separates some paragraphs with a lone U+0080, and Trim doesn't count that as space
        $plain = [regex]::Replace($plain.Replace("`r", ''), '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]', '')

        # Collapse blank runs to one
        $lastBlank = $true
        foreach ($line in $plain.Split("`n")) {
            $blank = !$line.Trim()
            if ($blank -and $lastBlank) { continue }
            Write-Host $(if ($blank) { '' } else { "$Indent$line" })
            $lastBlank = $blank
        }
    }

    # Installed help leaves Type empty and puts the name in parameterValue
    $typeLabel = {
        param($Parameter)
        if ($Parameter.Type.Name) { return $Parameter.Type.Name }
        if ($Parameter.parameterValue) { return ([string]$Parameter.parameterValue).Split('.')[-1] }
        'Object'
    }

    # Installed help leaves Code empty and puts it all in introduction
    $writeExample = {
        param($Example)

        $title = ([string]$Example.Title).Trim().Trim('-').Trim()
        Write-Host "  $(ConvertFrom-UiHelpMarkdown -Text $title -Plain)" -ForegroundColor Cyan
        if ($Example.Code) { Write-Host "  $($Example.Code)" -ForegroundColor Green }

        # Every empty entry in introduction is a paragraph break of its own
        $intro  = ((@($Example.introduction) | ForEach-Object { $_.Text }) -join "`n").Replace("`r", '')
        $intro  = [regex]::Replace($intro, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]', '')
        $intro  = [regex]::Replace($intro, '\n[ \t]*(\n[ \t]*)+', "`n`n")
        $pieces = @([regex]::Split($intro, '(?s)(```[^\n]*\n.*?```)') | Where-Object { $_.Trim() })

        for ($i = 0; $i -lt $pieces.Count; $i++) {
            if ($i -gt 0) { Write-Host '' }
            if ($pieces[$i] -match '(?s)^```[^\n]*\n(.*?)```$') {
                foreach ($codeLine in $Matches[1].TrimEnd().Split("`n")) {
                    Write-Host "    $($codeLine.TrimEnd())" -ForegroundColor Green
                }
            }
            else { & $writeHelpText $pieces[$i].Trim() '    ' }
        }
        if ($Example.Remarks) { & $writeHelpText @($Example.Remarks | ForEach-Object { $_.Text }) '    ' }
        Write-Host ""
    }

    Write-Host "=== $displayName ===" -ForegroundColor Cyan
    Write-Host ""

    # Get-Help can't see a local function or a file's function from this runspace until it's loaded here
    if ($FunctionFile -or $CommandDefinition) {
        $help = $null
        try {
            # The whole file keeps help written above the function keyword
            if ($FunctionFile) { . $FunctionFile }
            else {
                $funcBlock = [scriptblock]::Create("function $CommandName {`n$CommandDefinition`n}")
                . $funcBlock
            }
            $help = Get-Help $CommandName -Full -ErrorAction SilentlyContinue
        }
        catch { Write-Debug "Help retrieval failed: $_" }

        if ($help -and $help.Description) {
            if ($help.Synopsis) {
                Write-Host "SYNOPSIS:" -ForegroundColor Yellow
                & $writeHelpText $help.Synopsis '  '
                Write-Host ""
            }
            if ($help.Description) {
                Write-Host "DESCRIPTION:" -ForegroundColor Yellow
                & $writeHelpText @($help.Description | ForEach-Object { $_.Text }) '  '
                Write-Host ""
            }
            if ($help.parameters.parameter) {
                Write-Host "PARAMETERS:" -ForegroundColor Yellow
                $help.parameters.parameter | ForEach-Object {
                    Write-Host "  -$($_.Name) <$(& $typeLabel $_)>" -ForegroundColor Green
                    if ($_.Description) {
                        & $writeHelpText @($_.Description | ForEach-Object { $_.Text }) '    '
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
                    Write-Host "  -$($_.Name) <$(& $typeLabel $_)>" -ForegroundColor Green
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
                & $writeHelpText $help.Synopsis '  '
                Write-Host ""
            }
            if ($help.Description) {
                Write-Host "DESCRIPTION:" -ForegroundColor Yellow
                & $writeHelpText @($help.Description | ForEach-Object { $_.Text }) '  '
                Write-Host ""
            }
            if ($help.parameters.parameter) {
                Write-Host "PARAMETERS:" -ForegroundColor Yellow
                $help.parameters.parameter | ForEach-Object {
                    Write-Host "  -$($_.Name) <$(& $typeLabel $_)>" -ForegroundColor Green
                    if ($_.Description) {
                        & $writeHelpText @($_.Description | ForEach-Object { $_.Text }) '    '
                    }
                    if ($_.Required -eq 'true') {
                        Write-Host "    Required: Yes" -ForegroundColor Gray
                    }
                    Write-Host ""
                }
            }
            if ($help.Examples.Example) {
                Write-Host "EXAMPLES:" -ForegroundColor Yellow
                foreach ($example in $help.Examples.Example) { & $writeExample $example }
            }
        }
    }
}
