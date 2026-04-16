using System;
using System.Collections;
using System.Diagnostics;

namespace PsUi
{
    // Script setup: builds the init script that runs before user code in background runspaces
    public partial class AsyncExecutor
    {
        // Builds the setup script: Write-Host override, Read-Host override, module imports, function defs
        private string BuildSetupScript(IDictionary functionsToDefine, System.Collections.Generic.IEnumerable<string> modulesToLoad, bool debugEnabled = false)
        {
            var sb = new System.Text.StringBuilder();

            // Force UTF-8 encoding for proper character handling in output
            sb.AppendLine("[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $global:OutputEncoding = [System.Text.Encoding]::UTF8");

            if (debugEnabled)
            {
                sb.AppendLine("$DebugPreference = 'Continue'");
            }

            // Override Write-Host with an alias so it takes precedence over the cmdlet.
            // This only lives in background runspaces - the user's interactive session is untouched.
            // Each runspace is ephemeral and dies after script completion, so no pollution.
            sb.AppendLine(@"
function Global:__PsUi_WriteHost {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [object]$Object,
        [Parameter(ValueFromRemainingArguments=$true)]
        [object[]]$RemainingArgs,
        [switch]$NoNewline,
        [ConsoleColor]$ForegroundColor,
        [ConsoleColor]$BackgroundColor,
        [string]$Separator = ' '
    )
    begin { $allObjects = [System.Collections.Generic.List[object]]::new() }
    process { 
        if ($null -ne $Object) { $allObjects.Add($Object) }
    }
    end {
        # Add any remaining arguments (Write-Host 'a' 'b' 'c' pattern)
        if ($RemainingArgs) {
            foreach ($arg in $RemainingArgs) {
                if ($null -ne $arg) { $allObjects.Add($arg) }
            }
        }
        $message = $allObjects -join $Separator
        if ($Global:AsyncExecutor) {
            $fg = if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $ForegroundColor } else { $null }
            $bg = if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $BackgroundColor } else { $null }
            $Global:AsyncExecutor.RaiseOnHost($message, $fg, $bg, [bool]$NoNewline)
        }
    }
}
Set-Alias -Name 'Write-Host' -Value '__PsUi_WriteHost' -Scope Global -Force
");

            // Override Read-Host to marshal input requests to the UI thread
            sb.AppendLine(@"
function Global:Read-Host {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string]$Prompt,
        [switch]$AsSecureString
    )
    if ($Global:AsyncExecutor) {
        if ($AsSecureString) {
            return $Global:AsyncExecutor.RaiseOnReadLineAsSecureString($Prompt)
        }
        else {
            return $Global:AsyncExecutor.RaiseOnReadLine($Prompt)
        }
    }
}
");

            // Override Clear-Host to clear the output panel
            sb.AppendLine(@"
function Global:Clear-Host {
    if ($Global:AsyncExecutor) {
        $Global:AsyncExecutor.RaiseOnClearHost()
    }
}
");

            // Override Pause - remove native alias/command first, then define our function
            sb.AppendLine(@"
Remove-Item -Path Function:Pause -ErrorAction SilentlyContinue
Remove-Item -Path Alias:Pause -ErrorAction SilentlyContinue
function Global:Pause {
    if ($Global:AsyncExecutor) {
        $Global:AsyncExecutor.RaiseOnPause()
    }
    else {
        $null = Read-Host 'Press Enter to continue...'
    }
}
");

            // Override Out-Host to route output to our host
            // Remove the alias first (if any), then define our function
            sb.AppendLine(@"
Remove-Item -Path Alias:Out-Host -ErrorAction SilentlyContinue
function Global:Out-Host {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]$InputObject,
        [switch]$Paging
    )
    begin {
        $collector = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -ne $InputObject) { $collector.Add($InputObject) }
    }
    end {
        if ($collector.Count -eq 0) { return }
        if ($Global:AsyncExecutor) {
            # Format all collected objects to text
            $text = ($collector | Out-String -Width 120).TrimEnd()
            if ($text) {
                $Global:AsyncExecutor.RaiseOnHost($text)
            }
        }
    }
}
");

            // Import linked modules (escape single quotes in paths)
            if (modulesToLoad != null)
            {
                foreach (string mod in modulesToLoad)
                {
                    if (!string.IsNullOrWhiteSpace(mod))
                    {
                        string escapedMod = mod.Replace("'", "''");
                        sb.AppendFormat("Import-Module '{0}' -ErrorAction SilentlyContinue\n", escapedMod);
                    }
                }
            }

            // Define caller-provided functions (validated identifiers only)
            if (functionsToDefine != null)
            {
                foreach (DictionaryEntry kvp in functionsToDefine)
                {
                    try
                    {
                        string name = kvp.Key.ToString();
                        if (!Constants.IsValidIdentifier(name)) continue;

                        string definition = kvp.Value.ToString();
                        sb.AppendFormat("function Global:{0} {{ {1} }}\n", name, definition);
                    }
                    catch (Exception ex) { Debug.WriteLine("AsyncExecutor Function Definition Error: " + ex.Message); }
                }
            }

            // We inject ALL private functions (~110 of them) into every async runspace. Yeah it's
            // ~40ms overhead, but they have interdependencies (Get-ThemeColors -> Get-ContrastColor)
            // and selective injection would be fragile. Reliability wins over latency here.
            
            // Inject private helper functions from ModuleContext
            var privateFuncs = ModuleContext.PrivateFunctions;
            if (privateFuncs != null && privateFuncs.Count > 0)
            {
                foreach (DictionaryEntry kvp in privateFuncs)
                {
                    try
                    {
                        string name = kvp.Key.ToString();
                        string definition = kvp.Value.ToString();
                        sb.AppendFormat("function Global:{0} {{ {1} }}\n", name, definition);
                    }
                    catch (Exception ex) { Debug.WriteLine("AsyncExecutor Private Function Definition Error: " + ex.Message); }
                }
            }

            // Inject public functions commonly used in button actions (curated list, not all public funcs)
            var publicFuncs = ModuleContext.PublicFunctions;
            if (publicFuncs != null && publicFuncs.Count > 0)
            {
                foreach (DictionaryEntry kvp in publicFuncs)
                {
                    try
                    {
                        string name = kvp.Key.ToString();
                        string definition = kvp.Value.ToString();
                        sb.AppendFormat("function Global:{0} {{ {1} }}\n", name, definition);
                    }
                    catch (Exception ex) { Debug.WriteLine("AsyncExecutor Public Function Definition Error: " + ex.Message); }
                }
            }

            return sb.ToString();
        }
    }
}
