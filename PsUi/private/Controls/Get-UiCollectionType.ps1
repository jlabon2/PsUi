function Get-UiCollectionType {
    <#
    .SYNOPSIS
        Classifies a collection handed to -ItemsSource as either Null, Ref, PsUiObservable, WpfObservable, or Other.
    #>
    [CmdletBinding()]
    param(
        # Untyped, since binding unwraps a [ref] for anything typed, [object] included, and then the grid's ref promotion never actually runs.
        [Parameter(Position = 0)]
        [AllowNull()]
        $Obj
    )

    if ($null -eq $Obj)                                      { return 'Null' }
    if ($Obj -is [System.Management.Automation.PSReference]) { return 'Ref' }

    # The test you would assume would be $Obj -is [PsUi.AsyncObservableCollection`1], but in 5.1 that throws "Late bound operations cannot be performed on fields with types for which Type.ContainsGenericParameters is true."
    # So, instead climb BaseType and compare FullName, the `1 suffix and all.
    # The ascent meets its own type first (a wrap is also an ObservableCollection).
    $type = $Obj.GetType()
    while ($null -ne $type) {
        if ($type.IsGenericType) {
            $def = $type.GetGenericTypeDefinition().FullName
            if ($def -eq 'PsUi.AsyncObservableCollection`1')                     { return 'PsUiObservable' }
            if ($def -eq 'System.Collections.ObjectModel.ObservableCollection`1') { return 'WpfObservable' }
        }
        $type = $type.BaseType
    }
    return 'Other'
}
