# PSScriptAnalyzer Settings for PsUi
# Matches project code style guide

@{
    # Formatting rules
    Rules = @{
        # 1TBS/K&R bracing - opening brace on same line
        PSPlaceOpenBrace = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }

        # Closing brace on its own line
        PSPlaceCloseBrace = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }

        # Use consistent indentation (4 spaces)
        PSUseConsistentIndentation = @{
            Enable              = $true
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind                = 'space'
        }

        # Consistent whitespace
        PSUseConsistentWhitespace = @{
            Enable                                  = $true
            CheckInnerBrace                         = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $true
            CheckPipe                               = $true
            CheckPipeForRedundantWhitespace         = $false
            CheckSeparator                          = $true
            CheckParameter                          = $false
            IgnoreAssignmentOperatorInsideHashTable = $false
        }

        # Align assignment statements in hashtables
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }

        # Auto-correct aliases to full cmdlet names
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }

        # Use correct casing for cmdlets and types
        PSUseCorrectCasing = @{
            Enable = $true
        }
    }

    # Exclude rules that conflict with style guide
    ExcludeRules = @(
        # We allow Write-Host for UI output
        'PSAvoidUsingWriteHost'
    )
}
