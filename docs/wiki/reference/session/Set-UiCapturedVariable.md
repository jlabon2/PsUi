# Set-UiCapturedVariable

## SYNOPSIS
Stores a value that later actions in the window receive as a variable.

## SYNTAX

```
Set-UiCapturedVariable [-Name] <String> [-Value] <Object>
 [<CommonParameters>]
```

## DESCRIPTION
Typically, an asyc action in PsUi does not return variables created during the action. This captures a value for later use in other actions. Every async action after this gets it back as a variable of that name, -EnabledWhen controls follow it, and New-UiWindow -ExportOnClose hands it to your script. Use it where -Capture can't, such as a -NoAsync action, a hotkey or the -Content block.

## EXAMPLES

### EXAMPLE 1
```
New-UiButton -Text 'Run' -NoOutput -Action {
    Start-Sleep -Seconds 2
    Set-UiCapturedVariable -Name 'lastRun' -Value (Get-Date)
}
New-UiButton -Text 'Last run' -Action { Write-Host "Last run: $lastRun" }
```

The first button records when it finished, and the second reads it back as $lastRun.

### EXAMPLE 2
```
New-UiButton -Text 'Sign in' -NoAsync -Action {
    $account = Show-UiCredentialDialog -Caption 'Sign in' -Message 'Mail account'
    if ($account) { Set-UiCapturedVariable 'account' $account }
}
New-UiButton -Text 'Check mail' -EnabledWhen 'account' -Action {
    Write-Host "Checking mail for $($account.UserName)"
}
```

A -NoAsync action has no runspace for -Capture to read from, so it stores the credential itself. Check mail stays disabled until then.

## PARAMETERS

### -Name
The variable name later actions see without the $.

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

### -Value
The value to store. $null is allowed.

<details><summary>Type: Object (required)</summary>

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
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
A stored value beats a control or a script variable of the same name, and loses to one passed through -Variables or -LinkedVariables.

## RELATED LINKS
