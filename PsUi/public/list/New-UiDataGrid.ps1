function New-UiDataGrid {
    <#
    .SYNOPSIS
        Themed datagrid. Drops inside a New-UiWindow next to other controls.
    .DESCRIPTION
        Drop a grid into a window, get the selected rows back in a button action via -Variable
        hydration. Columns auto-generate from the first row's properties, or specify them
        explicitly with -Columns.

        Cells can be text, checkbox, dropdown, date picker, or button/checkbox/link
        controls. OnCellEdit / OnRowEdit callbacks run when edits commit.

        A toolbar with basic filter, copy, export, and column picker is on by default,
        opt out of any with the matching -No* switch.

        Replace, append, or clear rows from a button action with Set-/Add-/Clear-UiDataGridItems.
    .PARAMETER Variable
        Hydration name. The selected rows show up as $varName in button actions, and the
        Set-/Add-/Clear-UiDataGridItems helpers look the grid up by this name.
    .PARAMETER Items
        Row objects to show. Take from the pipeline or pass directly. Can't be combined with
        -ItemsSource.
    .PARAMETER ItemsSource
        Point the grid at a collection you own. After the call, $list.Add() from anywhere
        lands in the grid, whether from a button action or the console.
        Accepted inputs:
          - any of the usual list types: array, ArrayList, List<T>, ObservableCollection, the
            PsUi async collection. Everything except the async collection gets wrapped, and
            PsUi walks the calling scope to repoint every variable holding the original at
            the wrap. The async collection already is the wrap, so it binds as is.
          - [ref] to any of the above

        The variable bind can't reach:
          - a collection held by a property: $obj.Items
          - a collection held inside a hashtable or dictionary: $state.list
          - a collection passed as a literal expression: -ItemsSource (Get-Thing)
          - a variable rebound to a different value after the call: $list = Get-Process
          - a variable captured by a closure built before the call

        In all of those, the grid still binds but you have no handle - use a local
        variable or [ref] (or skip the variable bind entirely with -NoBind).
        Can't be combined with -Items.
    .PARAMETER NoBind
        Skip the variable bind step. -ItemsSource still wraps the collection and points the grid
        at the wrap, but the variable you passed in keeps its original value. Mutations from
        outside the wrap won't reach the grid. Drive it through [ref] or the
        Set-/Add-/Clear-UiDataGridItems helpers. Off by default.
    .PARAMETER Columns
        How to lay out columns. Three options:
          - omit it: auto-generate from the first row
          - string[]: limit auto-generated columns to these property names, in this order
          - full control: a { New-UiColumn ... } definition block, an array of New-UiColumn
            output, or the equivalent hashtables. Each column can set Name, Header, Width,
            Format, ReadOnly, Editable ($true/$false/scriptblock/property name), EditorType
            (Auto/Text/CheckBox/ComboBox/DatePicker), Choices, Validator, plus
            Type=Button/Toggle/Link for live controls in the cell (with Text, Icon, Action,
            Binding, OnChange, Url as needed). Button and Link actions run in a background
            runspace by default; -Sync (or Sync = $true in the hashtable form) keeps one on
            the UI thread (dialogs or clipboard work). Link cells default to
            http/https/mailto/tel schemes only; -AllowFileScheme permits file: URLs (off by
            default because {Prop} substitution into a file: template lets row content
            launch arbitrary executables). Property-name strings and full column
            definitions mix in one array.
    .PARAMETER Height
        Height cap in pixels. Defaults to 300. The grid scrolls internally once row count
        pushes past it. Pass -Fill to lift the cap and grow with the window.
    .PARAMETER Width
        Fixed width in pixels. Optional.
    .PARAMETER FullWidth
        In a wrapping layout, stretch to fill the available width.
    .PARAMETER Fill
        Grow to the rest of the window's available height, lifting the -Height cap. The grid
        claims whatever space the window has left below it and resizes with the window. Use
        when the DataGrid is the dominant content. Two -Fill grids in the same panel split
        unevenly (first one claims, second gets leftovers). For an even split, wrap them in
        New-UiGrid -Rows '*,*' -Fill so the row layout handles the split natively.
    .PARAMETER MaxFillHeight
        Cap on -Fill growth in pixels. Defaults to no cap. Useful on 4K / multi-monitor setups
        where unbounded fill looks too tall.
    .PARAMETER MinFillHeight
        Floor on -Fill height in pixels. Defaults to 50. Raises the minimum so a tall sibling
        above can't pulverize the grid to a slim little slice.
    .PARAMETER SelectionMode
        Single (one row), Extended (Ctrl/Shift multi-select, default), or None (rows still
        highlight on click but OnSelectionChanged won't fire).
    .PARAMETER DefaultPropertiesOnly
        Respect $item.PSStandardMembers.DefaultDisplayPropertySet, hiding non-default props
        initially. Hidden ones come back via the column-picker. Off by default for embedded
        grids - showing everything is usually what makes sense there.
    .PARAMETER HideEmptyColumns
        Hide columns where every value is null or empty.
    .PARAMETER NoArrayPopup
        Don't pop a viewer when an array cell is clicked.
    .PARAMETER NoDictionaryPopup
        Don't pop a viewer when a nested hashtable / dictionary cell is clicked.
    .PARAMETER NoSafeWrap
        Skip the protective wrap done on input objects. Faster on big clean datasets, but one
        throwing property getter takes the whole grid down.
    .PARAMETER Editable
        Make the whole grid editable. Text cells get a themed editor and write back to the
        underlying property. Per-column Editable=$false in a column hashtable wins.
    .PARAMETER OnCellEdit
        Runs after a cell edit commits. Usage: param($row, $columnName, $newValue, $oldValue)
        $newValue is the editor's raw value (string from TextBox, bool from CheckBox, date from
        DatePicker, ComboBox SelectedItem). For typed row properties, read $row.$columnName
        inside the callback for the post-coercion value.
        Example: -OnCellEdit { param($r, $c, $new, $old) Write-Host "$($r.Id): $c $old -> $new" }
    .PARAMETER OnRowEdit
        Runs after the last cell in a row commits. Usage: param($row, $changedColumns)
        Example: -OnRowEdit { param($r, $c) Save-Item $r; Write-Host "$($r.Id): $($c -join ',')" }
    .PARAMETER NoToolbar
        Kill the toolbar entirely.
    .PARAMETER NoFilter
        Hide the filter textbox.
    .PARAMETER NoExport
        Kill the Export-to-CSV button.
    .PARAMETER NoCopy
        Kill the copy button.
    .PARAMETER NoSort
        Kill click-to-sort on column headers.
    .PARAMETER NoContextMenu
        Kill the right-click Copy/Export/Select-All menu.
    .PARAMETER NoColumnPicker
        Kill the show/hide columns button.
    .PARAMETER NoStretchLastColumn
        Don't stretch the rightmost column to fill the grid. Use when every column
        should size to its content and trailing whitespace is fine.
    .PARAMETER NoVisualValues
        Render bool and null values as plain text. By default bool columns show a green check
        or red cross, and nulls show a dash instead of "True"/"False"/blank. Editable
        bools show the glyph normally and swap to a themed checkbox on edit, double-click or
        F2 to flip.
    .PARAMETER NoMarkEmptyCells
        Don't mark empty cells. By default null / empty-string cells get a subtle diagonal
        hatch so empty data is easier to spot at a glance. Only applies to text columns.
    .PARAMETER CaptureScrollWheel
        Keep mouse-wheel events inside the grid instead of getting grabbed by the parent. The PsUi
        default lets the wheel reach the outer window so it scrolls under the cursor. Turn this
        on for grids tall enough or with enough meaningful data to need their own scroll.
    .PARAMETER OnSelectionChanged
        Runs when the selected row(s) change. Usage: param($selectedItems)
        Example: -OnSelectionChanged { param($sel) Write-Host "Selected $($sel.Count) row(s)" }
    .PARAMETER OnDoubleClick
        Runs on row double-click. Usage: param($row)
        Example: -OnDoubleClick { param($r) Show-UiMessageDialog -Message ($r|Out-String) }
    .PARAMETER EnabledWhen
        Variable name (or scriptblock). The grid is enabled while it's truthy.
    .PARAMETER WPFProperties
        Extra properties to set on the grid (or its toolbar host if there's a toolbar).
        Hashtable of property name to value.
    .PARAMETER RowDetailsTemplate
        Scriptblock that builds the expandable detail panel under the selected row.
        `$_`/`$row` inside are the row data. Runs on the UI thread when the row expands, use
        Invoke-UiAsync inside for anything slow.

        Example: -RowDetailsTemplate { New-UiLabel -Text $_.Description; New-UiLabel -Text $_.Notes}

        Example: -RowDetailsTemplate { New-UiTextArea -Default ($_|Out-String) -ReadOnly }
    .PARAMETER RowBackground
        Scriptblock that colors rows. Returns a color string (e.g. '#33FF6B6B') or `$null`.
        `$_`/`$row` is the row data. Runs as rows scroll into view.
    .PARAMETER FrozenColumns
        How many columns to pin on the left during horizontal scroll. Useful when the leftmost
        columns have identifying info and the grid is wide enough to need horizontal scroll.
    .PARAMETER EmptyMessage
        Text shown over the grid when the collection is empty.
    .PARAMETER NoAlternatingRowBrush
        Kill the alternating row stripe. The default striping uses a theme color that flips
        direction across light/dark themes so the stripe stays readable either way; the
        built-in WPF stripe is too subtle in most themes.
    .PARAMETER DefaultSort
        Sort the grid before showing it. Accepts:
          - 'PropName' (ascending)
          - 'PropName -Descending'
          - @{ Property = 'PropName'; Direction = 'Ascending'|'Descending' }
          - an array of any of the above for multi-key sorting
    .PARAMETER RowHeight
        Fixed pixel row height. Default sizes rows to their content.
    .PARAMETER RowContextMenu
        Custom items to add to the right-click menu, shown above the standard Copy/Export
        entries. Pass a { New-UiMenuItem ... } definition block (menu order follows call
        order), or the legacy hashtable mapping a label to an action, where the action is:
          - a scriptblock: { Restart-Service $_.Name }
          - a hashtable: @{ Action = {}; Enabled = {} or $bool; Icon = 'Name'; Sync = $false }

        Inside the action, $_ is the row being acted upon. The grid refreshes itself after
        the action runs, so $_.Status = 'Stopped' actually shows up. Write-Host goes
        wherever PsUi normally puts host output (the output window, the active status bar).

        Multi-select: if the right-click lands on a row that's part of a multi-selection,
        the action fans out across every selected row (Excel / Explorer convention).
        Right-clicking outside the selection acts on just the click target. With a
        multi-selection, Enabled runs twice: once for the menu (enabled while at least one
        of the first 20 selected rows qualifies; bigger selections enable without probing
        and the click still filters) and once per row as the action fans out (ineligible
        rows are skipped silently).

        Actions run in a background runspace by default so the UI stays responsive during
        slow work (Restart-Service, Invoke-WebRequest, etc.). Use -Sync on New-UiMenuItem
        (Sync = $true in the hashtable form) for actions that have to stay on the UI thread
        (Show-UiMessageDialog or clipboard stuff).

        Background action variable capture: PsUi grabs the values of variables your action
        mentions by name and copies them into the background runspace. A local secret with a
        name that collides with something in the action body ($cred is the common one) gets
        copied too. Sync actions skip the variable copy.
    .PARAMETER SanitizeFormulas
        Prefix exported / copied cells whose first character is =/+/-/@/tab/CR/LF with an
        apostrophe so Excel (assuming it's the default) treats them as literal text. Off by
        default. Clean data roundtrips (export then re-import) stay byte identical without
        this. Flip it on when the grid is showing values from untrusted sources (user-supplied
        filenames, log lines, anything off the network) that a downstream user might open in
        Excel.
    .EXAMPLE
        New-UiWindow -Title 'Procs' -Content {
            Get-Process | New-UiDataGrid -Variable procs -Height 400 -DefaultPropertiesOnly
            New-UiButton -Text 'Kill Selected' -Action {
                foreach ($p in $procs) { Stop-Process -Id $p.Id }
            }
        }
    .EXAMPLE
        # Editable grid with mixed cell types
        New-UiDataGrid -Variable svc -Items (Get-Service | Select Name, Status, StartType) -Editable -Columns {
            New-UiColumn Name -ReadOnly
            New-UiColumn Status -Editable $true
            New-UiColumn StartType -Editable $true -EditorType ComboBox -Choices 'Automatic', 'Manual', 'Disabled'
            New-UiColumn -Header 'Restart' -Type Button -Text 'Restart' -Action { Restart-Service $_.Name }
        } -OnCellEdit {
            param($row, $col, $new, $old)
            Write-Host "$($row.Name): $col $old -> $new"
        }
    .EXAMPLE
        # Row details with conditional row coloring
        $gridParams = @{
            Variable           = 'svc'
            Items              = Get-Service
            Height             = 500
            RowBackground      = { if ($_.Status -eq 'Stopped') { '#33FF6B6B' } }
            RowDetailsTemplate = {
                New-UiLabel -Text "Dependencies: $($_.DependentServices.Count)"
                New-UiLabel -Text $_.Description
            }
        }
        New-UiDataGrid @gridParams
    .EXAMPLE
        # Cell-embedded controls: Toggle (two-way), Button (per-row), Link (clickable URL)
        $rows = @(
            [pscustomobject]@{ Name='node-a'; Online=$true;  Url='https://node-a.local' }
            [pscustomobject]@{ Name='node-b'; Online=$false; Url='https://node-b.local' }
        )
        New-UiDataGrid -Variable nodes -Items $rows -Editable -Columns {
            New-UiColumn Name -ReadOnly
            New-UiColumn -Header 'Enabled' -Type Toggle -Binding Online -OnChange { Write-Host "$($_.Name) -> $($_.Online)" }
            New-UiColumn -Header 'Ping' -Type Button -Text 'Ping' -Icon NetworkAdapter -Action { Test-Connection $_.Name -Count 1 }
            New-UiColumn -Header 'Open' -Type Link -Text 'Open' -Url '{Url}'
        }
    .EXAMPLE
        # Live updates via -ItemsSource. Bare ArrayList works because PsUi binds $rows to
        # the wrap - $rows after the call IS the thread-safe list, so $rows.Add() from
        # a button action lands in the grid without ceremony.
        $rows = [System.Collections.ArrayList]::new()
        New-UiWindow -Title 'Live feed' -Content {
            New-UiDataGrid -Variable feed -ItemsSource $rows -Fill
            New-UiButton -Text 'Add row' -Action {
                [void]$rows.Add([pscustomobject]@{ Time = Get-Date; Value = Get-Random })
            }
        }
    .EXAMPLE
        # Right-click actions per row
        New-UiDataGrid -Variable svc -Items (Get-Service) -RowContextMenu {
            New-UiMenuItem 'Restart' -Icon Refresh -Action { Restart-Service $_.Name } -Enabled { $_.Status -eq 'Stopped' }
            New-UiMenuItem 'Details' -Sync -Action { Show-UiMessageDialog -Message ($_ | Format-List | Out-String) }
        }
    .EXAMPLE
        # Legacy hashtable forms (still supported), columns and menu items alike
        New-UiDataGrid -Variable svc -Items (Get-Service) -Columns @(
            @{ Name='Name'; ReadOnly=$true }
            @{ Header='Restart'; Type='Button'; Text='Restart'; Action={ Restart-Service $_.Name } }
        ) -RowContextMenu ([ordered]@{
            'Restart' = @{ Action = { Restart-Service $_.Name }; Icon = 'Refresh'; Enabled = { $_.Status -eq 'Stopped' } }
            'Details' = @{ Action = { Show-UiMessageDialog -Message ($_ | Format-List | Out-String) }; Sync = $true }
        })
    .NOTES
        Variable binding: -ItemsSource wraps your list in a thread-safe one and repoints
        the scope variables that hold the original at the wrap. End result, $list IS the
        wrap afterwards. Five cases the rebind can't reach (see -ItemsSource). When none
        of your scope variables get rebound, a warning fires. Pass -NoBind to opt out and manage
        the binding yourself.

        Async by default actions: cell embedded Button actions and -RowContextMenu items run
        in a background runspace so slow work doesn't freeze the grid. Use -Sync on
        New-UiColumn / New-UiMenuItem (Sync = $true in the hashtable forms) for actions that
        have to stay on the UI thread (dialogs and clipboard work).

        First-row column seeding: if the grid starts empty and rows arrive later, columns are
        built from the first row with readable properties. Once columns exist, additional
        properties on later rows won't add columns. Pass -Columns explicitly for grids whose
        schema isn't uniform across rows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Variable,

        [Parameter(ValueFromPipeline)]
        [object[]]$Items,

        # Untyped so the body can accept ObservableCollection, AsyncObservableCollection,
        # [ref] to either or to a raw IList, or any IEnumerable. [System.Collections.IEnumerable]
        # would reject [ref] (PSReference doesn't implement IEnumerable).
        $ItemsSource,

        $Columns,

        [int]$Height = 300,

        [int]$Width,

        [switch]$FullWidth,

        [switch]$Fill,

        [double]$MaxFillHeight = [double]::PositiveInfinity,

        [double]$MinFillHeight = 50,

        [ValidateSet('Single', 'Extended', 'None')]
        [string]$SelectionMode = 'Extended',

        [switch]$DefaultPropertiesOnly,

        [switch]$HideEmptyColumns,

        [switch]$NoArrayPopup,

        [switch]$NoDictionaryPopup,

        [switch]$NoSafeWrap,

        [switch]$NoBind,

        [switch]$Editable,

        [scriptblock]$OnCellEdit,

        [scriptblock]$OnRowEdit,

        [switch]$NoToolbar,

        [switch]$NoFilter,

        [switch]$NoExport,

        [switch]$NoCopy,

        [switch]$NoSort,

        [switch]$NoContextMenu,

        [switch]$NoColumnPicker,

        [switch]$NoStretchLastColumn,

        [switch]$NoVisualValues,

        [switch]$NoMarkEmptyCells,

        [switch]$CaptureScrollWheel,

        [scriptblock]$OnSelectionChanged,

        [scriptblock]$OnDoubleClick,

        [object]$EnabledWhen,

        [hashtable]$WPFProperties,

        [scriptblock]$RowDetailsTemplate,

        [scriptblock]$RowBackground,

        [int]$FrozenColumns,

        [string]$EmptyMessage = 'No items to display.',

        [switch]$NoAlternatingRowBrush,

        $DefaultSort,

        [double]$RowHeight,

        # Untyped: takes a New-UiMenuItem definition block or array, or the legacy IDictionary keyed by label. No [hashtable] constraint on the legacy form: it silently converts [ordered]@{} to Hashtable and scrambles the declared menu order.
        $RowContextMenu,

        [switch]$SanitizeFormulas
    )

    begin {  $accumulated = [System.Collections.Generic.List[object]]::new() }

    process {
        if ($null -ne $Items) {  foreach ($entry in $Items) { [void]$accumulated.Add($entry) }  }
    }

    end {
        # An empty ObservableCollection passed to -ItemsSource is falsy in PS, but still counts as "you supplied a collection".
        if ($accumulated.Count -gt 0 -and $PSBoundParameters.ContainsKey('ItemsSource')) {
            throw "New-UiDataGrid cannot use both -Items and -ItemsSource. Only one can be used."
        }

        if ($PSBoundParameters.ContainsKey('ItemsSource') -and $NoSafeWrap) {
            Write-Warning "New-UiDataGrid: -NoSafeWrap has no effect with -ItemsSource. The caller's collection is bound as-is; the safe-wrap pass only runs on the -Items path."
        }

        $session = Assert-UiSession -CallerName 'New-UiDataGrid'
        $parent  = $session.CurrentParent
        $colors  = Get-ThemeColors

        Write-Debug "Creating data grid '$Variable' items=$($accumulated.Count) editable=$Editable"

        # Builder input for -Columns (New-UiColumn block or array) normalizes here. Plain property name strings stay legal in the mix. Empty coerces back to $null so the auto column path still triggers.
        if ($null -ne $Columns) {
            $Columns = ConvertTo-UiDefinitionArray -InputObject $Columns -ParameterName '-Columns' -CallerName 'New-UiDataGrid' -AllowString
            if ($Columns.Count -eq 0) { $Columns = $null }
        }

        # Builder input for -RowContextMenu folds into the ordered form keyed by label that the menu builder already eats. The legacy IDictionary passes through whole.
        if ($null -ne $RowContextMenu) {
            $RowContextMenu = ConvertTo-UiDefinitionArray -InputObject $RowContextMenu -ParameterName '-RowContextMenu' -CallerName 'New-UiDataGrid' -PassThruDictionary
            if ($RowContextMenu -isnot [System.Collections.IDictionary]) {
                $folded = [ordered]@{}
                foreach ($menuDef in $RowContextMenu) {
                    if (!$menuDef['Text']) {
                        throw "New-UiDataGrid: each -RowContextMenu item needs a Text key. Use New-UiMenuItem, or the legacy [ordered]@{ 'Label' = @{ Action = ... } } form."
                    }
                    if ($folded.Contains([string]$menuDef['Text'])) {
                        throw "New-UiDataGrid: duplicate -RowContextMenu label '$($menuDef['Text'])'. Menu items are keyed by label, and labels must be unique (case-insensitive)."
                    }

                    # Copy all but Text so absent Sync/Enabled stay absent. The menu builder reads .Contains() on them.
                    $itemDef = @{}
                    foreach ($key in $menuDef.Keys) { if ($key -ne 'Text') { $itemDef[$key] = $menuDef[$key] } }
                    $folded[[string]$menuDef['Text']] = $itemDef
                }
                $RowContextMenu = $folded
            }
        }

        # Resolve the backing collection
        $collection     = $null
        $isOwned        = $false
        $mirrorAttached = $false

        if ($PSBoundParameters.ContainsKey('ItemsSource')) {
            $uiDispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher

            # PS 5.1 $obj -is [Open`1] throws "Late bound operations cannot be performed on fields with types for which Type.ContainsGenericParameters is true."
            # Check the inheritance and match the generic type definition by FullName instead.
            $kindOf = {
                param($Obj)
                if ($null -eq $Obj)                                             { return 'Null' }
                if ($Obj -is [System.Management.Automation.PSReference])        { return 'Ref' }
                $t = $Obj.GetType()
                while ($null -ne $t) {
                    if ($t.IsGenericType) {
                        $def = $t.GetGenericTypeDefinition().FullName
                        if ($def -eq 'PsUi.AsyncObservableCollection`1')                  { return 'PsUiObservable' }
                        if ($def -eq 'System.Collections.ObjectModel.ObservableCollection`1') { return 'WpfObservable' }
                    }
                    $t = $t.BaseType
                }
                return 'Other'
            }

            # Plain ol' ObservableCollection<T> isn't threadsafe. Helpers fired from async button actions live on a background runspace. Calling .Add() on the user's bare ObservableCollection from there throws "This type of CollectionView does not support changes to its SourceCollection from a thread different from the Dispatcher thread."
            # Only PsUi.AsyncObservableCollection is safe to bind directly. Everything else gets wrapped + mirrored.
            $itemsSourceKind = & $kindOf $ItemsSource
            switch ($itemsSourceKind) {
                'Null' {
                    $collection = [PsUi.GridOwnedCollection[object]]::new()
                    $isOwned    = $true
                    break
                }

                # Already the threadsafe observable, bind directly. Refresh its Dispatcher in case the collection was constructed on a different STA thread.
                'PsUiObservable' {
                    try { $ItemsSource.UpdateDispatcher() } catch { Write-Debug "UpdateDispatcher failed: $_" }
                    $collection = $ItemsSource
                    break
                }

                # Plain WPF ObservableCollection. Same wrap and mirror as the value type branch.
                'WpfObservable' {
                    $wrapper = [PsUi.AsyncObservableCollection[object]]::new($ItemsSource, $uiDispatcher)
                    $wrapper.AttachMirror($ItemsSource)
                    $mirrorAttached = $true
                    $collection = $wrapper
                    break
                }

                # [ref] promotion
                'Ref' {
                    $orig     = $ItemsSource.Value
                    $origKind = & $kindOf $orig
                    if ($origKind -eq 'PsUiObservable') {
                        try { $orig.UpdateDispatcher() } catch { Write-Debug "UpdateDispatcher failed: $_" }
                        $collection = $orig
                    }
                    else {
                        $wrapper           = [PsUi.AsyncObservableCollection[object]]::new($orig, $uiDispatcher)
                        $ItemsSource.Value = $wrapper
                        $collection        = $wrapper
                    }
                    break
                }

                # Value type collection (ArrayList, List<T>, array, anything else IEnumerable).
                  default {
                    $wrapper = [PsUi.AsyncObservableCollection[object]]::new($ItemsSource, $uiDispatcher)
                    if ($ItemsSource -is [System.Collections.IList] -and !$ItemsSource.IsReadOnly -and !$ItemsSource.IsFixedSize) {
                        $wrapper.AttachMirror($ItemsSource)
                        $mirrorAttached = $true
                    }
                    $collection = $wrapper
                }
            }

            # Walk up the scopes, repoint every variable that ref equals the original at the wrap.
            # $list.Add() from outside now lands on the threadsafe collection. Ref/PsUiObservable are handled above. Null branch has nothing to wrap.
            if (!$NoBind -and
                $itemsSourceKind -in 'WpfObservable', 'Other' -and
                $null -ne $collection -and
                !([object]::ReferenceEquals($collection, $ItemsSource))) {

                $promotedNames = [System.Collections.Generic.List[string]]::new()
                for ($scopeIdx = 1; $scopeIdx -lt 50; $scopeIdx++) {
                    try {
                        $scopeVars = Get-Variable -Scope $scopeIdx -ErrorAction Stop
                    }
                    catch [System.ArgumentOutOfRangeException] { break }
                    catch { Write-Debug "Variable bind scope $scopeIdx walk failed: $_"; continue }

                    foreach ($psVar in $scopeVars) {
                        # $psVar.Value can throw for lazy loaded variables (disposed COM, missing registry, etc). Catch per variable so one misbehaving slot doesn't kill the rest of the scope.
                        $matched = $false
                        try { $matched = [object]::ReferenceEquals($psVar.Value, $ItemsSource) }
                        catch { Write-Debug "Variable bind read of '$($psVar.Name)' failed: $_"; continue }
                        if ($matched) {
                            try {
                                Set-Variable -Name $psVar.Name -Value $collection -Scope $scopeIdx -Force -ErrorAction Stop
                                [void]$promotedNames.Add("`$$($psVar.Name)@$scopeIdx")
                            }
                            catch { Write-Debug "Variable bind rewrite of '$($psVar.Name)' at scope $scopeIdx failed: $_" }
                        }
                    }
                }
                if ($promotedNames.Count -gt 0) {
                    Write-Debug "Variables bound: $($promotedNames -join ', ')"
                }
                else {
                    Write-Debug "Variables bound: nothing matched"
                    # Zero rewrite usually means -ItemsSource got fed a property access ($obj.Items) or an unbound expression (eg Get-Garbage). The grid still binds against the wrap but you have no handle - Add-/Set-/Clear-UiDataGridItems and outside $list.Add() drop on the floor with no obvious clue why.
                    Write-Warning 'New-UiDataGrid -ItemsSource: could not repoint any caller variable to the autowrapped collection. Use a local variable or [ref] so $list.Add() and the helpers stay connected to the grid.'
                }
            }
            elseif ($NoBind -and
                    $itemsSourceKind -in 'WpfObservable', 'Other' -and
                    $null -ne $collection -and
                    !([object]::ReferenceEquals($collection, $ItemsSource))) {
                # You asked for explicit binding management. Skip the scope rewrite. The wrap is still attached to the grid, but your $list keeps pointing at the original.
                Write-Debug "Variable bind skipped (-NoBind). Caller's variable still points at the original collection."
            }
        }
        else {
            $rawItems  = $accumulated.ToArray()
            $safeItems = if ($NoSafeWrap -or $rawItems.Count -eq 0) { $rawItems }
                         else { @(ConvertTo-SafeDataArray -DataArray $rawItems) }

            # Flatten to PSCustomObject so WPF binding stops pretending PowerShell added properties don't exist. The snapshot tucks a cached _SearchText on each row for the filter and keeps the original at $row._BaseObject. Skip on empty input - Mandatory binding chokes.
            $snapItems = if ($null -eq $safeItems -or $safeItems.Count -eq 0) { @() }
            else { @(ConvertTo-UiDataGridSnapshot -Items $safeItems -BuildSearchIndex) }

            # GridOwnedCollection is how Set/Add/Clear-UiDataGridItems tell owned (built here) from what you passed via -ItemsSource.
            $observable = [PsUi.GridOwnedCollection[object]]::new()
            foreach ($entry in $snapItems) { [void]$observable.Add($entry) }
            $collection = $observable
            $isOwned    = $true
        }

        # WPF doesn't ship a "highlight but don't fire events" mode. Single mode plus a suppressed SelectionChanged handler here is the closest thing.
        $effectiveSelMode = if ($SelectionMode -eq 'None') { 'Single' } else { $SelectionMode }
        $singleSelect     = ($effectiveSelMode -eq 'Single')

        $dataGrid = New-StyledDataGrid -SingleSelect:$singleSelect -NoSort:$NoSort -NoContextMenu:$NoContextMenu -NoStarResizeUnlock:$NoStretchLastColumn

        $dataGrid.ItemsSource = [System.Windows.Data.CollectionViewSource]::GetDefaultView($collection)
        $dataGrid.IsReadOnly  = !$Editable

        # Height is a cap. Grid shrinks to data when there's less of it (no dead space below the last row), scrolls internally once data overflows.
        $dataGrid.MaxHeight = if ($Fill) { [double]::PositiveInfinity } else { $Height }
        $dataGrid.MinHeight = 64
        if ($Width) { $dataGrid.Width = $Width  }
        else {
            # MinWidth floors autosize so a default properties Get-Service grid (~450px wide) doesn't open in a dwarf of a window. Stretch is preserved - a wider parent still gets a wider grid.
            $dataGrid.MinWidth = 600
        }
        if ($RowHeight) { $dataGrid.RowHeight = $RowHeight }
        elseif ($Editable) {
            # Edit controls (TextBox focus border, ComboBox padding) are taller than the display cell, so lock the row height or click to edit ends up bouncing the row taller.
            $dataGrid.RowHeight = 32
        }

        # Default cell padding (12,6,12,6) eats up 12px vertical. Fine at 32px but text can sometimes clip below that. Tighten the padding when rows are short or editable.
        $wantsCompactCells = $Editable -or ($RowHeight -gt 0 -and $RowHeight -lt 32)
        if ($wantsCompactCells) {
            $cellBaseStyle = if ($null -ne [System.Windows.Application]::Current) {  [System.Windows.Application]::Current.TryFindResource('ModernDataGridCellStyle')  }
                             else { $null }

            $compactCellStyle = if ($cellBaseStyle) {  [System.Windows.Style]::new([System.Windows.Controls.DataGridCell], $cellBaseStyle)  }
                                else { [System.Windows.Style]::new([System.Windows.Controls.DataGridCell]) }

            [void]$compactCellStyle.Setters.Add([System.Windows.Setter]::new(  [System.Windows.Controls.Control]::PaddingProperty, [System.Windows.Thickness]::new(12, 2, 12, 2)))
            $dataGrid.CellStyle = $compactCellStyle
        }

        # FrozenColumns lands after the column build below. Build-UiDataGridColumns rebuilds the column collection and WPF helpfully resets FrozenColumnCount in the process.
        # Alternating row brush handling sits after RegisterElement below - the registration call (and eve bnry theme switch after) resets the stripe color, which would clobber it here.

        # Build-UiDataGridColumns takes [object[]], so binding copies $collection into an array. It only probes Count and indexers, both fine on the copy.
        $colBuildParams = @{
            DataGrid              = $dataGrid
            Items                 = $collection
            Columns               = $Columns
            Editable              = $Editable
            DefaultPropertiesOnly = $DefaultPropertiesOnly
            HideEmptyColumns      = $HideEmptyColumns
            NoStretchLastColumn   = $NoStretchLastColumn
            VisualValues          = !$NoVisualValues
            MarkEmptyCells        = !$NoMarkEmptyCells
        }
        $colInfo = Build-UiDataGridColumns @colBuildParams

        # Prerender flood guard. Threshold and clause come from Get-UiGridFloodWarning, shared with the column picker's $confirmFlood (New-ColumnVisibilityPopup.ps1) so the two can't drift.
        # Suppressed when -DefaultPropertiesOnly is on or -Columns was handpicked. PSCustomObject input has no DefaultDisplayPropertySet ($defaultCount = 0), so the dialog drops the "Load defaults" option and offers cancel only.
        $flood         = Get-UiGridFloodWarning
        $cellThreshold = $flood.CellThreshold
        $allCount      = [int]$colInfo.AllProperties.Count
        $defaultCount  = [int]$colInfo.DefaultProperties.Count
        $rowCount      = [int]$collection.Count
        $cellCount     = $rowCount * $allCount
        $hasDefaults   = ($defaultCount -gt 0 -and $defaultCount -lt $allCount)

        if ($cellCount -gt $cellThreshold -and
            !$DefaultPropertiesOnly -and
            $null -eq $Columns) {

            $msg = if ($hasDefaults) {
                ("This grid is about to load {0} columns across {1} rows. $($flood.Clause) " +
                 "Load the default set of {2} columns instead? Extras come back through the 'Show/Hide Columns' button in the toolbar.") -f
                    $allCount, $rowCount, $defaultCount
            }
            else {
                ("This grid is about to load {0} columns across {1} rows. $($flood.Clause) " +
                 "Continue?") -f $allCount, $rowCount
            }

            $dialogArgs = @{
                Title       = 'Load all columns?'
                Message     = $msg
                ConfirmText = if ($hasDefaults) { 'Load defaults' } else { 'Cancel load' }
                CancelText  = if ($hasDefaults) { 'Load all' } else { 'Continue' }
            }

            try {
                if (Show-UiConfirmDialog @dialogArgs) {
                    if ($hasDefaults) {
                        # Collapse nondefaults in place. The WPF column objects already exist. Cheaper than rebuilding.
                        foreach ($col in $dataGrid.Columns) {
                            $hdr = if ($null -ne $col.Header) { [string]$col.Header } else { '' }
                            if ($hdr -and ($hdr -notin $colInfo.DefaultProperties)) {
                                $col.Visibility = [System.Windows.Visibility]::Collapsed
                            }
                        }
                        # Star moved with the now hidden original last column. Reassign so the row fills again and ResizeUnlock's slack recovery has something to track.
                        Set-LastDataColumnStar -DataGrid $dataGrid -Skip:$NoStretchLastColumn
                    }
                    else {
                        # No defaults to fall back to. Confirm = cancel load: collapse every column.
                        foreach ($col in $dataGrid.Columns) {
                            $col.Visibility = [System.Windows.Visibility]::Collapsed
                        }
                    }
                }
            }
            catch { Write-Debug "Flood prompt at construction failed: $_" }
        }

        # Tag carries the bookkeeping the column picker reaches for on each visibility toggle.
        # StretchLastColumn is the gate that reruns Set-LastDataColumnStar, and it still honours the original -NoStretchLastColumn switch passed at construction.
        $dataGrid.Tag = @{
            AllProperties       = $colInfo.AllProperties
            DefaultProperties   = $colInfo.DefaultProperties
            PopulatedProperties = $colInfo.PopulatedProperties
            Collection          = $collection
            StretchLastColumn   = !$NoStretchLastColumn
            IsOwned             = $isOwned
            # New-UiTab's PreviewMouseWheel reads this and lets the wheel through when set.
            CaptureScrollWheel  = [bool]$CaptureScrollWheel
            # Export / copy paths consult this and quote prefix Excel formula triggers.
            SanitizeFormulas    = [bool]$SanitizeFormulas
        }

        # Resize unlock already attached inside New-StyledDataGrid (skipped under -NoStretchLastColumn: no star, no lockout).

        # No starter data means no row to read property names from. Watch for the first add, seed columns, then drop the sub so later Adds don't reenter the guard.
        if ($colInfo.AllProperties.Count -eq 0 -and $collection -is [System.Collections.Specialized.INotifyCollectionChanged]) {
            $seedState = @{
                DataGrid      = $dataGrid
                Collection    = $collection
                Params        = $colBuildParams
                FrozenColumns = $FrozenColumns
                Handler       = $null
            }
            $seedHandler = {
                param($sender, $eventArgs)
                if ($seedState.DataGrid.Columns.Count -gt 0) { return }
                if ($seedState.Collection.Count -eq 0) { return }

                # Detach, then defer the real work to Background priority. Building columns and reapplying FrozenColumnCount INSIDE the CollectionChanged notification corrupts the ItemContainerGenerator's accumulated count - WPF then spams "ItemsControl is inconsistent with its items source" on every layout pass. Same rule as the ScrollChanged pin in Add-UiDataGridStarResizeUnlock: never mutate layout affecting grid state from inside the pipeline that's mid notification.
                # MulticastDelegate.Invoke snapshots its invocation list, so removing from inside the fire is safe.
                # The closure reaches its own delegate through $seedState - it captured the hashtable reference, with the delegate stashed there after GetNewClosure.
                if ($seedState.Handler) {
                    $seedState.Collection.remove_CollectionChanged($seedState.Handler)
                    $seedState.Handler = $null
                }

                # Rebind to a local: nested .GetNewClosure() only captures the immediate scope's locals, not what the outer closure itself captured.
                $localState = $seedState
                [void]$seedState.DataGrid.Dispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::Background,
                    [Action]{
                        if ($localState.DataGrid.Columns.Count -gt 0) { return }

                        Write-Debug "New-UiDataGrid: seeding columns from first arrived row"
                        $items = [System.Collections.Generic.List[object]]::new()
                        foreach ($entry in $localState.Collection) { [void]$items.Add($entry) }
                        if ($items.Count -eq 0) { return }

                        # Detach ItemsSource for the whole surgery. Building columns on a LIVE grid corrupts the ItemContainerGenerator's change bookkeeping ("ItemsControl is inconsistent with its items source" on every layout pass after), and DeferRefresh is no answer - Build's BeginInit/EndInit refreshes the ItemCollection, which throws on a defer pending view.
                        # Unbound, there is no view processing to corrupt. Reattaching is a fresh bind, same as construction. Adds landing mid surgery are absorbed by it.
                        #
                        # No try/finally: PS's CheckActionPreference NREs on try block exit when the scriptblock runs off pipeline (this is a Dispatcher delegate), and the hijacked unwind SKIPS finally - the grid stayed detached, showing zero rows forever. trap handles the error path. The tail reattach handles success. Same pattern as Add-UiDataGridRowDetails.
                        # $seedGrid is a plain local on purpose. $rebind below closes over it, and an inner GetNewClosure only captures THIS scope's locals - reaching for $localState (an outer closure capture) in there hands back $null and the reattach silently does nothing, leaving the grid empty forever.
                        $seedGrid    = $localState.DataGrid
                        $savedSource = $seedGrid.ItemsSource
                        $savedView   = $savedSource -as [System.ComponentModel.ICollectionView]
                        $savedSorts  = if ($savedView) { @($savedView.SortDescriptions) } else { @() }

                        # Built BEFORE the detach below, because a trap covers its whole scope no matter where the statement sits. Dfined after, an error thrown on the detach itself would reach the trap with $rebind still $null, and & $null throws before the reattach ever runs.
                        # Cycling ItemsSource wipes the view's SortDescriptions, so -DefaultSort on a grid that started empty died the moment its first rows landed (it applied at build, then vanished). SortDescription is a struct, so the array above holds copies and survives the clear. Same save and restore the column picker and the errors tab already do around their rebuilds.
                        $rebind = {
                            $seedGrid.ItemsSource = $savedSource
                            if (!$savedView -or $savedSorts.Count -eq 0 -or $savedView.SortDescriptions.Count -gt 0) { return }
                            foreach ($sd in $savedSorts) {
                                # Per entry catch, same as Add-UiDataGridDefaultSort: a mixed type column throws on Add and has to come back out, or every later refresh rethrows it.
                                try { $savedView.SortDescriptions.Add($sd) }
                                catch {
                                    [void]$savedView.SortDescriptions.Remove($sd)
                                    Write-Debug "Seed rebind dropped sort '$($sd.PropertyName)': $($_.Exception.Message)"
                                }
                            }
                        }.GetNewClosure()

                        $seedGrid.ItemsSource = $null

                        trap {
                            & $rebind
                            Write-Debug "New-UiDataGrid seed build failed: $($_.Exception.Message)"
                            continue
                        }

                        $rebuildParams = $localState.Params
                        $rebuildParams.Items = $items
                        $newInfo = Build-UiDataGridColumns @rebuildParams

                        # First arriving row had nothing readable - rearm so a later row can try.
                        if (!$newInfo -or $newInfo.AllProperties.Count -eq 0) {
                            if ($localState.SelfRef -and !$localState.Handler) {
                                $localState.Handler = $localState.SelfRef
                                $localState.Collection.add_CollectionChanged($localState.SelfRef)
                            }
                            & $rebind
                            return
                        }

                        $tag = $localState.DataGrid.Tag
                        if ($tag -is [hashtable]) {
                            $tag.AllProperties       = $newInfo.AllProperties
                            $tag.DefaultProperties   = $newInfo.DefaultProperties
                            $tag.PopulatedProperties = $newInfo.PopulatedProperties
                        }

                        # WPF coerced the construction time FrozenColumnCount to 0 against the then empty Columns collection and never recoerces on column adds.
                        # CoerceValue reruns it against the real columns. The reassign to 0 then N covers hosts where the retained base value didn't survive. The accent helper bailed on the empty grid too.
                        if ($localState.FrozenColumns -gt 0) {
                            $localState.DataGrid.CoerceValue([System.Windows.Controls.DataGrid]::FrozenColumnCountProperty)
                            if ($localState.DataGrid.FrozenColumnCount -ne $localState.FrozenColumns) {
                                $localState.DataGrid.FrozenColumnCount = 0
                                $localState.DataGrid.FrozenColumnCount = $localState.FrozenColumns
                            }
                            Add-UiDataGridFrozenColumnAccent -DataGrid $localState.DataGrid -FrozenColumns $localState.FrozenColumns
                            foreach ($col in $localState.DataGrid.Columns) {
                                if ($col.DisplayIndex -lt $localState.FrozenColumns) { $col.CanUserReorder = $false }
                            }
                        }

                        # Known cosmetic: the last column star set during the unbound build renders at natural width after the rebind (dead space to its right). Some DataGrid internal width state doesn't reengage stars after an ItemsSource cycle - deferred star reapply and reactive arm suspension don't fix it, don't retry them. Freeze and filter behave. Leaving it.
                        & $rebind
                    }.GetNewClosure())
            }.GetNewClosure()
            $seedState.Handler = $seedHandler
            $seedState.SelfRef = $seedHandler
            $collection.add_CollectionChanged($seedHandler)
        }
        else { $seedState = $null }

        # Both the mirror subscription (set in the WpfObservable / writable IList branches above) and the seed handler subscription (just above) outlive the visual grid via delegate refs back to closures built here. Without an explicit detach, every long lived source collection or stale grid pins both alive until the user's collection is itself collected. Hook the owning Window.Closed - Unloaded would overfire on tab virtualization and rip both subs out the first time the user clicks away.
        if ($mirrorAttached -or ($null -ne $seedState -and $null -ne $seedState.Handler)) {
            $cleanup = @{
                Done           = $false
                Collection     = $collection
                MirrorAttached = $mirrorAttached
                SeedState      = $seedState
            }
            $hookCleanup = {
                if ($cleanup.Done) { return }
                $window = [System.Windows.Window]::GetWindow($this)
                if (!$window) { return }
                # Rebind to a local: PS .GetNewClosure() only captures the immediate parent scope.
                # Without this hop the inner Closed scriptblock sees an empty $cleanup.
                $localCleanup = $cleanup
                $window.Add_Closed({
                    if ($localCleanup.MirrorAttached) {
                        try { $localCleanup.Collection.DetachMirror() }
                        catch { Write-Debug "Grid mirror detach failed: $_" }
                    }
                    if ($localCleanup.SeedState -and $localCleanup.SeedState.Handler) {
                        try { $localCleanup.SeedState.Collection.remove_CollectionChanged($localCleanup.SeedState.Handler) }
                        catch { Write-Debug "Seed handler detach failed: $_" }
                        $localCleanup.SeedState.Handler = $null
                    }
                }.GetNewClosure())
                $cleanup.Done = $true
            }.GetNewClosure()
            # Initialized fallback - grids built and disposed without ever loading still get the detach hook. Double hook protection lives in $cleanup.Done.
            $dataGrid.Add_Loaded($hookCleanup)
            $dataGrid.Add_Initialized($hookCleanup)
        }

        if (!$NoArrayPopup)      { Add-ArrayCellPopupHandler -DataGrid $dataGrid }
        if (!$NoDictionaryPopup) { Add-DictionaryValuePopupHandler -DataGrid $dataGrid }

        if ($Editable) {
            Add-UiDataGridEditHandling -Grid $dataGrid -Columns $Columns -OnCellEdit $OnCellEdit -OnRowEdit $OnRowEdit
        }

        if ($OnSelectionChanged -and $SelectionMode -ne 'None') {
            $selHandler = $OnSelectionChanged
            $dataGrid.Add_SelectionChanged({
                param($sender, $eventArgs)
                $selected = @($sender.SelectedItems)
                try { & $selHandler $selected }
                catch { Write-Debug "OnSelectionChanged failed: $($_.Exception.Message)" }
            }.GetNewClosure())
        }

        if ($OnDoubleClick) {
            $dblHandler = $OnDoubleClick
            $dataGrid.Add_MouseDoubleClick({
                param($sender, $eventArgs)
                $row = $sender.SelectedItem
                if ($null -eq $row) { return }
                try { & $dblHandler $row }
                catch { Write-Debug "OnDoubleClick failed: $($_.Exception.Message)" }
            }.GetNewClosure())
        }

        if ($RowDetailsTemplate) { Add-UiDataGridRowDetails -DataGrid $dataGrid -Template $RowDetailsTemplate }

        if ($RowBackground) { Add-UiDataGridRowBackground -DataGrid $dataGrid -RowBackground $RowBackground }

        if ($RowContextMenu -and $RowContextMenu.Count -gt 0 -and !$NoContextMenu) { Add-UiDataGridRowContextMenuItems -DataGrid $dataGrid -Items $RowContextMenu }

        # FrozenColumnCount lands AFTER the column build - WPF resets it to zero on each column add.
        if ($FrozenColumns -gt 0) {
            $dataGrid.FrozenColumnCount = $FrozenColumns
            Add-UiDataGridFrozenColumnAccent -DataGrid $dataGrid -FrozenColumns $FrozenColumns

            # Frozen columns can't be dragged out of the freeze range...
            foreach ($col in $dataGrid.Columns) {
                if ($col.DisplayIndex -lt $FrozenColumns) { $col.CanUserReorder = $false }
            }

            # CanUserReorder=false doesn't stop nonfrozen columns landing inside the freeze range.
            # Snap them back out. ColumnReordered (not ColumnDisplayIndexChanged) so no recursion.
            $frozenCountForHandler = $FrozenColumns
            $dataGrid.Add_ColumnReordered({
                param($sender, $eventArgs)
                $col = $eventArgs.Column
                if ($null -ne $col -and $col.DisplayIndex -lt $frozenCountForHandler) {
                    $col.DisplayIndex = $frozenCountForHandler
                }
            }.GetNewClosure())
        }

        [PsUi.ThemeEngine]::RegisterElement($dataGrid)

        if (!$NoAlternatingRowBrush) { Add-UiDataGridAlternatingBrush -DataGrid $dataGrid }

        # Default: forward the wheel to the parent so the outer window scrolls with the cursor over the grid.
        # -CaptureScrollWheel keeps it inside the grid for its own scroll.
        if (!$CaptureScrollWheel) {
            $dataGrid.Add_PreviewMouseWheel({
                param($sender, $eventArgs)
                if ($eventArgs.Handled) { return }
                $eventArgs.Handled = $true
                $newEvent = [System.Windows.Input.MouseWheelEventArgs]::new($eventArgs.MouseDevice, $eventArgs.Timestamp, $eventArgs.Delta)
                $newEvent.RoutedEvent = [System.Windows.UIElement]::MouseWheelEvent
                $newEvent.Source = $sender
                $parentEl = $sender.Parent -as [System.Windows.UIElement]
                if ($parentEl) { $parentEl.RaiseEvent($newEvent) }
            })
        }

        $useToolbar = !$NoToolbar -and !($NoFilter -and $NoExport -and $NoCopy -and $NoColumnPicker)

        # Overlay wraps the DataGrid, not the dock panel. Otherwise the icon floats over the toolbar instead of the column header band.
        $gridArea = $dataGrid
        if (![string]::IsNullOrEmpty($EmptyMessage)) {
            $gridArea = Add-UiDataGridEmptyOverlay -HostControl $dataGrid -DataGrid $dataGrid -Message $EmptyMessage
        }

        $hostControl = $gridArea

        if ($useToolbar) {
            # Captures the live collection. Both paths are reference types, so the provider always sees current data.
            $collectionRef = $collection
            $itemsProvider = { $collectionRef }.GetNewClosure()

            $toolbarParams = @{
                DataGrid            = $dataGrid
                Colors              = $colors
                NoFilter            = $NoFilter
                NoExport            = $NoExport
                NoCopy              = $NoCopy
                NoColumnPicker      = $NoColumnPicker
                AllProperties       = $colInfo.AllProperties
                DefaultProperties   = $colInfo.DefaultProperties
                PopulatedProperties = $colInfo.PopulatedProperties
                ItemsProvider       = $itemsProvider
            }

            $tb = New-UiDataGridToolbar @toolbarParams

            if ($tb.FilterBox) {
                # Stash the FilterBox on Tag so Add-UiDataGridEditHandling can reach FilterBox.Tag.ClearSearchCache after a row commit. Without this key the filter keeps matching the old text and the edited row vanishes from a filtered view.
                if ($dataGrid.Tag -is [hashtable]) { $dataGrid.Tag.FilterBox = $tb.FilterBox }
                New-UiDataGridFilterController -DataGrid $dataGrid -FilterBox $tb.FilterBox | Out-Null
            }

            $dock = [System.Windows.Controls.DockPanel]@{
                LastChildFill = $true
                Margin        = [System.Windows.Thickness]::new(4, 4, 4, 8)
            }

            [System.Windows.Controls.DockPanel]::SetDock($tb.Container, 'Top')
            [void]$dock.Children.Add($tb.Container)
            [void]$dock.Children.Add($gridArea)
            $hostControl = $dock
        }
        else { $gridArea.Margin = [System.Windows.Thickness]::new(4, 4, 4, 8) }

        Set-FullWidthConstraint -Control $hostControl -Parent $parent -FullWidth:$FullWidth

        # -WPFProperties hits whichever container is onscreen (toolbar host or bare grid).
        if ($WPFProperties) { Set-UiProperties -Control $hostControl -Properties $WPFProperties }

        [void]$parent.Children.Add($hostControl)

        # Attach the fill helper to the outer host. With a toolbar that's the DockPanel - toolbar docks Top, DataGrid (LastChildFill) takes whatever's left. Without a toolbar, $hostControl is the grid (or its empty overlay wrap).
        if ($Fill) { Set-UiFillParentHeight -Control $hostControl -MaxHeight $MaxFillHeight -MinHeight $MinFillHeight }

        if ($EnabledWhen) { Register-UiCondition -TargetControl $hostControl -Condition $EnabledWhen }

        if ($DefaultSort) { Add-UiDataGridDefaultSort -DataGrid $dataGrid -Sort $DefaultSort }

        # Register the grid (not the host) for hydration and Set/Add/Clear lookup
        Register-UiControlComplete -Name $Variable -Control $dataGrid
        $session.RegisterListCollection($Variable, $collection)
    }
}
