function Set-UiProperties {
    <#
    .SYNOPSIS
        Applies a hashtable of WPF properties to a control, converting the common types in the process.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.UIElement]$Control,
        
        [Parameter(Mandatory)]
        [hashtable]$Properties
    )
    
    # Most controls keep their own status in Tag (a click action context or a theme brush key) so setting it elesewhere silently hamstrings the control.
    # Only a Tag already holding something is defended, so a Tag set on a control that has none already set will land. New-UiButton, New-UiProgress and New-UiStatusBar remove the key before they get here and never reach this.
    if ($Properties.ContainsKey('Tag') -and $null -ne $Control.Tag) {
        Write-Warning "[Set-UiProperties] Tag is reserved on $($Control.GetType().Name) and already holds the control's own state. Ignoring."
        $Properties = @{} + $Properties
        [void]$Properties.Remove('Tag')
    }

    foreach ($propName in $Properties.Keys) {
        try {
            $propValue = $Properties[$propName]
            
            # Attached properties use dot notation (e.g., "Grid.Row")
            # This should seperate a majority of common attached properties
            if ($propName -match '^(.+)\.(.+)$') {
                $ownerTypeName    = $matches[1]
                $attachedPropName = $matches[2]
                
                # Search common WPF namespaces for owner type
                $ownerType  = $null
                $namespaces = @(
                    'System.Windows.Controls',
                    'System.Windows',
                    'System.Windows.Controls.Primitives',
                    'System.Windows.Documents'
                )
                
                foreach ($ns in $namespaces) {
                    # -as [type] resolves through PowerShell, which scans loaded assemblies. [Type]::GetType wants an assembly-qualified name and returns $null for every WPF type from here.
                    $ownerType = "$ns.$ownerTypeName" -as [type]
                    if ($ownerType) { break }
                }
                
                if (!$ownerType) {
                    Write-Verbose "[Set-UiProperties] Owner type '$ownerTypeName' not found for attached property '$propName'. Skipping."
                    continue
                }
                
                # Locate the static DependencyProperty
                $bindingFlags = [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static
                $dpField      = $ownerType.GetField("${attachedPropName}Property", $bindingFlags)
                
                if (!$dpField) {
                    Write-Verbose "[Set-UiProperties] Attached property '$propName' not found. Skipping."
                    continue
                }
                
                $dp = $dpField.GetValue($null)

                # Attached values convert like instance properties do. 'DockPanel.Dock' = 'Left' arrives as a string and SetValue wants the enum.
                if ($null -ne $propValue -and $propValue -isnot $dp.PropertyType) {
                    $propValue = ConvertTo-WpfValue -Value $propValue -TargetType $dp.PropertyType -PropertyName $propName
                    if ($null -eq $propValue) { continue }
                }

                $Control.SetValue($dp, $propValue)
                Write-Verbose "[Set-UiProperties] Set attached '$propName' = '$propValue'"
            }
            else {
                # Regular instance property
                $propInfo = $Control.GetType().GetProperty($propName)
                
                if (!$propInfo) {
                    Write-Verbose "[Set-UiProperties] Property '$propName' not found on $($Control.GetType().Name). Skipping."
                    continue
                }
                
                if (!$propInfo.CanWrite) {
                    Write-Warning "[Set-UiProperties] Property '$propName' is read-only. Skipping."
                    continue
                }
                
                $targetType = $propInfo.PropertyType
                
                # Convert value if types don't match
                if ($null -ne $propValue -and $propValue -isnot $targetType) {
                    $propValue = ConvertTo-WpfValue -Value $propValue -TargetType $targetType -PropertyName $propName
                    if ($null -eq $propValue) { continue }
                }
                
                $propInfo.SetValue($Control, $propValue)
                Write-Verbose "[Set-UiProperties] Set '$propName' = '$propValue'"
            }
        }
        catch {
            Write-Warning "[Set-UiProperties] Failed to set '$propName': $_"
        }
    }
}

