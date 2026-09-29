<#
.SYNOPSIS
    Builds the PsUi C# backend into framework-specific DLLs.
.DESCRIPTION
    Compiles the C# source in ./src to DLLs for three targets: .NET Framework 4.5.2
    (WinPE), .NET Framework 4.7.2 (for 5.1) and .NET 6.0 (for 7+).

    Output is placed in ./PsUi/lib/net452/, ./PsUi/lib/desktop/ and ./PsUi/lib/core/

    Includes WebView2 dependencies for embedded browser support.
.PARAMETER Configuration
    Build configuration: Debug or Release. Default is Release.
.PARAMETER BuildDocs
    Run Build-Docs.ps1 after a successful compile, regenerating the wiki reference
    pages against the freshly built binaries. Needs PowerShell 7 on the PATH.
.EXAMPLE
    .\Build-PsUi.ps1
.EXAMPLE
    .\Build-PsUi.ps1 -Configuration Debug
.EXAMPLE
    .\Build-PsUi.ps1 -BuildDocs
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [switch]$BuildDocs
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$srcPath     = Join-Path $projectRoot 'src'
$modulePath  = Join-Path $projectRoot 'PsUi'

Write-Host "Building PsUi C# backend..." -ForegroundColor Cyan
Write-Host "  Source: $srcPath" -ForegroundColor Gray
Write-Host "  Output: $modulePath\lib\" -ForegroundColor Gray
Write-Host "  Config: $Configuration" -ForegroundColor Gray
Write-Host ""

# Bail early if the .NET SDK isn't installed
if (!(Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: 'dotnet' not found. Install the .NET SDK before building." -ForegroundColor Red
    Write-Host "  https://dotnet.microsoft.com/download" -ForegroundColor Gray
    return
}

# No wipe of lib/ up front. One locked file used to leave the module half deleted with no way back but another build, so every file is replaced on its own below.
$libPath = Join-Path $modulePath 'lib'

# Parallel builds share the obj/Release/ intermediates and collide when three frameworks write the same PsUi.dll at once.
Push-Location $srcPath
try {
    foreach ($tfm in @('net452', 'net472', 'net6.0-windows')) {
        Write-Host "  Building $tfm..." -ForegroundColor Gray
        dotnet build -c $Configuration -f $tfm
        if ($LASTEXITCODE -ne 0) { throw "Build failed for $tfm with exit code $LASTEXITCODE" }
    }
}
finally {
    Pop-Location
}

$net6Path   = Join-Path $libPath 'net6.0-windows'
$net472Path = Join-Path $libPath 'net472'
$net452Path = Join-Path $libPath 'net452'

# Remove known SDK artifacts and keep only PsUi + WebView2
$keepFiles = @('PsUi.dll', 'Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.Wpf.dll')
$keepFolders = @('runtimes')

foreach ($frameworkPath in @($net6Path, $net472Path)) {
    if (!(Test-Path $frameworkPath)) { continue }

    Get-ChildItem $frameworkPath -File | Where-Object { $_.Name -notin $keepFiles } | Remove-Item -Force -ErrorAction SilentlyContinue

    # Remove unwanted folders (localization, ref assemblies, etc.)
    Get-ChildItem $frameworkPath -Directory | Where-Object { $_.Name -notin $keepFolders } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Clean-WebView2Runtimes {
    param([string]$TargetPath)

    $runtimesPath = Join-Path $TargetPath 'runtimes'
    if (!(Test-Path $runtimesPath)) { return }

    # x64 loader keeps the raw filename, x86 gets the .x86 suffix
    $platforms = @(
        @{ Arch = 'win-x64'; Suffix = '' }
        @{ Arch = 'win-x86'; Suffix = '.x86' }
    )

    foreach ($plat in $platforms) {
        $srcLoader = Join-Path $runtimesPath "$($plat.Arch)\native\WebView2Loader.dll"
        if (Test-Path $srcLoader) {
            $dstLoader = Join-Path $TargetPath "WebView2Loader$($plat.Suffix).dll"
            Copy-Item $srcLoader $dstLoader -Force
        }
    }

    Remove-Item $runtimesPath -Recurse -Force -ErrorAction SilentlyContinue
}

Clean-WebView2Runtimes -TargetPath $net6Path
Clean-WebView2Runtimes -TargetPath $net472Path

# A file some process holds open keeps its old copy and is named at the end.
$held = [System.Collections.Generic.List[string]]::new()
function Update-LibFolder {
    param([string]$Source, [string]$Target)
    if (!(Test-Path $Source)) { return }
    $fresh = @(Get-ChildItem $Source -File)
    if ($fresh.Count -eq 0) { return }
    if (!(Test-Path $Target)) { $null = New-Item -ItemType Directory -Path $Target }

    foreach ($file in $fresh) {
        try { Copy-Item $file.FullName (Join-Path $Target $file.Name) -Force -ErrorAction Stop }
        catch { $held.Add((Join-Path $Target $file.Name)) }
    }

    # Whatever the build stopped producing goes too, unless it is held.
    foreach ($stale in @(Get-ChildItem $Target -File | Where-Object { $_.Name -notin $fresh.Name })) {
        try { Remove-Item $stale.FullName -Force -ErrorAction Stop }
        catch { $held.Add($stale.FullName) }
    }
}

Update-LibFolder -Source $net472Path -Target (Join-Path $libPath 'desktop')
Update-LibFolder -Source $net6Path   -Target (Join-Path $libPath 'core')
Remove-Item $net472Path, $net6Path -Recurse -Force -ErrorAction SilentlyContinue

# WinPE ships the DLL and its pdb and no more.
if (Test-Path $net452Path) {
    Get-ChildItem $net452Path -File | Where-Object { $_.Name -notin @('PsUi.dll', 'PsUi.pdb') } | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem $net452Path -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Build complete. Output:" -ForegroundColor Green

$desktopDll = Join-Path $modulePath 'lib\desktop\PsUi.dll'
$coreDll    = Join-Path $modulePath 'lib\core\PsUi.dll'

if (Test-Path $desktopDll) {
    $size = (Get-Item $desktopDll).Length / 1KB
    Write-Host "  [OK] desktop (PS 5.1): $([math]::Round($size, 1)) KB" -ForegroundColor Green
}
else {
    Write-Host "  [MISSING] desktop (PS 5.1)" -ForegroundColor Red
}

if (Test-Path $coreDll) {
    $size = (Get-Item $coreDll).Length / 1KB
    Write-Host "  [OK] core (PS 7+): $([math]::Round($size, 1)) KB" -ForegroundColor Green
}
else {
    Write-Host "  [MISSING] core (PS 7+)" -ForegroundColor Red
}

$net452Dll = Join-Path $modulePath 'lib\net452\PsUi.dll'
if (Test-Path $net452Dll) {
    $size = (Get-Item $net452Dll).Length / 1KB
    Write-Host "  [OK] net452 (WinPE): $([math]::Round($size, 1)) KB" -ForegroundColor Green
}
else {
    Write-Host "  [MISSING] net452 (WinPE)" -ForegroundColor Red
}

if ($held.Count -gt 0) {
    throw "Held open by another process and left at the old copy: $($held -join ', '). Close it and build again."
}

# This session's .NET types are cached. A docs build in the same process would document the DLLs from before the compile. Need to use a fresh pwsh.
if ($BuildDocs) {
    if (!(Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: -BuildDocs needs PowerShell 7 (pwsh) on the PATH." -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host "Building docs..." -ForegroundColor Cyan
    pwsh -NoProfile -File (Join-Path $projectRoot 'Build-Docs.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Docs build failed with exit code $LASTEXITCODE" }
}
