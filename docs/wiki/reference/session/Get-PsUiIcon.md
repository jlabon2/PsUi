# Get-PsUiIcon

## SYNOPSIS
Gets an icon glyph by name.

## SYNTAX

```
Get-PsUiIcon [-Name] <String> [<CommonParameters>]
```

## DESCRIPTION
Resolves an icon name to its glyph character from the shared icon map. Both icon fonts (Segoe MDL2 Assets and Segoe Fluent Icons) read the same map, so a name can resolve to a glyph the active font doesn't carry - Test-PsUiIcon says which ones. Warns and returns nothing for unknown names.

## EXAMPLES

### EXAMPLE 1
```
Get-PsUiIcon -Name 'Save'
```

### EXAMPLE 2
```
New-UiLabel -Text ((Get-PsUiIcon Check) + ' Done')
```

## PARAMETERS

### -Name
The icon name (e.g., 'Save', 'Delete', 'Check').

<details><summary>Type: String (required)</summary>

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
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
