# Get-UiValue

## SYNOPSIS
Gets the value of a UI control by its variable name.

## SYNTAX

```
Get-UiValue [-Variable] <String> [<CommonParameters>]
```

## DESCRIPTION
Retrieves the current value of a registered UI control. This works from -NoAsync button actions where hydration doesn't apply. The read happens on the UI thread on its own. Call it from wherever.

## EXAMPLES

### EXAMPLE 1
```
$url = Get-UiValue -Variable 'urlInput'
```

Gets the current value from the control registered as 'urlInput'.

### EXAMPLE 2
```
New-UiButton -Text 'Submit' -NoAsync -Action {
    $name = Get-UiValue -Variable 'userName'
    Write-Host "Hello, $name!"
}
```

Button action that reads a control value on the UI thread.

## PARAMETERS

### -Variable
The variable name of the control. This matches the -Variable parameter used when creating the control.

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
