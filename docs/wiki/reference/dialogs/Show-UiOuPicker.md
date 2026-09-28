# Show-UiOuPicker

## SYNOPSIS
Shows the native Windows OU/container browser dialog.

## SYNTAX

```
Show-UiOuPicker [[-Title] <String>] [[-Prompt] <String>] [[-Root] <String>] [[-Server] <String>]
 [-IncludeEntireDirectory] [-IncludeHidden] [-NoButtons] [-IgnoreTreatAsLeaf] [[-ParentWindow] <Window>]
 [[-Credential] <PSCredential>] [<CommonParameters>]
```

## DESCRIPTION
Wraps DsBrowseForContainerW (dsuiext.dll) - the same OU picker that ADUC, Group Policy Management, and every other Microsoft AD tool uses. Returns a PSCustomObject with Name, DistinguishedName, and AdsPath. Returns $null if the user cancels.

## EXAMPLES

### EXAMPLE 1
```
$ou = Show-UiOuPicker -Title 'Pick a target OU'
if ($ou) { New-ADUser -Path $ou.DistinguishedName -Name 'jdoe' }
```

### EXAMPLE 2
```
Show-UiOuPicker -Server 'dc01.corp.local' -Root 'OU=Servers,DC=corp,DC=local'
```

### EXAMPLE 3
```
$cred = Get-Credential 'CORP\admin'
$ou = Show-UiOuPicker -Credential $cred -Server 'dc01.corp.local'
```

## PARAMETERS

### -Title
Caption shown in the dialog title bar.

<details><summary>Type: String (optional)</summary>

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: Select an organizational unit
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -Prompt
Instruction text shown above the tree.

<details><summary>Type: String (optional)</summary>

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: Select an organizational unit:
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -Root
Distinguished name or ADsPath of the container to use as the tree root. Accepts either 'OU=Servers,DC=corp,DC=local' or 'LDAP://corp.local/...'. Defaults to the current domain.

<details><summary>Type: String (optional)</summary>

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -Server
Domain controller or DNS name to target. Useful when the local machine isn't joined to the target domain.

<details><summary>Type: String (optional)</summary>

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -IncludeEntireDirectory
Browse the full forest, not just the local domain.

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

### -IncludeHidden
Include hidden containers (CN=System, CN=Configuration, etc.).

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

### -NoButtons
Hide the expand/collapse buttons.

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

### -IgnoreTreatAsLeaf
Makes the dialog ignore treatAsLeaf display specifiers, so containers they mark as leaf objects still expand. Worth trying when a custom -Root or -Server leaves the tree refusing to expand things that clearly have children.

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

### -ParentWindow
WPF window to use as the modal parent. Falls back to the active session window.

<details><summary>Type: Window (optional)</summary>

```yaml
Type: Window
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### -Credential
Alternate credentials for accessing a directory the local machine is not joined to. Handed to the native dialog's own credential fields. No impersonation involved, no special privileges required.

<details><summary>Type: PSCredential (optional)</summary>

```yaml
Type: PSCredential
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

</details>

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### PSCustomObject
## NOTES

## RELATED LINKS
