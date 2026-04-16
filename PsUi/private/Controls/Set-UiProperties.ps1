function Set-UiProperties {
    <#
    .SYNOPSIS
        Applies custom WPF properties to a control from a hashtable.
        Uses ConvertTo-WpfValue to translate common types into WPF types.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.UIElement]$Control,
        
        [Parameter(Mandatory)]
        [hashtable]$Properties
    )
    
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
                    $ownerType = [Type]::GetType("$ns.$ownerTypeName")
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
                
                $Control.SetValue($dpField.GetValue($null), $propValue)
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

