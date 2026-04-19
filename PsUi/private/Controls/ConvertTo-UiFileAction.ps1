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

    # Build sanitized argument strings per target shell
    # cmd.exe metacharacters that enable injection: & | < > ^ % !
    # These must be escaped (^-prefixed) when passed to cmd.exe /c
    $cmdArgString = ''
    $psArgString  = ''

    if ($ArgumentList -and $ArgumentList.Count -gt 0) {
        $cmdArgValues = @($ArgumentList.Values | ForEach-Object {
            $val = $_.ToString()
            # Escape cmd metacharacters by prefixing with ^
            $safe = $val -replace '([&|<>^%!])', '^$1'
            if ($safe -match '\s') { "`"$safe`"" } else { $safe }
        })
        $cmdArgString = $cmdArgValues -join ' '

        $psArgValues = @($ArgumentList.Values | ForEach-Object {
            # Single-quote each value so PS treats it as a literal string
            $val = $_.ToString().Replace("'", "''")
            "'$val'"
        })
        $psArgString = $psArgValues -join ' '
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
            if ($cmdArgString) { $Action = [scriptblock]::Create("cmd.exe /c `"$escapedPath`" $cmdArgString") }
            else { $Action = [scriptblock]::Create("cmd.exe /c `"$escapedPath`"") }
        }

        '.vbs' {
            if ($cmdArgString) { $Action = [scriptblock]::Create("cscript.exe //nologo `"$escapedPath`" $cmdArgString") }
            else { $Action = [scriptblock]::Create("cscript.exe //nologo `"$escapedPath`"") }
        }

        '.exe' {
            if ($psArgString) { $Action = [scriptblock]::Create("& '$escapedPath' $psArgString") }
            else { $Action = [scriptblock]::Create("& '$escapedPath'") }
        }
    }

    return $Action
}
