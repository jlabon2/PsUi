# Write-UiHostDirect

## SYNOPSIS
Writes directly to the console bypassing PsUi's Write-Host proxy.

## SYNTAX

```
Write-UiHostDirect [[-Object] <Object>] [-ForegroundColor <ConsoleColor>] [-BackgroundColor <ConsoleColor>]
 [-NoNewline] [-Separator <Object>] [<CommonParameters>]
```

## DESCRIPTION
In async button actions, PsUi intercepts Write-Host to route output to the UI. Call this when you need actual console output - for example, when logging outside the UI or writing to a console window.

Uses \[Console\]::WriteLine to bypass both the PSHost proxy and runspace boundaries. Color support is thinner than Write-Host since Console APIs are doing the work.

## EXAMPLES

### EXAMPLE 1
```
Write-UiHostDirect "This goes to console, not the UI panel"
```

### EXAMPLE 2
```
# Inside a button action
New-UiButton -Text 'Log' -Action {
    Write-Host "This appears in UI output panel"
    Write-UiHostDirect "This goes to PowerShell console"
}
```

## PARAMETERS

### -Object
The object to write.

<details><summary>Type: Object (optional)</summary>

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: True (ByValue)
Accept wildcard characters: False
```

</details>

### -ForegroundColor
Text foreground color.

<details><summary>Type: ConsoleColor (optional)</summary>

```yaml
Type: ConsoleColor
Parameter Sets: (All)
Aliases:
Accepted values: Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -BackgroundColor
Text background color.

<details><summary>Type: ConsoleColor (optional)</summary>

```yaml
Type: ConsoleColor
Parameter Sets: (All)
Aliases:
Accepted values: Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -NoNewline
Don't append a newline.

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

### -Separator
Accepted so Write-Host calls swap over without edits. Not used.

<details><summary>Type: Object (optional)</summary>

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
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
