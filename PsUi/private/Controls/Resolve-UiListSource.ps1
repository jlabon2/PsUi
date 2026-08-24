function Resolve-UiListSource {
    <#
    .SYNOPSIS
        Wraps the calling script's collection in the thread-safe one and repoints the script's variable at the wrap.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Source,

        [switch]$NoBind,

        # Get-Variable -Scope counts frames up from here: 0 is this function and 1 is New-UiList, and both hold the original collection as a parameter ($Source here, $ItemsSource there).
        # Starting the walk that low repoints those parameters and counts it as success, so the calling script's variable stays on the unwrapped original and the 'could not repoint' warning never fires.
        # 2 skips exactly those two frames and the walk climbs from there.
        [int]$ScopeOffset = 2
    )

    $uiDispatcher   = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    $kind           = Get-UiCollectionKind -Obj $Source
    $collection     = $null
    $mirrorAttached = $false

    switch ($kind) {
        'Null' {
            $collection = [PsUi.AsyncObservableCollection[object]]::new($uiDispatcher)
            break
        }

        # Point it at this window's UI thread in case it was built for another one.
        'PsUiObservable' {
            try { $Source.UpdateDispatcher() } catch { Write-Debug "UpdateDispatcher failed: $_" }
            $collection = $Source
            break
        }

        'WpfObservable' {
            $wrapper = [PsUi.AsyncObservableCollection[object]]::new($Source, $uiDispatcher)
            $wrapper.AttachMirror($Source)
            $mirrorAttached = $true
            $collection     = $wrapper
            break
        }

        default {
            $wrapper = [PsUi.AsyncObservableCollection[object]]::new($Source, $uiDispatcher)
            # A fixed size array seeds the wrap fine but a mirrored Add back into it would throw, so no mirror. The array keeps its old contents and stops seeing changes.
            if ($Source -is [System.Collections.IList] -and !$Source.IsReadOnly -and !$Source.IsFixedSize) {
                $wrapper.AttachMirror($Source)
                $mirrorAttached = $true
            }
            $collection = $wrapper
        }
    }

    # PsUiObservable is used as handed in, so there is nothing to repoint.
    $repointed = [System.Collections.Generic.List[string]]::new()
    $needsBind = $kind -in 'WpfObservable', 'Other' -and
                 $null -ne $collection -and
                 !([object]::ReferenceEquals($collection, $Source))

    if ($needsBind -and !$NoBind) {
        for ($scopeIdx = $ScopeOffset; $scopeIdx -lt 50; $scopeIdx++) {
            try { $scopeVars = Get-Variable -Scope $scopeIdx -ErrorAction Stop }
            catch [System.ArgumentOutOfRangeException] { break }
            catch { Write-Debug "Variable bind scope $scopeIdx walk failed: $_"; continue }

            foreach ($psVar in $scopeVars) {
                $matched = $false
                try { $matched = [object]::ReferenceEquals($psVar.Value, $Source) }
                catch { Write-Debug "Variable bind read of '$($psVar.Name)' failed: $_"; continue }

                if ($matched) {
                    try {
                        Set-Variable -Name $psVar.Name -Value $collection -Scope $scopeIdx -Force -ErrorAction Stop
                        [void]$repointed.Add("`$$($psVar.Name)@$scopeIdx")
                    }
                    catch { Write-Debug "Variable bind rewrite of '$($psVar.Name)' at scope $scopeIdx failed: $_" }
                }
            }
        }
        Write-Debug "Variables bound: $(if ($repointed.Count) { $repointed -join ', ' } else { 'nothing matched' })"
    }
    elseif ($needsBind) {
        Write-Debug "Variable bind skipped (-NoBind). The calling script's variable still points at the original collection."
    }

    return @{
        Collection     = $collection
        Kind           = $kind
        MirrorAttached = $mirrorAttached
        Repointed      = $repointed
        NeedsBind      = $needsBind
    }
}
