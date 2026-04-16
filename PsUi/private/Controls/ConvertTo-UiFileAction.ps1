function ConvertTo-UiFileAction {
    <#
    .SYNOPSIS
        Converts a file path to a secure scriptblock for button execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$File,

        [hashtable]$ArgumentList
    )

    # Resolve to absolute path (handles relative paths like .\script.ps1)
    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($File)

    # Security: Validate the file exists at button creation time
    if (!(Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "File not found: '$resolvedPath'. The file must exist when the button is created."
    }

    # Security: Validate the path doesn't contain injection characters
    # The path will be embedded in a scriptblock, so we need to ensure it's safe
    if ($resolvedPath -match '[`$\{\}]') {
        throw "Invalid file path: '$resolvedPath'. Path contains characters that could cause script injection."
    }

    $extension = [System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()
    $supportedExtensions = @('.ps1', '.bat', '.cmd', '.vbs', '.exe')

    if ($extension -notin $supportedExtensions) {
        throw "Unsupported file type: '$extension'. Supported types: $($supportedExtensions -join ', ')"
    }

    # Escape single quotes in path for embedding in scriptblock
    $escapedPath = $resolvedPath.Replace("'", "''")

    # Build argument string from hashtable values (used by bat/cmd/vbs/exe)
    $argString = ''
    if ($ArgumentList -and $ArgumentList.Count -gt 0) {
        $argValues = @($ArgumentList.Values | ForEach-Object { 
            $val = $_.ToString()
            if ($val -match '\s') { "`"$val`"" } else { $val }
        })

        $argString = $argValues -join ' '
    }

    # Build the scriptblock based on file type
    switch ($extension) {
        '.ps1' {
            if ($ArgumentList -and $ArgumentList.Count -gt 0) {

                # For ps1 with arguments, capture the args at creation time via closure
                $capturedArgs = $ArgumentList.Clone()

                $Action = {
                    $splatArgs = $capturedArgs
                    & $resolvedPath @splatArgs
                }.GetNewClosure()

            }
            else { $Action = [scriptblock]::Create("& '$escapedPath'") }
        }

        { $_ -in '.bat', '.cmd' } {
            if ($argString) { $Action = [scriptblock]::Create("cmd.exe /c `"$escapedPath`" $argString") }
            else { $Action = [scriptblock]::Create("cmd.exe /c `"$escapedPath`"") }
        }

        '.vbs' {
            if ($argString) { $Action = [scriptblock]::Create("cscript.exe //nologo `"$escapedPath`" $argString") }
            else { $Action = [scriptblock]::Create("cscript.exe //nologo `"$escapedPath`"") }
        }

        '.exe' {
            if ($argString) { $Action = [scriptblock]::Create("& '$escapedPath' $argString") }
            else { $Action = [scriptblock]::Create("& '$escapedPath'") }
        }
    }

    return $Action
}
