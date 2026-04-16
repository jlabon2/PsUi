<#
.SYNOPSIS
    Builds the PsUi C# backend into framework-specific DLLs.
.DESCRIPTION
    Compiles the C# source in ./src to DLLs targeting both .NET Framework 4.7.2 
    (for PowerShell 5.1) and .NET 6.0 (for PowerShell 7+).
    
    Output is placed in ./PsUi/lib/desktop/ and ./PsUi/lib/core/
    
    Includes WebView2 dependencies for embedded browser support.
.PARAMETER Configuration
    Build configuration: Debug or Release. Default is Release.
.EXAMPLE
    .\Build-PsUi.ps1
.EXAMPLE
    .\Build-PsUi.ps1 -Configuration Debug
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$srcPath = Join-Path $projectRoot 'src'
$modulePath = Join-Path $projectRoot 'PsUi'

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

# Clean previous builds
$libPath = Join-Path $modulePath 'lib'
if (Test-Path $libPath) {
    Remove-Item $libPath -Recurse -Force
}

# Build
Push-Location $srcPath
try {
    dotnet build -c $Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

# Clean up SDK artifacts that shouldn't be in the module
$net6Path = Join-Path $libPath 'net6.0-windows'
$net472Path = Join-Path $libPath 'net472'

# Remove known SDK artifacts and keep only PsUi + WebView2
$keepFiles = @('PsUi.dll', 'Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.Wpf.dll')
$keepFolders = @('runtimes')

foreach ($frameworkPath in @($net6Path, $net472Path)) {
    if (!(Test-Path $frameworkPath)) { continue }
    
    # Remove unwanted files (SDK dependencies we don't need)
    Get-ChildItem $frameworkPath -File | Where-Object { $_.Name -notin $keepFiles } | Remove-Item -Force -ErrorAction SilentlyContinue
    
    # Remove unwanted folders (localization, ref assemblies, etc.)
    Get-ChildItem $frameworkPath -Directory | Where-Object { $_.Name -notin $keepFolders } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# Clean up WebView2 runtimes and copy native loader to lib root
function Clean-WebView2Runtimes {
    param([string]$TargetPath)
    
    $runtimesPath = Join-Path $TargetPath 'runtimes'
    if (!(Test-Path $runtimesPath)) { return }
    
    # Copy WebView2Loader.dll for each architecture to lib folder root
    $platforms = @(
        @{ Arch = 'win-x64'; Suffix = '' }       # Default for x64 (most common)
        @{ Arch = 'win-x86'; Suffix = '.x86' }   # Fallback for x86
    )
    
    foreach ($plat in $platforms) {
        $srcLoader = Join-Path $runtimesPath "$($plat.Arch)\native\WebView2Loader.dll"
        if (Test-Path $srcLoader) {
            $dstLoader = Join-Path $TargetPath "WebView2Loader$($plat.Suffix).dll"
            Copy-Item $srcLoader $dstLoader -Force
        }
    }
    
    # Remove runtimes folder - native DLLs now in lib root
    Remove-Item $runtimesPath -Recurse -Force -ErrorAction SilentlyContinue
}

Clean-WebView2Runtimes -TargetPath $net6Path
Clean-WebView2Runtimes -TargetPath $net472Path

# Rename framework folders to edition-agnostic names (future-proofing)
$desktopPath = Join-Path $libPath 'desktop'
$corePath = Join-Path $libPath 'core'

if (Test-Path $net472Path) {
    if (Test-Path $desktopPath) { Remove-Item $desktopPath -Recurse -Force }
    Rename-Item $net472Path $desktopPath
}

if (Test-Path $net6Path) {
    if (Test-Path $corePath) { Remove-Item $corePath -Recurse -Force }
    Rename-Item $net6Path $corePath
}

# Verify output
Write-Host ""
Write-Host "Build complete. Output:" -ForegroundColor Green

$desktopDll = Join-Path $modulePath 'lib\desktop\PsUi.dll'
$coreDll = Join-Path $modulePath 'lib\core\PsUi.dll'

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
