# Changelog

All changes to PsUi will be documented in this file.

## [1.1.1] - 2026-09-28


Controls now get built even if `New-UiWindow` isn't directly called. `Get-UiSession` is now exported. Functions that stand in for the parameters that used to only take hashtables, plus the attached property path in `-WPFProperties` finally working. The Pester suite split into one file per area and stands at 625 tests. Several fixes across buttons, charts, links, the tool window and the threadsafe lists. The docs are now in the [wiki](https://github.com/jlabon2/PsUi/wiki) and the main README got shrunk.

Two critical fixes:
 1) Installing from the gallery led to windows with no PsUi commands exported into them
 2) Opening any window on 5.1 took about nine seconds

### Added

#### Implicit window

- **Implicit window**: call `New-UiLabel` or any other control building function within a script with no `New-UiWindow` around it and PsUi'll read the script for the run of statements that build controls and puts a window around them. The script ends when the window closes. It refuses when the window would run a write like `Remove-Item` a second time, and it stays off under `-NonInteractive`, on a host with no desktop, over PSRemoting, or with `$env:PsUiNoImplicitWindow` set. Lines pasted at a prompt one at a time join the same window, after a prompt.

#### Stand-in functions

Five parameters took nested hashtables, and a something like a misspelled would error silently: `-RowContextMenu`, `-ResultActions`, `-CustomButtons`, `-Columns`, `-HeaderAction`. Useless the moment you typo a key. Each one now has a function behind it, so the same functionality can now be input with functions and parements with tab completion and `Get-Help`, and a bad one throws at the line you wrote instead of three functions deep. Pass a definition block, an array of them, or the hashtables you already have. Those still work everywhere. `-HeaderAction` is the exception as it holds one button and takes a single `New-UiHeaderAction` call in parens or a hashtable, not a block or an array.

- **New-UiMenuItem**: one `-RowContextMenu` entry. `-Text`, `-Action`, `-Icon`, `-NoAsync`, and `-Enabled` taking a literal bool or a per row scriptblock. A nonbool `-Enabled` throws now, where a misspelled one used to enable everything.
- **New-UiResultAction**: one entry in the output window's Actions dropdown. `-Confirm` takes a format string with `{0}` for the selection count, and `-ObjectType` limits the action to matching result tabs. Both existed and neither was documented.
- **New-UiDialogButton**: one `Show-UiMessageDialog -CustomButtons` entry. `-Value` defaults to the label, so a forgotten one no longer returns `$null`, and `-Cancel` answers Esc.
- **New-UiColumn**: one `-Columns` definition for all four column kinds. A Toggle with no `-Binding` or a Link with no `-Url` or `-Action` throws at the definition, not when the grid builds.
- **New-UiHeaderAction**: the `New-UiPanel -HeaderAction` button.

```powershell
New-UiDataGrid -Variable svc -Items (Get-Service) -RowContextMenu {
    New-UiMenuItem 'Restart' -Icon Refresh -Enabled { $_.Status -eq 'Running' } -Action { Restart-Service $_.Name }
    New-UiMenuItem 'Details' -NoAsync -Action { Show-UiMessageDialog -Message ($_ | Out-String) }
}
```

#### Other

- **Get-UiSession** is now exported. It always worked inside a window and now resolves everywhere.
- **Close-UiWindow**: closes, by default, the window the code is being called from. `-Window Parent` closes the one that opened it and `-Window Main` closes everything. `-Prompt` asks first. From a background action it waits for the action to end, so what `-Capture` collects still reaches `-ExportOnClose`.
- **Set-UiCapturedVariable**: `Set-UiCapturedVariable -Name 'lastRun' -Value (Get-Date)` is a prettier way to do what `(Get-UiSession).SetCapturedVariable()` does, and it refuses a name no action could receive.
- **`New-UiDropdown -ItemsSource` and `-NoBind`**: now can use a live list similar to what datagrids already use, so `$choices.Add()` from a background action is added seemlessly. `-Items` is no longer mandatory.
- **`-ScrollWheel` on `New-UiList`, `New-UiTree` and `New-UiDataGrid`**: three options now for scrollwheel behavior. `Page` scrolls the window, `Edge` scrolls the rows until the end of the control, and `Capture` holds the wheel on the control while you hover it.
- **`New-UiTree` rightclick menu**: Expand All, Collapse All, Expand, Collapse and Copy, plus Check and Uncheck All Below on a treelist where checkboxes are added. `-NoContextMenu` skips.
- **New-UiCredential `-NoPeek`**: the password field now has the hold to reveal eye button `New-UiInput -Password` has. `-NoPeek` removes it.
- **`New-UiChildWindow -SizeToContent`**: take the height off the content instead of `-Height`, capped to the work area of the monitor its parent is on. The window pins that height once it is up, so the grip and the edges still drag. `New-UiTool` uses it for a form that would otherwise leave most of a fixed window empty.

#### Docs

- **The wiki** (#18): Getting Started, an FAQ, examples, and pages on how PsUi scripts work, threading, sessions, output, theming, raw WPF access, and the architecture. Every command gets a reference page built from its comment help by `Build-Docs.ps1` and a GitHub Action fails a push when the committed pages don't match a fresh build.
- **`Get-Help New-UiWindow`** (#24): the one compiled cmdlet only printed its syntax. It has a synopsis, a description, every parameter, and five examples now on 5.1 and 7, and `-Online` opens its wiki page.
- **`Build-PsUi.ps1 -BuildDocs`**: rebuilds the reference pages after a compile.

### Changed

- **`-Sync` is now `-NoAsync` on `New-UiColumn` and `New-UiMenuItem`**: `New-UiButton` already called it that. `-Sync` still works as an alias.
- **`New-UiDataGrid` dropped `CaptureScrollWheel` from its `Tag` hashtable**: an internal key, not the parameter. `-CaptureScrollWheel` still works wherever it did and means `-ScrollWheel Capture`. Every control that keeps the wheel carries the same flag.
- **Tabs now give up the mousewheel**: a `-CaptureScrollWheel` grid was the only one that could actually grab it. The tab honors whatever asks for it now.
- **The column picker opens straight away on a wide grid**: it used to count filled cells first, so a `Get-Process` result has columns costing an insane ~7ms a row. The counts now populate in the background behind the popup.
- **The search box prices a property before it reads every row**: it filters against an index built in the background from every property of every row, and on a `Get-Process` result `CommandLine` alone costs 30ms a read on 7. Each property is timed over ten sample rows now and an expensive one stays out of the index, so the box comes active in under two seconds where it used to sit dead for close to 14. What it leaves out it cannot match, so the filter box tooltip names those columns.
- **Returning one object from a button action lists it as one row**: it used to open a Name/Value listing with no filter box as a hashtable would.
- **The Error Details panel uses PsUi's own expander**: it was the last raw WPF `Expander` in the module, drawing the stock circled arrow beside PsUi's own. Its detail text reads in the theme's error color now too.
- **Copy flashes a tick when something reaches the clipboard**: the grid toolbar's Copy button gave no visual indicator is had been run.
- **Labeled controls line up with the controls beside them**: a button beside a labeled input sat halfway between its caption and its box. It lines up with the box now wherever the two share a row, the way `New-UiGrid` rows already did. A `VerticalAlignment` or `Margin` passed through `-WPFProperties` stays as given.
- **Datagrids start with the object's default columns**: object types now lead with their default set in its own order, and files with Mode, LastWriteTime, Length and Name the way the console lists them. `-DefaultPropertiesOnly` and Out-Datagrid's Load defaults use that order, and so do the output window's grids.
- **A nonterminating error in `-Content` doesn't kill the window**: `Get-ChildItem` on a missing folder or a `Write-Error` kept `New-UiWindow` from opening, and only the first error showed. Each one prints now with its file and line, and the window still opens. If a PsUi control fails to build the window still stops, unless `SilentlyContinue` is set, which leaves that control out. A `throw` or `-ErrorAction Stop` stops it either way, and so does a PsUi command called with an invalid parameter.
- **Values that print over several lines show their first line in a grid**: a `FileVersionInfo` cell made its row ~240px tall. The cell reads the first line and an ellipsis.
- **`New-UiList -ItemsSource` points your variable at a threadsafe list**: `$list.Add()` from a background action reaches the list now. The variable isn't the list or array you passed anymore, so `.AddRange()` and `.Sort()` stop working on it, and so does `-is [ArrayList]`. `-NoBind` leaves it alone.
- **Pester tests**: split out of one file into eleven, one per area, at 625 in total, with a good chunk of them tightened up.

### Fixed

- **Output that landed before a terminating error went with it**: 1.1.0 fixed this for a `Write-Error`, which routed the run to OnError and dropped the output. This is the other half of it. `Invoke()` hands its output back only once the pipeline completes, so a terminating error threw everything produced before it away. Output is kept as it lands now, and the Results tab comes up beside the Errors tab.
- **A single object in an array column displayed as its type name**: a column takes its kind from the first row, so a property holding a list on one row and a lone object on the next fell through to WPF, which spells an object with its .NET `ToString`. That cell reads by name.
- **A services grid listed `System.ServiceProcess.ServiceController` for every dependency**: PowerShell hangs its own `ToString` on a few types, and every cell, popup, tooltip, Copy, Export and the search index took the .NET one. Where the .NET answer is the type's own full name, PowerShell's is used instead, so a search for `RpcSs` finds its row. A date or a number is untouched.
- **Focusing a text box shifted its text**: the border animated from 1 to 2 and took that pixel off the content box on every side, so every line jumped inward as the box took focus. The border holds at 1 now and focus reads by color, with hover on a shade of its own so the two still differ.
- **The taskbar icon insconsistently updated when changing themes during runtime**: the shell caches the icon when it builds the button, so a switch rebuilds the button.
- **`New-UiTab -Icon` drew no glyph**: the parameter existed and never reached the header. It sits next to the text in the header.
- **New-UiTool left its header description section when a command only has synopsis**: the synopsis will be used now if theres no description.
- **`New-UiTool` always opened at 800x600 whatever it held**: the height is baed off the form now unless you pass `-Height`.
- **Every window came up empty when PsUi was installed from the gallery**: a window builds its content in a runspace of its own, and that runspace imported PsUi by folder. A gallery install puts the folder at `PsUi\1.1.1\`, so it'd attempt to load `1.1.1.psd1` and came back with no module, leaving the window without a single PsUi command. It imports the manifest by path now.
- **Switching themes put the column headers back over an grid's empty message**: the empty state resyncs after the restyle.
- **Every window took about nine seconds to open on 5.1**: a `Get-Command` with no `-ListImported` walked every module on `PSModulePath` only for the filter to drop the lot. That call ran seven seconds on 5.1 and takes about a millisecond now. It cost 31ms on 7, which is why nobody there noticed.
- **`New-UiDropdown -Default` missed a choice that was itself a list**: the match filtered against it instead of comparing, it matches what the box displays.
- **Every theme switch added additional hover handlers to every menu item**: one per item now.
- **Every theme switch added additional mousewheel handler to every list**: one per list now.
- **The wheel moved no rows over a `-Fill` grid**: the default hands every wheel event to the page, and a `-Fill` grid leaves the page no scroll of its own to do it with. A `-Fill` grid starts on `Edge` now, so the wheel moves its own rows until they run out, and passing `-ScrollWheel` overrides that.
- **Dropdown lists wouldn't scroll inside a tab**: the tab sent the wheel out on its way to the popup. The tab leaves the popup alone.
- **Multiline `New-UiTextArea` ate the wheel in a tab without a scroll of its own**: it never carried the flag the tab reads. It carries it.
- **Importing PsUi deleted another PowerShell's live WebView2 profile**: the cleanup sweep skipped only its own process. It checks the owner first.
- **`Set-UiValue` and `Get-UiValue` were unreachable from grid cell and menu actions**: a curated list decides which public functions get injected into an async runspace, and neither was on it. The entry below is a different bug in the same two functions, about what they did once they could be reached.
- **Returning a folder or a service showed every PowerShell added column blank**: the async path dropped the PSObject carrying `Mode` and the `PS*` properties. The grid keeps it.
- **The results filter died after a search that matched no rows**: an empty result reads as false in PowerShell, so the guard treated every input after it as empty too.
- **Filtering a results grid down to zero rows left the header columns**: it gets the empty state message now, reading `No items matched 'x'`.
- **Result action status text vanished on filter or sort**: it was written onto the cell. It lives on the row.
- **Lists and hashtables displayed inconsistently in a results grid**: every list type reads and clicks the same now, and Copy and Export reach the Value column.
- **Returning one hashtable built a simplier grid than returning several**: one hashtable gets the full grid.
- **Returning a hashtable with a null value lost the whole results view**: it reads `(null)`.
- **A tooltip drained a forward only stream just by showing a row**: it only reads values it can count.
- **Generic results got an unreadable tab header**: `Dictionary<String,Object>` now, not a PublicKeyToken.
- **The column picker miscounted an empty `HashSet` and a hashtable with a `Count` key**: the same misread hid a column behind the Has Data filter and counted an empty `HashSet` as filled. All of it goes through the classifier.
- **The column picker's counts never appeared up on a wide grid**: above 40,000 cells the scan went to a runspace that never came back. One scan covers every size.
- **A hashtable cell in an object grid read `[2 items]`**: `[2 keys]`, so the cell and its tooltip agree.
- **The column picker never counted the first column**: it is locked against hiding, and the count pass skipped it along with the toggle.
- **Attached properties in `-WPFProperties` never applied**: `'Grid.Row' = 1` and similar apply and convert like normal ones.
- **`-WPFProperties @{ Tag = ... }` quietly destroyed most controls**: `Tag` holds a control's click context or theme key. It refuses with a warning on a control that already holds one.
- **`New-UiWindow -WPFProperties` did less than every control's use of the parameter**: strings never converted and attached properties were skipped silently. It runs through `Set-UiProperties` like every control, and `Tag` is reserved.
- **Charts with a custom `-LabelProperty` came up empty, and `Update-UiChart` showed 'No data' on one**: the data got converted twice and the second conversion nuked every row.
- **`New-UiChart -Width` and `-Height` were ignored**: neither reached the chart.
- **`New-UiChart` and `Update-UiChart` showed 'No data' for a `List[T]` or `ArrayList` passed to `-Data`**: only a plain array got read as rows. Any list does now.
- **Single point charts crashed or came up blank**: one point arrives as a scalar with no count, so the draw loop never ran. A one slice pie was blank too. It draws as a circle.
- **`New-UiButton -Width` under 16 crashed, and `-Height` alone never shrank**: WPF throws on a negative inner size, and the height guard only ran when a width was given.
- **`New-UiButton -Parameters` went in as one argument on a sync click**: it splats now.
- **Controls inside cards, tabs and expanders could vanish without a word**: six controls assumed a parent that takes a list of children. All use the shared placement rule now, and a parent that holds none warns.
- **New-UiGrid**: `-FormLayout` unwrapping fired on grids that never asked for it, and a row definition shorter than the child count pushed children into row 0.
- **`-Columns @{ Width = 'Auto' }` warned about an unparseable width**: Auto was always a documented spelling, and behaves like one.
- **`Add-UiListItem` from a background action threw on every `-Items` list**: only a list that started empty got a threadsafe collection. Every input path lands in the one the control uses now, and `-ItemsSource` points your variable at it so `$list.Add()` keeps working. It warns when it cannot, `-NoBind` opts out, and `-Items @('')` keeps the empty string.
- **`New-UiDataGrid -NoBind` did not cover a `[ref]`**: it was repointed at the threadsafe collection regardless.
- **Typing in a list's filter box disconnected the list from its collection**: each keystroke swapped in a copy. The filter drives the view now and ItemsSource never changes hands.
- **`Remove-UiListItem` with no `-Item` threw from async actions**: it read the selection off the raw ListBox, which belongs to another thread. It asks the proxy.
- **A grid column's `Choices` came up blank against an enum property**: passed strings never matched the enum behind SelectedValue. Strings parse into the enum now, and subsets survive.
- **An async Cancel button cancels itself**: `Stop-UiAsync` stops the newest running action, and from inside an async button that is the button. `New-UiButton` warns at build time now, and an explicit `-NoAsync:$false` stays quiet.
- **`Stop-UiAsync` after a finished run had no live run to stop**: every run parked its AsyncExecutor in the session until the window closed. Every ending releases it.
- **`New-UiLink` ran twice on a double click and went dead after a timeout**: the second run replaced the first as the one `Stop-UiAsync` could reach, and a run that never got a thread left its busy flag set.
- **Variables in scope beat the session store when the names matched**: `SetCapturedVariable('lastRun', ...)` lost to any `$lastRun` that existed when the button was built. The store wins at click time, but items in `-Variables` and `-LinkedVariables` still beat both.
- **`Set-UiValue` and `Get-UiValue` only warned from most async actions**: both looked the session up in a thread local only the pooled runspace sets, and most buttons get a runspace of their own. Both resolve it through `Get-UiSession`.
- **The hydration `-Debug` warning claimed your objects get serialized**: the same reference crosses. The message is now accurate.
- **Opening a tool from a button took over the outer tool's command**: `New-UiTool` put its definition on the live session before it knew a child window was coming.
- **`New-UiTool` with no `-Theme` opened Light and reset the process theme**: it resolves `Auto` from the Windows setting, like `New-UiWindow`.
- **Dialogs opened before any window came up unstyled**: the control styles only ever loaded into a WPF Application and no dialog created one. A dialog without an Application themes itself off its own window.
- **Closing a modal child window could throw**: the title bar X set DialogResult and then called Close() on a window already tearing down.
- **`New-UiProgress -Severity` gave bars the blue accent**: the theme pass had the ProgressBar branch hardcoded to the accent. The tint follows the severity now.
- **A throwing callback took the window with it**: an error in a `New-UiWebView` navigation handler escaped to WPF, and so did one in a panel header action or a child window's `-OnClosed`. Each warns and carries on.
- **New-UiWebView navigation callbacks got nulls**: a nested closure captured the wrong scope.
- **`New-UiWebView -OnNavigating` canceled on the wrong returns**: only a real `$false` cancels now.
- **`New-UiWebView` cut off the bottom of every tab in its window**: the view raised the window's minimum height by how far down its tab it sat, so the window laid itself out taller than the screen. The view asks the window for no size.
- **`New-UiWebView` smeared itself over the titlebar when you scrolled past it**: a WebView2 draws into its own child window and ignores WPF clipping. It sits in a fixed slot now and trims to the part of that slot on screen. With `-WPFProperties`, the placement keys (`Margin`, the alignments, `Visibility`, the widths, attached values) land on that slot, and `Height`, `MinHeight` and `MaxHeight` are refused in favor of `-Height` and `-MinHeight`.
- **`New-UiWebView` printed an init error every time you left its tab and came back**: Loaded fires again on every tab show, and the second pass built a fresh environment for a control that already had one. Setup runs once per view now. `New-UiWebView` is still rough, but niche and workable.
- **`-NoInteractive` help promised an error that never throws**: `Read-Host` hands back an empty string, `-AsSecureString` an empty one of those, `Get-Credential` returns no object, and a choice prompt takes its default. The help now indicates this.
- **Errors inside nested blocks named the line below the one they happened on**: the count for a nested block started at the `New-UiWindow` call instead of at the block.
- **Results that opened on a hashtable or text tab could not be filtered**: the box sat disabled at `Indexing...` until you visited another tab, and a hashtable only result had none.
- **`-WPFProperties` ignored a string for `FontFamily`**: same for a `CornerRadius` or a `Color`, each thrown into a swallowed debug log. It asks the type's own converter now, the one XAML runs.
- **Cell popups with wide lines scrolled sideways and lost the copy button off the right edge**: both popups now wrap.
- **`[ref]` to a variable that can't hold a list killed the window**: it warns and builds now.
- **`-ItemsSource` said "Cannot find an overload" when handed something that is not a list**: it now names the parameter and the type.
- **The output window's spinner overlay kept the colors of the theme it opened under**: the panel and the spinner read the theme.
- **Clicking a cell holding an empty hashtable opened a popup with a dead copy button**: it no longer opens to display no items.
- **Searches left on a text results tab stayed highlighted after the filter box emptied**: going back to a text tab clears them.
- **The dictionary results tab searched and exported its display strings**: a five item list indexed and exported as `[5 items]`. Both hold the values.
- **`New-UiDataGrid` search read hashtables as their type name**: its index goes through `ValueKind`, like the results grid, and Copy Cell writes what a row copy writes, comma joined.
- **The array popup listed nested hashtables and lists by type name**: each line uses the cell's own text, and both popup headers use the tooltip's count.
- **The search index did not evaluate the last rows**: 40 of 347 went unsampled. The sample runs first to last.
- **`Build-PsUi.ps1` wiped `lib/` before it built, so one locked file left the module half deleted**: each file is replaced on its own now, and a held one keeps its old copy and is named at the end.
- **Controls in a window ran against an open child window**: with a nonmodal `New-UiChildWindow` up, the parent's buttons, links, handlers, grid events and prompts all found the child, so `Write-Status` wrote to the child's bar and Stop canceled the child's job. Every control runs under the window that built it now.
- **A second child window closed along with the first**: it was owned by the first child instead of the window that opened it.
- **Closing one child window with another open handed the thread back to the parent**: and a child that outlived its opener left `Get-UiSession` returning `$null`. The thread only moves when the closing child held it.
- **`Invoke-UiAsync` left the thread on the session it ran under**: `-OnComplete` and `-OnError` ran against whichever child held it, and it never went back.
- **`Register-UiHotkey` keys didn't fire inside a child window**: only the main window listened for them.
- **F5 and the other F keys didn't fire while a text box had focus**: `Register-UiHotkey` skips keys without Ctrl or Alt while an input box is focused, and the F keys were included. F1 to F24 fire from a text box now. Escape and the letter keys still don't.
- **`Set-UiValue`, `Write-Status`, `Update-UiChart` and the other helpers lost their errors on the UI thread**: the action never got them. They show in the output window or the Action Error dialog now, and a throw there stops the action.
- **A `-NoAsync` action stopped dead at a failed line and showed no error**: a `Set-UiValue` the control refused ended the click. The error shows in a dialog now and the action carries on, and `Set-UiValue` says what it refused ('loud' isn't a value the slider 'volume' takes).
- **Errors from panel header actions, `-OnClosed`, `-OnComplete`, `-OnError`, web view navigation and `-ValidateScript` only reached `$Error`**: each one shows now as a warning on the console you launched from.
- **A long run of errors pushed the Action Error dialog off the screen**: it lists the first ten and counts the rest, and any message taller than the screen stops at the edge and scrolls.
- **A status bar inside `New-UiExpander` docked to the window**: it stays in the expander and hides when the expander collapses, and `Write-Status` without a name reaches the window's own bar.
- **The label over an `-AutoProgress` bar repeated the status text**: it shows the activity, or stays empty.
- **The status bar's message popup hung past the right edge of the window**: its right edge lines up with the bar's.
- **`New-UiExpander` and `New-UiRadioGroup` broke a child window opened from a `-NoAsync` button on 5.1**: the whole child failed. The same 5.1 bug stopped a `-NoAsync` action at `Write-UiHostDirect` with the console left recolored, and made the output window's filter box throw on every pass.
- **`New-UiTool` on a function a `-NoAsync` action defined failed on 5.1**: the form never opened and the action stopped. It opens now, and cleans up its temporary copy of the function.
- **`New-UiTool` on a .ps1 of functions failed on every Run**: 'Missing function body in function declaration', and an apostrophe in the path broke it before that. Run dot sources the file and calls the function now, and Help reads the comment help inside it. A file that runs code outside its functions is refused before anything runs.
- **Two `-Fill` grids on a page didn't share the height**: the upper one took all of it. Every `-Fill` control on a page splits the leftover height evenly and splits it again on resize.
- **`-Fill` controls ran past the right edge of their parent**: the width left out the control's own margins.
- **`-Editable` grids over plain objects threw before the window opened**: readonly members like `Process.Id` and `FileInfo.Length` stay readonly now, and so does a service's `DisplayName` on 5.1.
- **Handles came up blank on plain `Process` rows**: so did an explicit column typed in a different case from its property. Both bind to the member's real name.
- **The column picker's boxes drove the wrong columns when a header differed from its property**: each box drives its own column now, HandleCount and SessionId included.
- **The + button on a single select `New-UiList` threw after adding**: the new name was left unselected. It selects the name it just added, even one the list already had.
- **`Show-UiGlyphBrowser` let long icon names run past their tiles**: they end in an ellipsis, and the heading says which icon font is active.
- **After a long session new windows lost their taskbar icon, and copying stopped working in every app**: every window registered its own taskbar id, which Windows keeps until you sign out or reboot, and the table they share filled up. Each kind of window reuses one id now, so open windows of one kind share a taskbar button. Super edge case.
- **A curly apostrophe in a script's file name kept `New-UiWindow` from opening**: `Carl’s tools.ps1` broke the script PsUi builds around `-Content`, and `New-UiButton -File` wouldn't build on it either. It opens now, and a curly quote in an `-ArgumentList` value stays inside its quotes too.
- **A curly quote in the working folder's name broke the folder restore after every async action**: a `Set-Location` inside the action stayed in effect, and a crafted name ran whatever followed the quote as code. The folder comes back now whatever the name.
- **`Out-CSVDataGrid` Save turned accented letters into `?` on 5.1**: `Export-Csv` defaults to ASCII there, and Save wrote straight over the file you opened. Save, Save All, and Save As write UTF-8 now.
- **`Out-CSVDataGrid -NoHeader` put a `"Column1","Column2"` header on the file when saving**: a headerless file stays headerless.
- **`Out-CSVDataGrid` keeps files in order**: the dropdown and the first file shown came out in hash order. PS7 shuffled that every time.
- **`New-UiWindow -TabAlignment Center` tabs slid back to the left after a theme switch**: they stay centered now.

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

Standalone bar, separate from the output window's and the status bar's embedded ones. Shipped stripped down in 1.0.x (a variable, a height, a switch). Grown up now.

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
- **Selection foreground**: label text follows the selection color while the row is selected. Custom-header items get it too.

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
- **Second window, dead callbacks**: async completions in a second window queued onto the first window's exited thread and vanished, while the action itself ran fine. A context menu edit changed the row and the cell kept its old text. Callbacks land on their own window.
- **Actions that edit a row**: search and filter kept matching the old values after a rightclick action or cell toggle changed them. They see the new ones now.
- **`-DefaultSort` on an empty start**: a grid that began empty lost its sort the moment the first rows landed. It sticks now.
- **Toggle ticks landed on the copy**: with `-Items`, a cell toggle wrote to the grid's snapshot, so a Save button reading your objects saw nothing changed. Ticks land on the original.
- **Row colors went stale**: `-RowBackground` brushes didn't keep up with list changes. They keep up.
- **Piped scalars and falsy rows**: piping `0`, `''`, or `$false` to `Out-Datagrid` dropped those rows, and piping plain strings or numbers drew a ghost grid (strings got a lone `Length` column). Falsy rows stay now, and scalars get a `Value` column. Copy and export emit the values, not character counts.
- **Array cells in copy/export**: Copy Rows and Export CSV wrote `System.Object[]` for array cells. They come out as their joined contents now, ie (`a, b, c`).
- **Resizing `'*'` columns could lock up**: columns that share the leftover width stop taking resize drags once there's none left to give: no error, the drag just stops existing. `New-UiDataGrid` unlocks that, and a click that never drags doesn't pin the width.

#### Status Bar

- **Two ways to kill the bar**: `Write-Status -Severity Info` could freeze the window, and `Set-UiStatusBar` could take down the embedded progress bar. Both fixed.

#### Theme System

- **Update-SingleControlTheme**: theme switches silently skipped some text labels and borders, and nothing ever reported it. They recolor with everything else.
- **Out-TextEditor / Out-CSVDataGrid theme inheritance**: launched from paths with no theme context, both fell back to `Light` and re-themed the whole process - flipping the parent window's theme out from under you. Both inherit the active theme.

#### Out-TextEditor

- **Session isolation**: standalone `Out-TextEditor` adopted the calling window's session and disposed it on close, taking the window's captured variables with it. It runs sessionless now, and your session survives even if setup throws midflight.

#### Native Dialogs

- **Show-WindowsObjectPicker**: fixed "No locations can be found" on workgroup machines, DCs, and some domain-joined boxes. It checks domain membership up front and backs off through local+domain+GC, then local+domain, then local. `DiagnoseInit` reports what it detected when it still goes wrong.

#### New-UiTool

- **Async button actions**: `New-UiTool` crashed when launched from a normal async `-Action` - the new window came back to a thread that was already gone. `New-UiButton` spots window-spawners in the action and runs them synchronously instead. (Fixes #22)

#### Other

- **One error ate the run**: a single `Write-Error` midrun routed the whole run to OnError and threw away the pipeline output that worked. OnError still fires; OnComplete gets the results too.
- **Copy/export leaked internals**: every copy path - toolbar Copy and Export, rightclick copy, CSV export, Ctrl+C - wrote the raw rows, so the grid's internal search properties rode along as extra columns. One shared path strips them now, on `Out-Datagrid` and the output window alike.
- **Link color stuck after theme switch**: expandable-cell links froze at their build-time color, so Dark then Light meant white on white. They follow the theme live.
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
- **New-UiChildWindow**: opening a child window without a parent threw `The term 'Set-UIResources' is not recognized` - a click handler couldn't find a module-private function by name. Present since the initial release, resolved ahead of time.
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
