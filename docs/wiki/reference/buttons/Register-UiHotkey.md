# Register-UiHotkey

## SYNOPSIS
Registers a keyboard shortcut to trigger an action.

## SYNTAX

```
Register-UiHotkey [-Key] <String> [-Action] <ScriptBlock> [-NoAsync]
 [<CommonParameters>]
```

## DESCRIPTION
Binds a key combination (like Ctrl+S or F5) to a ScriptBlock. The shortcut works anywhere in the window,, except that plain keys (no Ctrl or Alt in the combination) other than F1 to F24 don't fire while an editable text box has focus, so typing never triggers them. Actions run asynchronously by default.

## EXAMPLES

### EXAMPLE 1
```
Register-UiHotkey -Key 'Ctrl+S' -Action { Save-CurrentDocument }
```

### EXAMPLE 2
```
Register-UiHotkey -Key 'Escape' -Action { Close-UiWindow } -NoAsync
```

### EXAMPLE 3
```
Register-UiHotkey -Key 'F5' -Action { Invoke-Refresh } -NoAsync
```

## PARAMETERS

### -Key
Key combination string. Format: "\[Ctrl+]\[Alt+]\[Shift+]Key"

Examples: "Ctrl+S", "F5", "Ctrl+Shift+N", "Escape"

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

### -Action
ScriptBlock to execute when the hotkey is pressed. Runs async by default; use -NoAsync for synchronous execution.

<details><summary>Type: ScriptBlock (required)</summary>

```yaml
Type: ScriptBlock
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -NoAsync
Run the action on the UI thread instead of a background runspace.

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
