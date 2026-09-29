# Get-PsUiIconList

## SYNOPSIS
Lists all available icon names.

## SYNTAX

```
Get-PsUiIconList [[-Filter] <String>] [<CommonParameters>]
```

## DESCRIPTION
Every icon name in the module's glyph map, optionally narrowed by wildcard. The map isn't tied to a font - Test-PsUiIcon tells you whether a name renders in the active one. For the visual version, Show-UiGlyphBrowser draws them all as clickable tiles.

## EXAMPLES

### EXAMPLE 1
```
Get-PsUiIconList
```

### EXAMPLE 2
```
Get-PsUiIconList -Filter '*Arrow*'
```

## PARAMETERS

### -Filter
Optional wildcard filter for icon names.

<details><summary>Type: String (optional)</summary>

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: *
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
