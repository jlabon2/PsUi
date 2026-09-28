# Reset-UiSession

## SYNOPSIS
Resets the PsUi module state after a crash or error.

## SYNTAX

```
Reset-UiSession [<CommonParameters>]
```

## DESCRIPTION
Clears all active sessions, resets the ThemeEngine, shuts down the runspace pool. Use this when a script crashes mid-execution and you can't run New-UiWindow again in the same console. Or don't want to restart the console for whatever reason.

## EXAMPLES

### EXAMPLE 1
```
Reset-UiSession
# Now you can run New-UiWindow again
```

## PARAMETERS

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

## RELATED LINKS
