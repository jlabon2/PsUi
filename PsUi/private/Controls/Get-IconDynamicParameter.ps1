function Get-IconDynamicParameter {
    <#
    .SYNOPSIS
        Creates a dynamic parameter for icon selection with ValidateSet from CharList.json.
        Any of the public functions that accept an 'Icon' parameter can use this to provide intellisense for valid icon names.
    #>
    [CmdletBinding()]
    param(
        [string]$ParameterName = 'Icon',
        [string]$DefaultValue = $null,
        [bool]$Mandatory = $false
    )

    # Use cached icon dictionary from module context (loaded at import)
    $iconDict = [PsUi.ModuleContext]::Icons
    if ($iconDict -and $iconDict.Count -gt 0) { $iconNames = $iconDict.Keys | Sort-Object }
    else { $iconNames = @('Info', 'Warning', 'Error', 'Question', 'Settings', 'User') }

    # Create the dynamic parameter dictionary and attribute collection
    $paramDictionary     = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
    $attributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()

    # Parameter attribute
    $paramAttribute           = [System.Management.Automation.ParameterAttribute]::new()
    $paramAttribute.Mandatory = $Mandatory
    $attributeCollection.Add($paramAttribute)

    # ValidateSet attribute with icon names
    if ($iconNames.Count -gt 0) {
        [string[]]$validValues = $iconNames
        $validateSet = [System.Management.Automation.ValidateSetAttribute]::new($validValues)
        $attributeCollection.Add($validateSet)
    }

    $dynParam = [System.Management.Automation.RuntimeDefinedParameter]::new(
        $ParameterName,
        [string],
        $attributeCollection
    )

    if ($DefaultValue) { $dynParam.Value = $DefaultValue }

    $paramDictionary.Add($ParameterName, $dynParam)
    return $paramDictionary
}
