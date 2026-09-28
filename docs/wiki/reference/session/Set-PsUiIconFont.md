# Set-PsUiIconFont

## SYNOPSIS
Sets the icon font used by PsUi controls.

## SYNTAX

```
Set-PsUiIconFont [-FontName] <String> [-NoIconFontFallback]
 [<CommonParameters>]
```

## DESCRIPTION
Switches the icon font between Segoe MDL2 Assets (Windows 10) and Segoe Fluent Icons (Windows 11). Use 'Auto' to let PsUi detect the appropriate font for the current system. If the requested font is not installed, falls back to Segoe MDL2 Assets and writes a warning.

By default the chosen font is paired with the other as a WPF font-fallback chain - any glyph missing from the primary still renders via the secondary. -NoIconFontFallback pins to the primary only (missing glyphs render as tofu).

Affects newly-created controls only. Existing controls keep the font they were built with. Reload the window to apply a font change to UI that's already on screen.

## EXAMPLES

### EXAMPLE 1
```
Set-PsUiIconFont -FontName 'SegoeFluentIcons'
```

### EXAMPLE 2
```
Set-PsUiIconFont -FontName 'SegoeMDL2' -NoIconFontFallback
# Strict MDL2 - won't borrow Fluent glyphs as fallback.
```

## PARAMETERS

### -FontName
The icon font to use: Auto, SegoeMDL2, or SegoeFluentIcons.

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

### -NoIconFontFallback
Pin to the chosen font only. Disables the WPF fallback chain. Glyphs missing from the chosen font render as tofu.

On a Win10 box with only MDL2 installed there's no secondary font to fall back to, so this changes nothing on screen. Its remaining effect there: tighter tab completion for -Icon parameters (names that would render tofu drop out of the completion list). Also matters later if CharList.json ever picks up entries only one font carries, or if MS ships a third icon font.

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
Rendering caveat: 125 names in CharList.json (Blocked, Effects, PhotoCollection, ...) only live in Fluent. With MDL2 active and fallback on they still render (WPF substitutes from Fluent), so a glyph drawn in Fluent's newer style sneaks into an otherwise MDL2 app. Use -NoIconFontFallback for strict consistency; the Fluent-only names will tofu instead, telling you which ones to swap.

## RELATED LINKS
