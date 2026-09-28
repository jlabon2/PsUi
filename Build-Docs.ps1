<#
.SYNOPSIS
    Rebuilds docs/wiki/reference from source help. The pages are build output and shouldn't be
    edited directly.
#>

#requires -Version 7
[CmdletBinding()]
param(
    # Rebuild into a temp scratch folder, diff against the committed pages, write nothing.
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'

# Use the en-US culture for all help text
[System.Threading.Thread]::CurrentThread.CurrentCulture   = [cultureinfo]'en-US'
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [cultureinfo]'en-US'

$repoRoot       = $PSScriptRoot
$wikiDir        = Join-Path $repoRoot 'docs/wiki'
$referenceDir   = Join-Path $wikiDir 'reference'
$overlayRoot    = Join-Path $repoRoot 'docs/pages'
$indexPath      = Join-Path $wikiDir 'Command-Index.md'
$cmdletHelpPath = Join-Path $repoRoot 'PsUi/en-US/PsUi.dll-Help.xml'
$newline        = "`r`n"

# Commands with no generated page and no page.md yet get a pending row in the index
$deferredPages = @()

# platyPS 0.14.2. The v2 module renders differently
if (!(Get-Module platyPS -ListAvailable | Where-Object Version -eq '0.14.2')) {
    Install-Module platyPS -RequiredVersion 0.14.2 -Scope CurrentUser -Force
}
Import-Module platyPS -RequiredVersion 0.14.2
Import-Module (Join-Path $repoRoot 'PsUi/PsUi.psd1') -Force

# Category and source file per command from the public/ folder layout. The binary cmdlet has no source under public/, so it is set manually
$categoryByCommand   = @{ 'New-UiWindow' = 'window' }
$sourceFileByCommand = @{}
Get-ChildItem (Join-Path $repoRoot 'PsUi/public') -Recurse -Filter *.ps1 | ForEach-Object {
    $categoryByCommand[$_.BaseName]   = $_.Directory.Name
    $sourceFileByCommand[$_.BaseName] = $_.FullName
}

#  New-UiWindow shows up in both export lists (psd1 function export and also the binary cmdlet)
$psuiModule = Get-Module PsUi
$exported   = @($psuiModule.ExportedFunctions.Keys) + @($psuiModule.ExportedCmdlets.Keys) | Sort-Object -Unique

# Anything exported that the category map doesn't know is a new command added without a source file convention that this script recognizes
$unmapped = $exported | Where-Object { !$categoryByCommand.ContainsKey($_) }
if ($unmapped) { throw "No category for: $($unmapped -join ', '). Add the source file under PsUi/public/<category>/ or pin it in Build-Docs.ps1." }

$commonParams = @([System.Management.Automation.PSCmdlet]::CommonParameters) +
                @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)

function Get-CommandFolder {
    param([string]$CommandName)
    Join-Path $overlayRoot $categoryByCommand[$CommandName] $CommandName
}

function Test-PageMd {
    param([string]$CommandName)
    Test-Path (Join-Path (Get-CommandFolder $CommandName) 'page.md')
}

function Test-UpToDate {
    # Get-Content is unreliable for comparisons due to encoding. Compare the raw bytes instead.
    param([string]$Path, [string]$Text)
    if (!(Test-Path $Path)) { return $false }
    [System.Linq.Enumerable]::SequenceEqual([IO.File]::ReadAllBytes($Path), [System.Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Remove-ProgressAction {
    param([string]$PageText)
    $PageText = $PageText -replace '(?ms)^### -ProgressAction\r?\n.*?```yaml\r?\n.*?```\r?\n\r?\n', ''
    $PageText -replace ' \[-ProgressAction <ActionPreference>\]', ''
}

function Remove-YamlHeader {
    param([string]$PageText)
    $PageText -replace '(?s)\A---\r\n.*?\r\n---\r\n(\r\n)?', ''
}

function Format-HelpText {
    param([string]$HelpText)
    ($HelpText -replace '<', '\<') -replace '\[', '\['
}

function Get-SourceParamHelp {
    # Get-Help drops dynamic parameter descriptions (the -Icon params built in DynamicParam) so pull the .PARAMETER block straight out of the source comment help
    param([string]$CommandName, [string]$ParameterName)
    $sourcePath = $sourceFileByCommand[$CommandName]
    if (!$sourcePath) { return $null }

    $blockMatch = [regex]::Match((Get-Content $sourcePath -Raw), "(?ms)^[ \t]*\.PARAMETER[ \t]+$([regex]::Escape($ParameterName))[ \t]*\r?\n(.*?)(?=^[ \t]*\.\w+|#>)")
    if (!$blockMatch.Success) { return $null }

    # Strip the comment block shared indent or the text renders as a code block
    $blockLines = $blockMatch.Groups[1].Value -split "\r?\n"
    $indentSize = ($blockLines | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Length - $_.TrimStart().Length } | Measure-Object -Minimum).Minimum
    if ($null -eq $indentSize) { return $null }
    (($blockLines | ForEach-Object { if ($_.Length -gt $indentSize) { $_.Substring($indentSize) } else { $_.TrimStart() } }) -join $newline).Trim()
}

function Update-ParamHelp {
    # platyPS flattens the paragraph breaks out of .PARAMETER text while Get-Help keeps them. Swap each parameter body for the Get-Help version.
    param([string]$PageText, [string]$CommandName)
    $helpInfo = Get-Help $CommandName -Full
    foreach ($parameterName in (Get-Command $CommandName).Parameters.Keys) {
        if ($commonParams -contains $parameterName) { continue }

        $helpParam = @($helpInfo.parameters.parameter) | Where-Object name -eq $parameterName | Select-Object -First 1
        $bodyText  = ''
        if ($helpParam -and $helpParam.description) { $bodyText = (@($helpParam.description) | ForEach-Object { $_.Text }) -join "$newline$newline" }
        if (!"$bodyText".Trim()) { $bodyText = Get-SourceParamHelp -CommandName $CommandName -ParameterName $parameterName }
        if (!"$bodyText".Trim()) { $bodyText = "{{ Fill $parameterName Description }}" }
        else { $bodyText = Format-HelpText "$bodyText".Trim() }

        $sectionPattern = '(?ms)^(### -' + [regex]::Escape($parameterName) + '\r?\n).*?(?=^```yaml)'
        $replacementBody = $bodyText + $newline + $newline
        $PageText = [regex]::Replace($PageText, $sectionPattern, { param($sectionMatch) $sectionMatch.Groups[1].Value + $replacementBody })
    }
    $PageText
}

function Undo-LineWrap {
    # platyPS renders every paragraph one sentence per line, wrapped around 70 chars. Raw markdown reads like a ransom note. Rejoin each paragraph onto a single line.
    param([string]$PageText)
    $srcLines    = $PageText -split "\r?\n"
    $outLines    = [System.Collections.Generic.List[string]]::new()
    $paragraph   = $null
    $insideFence = $false
    $lineIndex   = 0

    # The YAML header passes through untouched (still present at this stage of the pipeline)
    if ($srcLines[0] -eq '---') {
        $outLines.Add($srcLines[0])
        $lineIndex = 1
        while ($lineIndex -lt $srcLines.Count) {
            $outLines.Add($srcLines[$lineIndex])
            $lineIndex++
            if ($srcLines[$lineIndex - 1] -eq '---') { break }
        }
    }

    for (; $lineIndex -lt $srcLines.Count; $lineIndex++) {
        $srcLine = $srcLines[$lineIndex]

        if ($srcLine -match '^```') {
            if ($null -ne $paragraph) { $outLines.Add($paragraph); $paragraph = $null }
            $insideFence = !$insideFence
            $outLines.Add($srcLine)
            continue
        }
        if ($insideFence) { $outLines.Add($srcLine); continue }

        if ($srcLine -notmatch '\S' -or $srcLine -match '^(#|>|<)' -or $srcLine -match '^\s*\|' -or $srcLine -match '^\[[^\]]*\]\([^)]*\)$') {
            if ($null -ne $paragraph) { $outLines.Add($paragraph); $paragraph = $null }
            $outLines.Add($srcLine)
            continue
        }

        # A list item opens its own line. Following plain lines are its continuation and join onto it.
        if ($srcLine -match '^\s*([-*+]|\d+\.)\s') {
            if ($null -ne $paragraph) { $outLines.Add($paragraph) }
            $paragraph = $srcLine.TrimEnd()
            continue
        }

        # Plain text joins the open paragraph
        $paragraph = if ($null -eq $paragraph) { $srcLine.TrimEnd() } else { "$paragraph $($srcLine.Trim())" }
    }
    if ($null -ne $paragraph) { $outLines.Add($paragraph) }

    $outLines -join $newline
}

function Hide-YamlBlock {
    # GitHub renders details/summary. No way to expand them all without scripting so every block just ships closed.
    param([string]$PageText)
    [regex]::Replace($PageText, '(?ms)^```yaml\r\n.*?^```\r\n', {
        param($blockMatch)
        $yamlBody = $blockMatch.Value
        $typeName = if ($yamlBody -match '(?m)^Type:\s*(.+?)\s*$') { $Matches[1] } else { $null }
        $required = if ($yamlBody -match '(?m)^Required:\s*True') { 'required' } elseif ($yamlBody -match '(?m)^Required:\s*False') { 'optional' } else { $null }
        $summary  = if ($typeName -and $required) { "Type: $typeName ($required)" } elseif ($typeName) { "Type: $typeName" } else { 'Details' }
        "<details><summary>$summary</summary>$newline$newline" + $blockMatch.Value.TrimEnd() + "$newline$newline</details>$newline"
    })
}

function Merge-CommandFolder {
    param([string]$PageText, [string]$CommandName)
    $overlayFolder = Get-CommandFolder $CommandName
    if (!(Test-Path $overlayFolder)) { return $PageText }

    # Screenshots go at the end of their example block,before the next heading
    $imagePrefix = "../../../pages/$($categoryByCommand[$CommandName])/$CommandName"
    foreach ($imageFile in Get-ChildItem $overlayFolder -File | Where-Object { $_.Name -cmatch '^example([1-9][0-9]*)\.(png|gif)$' }) {
        $exampleNumber = [int]($imageFile.Name -creplace '^example([1-9][0-9]*)\.(png|gif)$', '$1')
        $headingIndex  = $PageText.IndexOf("### EXAMPLE $exampleNumber$newline")
        if ($headingIndex -lt 0) { continue }

        # Centered to match the README's image treatment
        $imageMarkdown    = '<p align="center"><img src="' + "$imagePrefix/$($imageFile.Name)" + '" alt=""></p>' + $newline + $newline
        $nextHeadingIndex = @($PageText.IndexOf("$newline### ", $headingIndex + 1), $PageText.IndexOf("$newline## ", $headingIndex + 1)) |
                            Where-Object { $_ -ge 0 } | Sort-Object | Select-Object -First 1
        if ($null -ne $nextHeadingIndex) { $PageText = $PageText.Insert($nextHeadingIndex + 2, $imageMarkdown) }
        else { $PageText = $PageText.TrimEnd() + $newline + $newline + $imageMarkdown.TrimEnd() + $newline }
    }

    # The overview shot and head.md land directly under the H1, image first
    $underH1  = [System.Collections.Generic.List[string]]::new()
    if (Test-Path (Join-Path $overlayFolder 'overview.png')) { $underH1.Add('<p align="center"><img src="' + "$imagePrefix/overview.png" + '" alt=""></p>') }
    $headPath = Join-Path $overlayFolder 'head.md'
    if (Test-Path $headPath) { $underH1.Add(((Get-Content $headPath -Raw) -replace '\r?\n', $newline).Trim()) }
    if ($underH1.Count) {
        $h1End    = $PageText.IndexOf($newline) + 2
        $PageText = $PageText.Insert($h1End, $newline + ($underH1 -join "$newline$newline") + $newline)
    }

    # foot.md ahead of RELATED LINKS so the links stay
    $footPath = Join-Path $overlayFolder 'foot.md'
    if (Test-Path $footPath) {
        $footText     = ((Get-Content $footPath -Raw) -replace '\r?\n', $newline).Trim()
        $relatedIndex = $PageText.IndexOf("## RELATED LINKS")
        if ($relatedIndex -ge 0) { $PageText = $PageText.Insert($relatedIndex, $footText + $newline + $newline) }
        else { $PageText = $PageText.TrimEnd() + $newline + $newline + $footText + $newline }
    }
    $PageText
}

function Build-Page {
    # Returns the final composed page text, or $null for a command with no page yet
    param([string]$CommandName, [string]$GenDir)

    # Two transforms here. The YAML header strip (New-UiWindow's page.md keeps its as New-ExternalHelp input, the published copy drops it), then example screenshots compose in like on any other page. The MAML compile reads the raw page.md... Get-Help never sees the img tags.
    $overridePath = Join-Path (Get-CommandFolder $CommandName) 'page.md'
    if (Test-Path $overridePath) { return Merge-CommandFolder -PageText (Remove-YamlHeader ((Get-Content $overridePath -Raw) -replace '\r?\n', $newline)) -CommandName $CommandName }
    if ($deferredPages -contains $CommandName) { return $null }

    $pageText = (Get-Content (Join-Path $GenDir "$CommandName.md") -Raw) -replace '\r?\n', $newline
    $pageText = Remove-ProgressAction $pageText
    $pageText = Update-ParamHelp -PageText $pageText -CommandName $CommandName
    $pageText = Undo-LineWrap $pageText
    $pageText = Remove-YamlHeader $pageText
    $pageText = Hide-YamlBlock $pageText
    Merge-CommandFolder -PageText $pageText -CommandName $CommandName
}

function Build-Maml {
    # Get-Help for the binary cmdlet, page.md is the source and New-ExternalHelp compiles it to MAML. The details wrap and the flat wiki links are publish side stuff the MAML must not see, so the details lines get dropped and RELATED LINKS expand to full wiki URLs.
    $overrideCmdlets = @($exported | Where-Object { (Get-Command $_).CommandType -eq 'Cmdlet' -and (Test-PageMd $_) })
    if (!$overrideCmdlets) { return $null }

    $mamlGenDir = Join-Path ([IO.Path]::GetTempPath()) "psui-maml-gen-$PID"
    if (Test-Path $mamlGenDir) { Remove-Item $mamlGenDir -Recurse -Force }
    $null = New-Item $mamlGenDir -ItemType Directory
    foreach ($commandName in $overrideCmdlets) {
        $pageText = (Get-Content (Join-Path (Get-CommandFolder $commandName) 'page.md') -Raw) -replace '\r?\n', $newline
        $pageText = $pageText -replace '(?m)^<details><summary>.*</summary>\r?\n', ''
        $pageText = $pageText -replace '(?m)^</details>\r?\n', ''
        # \r? before $ matters: multiline $ only matches ahead of \n, and these lines end CRLF
        $pageText = [regex]::Replace($pageText, '(?m)^\[([^\]]+)\]\((?!https?:)([^)/]+)\)\r?$', '[$1](https://github.com/jlabon2/PsUi/wiki/$2)')
        [IO.File]::WriteAllText((Join-Path $mamlGenDir "$commandName.md"), $pageText, [System.Text.UTF8Encoding]::new($false))
    }

    $mamlOutDir = Join-Path $mamlGenDir 'out'
    $null = New-ExternalHelp -Path $mamlGenDir -OutputPath $mamlOutDir -Force
    $helpFile = Get-ChildItem $mamlOutDir -Filter *.xml | Select-Object -First 1
    $helpXml  = (Get-Content $helpFile.FullName -Raw) -replace '\r?\n', $newline
    Remove-Item $mamlGenDir -Recurse -Force
    $helpXml
}

function Build-Reference {
    # Writes every page under $OutputRoot (only files whose content changed), returns the relative paths that belong in the tree.
    param([string]$OutputRoot)

    # One New-MarkdownHelp scaffolds fresh and never reads an existing page. -Force only ever touches this temp folder.
    $genDir = Join-Path ([IO.Path]::GetTempPath()) "psui-docs-gen-$PID"
    if (Test-Path $genDir) { Remove-Item $genDir -Recurse -Force }
    $generateNames = @($exported | Where-Object { $deferredPages -notcontains $_ -and !(Test-PageMd $_) })
    $null = New-MarkdownHelp -Command $generateNames -OutputFolder $genDir -Force

    $treePaths = [System.Collections.Generic.List[string]]::new()
    foreach ($commandName in $exported) {
        $pageText = Build-Page -CommandName $commandName -GenDir $genDir
        if ($null -eq $pageText) { continue }

        $relativePath = Join-Path $categoryByCommand[$commandName] "$commandName.md"
        $outPath      = Join-Path $OutputRoot $relativePath
        $outDir       = Split-Path $outPath -Parent
        if (!(Test-Path $outDir)) { $null = New-Item $outDir -ItemType Directory -Force }
        if (!(Test-UpToDate $outPath $pageText)) {
            [IO.File]::WriteAllText($outPath, $pageText, [System.Text.UTF8Encoding]::new($false))
        }
        $treePaths.Add($relativePath)
    }
    Remove-Item $genDir -Recurse -Force
    $treePaths
}

function Build-Index {
    # Wiki links are flat names regardless of subfolder. Single EOL throughout (mixed EOLs break the byte compare).
    $sectionNames = [ordered]@{
        window  = 'Windows'
        layout  = 'Layout'
        buttons = 'Buttons and Actions'
        inputs  = 'Inputs'
        display = 'Display'
        charts  = 'Charts'
        status  = 'Status and Progress'
        list    = 'Lists, Grids, Trees, and Menus'
        output  = 'Standalone Viewers and Output'
        dialogs = 'Dialogs and Pickers'
        tool    = 'Form Generation'
        session = 'Session, Theming, Icons, and Async'
    }
    $indexLines = [System.Collections.Generic.List[string]]::new()
    $indexLines.Add('# Command Index')
    $indexLines.Add('')
    $indexLines.Add('<!-- Generated by Build-Docs.ps1. Do not edit. Your changes will be overwritten. -->')
    foreach ($sectionKey in $sectionNames.Keys) {
        $sectionCommands = $exported | Where-Object { $categoryByCommand[$_] -eq $sectionKey }
        if (!$sectionCommands) { continue }
        $indexLines.Add('')
        $indexLines.Add("## $($sectionNames[$sectionKey])")
        $indexLines.Add('')
        $indexLines.Add('| Command | Synopsis |')
        $indexLines.Add('|---------|----------|')
        foreach ($commandName in $sectionCommands) {
            if ($deferredPages -contains $commandName -and !(Test-PageMd $commandName)) {
                $indexLines.Add("| $commandName | (reference page pending) |")
                continue
            }
            # A page.md command has no comment help behind it so Get-Help would hand the index its raw syntax string. Read the page's own SYNOPSIS line instead.
            if (Test-PageMd $commandName) {
                $overrideText = Get-Content (Join-Path (Get-CommandFolder $commandName) 'page.md') -Raw
                $synopsis     = if ($overrideText -match '(?m)^## SYNOPSIS[ \t]*\r?\n(.+)$') { $Matches[1].Trim() } else { '' }
            }
            else {
                $synopsis = ((Get-Help $commandName).Synopsis -replace '\s*\r?\n\s*', ' ').Trim()
            }
            $indexLines.Add("| [$commandName]($commandName) | $synopsis |")
        }
    }
    ($indexLines -join $newline) + $newline
}

function Test-PagesFolder {
    # Naming is checked case sensitively on purpose: Windows happily matches the wrong case, then the wiki's case sensitive URLs 404 every image ref.
    param([System.Collections.Generic.List[string]]$Problems, [string]$ComposedRoot)
    if (!(Test-Path $overlayRoot)) { return }
    foreach ($categoryFolder in Get-ChildItem $overlayRoot -Directory) {
        foreach ($commandFolder in Get-ChildItem $categoryFolder.FullName -Directory) {
            $folderName = $commandFolder.Name
            if ($exported -cnotcontains $folderName) {
                $Problems.Add("overlay folder $($categoryFolder.Name)/$folderName matches no exported command (exact case required)")
                continue
            }
            if ($categoryByCommand[$folderName] -cne $categoryFolder.Name) {
                $Problems.Add("overlay folder for $folderName sits under $($categoryFolder.Name)/ but its category is $($categoryByCommand[$folderName])/ (it gets silently ignored there)")
                continue
            }

            $hasOverride = Test-Path (Join-Path $commandFolder.FullName 'page.md')
            foreach ($overlayFile in Get-ChildItem $commandFolder.FullName -File) {
                $fileName = $overlayFile.Name
                if ($fileName -cin 'head.md', 'foot.md', 'overview.png') {
                    if ($hasOverride) { $Problems.Add("$folderName has page.md plus $fileName (page.md has the whole page)") }
                    continue
                }
                if ($fileName -ceq 'page.md') { continue }
                if ($fileName -cmatch '^example([1-9][0-9]*)\.(png|gif)$') {
                    $exampleNumber = [int]$Matches[1]
                    # Checked from the png side only, so the pair reports once
                    if ($Matches[2] -eq 'png' -and (Test-Path (Join-Path $commandFolder.FullName "example$exampleNumber.gif"))) { $Problems.Add("$folderName has example$exampleNumber as both png and gif (the page would show it twice)") }
                    $pagePath      = Join-Path $ComposedRoot $categoryByCommand[$folderName] "$folderName.md"
                    $pageExamples  = if (Test-Path $pagePath) { @([regex]::Matches((Get-Content $pagePath -Raw), '(?m)^### EXAMPLE (\d+)') | ForEach-Object { [int]$_.Groups[1].Value }) } else { @() }
                    if ($pageExamples -notcontains $exampleNumber) { $Problems.Add("$folderName/$fileName has no EXAMPLE $exampleNumber on the page") }
                    continue
                }
                if ($fileName -match '^example.*\.(png|gif)$') { $Problems.Add("$folderName/$fileName is not a valid screenshot name: example<N>.png or .gif, 1-based. Use exact case") }
                else { $Problems.Add("$folderName/$fileName is not one of the overlay files (head.md, foot.md, page.md, overview.png, example<N>.png/.gif)") }
            }
        }
    }
}

$problems = [System.Collections.Generic.List[string]]::new()

if ($Verify) {
    # Everything runs against a scratch build so a failed check never taints the repo
    if (!(Test-Path $referenceDir)) { throw 'docs/wiki/reference does not exist. Run Build-Docs.ps1 without -Verify first.' }
    $scratchDir = Join-Path ([IO.Path]::GetTempPath()) "psui-docs-check-$PID"
    if (Test-Path $scratchDir) { Remove-Item $scratchDir -Recurse -Force }
    $null = New-Item $scratchDir -ItemType Directory

    $treePaths = Build-Reference -OutputRoot $scratchDir

    # Both directions since a stale extra page would otherwise ship to the wiki forever with green CI
    $committedPaths = @(Get-ChildItem $referenceDir -Recurse -Filter *.md | ForEach-Object { [IO.Path]::GetRelativePath($referenceDir, $_.FullName) })
    foreach ($pathDrift in Compare-Object @($treePaths) $committedPaths) {
        if ($pathDrift.SideIndicator -eq '<=') { $problems.Add("page not committed: $($pathDrift.InputObject) (run Build-Docs.ps1 and commit)") }
        else { $problems.Add("orphan committed page: $($pathDrift.InputObject) (no exported command produces it)") }
    }

    # Compare on the intersection
    foreach ($relativePath in $treePaths) {
        $committedFile = Join-Path $referenceDir $relativePath
        if (!(Test-Path $committedFile)) { continue }
        if ((Get-FileHash (Join-Path $scratchDir $relativePath)).Hash -ne (Get-FileHash $committedFile).Hash) {
            $problems.Add("stale committed page: $relativePath (run Build-Docs.ps1 and commit)")
        }
    }

    # The index is part of the artifact set
    if (!(Test-UpToDate $indexPath (Build-Index))) {
        $problems.Add('stale Command-Index.md (run Build-Docs.ps1 and commit)')
    }

    # Leftover stubs mean a parameter lost its source help (Update-ParamHelp restubs an empty one) or a command has no .EXAMPLE ({{ Add example code here }})
    foreach ($stub in Get-ChildItem $scratchDir -Recurse -Filter *.md | Select-String -Pattern '\{\{ (Fill|Add) ' -List) {
        $problems.Add("unfilled placeholder in $(Split-Path $stub.Path -Leaf)")
    }

    # Exactly one H1 outside code per page, matching the filename. Also polices head.md/foot.md, where an H1 lands a second H1 on the composed page.
    foreach ($page in Get-ChildItem $scratchDir -Recurse -Filter *.md) {
        $insideFence = $false
        $h1Lines     = [System.Collections.Generic.List[string]]::new()
        foreach ($pageLine in Get-Content $page.FullName) {
            if ($pageLine -match '^```') { $insideFence = !$insideFence; continue }
            if (!$insideFence -and $pageLine -match '^# ') { $h1Lines.Add($pageLine) }
        }
        if ($h1Lines.Count -ne 1 -or $h1Lines[0] -ne "# $($page.BaseName)") {
            $problems.Add("H1 problem in $($page.Name): $($h1Lines.Count) bare H1 line(s) outside fences")
        }
    }

    # Page parameter headings match the live command surface
    foreach ($commandName in $exported) {
        $pagePath = Join-Path $scratchDir $categoryByCommand[$commandName] "$commandName.md"
        if (!(Test-Path $pagePath)) { continue }
        $documented  = @(Select-String -Path $pagePath -Pattern '^### -(\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value })
        $liveCommand = Get-Command $commandName
        # WhatIf/Confirm filter only when they're the switches ShouldProcess injects. A real parameter sharing the name (New-UiResultAction's [string]$Confirm) is part of the surface.
        $actual      = @($liveCommand.Parameters.Keys | Where-Object {
            if ($commonParams -notcontains $_) { return $true }
            $_ -in @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters) -and $liveCommand.Parameters[$_].ParameterType -ne [System.Management.Automation.SwitchParameter]
        })
        $paramDrift = Compare-Object $documented $actual
        if ($paramDrift) { $problems.Add("parameter drift in ${commandName}: $(($paramDrift | ForEach-Object { "$($_.SideIndicator)$($_.InputObject)" }) -join ' ')") }
    }

    # Backticks pass through unescaped, so a stray one can pair with a real code span and swallow the text between them. Pair runs the way CommonMark does (an opener closes at the next run of the same length) and flag whatever never closes. A literal backtick belongs inside double backtick delimiters.
    foreach ($page in Get-ChildItem $scratchDir -Recurse -Filter *.md) {
        foreach ($bodyMatch in [regex]::Matches((Get-Content $page.FullName -Raw), '(?ms)^### -(\S+)\r\n(.*?)(?=^<details|^```yaml)')) {
            $runLengths = @([regex]::Matches($bodyMatch.Groups[2].Value, '`+') | ForEach-Object { $_.Value.Length })
            $runIndex   = 0
            while ($runIndex -lt $runLengths.Count) {
                $closerIndex = -1
                for ($j = $runIndex + 1; $j -lt $runLengths.Count; $j++) {
                    if ($runLengths[$j] -eq $runLengths[$runIndex]) { $closerIndex = $j; break }
                }
                if ($closerIndex -lt 0) {
                    $problems.Add("unmatched backtick in $($page.BaseName) -$($bodyMatch.Groups[1].Value) (wrap a literal backtick in double backtick delimiters)")
                    break
                }
                $runIndex = $closerIndex + 1
            }
        }
    }

    Test-PagesFolder -Problems $problems -ComposedRoot $scratchDir

    # The binary cmdlet's Get-Help MAML is a build artifact too
    $expectedHelpXml = Build-Maml
    if ($null -ne $expectedHelpXml) {
        if (!(Test-UpToDate $cmdletHelpPath $expectedHelpXml)) {
            $problems.Add('stale PsUi/en-US/PsUi.dll-Help.xml (run Build-Docs.ps1 and commit)')
        }
    }

    Remove-Item $scratchDir -Recurse -Force
    if ($problems.Count) {
        $problems | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
        throw "docs-check failed with $($problems.Count) problem(s)."
    }
    Write-Host 'docs-check passed.' -ForegroundColor Green
    return
}

# Build mode regenerates in place, removes orphans, rewrites the index
$treePaths = Build-Reference -OutputRoot $referenceDir
foreach ($existingPage in Get-ChildItem $referenceDir -Recurse -Filter *.md) {
    $relativePath = [IO.Path]::GetRelativePath($referenceDir, $existingPage.FullName)
    if ($treePaths -notcontains $relativePath) {
        Remove-Item $existingPage.FullName
        Write-Host "removed orphan $relativePath"
    }
}
[IO.File]::WriteAllText($indexPath, (Build-Index), [System.Text.UTF8Encoding]::new($false))
Write-Host "built $($treePaths.Count) pages + Command-Index.md"

# The Get-Help for the binary cmdlet goes along with the docs build
$helpXml = Build-Maml
if ($null -ne $helpXml) {
    $helpDir = Split-Path $cmdletHelpPath -Parent
    if (!(Test-Path $helpDir)) { $null = New-Item $helpDir -ItemType Directory }
    if (!(Test-UpToDate $cmdletHelpPath $helpXml)) {
        [IO.File]::WriteAllText($cmdletHelpPath, $helpXml, [System.Text.UTF8Encoding]::new($false))
        Write-Host 'built PsUi/en-US/PsUi.dll-Help.xml'
    }
}

# Stubs at build mean a parameter or section has no source help. Fix the .ps1 before committing.
$stubHits = Get-ChildItem $referenceDir -Recurse -Filter *.md | Select-String -Pattern '\{\{ (Fill|Add) ' | Group-Object Path
foreach ($stubGroup in $stubHits) { Write-Warning "placeholders in $(Split-Path $stubGroup.Name -Leaf): $($stubGroup.Count)" }
