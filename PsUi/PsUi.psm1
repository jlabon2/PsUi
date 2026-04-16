#requires -Version 5.1

# Module state will be managed by ModuleContext C# class

# Load required WPF and Windows Forms assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# Load the pre-compiled C# backend DLL (framework-specific)
$dllLoaded = $false

# Determine the correct lib folder based on PowerShell edition
if ($PSVersionTable.PSEdition -eq 'Core') {
    $libPath = Join-Path $PSScriptRoot 'lib\core'
}
else {
    $libPath = Join-Path $PSScriptRoot 'lib\desktop'
}

$dllPath = Join-Path $libPath 'PsUi.dll'

if (Test-Path $dllPath) {
    try {
        # Load WebView2 dependencies first (they're referenced by PsUi.dll)
        $webView2Core = Join-Path $libPath 'Microsoft.Web.WebView2.Core.dll'
        $webView2Wpf  = Join-Path $libPath 'Microsoft.Web.WebView2.Wpf.dll'
        
        if (Test-Path $webView2Core) {
            [System.Reflection.Assembly]::LoadFrom($webView2Core) | Out-Null
        }
        if (Test-Path $webView2Wpf) {
            [System.Reflection.Assembly]::LoadFrom($webView2Wpf) | Out-Null
        }
        
        # Import the main module DLL
        Import-Module $dllPath -Global -DisableNameChecking -Force
        $dllLoaded = $true
        Write-Verbose "Loaded PsUi backend from: $dllPath"
    }
    catch {
        Write-Warning "Failed to load PsUi backend DLL: $_"
    }
}
else {
    Write-Warning "PsUi backend DLL not found at: $dllPath"
    Write-Warning "Run Build-PsUi.ps1 from the repository root to compile the C# backend."
}

# Wire up module context now that the DLL is loaded
if ($dllLoaded) {
    [PsUi.ModuleContext]::IsInitialized = $true
    [PsUi.ModuleContext]::ModulePath = $PSScriptRoot
    try {
        [PsUi.ThemeEngine]::SetModulePath($PSScriptRoot)
    }
    catch {
        Write-Verbose "ThemeEngine module path not set: $_"
    }
    
    # Clean up orphaned WebView2 temp folders from previous sessions
    try { [PsUi.WebViewHelper]::CleanupOldUserDataFolders() } catch { }
}

# Load icon definitions from JSON resource file
$iconPath = Join-Path $PSScriptRoot 'resources\CharList.json'
if (Test-Path $iconPath) {
    try {
        $iconData = Get-Content $iconPath | ConvertFrom-Json

        # Convert PSCustomObject to Dictionary for C# ModuleContext
        $iconDict = [System.Collections.Generic.Dictionary[string,string]]::new()
        $iconData.PSObject.Properties | ForEach-Object {
            $iconDict.Add($_.Name, $_.Value)
        }

        # Hand off the icons to the C# side
        [PsUi.ModuleContext]::Initialize($iconDict)
    }
    catch {
        Write-Warning "Failed to load icons: $_"
    }
}

# Dot-source all PowerShell function files from private and public folders (including subdirectories)
foreach ($folder in @('private', 'public')) {
    $path = Join-Path $PSScriptRoot $folder
    if (Test-Path $path) {
        Get-ChildItem $path -Filter '*.ps1' -File -Recurse | ForEach-Object {
            . $_.FullName
        }
    }
}

# Register private functions in ModuleContext for injection into async runspaces.
# Private functions work inside button actions because they're injected into each async
# runspace by AsyncExecutor.Setup.cs. They're NOT exported to the user's console, but
# ARE available inside -Action scriptblocks.
$privatePath = Join-Path $PSScriptRoot 'private'
$publicPath  = Join-Path $PSScriptRoot 'public'

# Only capture PRIVATE helper functions for injection
$privateFuncs = @{}

if (Test-Path $privatePath) {
    Get-ChildItem $privatePath -Filter '*.ps1' -File -Recurse | ForEach-Object {
        $funcName = $_.BaseName
        $cmd = Get-Command -Name $funcName -CommandType Function -ErrorAction SilentlyContinue
        if ($cmd) {
            $privateFuncs[$funcName] = $cmd.Definition
        }
    }
}

[PsUi.ModuleContext]::PrivateFunctions = $privateFuncs

# Capture public functions commonly used in async button actions
# These are injected into async runspaces so they're available in background execution
$asyncPublicFuncs = @(
    'Add-UiListItem'
    'Remove-UiListItem'
    'Clear-UiList'
    'Get-UiListItems'
    'Set-UiProgress'
    'Invoke-UiAsync'
    'Get-UiSession'
    'Update-UiChart'
)

$publicFuncs = @{}
foreach ($funcName in $asyncPublicFuncs) {
    $cmd = Get-Command -Name $funcName -CommandType Function -ErrorAction SilentlyContinue
    if ($cmd) {
        $publicFuncs[$funcName] = $cmd.Definition
    }
}
[PsUi.ModuleContext]::PublicFunctions = $publicFuncs

# Store module path for async runspace Import-Module
[PsUi.ModuleContext]::ModulePath = $PSScriptRoot

# Register module unload handler to clean up RunspacePool
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    # Shut down the runspace pool first (blocks until threads drain)
    try {
        [PsUi.RunspacePoolManager]::Shutdown()
        Write-Verbose "PsUi RunspacePool shutdown complete"
    }
    catch { Write-Debug "[PsUi] RunspacePool shutdown error: $_" }

    # Reset ThemeEngine static state so re-import starts clean
    try { [PsUi.ThemeEngine]::Reset() }
    catch { Write-Debug "[PsUi] ThemeEngine reset error: $_" }

    # Dispose all active sessions
    try { [PsUi.SessionManager]::Reset() }
    catch { Write-Debug "[PsUi] SessionManager cleanup error: $_" }

    # Clear module-level statics
    try {
        [PsUi.ModuleContext]::IsInitialized = $false
        [PsUi.ModuleContext]::PrivateFunctions = $null
        [PsUi.ModuleContext]::PublicFunctions = $null
    }
    catch { Write-Debug "[PsUi] ModuleContext reset error: $_" }

    # Clean up the global session ID marker
    Remove-Variable -Name __PsUiSessionId -Scope Global -ErrorAction SilentlyContinue
}

# Build explicit export list from public folder only (private functions stay internal)
$publicFunctions = @(
    Get-ChildItem $publicPath -Filter '*.ps1' -File -Recurse |
        ForEach-Object { $_.BaseName }
)

Export-ModuleMember -Function $publicFunctions -Cmdlet 'New-UiWindow'
