# Close-UiWindow

## SYNOPSIS
Closes the window your code is running in (or the window that opened it).

## SYNTAX

```
Close-UiWindow [[-Window] <String>] [-Prompt] [-Message <String>]
 [<CommonParameters>]
```

## DESCRIPTION
Works anywhere PsUi calls code. The window goes the way it would from its own close button. -OnClosed, a -Modal child returns $false, and -ExportOnClose still hands back what the window captured. From an async action the window closes when the action ends,and a canceled action leaves it open.

## EXAMPLES

### EXAMPLE 1
```
New-UiButton -Text 'Close' -NoAsync -Action { Close-UiWindow }
```

### EXAMPLE 2
```
Register-UiHotkey -Key 'Escape' -NoAsync -Action { Close-UiWindow -Prompt }
```

Escape asks 'Close this window?' and closes the window on Yes.

### EXAMPLE 3
```
New-UiWindow -Title 'Pick a server' -ExportOnClose -Content {
    New-UiDropdown -Label 'Server' -Variable 'server' -Items @('web01', 'web02')
    New-UiButton -Text 'OK' -NoOutput -Capture 'picked' -Action {
        $picked = $server
        Close-UiWindow
    }
}
Write-Host "You picked $picked"
```

The OK action runs in the background, so the window waits for it to end and $picked still makes it back to the script.

### EXAMPLE 4
```
New-UiButton -Text 'Finish' -NoAsync -Action {
    Close-UiWindow -Window Main -Message 'All done. Close the wizard?'
}
```

A button in a child window that asks, then closes the child and the window behind it.

## PARAMETERS

### -Window
Which window to close. Also taken by position (eg Close-UiWindow Main).

- Current: the window the code is running in. Default.
- Parent: the window that opened this child window. The child closes with it.
- Main: the New-UiWindow window at the top and every child window with it.

<details><summary>Type: String (optional)</summary>

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: Current
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -Prompt
Confirms first, with Yes and No buttons. No leaves the window open. -Prompt:$false turns the question off even with -Message so -Prompt:$unsaved asks only when $unsaved is true.

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

### -Message
The prompt to ask. The default is 'Close this window?'. Using -Message implies -Prompt.

<details><summary>Type: String (optional)</summary>

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: Close this window?
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES
An error the action hits after the call goes with the window, the output window and all. Call Close-UiWindow last, and give the commands that can fail -ErrorAction Stop.

## RELATED LINKS
