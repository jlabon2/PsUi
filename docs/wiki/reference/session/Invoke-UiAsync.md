# Invoke-UiAsync

## SYNOPSIS
Runs a scriptblock in the background without freezing the UI.

## SYNTAX

```
Invoke-UiAsync [-ScriptBlock] <ScriptBlock> [[-OnComplete] <ScriptBlock>] [[-OnError] <ScriptBlock>]
 [[-OnHost] <ScriptBlock>] [[-Arguments] <Object[]>] [[-Variables] <Hashtable>] [[-Capture] <String[]>]
 [-NoAutoCapture] [-NoActiveExecutor] [<CommonParameters>]
```

## DESCRIPTION
Runs the scriptblock off the UI thread so the window keeps responding while it works. Variables and functions from the calling scope come along automatically; pass extra ones with -Variables, or shut auto capture off with -NoAutoCapture.

## EXAMPLES

### EXAMPLE 1
```
Invoke-UiAsync -ScriptBlock {
    Get-ChildItem C:\ -Recurse
} -OnComplete {
    param($result)
    Write-Host "Found $($result.Count) items"
}
```

### EXAMPLE 2
```
$path = "C:\Temp"
Invoke-UiAsync -ScriptBlock {
    Get-ChildItem $path   # $path is captured for you
}
```

## PARAMETERS

### -ScriptBlock
Code to run in background.

<details><summary>Type: ScriptBlock (required)</summary>

```yaml
Type: ScriptBlock
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -OnComplete
Code to run when done. Receives the result as parameter. Runs on every finish that wasn't cancelled, errors or not, so a run that wrote to the error stream and still returned data delivers that data here as well as reporting through OnError.

<details><summary>Type: ScriptBlock (optional)</summary>

```yaml
Type: ScriptBlock
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -OnError
Code to run when the background script wrote to the error stream. Receives the joined error text. A non-terminating error counts, so this can fire on a run that still produced results and still reaches OnComplete.

<details><summary>Type: ScriptBlock (optional)</summary>

```yaml
Type: ScriptBlock
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -OnHost
Per-record Write-Host handler for background output. Receives the emitted record. Background runspaces have no console-visible host of their own; hook this to route Write-Host somewhere useful (status text, log panel, existing output window).

<details><summary>Type: ScriptBlock (optional)</summary>

```yaml
Type: ScriptBlock
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -Arguments
Arguments to pass to the scriptblock (legacy compatibility).

<details><summary>Type: Object[] (optional)</summary>

```yaml
Type: Object[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -Variables
Hashtable of variables to pass to the background runspace.

<details><summary>Type: Hashtable (optional)</summary>

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -Capture
Variable names to capture from the runspace after execution completes. Captured variables are stored in the session and available to subsequent async calls. They reach the calling script's scope after close only when the window was opened with -ExportOnClose.

<details><summary>Type: String[] (optional)</summary>

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 7
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -NoAutoCapture
Disables automatic variable capture from the calling scope. Use when you want full control over what's passed in.

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

### -NoActiveExecutor
Leaves the session's ActiveExecutor alone, so Stop-UiAsync and the status bar's AutoCancel keep targeting whatever was already running. For background maintenance work (count scans, prefetches) that shouldn't own Cancel.

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
