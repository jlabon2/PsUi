function Resolve-UiListSource {
    <#
    .SYNOPSIS
        Wraps the calling script's list in a threadsafe one and repoints the variable at the wrap.
    #>
    [CmdletBinding()]
    param(
        # Untyped, because any type on this parameter, [object] included, unwraps a [ref] and the Ref case needs the holder.
        [Parameter(Mandatory)]
        [AllowNull()]
        $Source,

        [switch]$NoBind,

        # Get-Variable -Scope counts frames up from here. 0 (this function) and 1 (the public builder) both hold the original as a parameter.
        # Starting at 0 repoints those two parameters and calls that a success, while the script's own variable stays on the original.
        # 2 skips both and climbs from there.
        [int]$ScopeOffset = 2
    )

    $uiDispatcher    = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    $collectionType  = Get-UiCollectionType -Obj $Source
    $collection      = $null
    $mirrorAttached  = $false
    $refWriteMissed  = $false
    $converted       = [System.Collections.Generic.List[string]]::new()

    # The mirror inserts through IList, and Collection<T> throws there for anything that isn't already a T, so a typed list gets a typed wrap and PS converts on Add.
    $newWrap = {
        param($list)
        $itemType = [object]
        $seed     = $list

        # PS hands a string to the IEnumerable seed as its characters
        if ($list -is [string]) { $seed = @($list) }
        elseif ($list -is [System.Collections.IList] -and !$list.IsFixedSize) {
            $listOfT = $list.GetType().GetInterface('System.Collections.Generic.IList`1')
            if ($listOfT) { $itemType = $listOfT.GetGenericArguments()[0] }
        }
        $wrapType = [PsUi.AsyncObservableCollection`1].MakeGenericType($itemType)
        ,$wrapType::new($seed, $uiDispatcher)
    }

    switch ($collectionType) {
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
            $wrapper = & $newWrap $Source
            $wrapper.AttachMirror($Source)
            $mirrorAttached = $true
            $collection     = $wrapper
            break
        }

        'Ref' {
            $inner     = $Source.Value
            $innerType = Get-UiCollectionType -Obj $inner
            if ($innerType -eq 'PsUiObservable') {
                try { $inner.UpdateDispatcher() } catch { Write-Debug "UpdateDispatcher failed: $_" }
                $collection = $inner
            }
            else {
                $innerName = if ($null -eq $inner) { 'null' } else { $inner.GetType().Name }
                try { $wrapper = & $newWrap $inner }
                catch {
                    throw "-ItemsSource takes a list. The [ref] points at a $innerName, which is not one, and PowerShell cannot read it as a sequence either."
                }
                if ($inner -is [System.Collections.IList] -and !$inner.IsReadOnly -and !$inner.IsFixedSize) {
                    $wrapper.AttachMirror($inner)
                    $mirrorAttached = $true
                }
                $collection = $wrapper

                # -NoBind promises the thing passed in keeps its value, and a [ref] is that thing.
                if (!$NoBind) {
                    # Writing to a [ref] whose variable can't hold a list throws, and unguarded that takes the whole window build down.
                    try { $Source.Value = $wrapper } catch { Write-Debug "[ref] target refused the wrap: $_" }

                    # [ArrayList]$list behind the ref converts the wrap, and a target that can't hold a list refuses it and keeps what it had.
                    $landed = $Source.Value
                    if (!([object]::ReferenceEquals($landed, $wrapper))) {
                        $landedDesc = if ($null -eq $landed) { 'which refused the wrap and still holds null' } else { "now a fresh $($landed.GetType().Name)" }
                        [void]$converted.Add("the [ref] target, $landedDesc")
                    }
                    # [ref]$state.List writes to the holder and stops there ([ref]$list writes through).
                    # AttachMirror carries an ObservableCollection's adds either way.
                    elseif (!(Test-UiRefWritesThrough -Reference $Source) -and $inner -isnot [System.Collections.Specialized.INotifyCollectionChanged]) {
                        $refWriteMissed = $true
                    }
                }
            }
            break
        }

        default {
            # PS can't read a DateTime or a PSCustomObject as a sequence, so the constructor dies talking about overloads.
            try { $wrapper = & $newWrap $Source }
            catch {
                throw "-ItemsSource takes a list. A $($Source.GetType().Name) is not one, and PowerShell cannot read it as a sequence either."
            }

            # A fixed size array seeds the wrap fine but a mirrored Add back into it would throw, so no mirror. The array keeps its old contents and stops seeing changes.
            if ($Source -is [System.Collections.IList] -and !$Source.IsReadOnly -and !$Source.IsFixedSize) {
                $wrapper.AttachMirror($Source)
                $mirrorAttached = $true
            }
            $collection = $wrapper
        }
    }

    # PsUiObservable is used as handed in, so no variable needs repointing.
    $repointed = [System.Collections.Generic.List[string]]::new()
    $needsBind = $collectionType -in 'WpfObservable', 'Other' -and
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

                        # Type constrained variables convert the wrap here too.
                        # If the read back fails, count it as landed, since a warning that can't be acted on is worse than none.
                        $landed = $collection
                        try { $landed = Get-Variable -Name $psVar.Name -Scope $scopeIdx -ValueOnly -ErrorAction Stop }
                        catch { Write-Debug "Variable bind read back of '$($psVar.Name)' failed: $_" }

                        if ([object]::ReferenceEquals($landed, $collection)) { [void]$repointed.Add("`$$($psVar.Name)@$scopeIdx") }
                        else {
                            $landedDesc = if ($null -eq $landed) { 'which refused the wrap and holds null' } else { "now a fresh $($landed.GetType().Name)" }
                            [void]$converted.Add("`$$($psVar.Name), $landedDesc")
                        }
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
        Type           = $collectionType
        MirrorAttached = $mirrorAttached
        Repointed      = $repointed
        NeedsBind      = $needsBind
        RefWriteMissed = $refWriteMissed
        Converted      = $converted
    }
}
