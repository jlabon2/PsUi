# Get-UiThemeTemplate

## SYNOPSIS
Returns a template hashtable showing all available theme color keys.

## SYNTAX

```
Get-UiThemeTemplate [[-Type] <String>] [-AsHashtable] [<CommonParameters>]
```

## DESCRIPTION
Outputs a hashtable with every theme key filled from the base Light or Dark palette. Copy and modify this template to create custom themes with Register-UiTheme.

## EXAMPLES

### EXAMPLE 1
```
Get-UiThemeTemplate -Type Dark
```

### EXAMPLE 2
```
$template = Get-UiThemeTemplate -AsHashtable
$template.Accent = '#FF6B6B'
Register-UiTheme -Name 'MyTheme' -Colors $template
```

## PARAMETERS

### -Type
Generate template for 'Light' or 'Dark' base theme. Defaults to 'Dark'.

<details><summary>Type: String (optional)</summary>

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: Dark
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -AsHashtable
Return raw hashtable instead of formatted output. Useful for scripting.

<details><summary>Type: SwitchParameter (optional)</summary>

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
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
