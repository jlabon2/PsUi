# Hide-UiStatusBar

## SYNOPSIS
Collapses a status bar from view without removing it.

## SYNTAX

```
Hide-UiStatusBar [[-Variable] <String>] [<CommonParameters>]
```

## DESCRIPTION
Sets Visibility to Collapsed so the bar takes no space and disappears. Safe to call from any thread. State is preserved - Show-UiStatusBar restores it.

## EXAMPLES

### EXAMPLE 1
```
Hide-UiStatusBar
```

<p align="center"><img src="../../../pages/status/Hide-UiStatusBar/example1.gif" alt=""></p>

### EXAMPLE 2
```
Hide-UiStatusBar -Variable 'mainBar'
```

## PARAMETERS

### -Variable
Optional session variable name. When omitted, the registered status bar is resolved automatically (window bars win over inline ones).

<details><summary>Type: String (optional)</summary>

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

## RELATED LINKS
