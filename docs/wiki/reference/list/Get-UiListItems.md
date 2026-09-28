# Get-UiListItems

## SYNOPSIS
Gets all items from a list or dropdown.

## SYNTAX

```
Get-UiListItems [-Variable] <String> [<CommonParameters>]
```

## DESCRIPTION
Returns a snapshot of the list's current contents as a plain array. Items hidden by an active filter are still included.

## EXAMPLES

### EXAMPLE 1
```
$items = Get-UiListItems 'myList'
```

## PARAMETERS

### -Variable
The -Variable name of the list or dropdown.

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
