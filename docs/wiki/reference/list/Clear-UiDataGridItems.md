# Clear-UiDataGridItems

## SYNOPSIS
Empties a New-UiDataGrid.

## SYNTAX

```
Clear-UiDataGridItems [-Variable] <String> [<CommonParameters>]
```

## DESCRIPTION
Empties the row collection on the grid identified by -Variable. Works on both -Items grids and -ItemsSource grids. On -ItemsSource grids your own collection gets cleared too.

## EXAMPLES

### EXAMPLE 1
```
Clear-UiDataGridItems -Variable queue
```

<p align="center"><img src="../../../pages/list/Clear-UiDataGridItems/example1.gif" alt=""></p>

## PARAMETERS

### -Variable
The -Variable name passed to the originating New-UiDataGrid.

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
