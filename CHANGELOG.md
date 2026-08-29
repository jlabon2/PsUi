# Changelog

All changes to PsUi will be documented in this file.

## [1.1.1] - 2026-08-24

Functions that standin for the parameters that used to take hashtables, plus the attached property path in `-WPFProperties` finally doing something. Misc bug fixes and threadsafe list improvements. 

### Added

#### Standin functions

Five parameters took nested hashtables and told you nothing when a key was misspelled: `-RowContextMenu`, `-ResultActions`, `-CustomButtons`, `-Columns`, `-HeaderAction`. Neat, and useless the moment you typo a key. Each one now has a function behind it, so keys are real parameters with tab completion and `Get-Help`, and a bad one throws at the line you wrote instead of three functions deep. Pass a definition block, an array of them, or the hashtables you already have. All three forms work everywhere, and the legacy hashtable form is still accepted.

- **New-UiMenuItem**: one `-RowContextMenu` entry. `-Text`, `-Action`, `-Icon`, `-Sync`, and `-Enabled` taking a literal bool or a per row scriptblock. A misspelled `Enabled` used to cast to `$true` and quietly enable everything; a non-bool throws now.
- **New-UiResultAction**: one entry in the output window's Actions dropdown. `-Confirm` (a format string, `{0}` is the selection count) and `-ObjectType` (show the action only on matching result tabs) were both consumed by the code and documented nowhere until now.
- **New-UiDialogButton**: one `Show-UiMessageDialog -CustomButtons` entry. `-Label`, `-Value` (defaults to the label, so a forgotten Value no longer returns `$null`), `-Default`, `-Accent`, and `-Cancel`, which answers Esc.
- **New-UiColumn**: one `-Columns` definition, covering all four column kinds. Toggle without a `-Binding` and Link without a `-Url` or `-Action` throw when you define them, not when the grid builds.
- **New-UiHeaderAction**: the `New-UiPanel -HeaderAction` button.

```powershell
New-UiDataGrid -Variable svc -Items (Get-Service) -RowContextMenu {
    New-UiMenuItem 'Restart' -Icon Refresh -Enabled { $_.Status -eq 'Running' } -Action { Restart-Service $_.Name }
    New-UiMenuItem 'Details' -Sync -Action { Show-UiMessageDialog -Message ($_ | Out-String) }
}
```

#### Other

- **New-UiCredential `-NoPeek`**: the password field grew the same hold to reveal eye button `New-UiInput -Password` has. `-NoPeek` takes it away for tools that run on a screen other people watch.
- **New-UiTab `-Icon`**: the parameter existed and drew nothing. Tab headers render the glyph next to the text now.

### Fixed

- **Attached properties in `-WPFProperties` never applied**: `'Grid.Row' = 1` looked right but did nothing and warned about nothing. The type lookup used an unqualified name that always came back null. Attached values also convert like normal ones now, so `'DockPanel.Dock' = 'Left'` and `'Grid.Row' = '1'` land instead of silently skipping.
- **Charts with a custom `-LabelProperty` came up empty**: the data got converted twice, and the second pass dropped every row. Grouped objects with `-LabelProperty Name -ValueProperty Count` chart correctly now.
- **New-UiWebView navigation callbacks got nulls**: `-OnNavigating` and such fired with empty values because a nested closure captured the wrong scope.
- **Closing a modal child window could throw**: the title bar X set DialogResult and then called Close(), and the second close landed on a window already tearing down.
- **`-Columns @{ Width = 'Auto' }`** warned about an unparseable width and fell back to a default. Auto is a documented spelling and now behaves like one.
- **New-UiGrid**: `-FormLayout` unwrapping fired on grids that never asked for it, and a row definition shorter than the child count pushed children into row 0.
- **Dialogs opened before any window came up unstyled**: a bare `Show-UiMessageDialog`, or a `Show-UiCredentialDialog` you call before your first `New-UiWindow`, drew its text and password boxes with no border and no background. The control styles only ever loaded into a WPF Application, and no dialog created one. A dialog with no Application now themes itself off its own window, which also leaves `Application.Current` free for the next real window to claim on its own thread.
- **`New-UiProgress -Severity` gave every bar the accent blue**: Success, Warning, and Error all came out the same color. The severity brush went into the bar's Tag, and the theme pass that reads Tags for everything else had the ProgressBar branch hardcoded to the accent. The tint follows the severity now.
- **`Add-UiListItem` from a background action threw on every `-Items` list**: only a list that started empty got the threadsafe collection and everything else was a plain ol' ObservableCollection that WPF refuses to change from another thread. All three input paths land in the collection the grid uses now, and `-ItemsSource` now adjust so your variable is repointed at the wrap so `$list.Add()` keeps landing, a warning fires when nothing could be repointed, and `-NoBind` opts out. `-Items @('')` also seeds the empty string instead of silently dropping it. Goal here is effective abstraction of all the common PS arrays/lists to easily use as a threadsafe, observable collection.
- **Typing in a list's filter box disconnected the list from its collection**: each keystroke swapped in a copy, so every later add went to the registered collection and never showed. The filter drives the view now and ItemsSource never changes hands.
- **`Remove-UiListItem` with no `-Item` threw from async actions**: it read the selection off the raw ListBox, which belongs to another thread. It kindly asks the proxy now.
- **An async Cancel button cancels itself**: `Stop-UiAsync` stops the newest running action, and from inside an async button that is the button. Documented, never enforced. `New-UiButton` warns at build time now; an explicit `-NoAsync:$false` is taken as deliberate and stays quiet.
- **`Stop-UiAsync` after a finished run had nothing real to stop**: every run parked its AsyncExecutor in the session until the window closed, disposed or not. Every ending releases it now: complete, error, cancel, the output window path included.
- **`New-UiWindow -WPFProperties` did less than every control's**: strings never converted (`Cursor = 'Hand'` threw into a swallowed debug log), attached properties were skipped without a word, and `Tag` would overwrite the window chrome. It runs through the same path as the controls now, and `Tag` is reserved and stripped with a warning.
- **The hydration `-Debug` warning claimed your objects get serialized**: the same reference crosses; what it loses is the thread that opened it. The message is now more accurate.
- **`Set-UiValue` and `Get-UiValue` did nothing from most async actions**: both looked the session up in a thread local that only the pooled runspace sets. Anything that can prompt gets a runspace of its own instead, which is every button that isn't using `-NoOutput -NoInteractive`, so the ordinary case warned "No active UI session found" and carried on. Both resolve the session the way the rest of the module does now.
- **A grid column's `Choices` came up blank against an enum property**: passed strings never matched the enum sitting behind SelectedValue, so every cell that wasn't midedit rendered empty. Strings parse into the property's own enum type now, and subsets survive instead of being replaced by the full set.
- **`-NoInteractive` help promised an error that doesn't throw**: the text said interactive input fails. `Read-Host` hands back an empty string, `-AsSecureString` an empty one of those, `Get-Credential` nothing at all, and a choice prompt its default answer. The help describes that accurately now.
- **A window with a `New-UiWebView` control added cut off the bottom of the window**: the view raised the window's minimum height by how far down the tab it sat, and down a longish tab that is more than the monitor is tall. The window then laid itself out taller than its own frame, so the last few hundred pixels of every tab sat below the screen edge where no scroll offset reaches. Maximizing made it plain, and once one view had loaded every tab carried it. Dragging such a window short did the same thing from the other end and took the status bar off the bottom with it. The view asks the window for nothing now.
- **A `New-UiWebView` smeared itself over the titlebar when you scrolled past it**: a WebView2 draws into its own child window and takes no notice of WPF clipping. It sits in a fixed slot now and trims to whatever part of that slot is on screen, so it stays readable on the way past instead of drawing over its neighbours. One thing to know if you pass `-WPFProperties`: the keys that place a control in its parent (`Margin`, the alignments, `Visibility`, the widths, attached values like `'Grid.Row'`) now apply to that slot rather than to the browser, and `Height` / `MinHeight` / `MaxHeight` are refused with a warning, since `-Height` and `-MinHeight` are what size a view. Everything else still reaches the browser.
- **A `New-UiWebView` printed an init error every time you left its tab and came back**: WPF raises Loaded again each time a tab shows its content, and the second pass built a fresh CoreWebView2Environment for a control that already had one. The browser carried on working and complained anyway, once per visit. Setup runs once per view now, which also stops the scroll clip hanging another handler off every ancestor on each switch. `New-UiWebView` is sort of... rough, but it's niche, and in a workable state. 

## [1.1.0] - 2026-08-08

- **New-UiDataGrid**: a full datagrid suite with cell buttons / toggles / links, cell editing, row details, row coloring, frozen columns, live `-ItemsSource` binding from background runspaces
- Status bar suite with `Write-*` interception: badges, status text, embedded progress
- Standalone progress bars
- Segoe Fluent Icons support with automatic detection
- Tree checkboxes
- `-Fill` vertical sizing
- A batch of threading and theme fixes, plus strays

### Added

#### DataGrid

`New-UiDataGrid` is the same grid the output window builds its results panel from, dropped inside a `New-UiWindow`. Same columns, same context menu, plus cells that hold controls and opt-in editing.

- **New-UiDataGrid**: `-Items` for a fixed set, `-ItemsSource` for a live one. `-Variable` hands button actions the selected rows as `object[]`. Columns come from the first row, and the toolbar (filter, copy, export, column picker) is on by default with a `-No` switch for every piece.
- **`-Columns`**: omit for automatic column generation, a `string[]` to pick and reorder, hashtables for per-column control (`Name`, `Header`, `Width`, `Format`, `ReadOnly`, editors, validators, cell control `Type`).
- **Cell controls**: `Type = 'Button'`, `'Toggle'`, or `'Link'` in a column hashtable. `$_` in a button's `Action` is the row, a toggle reads and writes the row's value, a link substitutes `{PropName}` into its URL. Buttons and links can pull their label from a row property instead of static `Text`. Actions run async like `New-UiButton`; `Sync = $true` for the rare ones that can't (child windows, mostly).
- **Editable cells**: `-Editable` turns it on, per-column `Editable` narrows it (a bool, a scriptblock, or a property name). Editors follow the value type - bools get a checkbox, enums a dropdown, dates a date picker, everything else text. `Validator` runs before the commit and `$false` cancels it; `-OnCellEdit` and `-OnRowEdit` fire after.
- **`-ItemsSource` binds your variable**: pass a plain `ArrayList`, `List[T]`, array, or `ObservableCollection` and your variable gets rebound to a threadsafe copy the grid watches - `$list.Add(...)` from any runspace just shows up, no `[ref]` ceremony. Handing it 10k rows redraws once, not 10k times. The rebind can't reach what it can't see (property values, hashtable entries, expressions); a warning fires when nothing could be rebound, and `-NoBind` opts out.
- **Add-UiDataGridItem / Set-UiDataGridItems / Clear-UiDataGridItems**: append, replace, or empty a grid from any button action. Hashtable rows convert to PSCustomObject on the way in; `-PassThru` hands back what landed.
- **`-RowContextMenu`**: your own entries above the standard menu - label to scriptblock, `$_` is the rightclicked row. A click inside a multi-selection runs the action against each selected row in turn; Cancel stops the rest, and failures collect into one error dialog. The hashtable form adds `Enabled`, `Icon`, and `Sync`.
- **`-RowDetailsTemplate`**: a scriptblock that builds an expandable panel under the clicked row with the usual PsUi controls; `$_` is the row. Heavy lookups belong in `Invoke-UiAsync` inside it.
- **`-RowBackground`**: scriptblock gets the row, returns a color (or `$null` for the default).
- **`-FrozenColumns N`**: the leftmost N columns stay put under horizontal scroll.
- **`-EmptyMessage`**: what an empty grid says. Defaults to `'No items to display.'`; pass `''` to drop the overlay.
- **`-DefaultSort`**: `'Name'`, `'Name -Descending'`, or an array of them for a multi-key sort.
- **`-RowHeight`**: fixed row height for denser grids.
- **`-SanitizeFormulas`**: quotes copied and exported cells that start like Excel formulas (`=`, `+`, `-`, `@`) so they open as text. Off by default so it leaves clean data alone; turn it on when the rows hold untrusted values.
- **Visual defaults are all opt-out**: striped rows, glyphs for bools, a hatch effect over empty readonly cells. `-NoAlternatingRowBrush`, `-NoVisualValues`, `-NoMarkEmptyCells`.
- **Output window parity flags**: `-DefaultPropertiesOnly`, `-HideEmptyColumns`, `-NoArrayPopup`, `-NoDictionaryPopup`, `-NoSafeWrap`.
- **Filtering**: the toolbar filter hides rows without touching your source list.
- **Column picker**: rebuilt each time it opens, so a grid that starts empty still grows one. Entries show a populated count (`Owner (12/50)`), and "Has Data" hides the all-empty columns. Warns when a bulk reveal would push the grid past ~10k cells.
- **Copy Cell**: first item on the context menu now, and it works in every column type. Copy and export honor column visibility, and the three copy paths (toolbar, menu, Ctrl+C) finally share one implementation - they used to drift.
- **`-CaptureScrollWheel`**: the grid keeps the wheel for its own scrolling instead of handing it to the page.
- **Out-Datagrid catch-up**: the standalone viewer picked up `-RowBackground`, `-DefaultSort`, `-NoSafeWrap`.

#### Status Bar

`New-UiStatusBar` builds the bar, the rest operate on it from any thread.

- **New-UiStatusBar**: docked top or bottom, freeform `-Content` that takes most PsUi controls. It's a customized PsUi status bar rather than the builtin StatusBar control (the builtin's layout rules got in the way).
  - `-DefaultText` prepends a text label.
  - `-AutoProgress` embeds a progress bar driven by plain `Write-Progress` from your actions. Hidden until the first record, gone again on `-Completed`.
  - `-AutoCancel` embeds a Cancel button that lights up while something runs.
  - `-Intercept` makes the bar capture and print your actions' output. `Write-Warning` and `Write-Error` pile up as clickable badges, and the error popup keeps the useful parts (exception type, script, line, stack).
  - `-CaptureHost` (with `-Intercept`) sends `Write-Host` from your buttons into the status text, batched so heavy output stays smooth.
  - `-NoOutputOnly` counts only buttons without output windows, so badges don't double-count what a window already shows.
  - `-CaptureVerbose` and `-CaptureDebug` add badges for those streams; `-CaptureAll` is shorthand for turning every capture on.
  - `-Persist` keeps badge counts across clicks instead of resetting each action.
  - `-MaxMessages` caps popup entries (default 100), oldest out first.
  - Severity tinting: the bar shifts green/yellow/red with the stream and settles back to neutral (2s green, 5s yellow, 8s red).
- **New-UiSpacer**: fills leftover space. Drop it between your label and your buttons to push the buttons right.
- **Set-UiStatusBar**: Adjust the status bar's text, progress, severity, or indeterminate mode, from any thread. Severity coloring resets after 5s unless `-Timeout 0`.
- **Write-Status**: Use it like `Write-Host` but it's aimed at the bar. Usable from any thread.
- **Clear-UiStatus**: Full reset of text, tint, progress, badges, messages.
- **Show-UiStatusBar / Hide-UiStatusBar**: toggle visibility. A hidden bar keeps its state.

#### Progress Bar

Standalone bar, separate from the output window's and the status bar's embedded ones. Shipped bare in 1.0.x (a variable, a height, a switch); grown up now.

- **New-UiProgress**: severity tints, optional label, value display, `-Indeterminate` mode, custom ranges and formats.
- **Set-UiProgress**: update any of that from a background runspace. No parameters, no action.

#### Icon Font

Pick Segoe MDL2 Assets (Win10) or Segoe Fluent Icons (Win11), per session or per window. The default auto-detects, and every control reads the active font from the same place, so a flip shows up on the next thing drawn.

`-NoIconFontFallback` and the fallback-chain machinery shipped before the fonts were manually compared. Fluent turns out to carry every MDL2 icon plus 174 more, and the first cut of CharList.json only named the MDL2 subset. The fallback had nothing to do. This release names 125 of Fluent's documented modern icons (`Blocked`, `Effects`, `PhotoCollection`, `ApplicationGuard`, ...), so the chain finally has real work. Strict MDL2 doesn't recognize them (ie tofu), MDL2 with fallback borrows the Fluent glyph, plain Fluent just draws them.
- **Set-PsUiIconFont / Get-PsUiIconFont**: flip the font for the session. `Auto` picks Fluent when it's installed. Controls already drawn keep their font - reload the window for a full swap.
- **Test-PsUiIcon**: `$true` if a named glyph will actually render, so typos surface at write time instead of as a blank square. Modes: `Active`, `Fluent`, `MDL2`, `Either`.
- **New-UiWindow `-IconFont` / `-NoIconFontFallback`**: per-window override, put back on close so one-off picks don't bleed into the session. Default `Inherit`.
- **Out-TextEditor / Out-Datagrid / Out-CSVDataGrid**: same two params, honored standalone. Inside a parent window the parent wins - same rule as `-Theme`.
- **Show-UiGlyphBrowser**: the title shows renderable against total (`1504 of 1519` under Fluent), tiles missing from the active font dim, and tooltips say which fonts carry each icon. 15 documented names never shipped in either font - the docs lie.
- **CharList.json**: 1659 to 1784 entries. With fallback on, the new names render Fluent-style inside an MDL2 app; `-NoIconFontFallback` keeps it strict and lets them tofu so you know which ones to swap.
- **Build-PsUi.ps1**: builds the target frameworks one at a time. Parallel builds raced on shared files. Costs a few seconds, buys reliability.

#### Tree CheckBoxes

`-ParentCheckBoxes` and `-ChildCheckBoxes` on `New-UiTree`, separately or together. Cascade is on when both are; `-NoCascade` opts out.

- **`-ParentCheckBoxes`**: a box on every item with children. Checking one selects its enabled descendants.
- **`-ChildCheckBoxes`**: a box on every leaf. Used alone, parents become plain labels so the box is the obvious control.
- **`-WhenEnabled` / `-Checked`**: per-item scriptblocks. `WhenEnabled` returning `$false` dims and disables the box (cascade skips it); `Checked` returning `$true` pre-checks it.
- **`-NoCascade`**: independent boxes, for when parent and leaf checks mean different things.
- **Hydration**: `$tree` in a button action is the checked source items - each once, in tree order. Parent-only mode returns the leaves under checked branches, and pathmode standin parents never leak into the result.
- **Selection foreground**: label text follows the selection color while the row is selected. Custom-header items didn't get that on their own; they do now.

#### `-Fill`

- **`-Fill` on `New-UiDataGrid`, `New-UiTree`, `New-UiList`**: the control grows to claim the vertical space left under it and follows resizes. Anything declared after it (buttons, status bars) stays pinned at the bottom.
- **`-Fill` on `New-UiGrid`**: same idea for the layout container, so star rows can split the leftover space. `-FillParent` from previous releases stays as an alias. The cheatsheet is two switches: `-Fill` grows down, `-Stretch` flexes across.
- **`-MaxFillHeight` / `-MinFillHeight` on `New-UiDataGrid`**: a cap for 4K monitors, a floor for layouts where a tall sibling could squash the grid.
- Two `-Fill` controls in one panel split unevenly (the first claims most). Wrap them in `New-UiGrid -Rows '*,*' -Fill` for an even split.

#### Other

- **New-UiTool**: UserPicker, GroupPicker, MemberPicker, and OUPicker input helpers - auto-detected from parameter names, or assigned with `-UserPickerParameters` and friends. The browse button opens the native Windows picker.
- **New-UiInput `OUPicker`**: helper button that opens the OU browser. Off-domain it asks for a DC and credentials first; real failures (network, bad creds) go to the error dialog, not back to the prompt.
- **New-UiInput `-HelperOptions`**: feeds helper buttons from sibling controls. `HelperOptions = @{ Server = 'dcServer'; Credential = 'dcCred' }` pulls both live values at click time - strings naming a registered `-Variable` resolve to that control's value, everything else passes through. Credential controls unwrap to `PSCredential` on their own.
- **Helper button errors**: a failing picker click raises a themed dialog with a cleaned stack, plus a transcript warning. Covers `New-UiInput` helpers and `New-UiTool`'s auto-generated pickers alike.
- **Show-UiOuPicker**: wraps the native OU picker ADUC uses. Returns Name, DistinguishedName, AdsPath; alternate credentials, custom root DN, target DC; works from any thread. The dialog itself is pretty horrendous - it lazy-loads containers and shows a (+) on empty OUs. Placeholder until a hand-rolled replacement lands.
- **New-UiWindow `-Theme Auto`** is the new default: follows the system light/dark setting, Light if the registry key is missing.
- **New-UiDropdown `-OnChange`**: fires with the new value on selection change, matching `New-UiDropdownButton`.
- **New-UiDropdown** items ride the same threadsafe list as everything else now, so `Add-UiListItem` and friends work on dropdowns from background runspaces too.
- **net452 target**: a .NET 4.5.2 build for WinPE and older Windows (no WebView2 there). The build verifies all three output DLLs.
- **New-UiChildWindow**: the title bar shows the resolved window icon next to the title. Borderless child windows never get the OS-drawn icon, so the custom chrome draws its own; no icon if `-Icon` doesn't resolve.

#### Tests

- 40+ new Pester tests over the status bar surface: parameters, severity validation, badges, popups, Clear resets, brush mapping, PS 5.1 clamping.
- 14 for New-UiProgress / Set-UiProgress: indeterminate mode, clamping, severity, labels, the no-params and missing-control paths.
- The DataGrid suites: construction, variable binding, the overhaul regressions, the threadsafe collection's mirror and cross-thread behavior, null rows through the public API, Invoke-UiAsync capture and cancel.

### Fixed

#### DataGrid

- **Cross-thread adds could throw**: a background loop adding to a list or grid the window is showing could die with `Cannot change ObservableCollection during a CollectionChanged event`. Mutations queue onto the window's thread in order now. Hammer away.
- **Second window, dead collection**: a collection made in a second window pinned itself to the first window's thread - adds went through, nothing showed. It homes to its own window now, and creating one on a background thread now throws up front instead of silently dropping everything.
- **Second window, dead callbacks**: async completions in a second window queued onto the first window's exited thread and vanished, while the action itself ran fine. A context menu edit changed the row and the cell kept its old text. Callbacks land on their own window now.
- **Actions that edit a row**: search and filter kept matching the old values after a rightclick action or cell toggle changed them. They see the new ones now.
- **`-DefaultSort` on an empty start**: a grid that began empty lost its sort the moment the first rows landed. It sticks now.
- **Toggle ticks landed on the copy**: with `-Items`, a cell toggle wrote to the grid's snapshot, so a Save button reading your objects saw nothing changed. Ticks land on the original now.
- **Row colors went stale**: `-RowBackground` brushes didn't keep up with list changes. They do now.
- **Piped scalars and falsy rows**: piping `0`, `''`, or `$false` to `Out-Datagrid` dropped those rows, and piping plain strings or numbers drew a ghost grid (strings got a lone `Length` column). Falsy rows stay now, and scalars get a `Value` column. Copy and export emit the values, not character counts.
- **Array cells in copy/export**: Copy Rows and Export CSV wrote `System.Object[]` for array cells. They come out as their joined contents now, ie (`a, b, c`).
- **Resizing `'*'` columns could lock up**: columns that share the leftover width stop taking resize drags once there's none left to give: no error, the drag just stops existing. `New-UiDataGrid` unlocks that, and a click that never drags doesn't pin the width.

#### Status Bar

- **Two ways to kill the bar**: `Write-Status -Severity Info` could freeze the window, and `Set-UiStatusBar` could take down the embedded progress bar. Both fixed.

#### Theme System

- **Update-SingleControlTheme**: theme switches silently skipped some text labels and borders, and nothing ever reported it. They recolor with everything else now.
- **Out-TextEditor / Out-CSVDataGrid theme inheritance**: launched from paths with no theme context, both fell back to `Light` and re-themed the whole process - flipping the parent window's theme out from under you. Both inherit the active theme now.

#### Out-TextEditor

- **Session isolation**: standalone `Out-TextEditor` adopted the calling window's session and disposed it on close, taking the window's captured variables with it. It runs sessionless now, and your session survives even if setup throws midflight.

#### Native Dialogs

- **Show-WindowsObjectPicker**: fixed "No locations can be found" on workgroup machines, DCs, and some domain-joined boxes. It checks domain membership up front and backs off through local+domain+GC, then local+domain, then local. `DiagnoseInit` reports what it detected when it still goes wrong.

#### New-UiTool

- **Async button actions**: `New-UiTool` crashed when launched from a normal async `-Action` - the new window came back to a thread that was already gone. `New-UiButton` spots window-spawners in the action and runs them synchronously instead. (Fixes #22)

#### Other

- **One error ate the run**: a single `Write-Error` midrun routed the whole run to OnError and threw away the pipeline output that worked. OnError still fires; OnComplete gets the results too.
- **Copy/export leaked internals**: every copy path - toolbar Copy and Export, rightclick copy, CSV export, Ctrl+C - wrote the raw rows, so the grid's internal search properties rode along as extra columns. One shared path strips them now, on `Out-Datagrid` and the output window alike.
- **Link color stuck after theme switch**: expandable-cell links froze at their build-time color, so Dark then Light meant white on white. They follow the theme live now.
- **ConvertTo-UiBrush**: the brush cache could be null on the first call from a button action, so color lookups there threw. It initializes itself now, whichever copy of the function ends up running.
- **New-UiButton**: `-WPFProperties Tag` is rejected with a warning - a custom Tag silently disarmed the click handler, and every click died in a cryptic "expression after '&'" dialog. Swapping the Tag after construction gets the same warning.
- **New-UiTree**: a null element in `-Items` is dropped instead of crashing the window build.
- **New-UiGrid stopped unwrapping hand-built label panels**: the label+control unwrap runs only under `-FormLayout` now, so a plain grid no longer tears apart a `New-UiProgress -Label`.
- **Output window errors**: the log shows the real exception instead of the generic shell it arrived in.
- **Output window Escape stall**: the Escape and close handlers no longer freeze the window for half a second.
- **Output window polling timer**: stops when the run finishes instead of ticking 20 times a second for the window's whole life.
- **Nested progress in `-NoWait` output windows**: child activity bars (`Write-Progress -Id` above 0) never rendered - the bar builder read its colors from a scope that was already gone, and every tick logged a "Cannot bind argument to parameter 'Color'" error. Colors are captured up front now.
- **New-UiLabel / New-UiToggle alignment**: labels center vertically now (was Top), and toggles sit level with labeled controls in horizontal panels. Stacked layouts shift slightly.
- **ControlValueExtractor**: tree, grid, and list snapshots stopped carrying a live control reference that could deadlock background threads. Nothing read it - leftover from an earlier design.
- **New-UiChildWindow**: opening a child window without a parent threw `The term 'Set-UIResources' is not recognized` - a click handler couldn't find a module-private function by name. Present since the initial release; resolved ahead of time now.
- **Start-PSUiDemo**: the "Multi-Tab DataSet" card called a function that has never existed in source (aspirational demo code from the initial release). Replaced with a "View Drives" card that runs.
- **Invoke-OnUIThread**: runs its work directly when there's no window to hand it to (tests, mostly), and surfaces failures it used to swallow.
- **Show-UiConfirmDialog**: long button labels grow instead of clipping at the edges.

## [1.0.4] - 2026-04-30

### Fixed
- **PsUi.psm1**: `Import-Module -Force` no longer wipes static state out from under live windows. `OnRemove` fires for `-Force` re-imports, and resetting state mid-execution broke the next click on every open window. Skips the reset when sessions are still alive.
- **New-UiTree**: Dotted property paths (`'Manager.EmployeeId'`, etc.) now actually walk into the child object instead of being treated as one literal property name. Same for `IdProperty`, `PathProperty`, and `DisplayProperty`.
- **New-UiTree**: Path-mode parent nodes used to have `$null` in `.Tag`, which made them dead on click. They now carry a stand-in object with the path so consumers always have something to read. If a piped item later matches a synthesized parent node, that node's tag gets promoted to the real item.
- **New-UiTree**: Help example replaced. The old `Get-Process` example never worked on PS 5.1 (no `.Parent` property), so it's now an org-chart example that runs on both 5.1 and 7+.

### Housekeeping
- Pulled `VirtualizingPanel` setters off the tree style. They were ornamental - the builder hands the tree pre-built `TreeViewItems`, which kills virtualization regardless of the style.

## [1.0.3] - 2026-04-19

### Fixed
- **EnabledWhen**: Dispatcher error on TextBox / PasswordBox controls. (Fixes #3)
- **New-UiTab**: Tab content no longer gets clipped when content overflows the window height.
- **Auto-size windows**: Now scroll properly when `MaxHeight` is reached.

### Housekeeping
- Stale version assertion in `PsUi.Tests.ps1` updated.

## [1.0.2] - 2026-04-19

### Added
- **EnabledWhen**: Added `-EnabledWhen` to 6 controls that were missing it. Now uniform across the input surface.
- **Out-Datagrid / Out-TextEditor / Out-CSVDataGrid**: `-Title` alias for the window title parameter so callers don't have to remember which one each command picked.

### Fixed
- **Read-Host during shutdown**: Closing a window while a background action was sitting on `Read-Host` used to hang the process for ~5 minutes waiting on the input stream. Now exits cleanly.
- **ConvertTo-UiFileAction**: Sanitize arguments before handing them to `cmd`/`exe` invocations to prevent command injection through file paths or user-supplied tokens.

### Performance
- **Variable injection**: Batched into a single `PowerShell` call instead of N round-trips per action. Noticeable on actions with lots of hydrated controls.
- **Async setup**: Cached the setup script and deduplicated the STA/MTA paths. Less work per button click.

### Housekeeping
- README badges (downloads, PowerShell version, tests, stars).

## [1.0.1] - 2026-04-17

### Added
- **New-UiButton**: `-ScrollToTop` switch - scrolls console output to top on completion instead of bottom. Applied to Help button in New-UiTool because nobody reads help from the bottom up.
- **New-UiTool**: Detect missing help files in PS 7+ and offer to open online docs via dialog. PS 7 doesn't ship help by default (kinda lame, but whatever), so we show a parameter quick reference and prompt to open the HelpUri if available.
- **CI**: Pester test workflow for automated testing.

### Fixed
- **Show-UiFilterBuilder**: Presets combobox text now vertically centered.
- **Invoke-OnCompleteHandler**: Null guard on `$autoScrollCheckbox` to prevent potential error when checkbox isn't present.

### Housekeeping
- Remove `settings.json` from tracking, add to `.gitignore`.

## [1.0.0] - 2026-04-16

- Initial release on PSGallery.
