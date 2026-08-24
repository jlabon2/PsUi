function Get-UiCollectionKind {
    <#
    .SYNOPSIS
        Classifies a collection handed to -ItemsSource: Null, Ref, PsUiObservable, WpfObservable, or Other.
    #>
    [CmdletBinding()]
    param(
        # Untyped on purpose. Parameter binding unwraps a [ref] for anything typed, [object] included, so a typed param would classify every [ref] as whatever it points at and the grid's ref promotion would never occur.
        [Parameter(Position = 0)]
        [AllowNull()]
        $Obj
    )

    if ($null -eq $Obj)                                      { return 'Null' }
    if ($Obj -is [System.Management.Automation.PSReference]) { return 'Ref' }

    # The natural test is $Obj -is [PsUi.AsyncObservableCollection`1], and in 5.1 that throws "Late bound operations cannot be performed on fields with types for which Type.ContainsGenericParameters is true."
    # So climb BaseType and compare FullName instead, `1 suffix and all.
    # A wrap is also an ObservableCollection. The climb meets its own type first.
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
