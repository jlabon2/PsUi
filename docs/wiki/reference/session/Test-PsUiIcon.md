# Test-PsUiIcon

## SYNOPSIS
Tests whether an icon name will render under the current (or a specified) icon font.

## SYNTAX

```
Test-PsUiIcon [-Name] <String> [-Font <String>] [<CommonParameters>]
```

## DESCRIPTION
Returns $true if the named glyph is present in the requested font. Use this in scripts to skip rendering an icon you can't trust, or to lint a list against a target font.

-Font picks the check:
- Active (default): checks the live active font. Strict: a failed glyph cache build returns $false instead of guessing (the glyph browser guesses on purpose so its tiles don't all dim). Honors the fallback chain unless Set-PsUiIconFont was called with -NoIconFontFallback.
- Fluent: checks Segoe Fluent Icons explicitly.
- MDL2: checks Segoe MDL2 Assets explicitly.
- Either: returns true if either icon font has the glyph.

## EXAMPLES

### EXAMPLE 1
```
Test-PsUiIcon -Name 'Calculator'
# True if the active font has Calculator
```

### EXAMPLE 2
```
if (-not (Test-PsUiIcon 'WeirdNewGlyph' -Font MDL2)) { Write-Warning "WeirdNewGlyph won't render on Win10" }
```

## PARAMETERS

### -Name
The icon name to test (key from CharList.json).

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

### -Font
Which font to test against. Defaults to Active.

<details><summary>Type: String (optional)</summary>

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: Active
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Boolean
## NOTES

## RELATED LINKS
