# Changelog

All changes to PsUi will be documented in this file.

## [Unreleased]

Status bars, progress bars, input dialogs, threading fixes, and a pile of theme corrections. The headline feature is `-Intercept` on `New-UiStatusBar` - drop a status bar in your window and Write-Warning, Write-Error, Write-Host, and Write-Progress just show up.

### Added

#### Status Bar

The whole suite ships as a set of cooperating functions. `New-UiStatusBar` builds the bar, the rest operate on it from any thread.

- **New-UiStatusBar**: Docked top or bottom, freeform `-Content` block that accepts most PsUi controls. The bar is a themed Border wrapping a DockPanel, not a WPF StatusBar (those have layout quirks that ended up not being worth fighting).
  - `-DefaultText` prepends a text label that all the setter functions target.
  - `-AutoProgress` embeds a progress bar driven by `Write-Progress` from button actions. Hides when idle, appears on first progress record, stays visible on completion so you can see where it landed.
  - `-AutoCancel` embeds a Cancel button that lights up during async work. Uses Hidden instead of Collapsed so it doesn't jitter the layout.
  - `-Intercept` is the headline feature, which presents another means to display data from runspaces in the UI. Turns the bar into a live output sink. Write-Warning and Write-Error accumulate as clickable badge pill counters with popup detail views. Error popups pull everything useful off the ErrorRecord: exception type, source location, offending code line, first stack frame, target object, and inner exception.
  - `-CaptureHost` (requires `-Intercept`) routes Write-Host from NoOutput buttons to the status text, turning it into a live activity feed. The C# host batching (50 records or 50ms flush, whichever comes first) keeps it smooth even under heavy output.
  - `-NoOutputOnly` limits interception to buttons that don't have output windows (e.g. `New-UiAction` or `New-UIActionCard`). Prevents duplicate badge counts when Show-UiOutput is already showing the same warnings.
  - `-Persist` keeps badge counts across button actions instead of resetting on each click. Good for tracking cumulative issues across a multi-step workflow.
  - `-MaxMessages` caps popup entries at N (default 100). Oldest entries drop when exceeded.
  - Severity tinting with auto-reset: bar background shifts to match the stream (green/yellow/red) with a small indicator glyph, then fades back to neutral after a few seconds.
- **New-UiSpacer**: Fills remaining space in the parent container. Inside a status bar, drop it between your label and your buttons to push the buttons right.
- **Set-UiStatusBar**: Update text, progress, severity, or indeterminate mode from any thread. `-Progress` and `-Increment` for fine-grained control (Progress wins when both are bound). Severity auto-resets after 5s; `-Timeout 0` to keep the tint indefinitely.
- **Write-Status**: The casual version. Positional `-Message`, optional `-Severity`. Use it the same way you'd use `Write-Host` but it targets the status bar instead.
- **Clear-UiStatus**: Full reset. Clears text, drops tint, zeros the progress bar, dims all badges, clears popup messages. The panic button.
- **Show-UiStatusBar / Hide-UiStatusBar**: Toggle visibility from any thread. Hidden bars keep their state.

#### Progress Bar

Standalone progress bar control, independent from the status bar's embedded one.

- **New-UiProgress**: Severity tints (Info, Success, Warning, Error), optional label, percentage/value display, `-Indeterminate` marquee, custom min/max ranges, and value format strings.
- **Set-UiProgress**: Update value, increment, label, severity, or indeterminate mode on a live bar from a background runspace. No-op when no params are bound.

#### Icon Font

Pick Segoe MDL2 Assets (Win10) or Segoe Fluent Icons (Win11) per-session or per-window. Default auto-detects. Every control asks for the active font from the same place, so flipping it flips every glyph the next time something gets drawn.

`-NoIconFontFallback` and the WPF fallback-chain machinery shipped before jlabon2 actually compared the two fonts. Turns out Fluent has every icon MDL2 has plus 174 more, and the lone MDL2-only icon is in the deprecated range MS itself tells you not to use. The first cut of CharList.json only named the MDL2 subset, so the fallback chain was decoration. Then we added 125 of those Fluent-modern icons by name (the ones MS documents - `Blocked`, `Effects`, `PhotoCollection`, `ApplicationGuard`, ...) and now the chain has actual work to do: on Win10/MDL2 the new names tofu, on Win11/MDL2 + fallback on they render via Fluent substitution, on Fluent they render natively. The remaining 44 Fluent-extras ship in the font but MS doesn't document names, so they're staying anonymous until they're not. And when Windows 13 ships Segoe UI HyperIcons we'll already be ready.

- **Set-PsUiIconFont / Get-PsUiIconFont**: Flip the active icon font for the session. `Auto` picks Fluent if installed, MDL2 if not. Existing controls keep the font they were drawn with - reload the window to update everything.
- **Test-PsUiIcon**: Returns `$true` if a named glyph will actually render. Modes: `Active`, `Fluent`, `MDL2`, `Either`. Catches typos at write-time, not when an icon comes up blank.
- **New-UiWindow `-IconFont` / `-NoIconFontFallback`**: Per-window override. Remembers the active font on open and puts it back on close - one-off picks don't bleed into the session. Default `Inherit` keeps whatever was set before.
- **Out-TextEditor / Out-Datagrid / Out-CSVDataGrid**: Same two params, honored only when launched standalone. Inside a `New-UiWindow` parent, the parent wins - same pattern as `-Theme`.
- **Show-UiGlyphBrowser**: Title now reads the renderable count next to the total - `1504 of 1519` under Fluent, `1379 of 1519` under strict MDL2. The 125 gap is the new Fluent-only names dropping out when there's nothing to fall back to. Tiles missing from the active font dim to 30%; tooltips show which fonts carry each icon. 15 entries (`Windows`, `Excel`, `SQL`, `Stack`, the `*Portrait` / `*Landscape` group, ...) are in MS's MDL2 docs but never actually shipped in either font. The docs lie about a few entries.
- **CharList.json**: Grew from 1659 to 1784 entries. Added 125 Fluent-modern icons that MS documents in the Fluent-only range (`Blocked`, `Effects`, `PhotoCollection`, `ApplicationGuard`, ...). Under MDL2 these new names tofu unless the fallback chain is on; under Fluent they render natively. The remaining 44 Fluent-only codepoints in the font don't have published names from MS, so we left them out for now. Heads up: with MDL2 active + fallback on, those new names render in Fluent style mid-MDL2-app - cleaner strokes mixed with the older vintage. Set `-NoIconFontFallback` for strict consistency; the Fluent-only names will tofu and you'll know which ones to swap. 5 Fluent docs entries that reuse existing MDL2 names for different codepoints (`Contrast`, `Clock`, `RAM`, `TextEdit`, `Pen`) kept their original MDL2 mappings - the Fluent-redesigned codepoints at those positions stayed unnamed.
- **`-NoIconFontFallback` on single-font systems**: On Win10/MDL2-only there's nothing to fall back to. The flag still tightens the `-Icon` dropdown so write-time picks can't include the 15 names that don't render anywhere.
- **Build-PsUi.ps1**: Builds each target framework one at a time now. Parallel builds were racing on shared files while three frameworks tried to write the same DLL. Costs a few seconds, buys reliability.

#### Tree CheckBoxes

`-ParentCheckBoxes` and `-ChildCheckBoxes` on `New-UiTree`. Each flag is independent: parents-only, leaves-only, or both for the full picker. Cascade defaults on when both are; `-NoCascade` opts out.

- **New-UiTree `-ParentCheckBoxes`**: Checkbox on every item with children. Click a parent to mass-select enabled descendants. Used alone, hydration returns descendant leaves under checked branches.
- **New-UiTree `-ChildCheckBoxes`**: Checkbox on every leaf. Used alone, parents become unselectable (Focusable=$false) so the checkbox is the obvious selection control.
- **New-UiTree `-WhenEnabled` / `-Checked`**: Scriptblock run per item. WhenEnabled returns $false and the box renders disabled and dimmed; cascade skips it. Checked returns $true and the box starts checked at build time.
- **New-UiTree `-NoCascade`**: Independent boxes for tagging workflows where parent and leaves are orthogonal selections.
- **Hydration**: `$tree` in a button action returns an array of checked source items - each once, in tree order. Both modes: parents + leaves. Parent-only: descendant leaves under checked branches. Child-only: checked leaves. Path-mode stand-in parents never appear in the result.
- **Selection foreground tracking**: Label text follows `SelectionForegroundBrush` when the row is selected and the tree has focus, falls back to `ControlForegroundBrush` otherwise. Custom-header TVIs (anything that isn't a plain string header) don't inherit this through WPF property inheritance - hooked explicitly via `Loaded`/`Unloaded` so the subscription doesn't outlive the window.

#### Other

- **New-UiTool**: Added UserPicker, GroupPicker, MemberPicker, and OUPicker input helpers. Auto-detected from parameter names or assignable via `UserPickerParameters`, `GroupPickerParameters`, `MemberPickerParameters`, and `OUPickerParameters` parameters. Click the browse button to open the native Windows object picker.
- **New-UiInput**: Added `OUPicker` helper button. On non-domain machines, prompts for a domain controller hostname/IP and credentials before opening the OU browser. The prompt fallback only fires on the no-domain exception; real failures (network, bad creds, unreachable server) bubble to the error dialog instead.
- **New-UiInput**: Added `-HelperOptions` for wiring helper buttons to other controls. Hashtable splats verbatim into the underlying `Show-*` picker at click time. String values get looked up against registered control Variables - on a match the live value wins, otherwise it's a literal. Credential controls auto-unwrap to `PSCredential`. Works across every picker mode. `HelperOptions = @{ Server = 'dcServer'; Credential = 'dcCred' }` on an OUPicker pulls both from sibling inputs without prompting.
- **Helper button errors**: Click failures surface in a themed `Show-UiMessageDialog` with a cleaned stack trace, plus a transcript `Write-Warning`. Same dispatcher serves both `New-UiInput`'s helper button and `New-UiTool`'s auto-generated pickers.
- **Show-UiOuPicker**: Wraps DsBrowseForContainerW (the native OU picker that ADUC and GPMC use). Returns Name, DistinguishedName, AdsPath. Supports alternate credentials, custom root DN, hidden containers, and a target DC. Works from UI and background runspace threads. The dialog itself is pretty horrendous - it lazy-loads containers and always shows a (+) icon even on empty OUs. Placeholder until we build something better.
- **New-UiWindow**: `-Theme Auto` is now the default. Reads the system light/dark preference from the registry and applies the matching theme. Falls back to Light if the key is missing.
- **New-UiDropdown**: `-OnChange` scriptblock fires on selection change. Receives the new value, matching New-UiDropdownButton behavior.
- **New-UiDropdown**: Items now managed via `AsyncObservableCollection` + `ItemsSource`. The existing list helpers (`Add-UiListItem`, `Remove-UiListItem`, `Clear-UiList`, `Get-UiListItems`) work on dropdowns, including from background threads.
- **net452 target**: .NET 4.5.2 build for WinPE and older Windows. WebView2 excluded (not supported). C# changes are compatibility-only: conditional LangVersion, NET452 define, `FormattedText` constructor overload selection, `out var` replaced with explicit declarations. Build verifies all three output DLLs.

#### Tests

- 40+ new Pester tests covering status bar parameter shapes, severity validation, badge structure, popup behavior, Clear button resets, severity brush mapping, PS 5.1 clamping safety, progress suppression, and ThemeEngine status bar awareness.
- 14 tests for New-UiProgress and Set-UiProgress covering indeterminate mode, value clamping, severity metadata, label/value blocks, Tag guard, no-op, and missing-control.

### Fixed

#### Threading

- **ControlValueExtractor**: Unknown registered controls (status bar Borders, custom shapes) used to return the live WPF object as the hydrated value. Live WPF references cross runspace boundaries and deadlock when STA pool threads try to marshal them back. Fallback now returns `$null`.
- **Invoke-OnUIThread**: Hardened `BeginInvoke().Wait()`. Catches the `AggregateException` wrapper, falls back to direct execution on `OperationCanceled` (common in tests with no dispatcher), and inspects operation status for Faulted/Aborted that `Wait()` doesn't always surface.

#### Theme System

- **Update-SingleControlTheme**: Null Tag on TextBlocks and Borders was silently killing the switch statement when the function ran from a dispatched scriptblock. Certain theme updates (foreground colors, border backgrounds) would just not apply - no error, no warning, the dispatcher swallowed the failure entirely. Added null-tag fast paths that skip the switch and apply defaults directly.

#### Native Dialogs

- **Show-WindowsObjectPicker**: Fixed "No locations can be found" on workgroup, DCs, and, in some instances, domain joined machines. Now auto-detects domain membership via `NetGetJoinInformation` and zeroes uplevel filters on workgroup machines. Also added `SKIP_TARGET_COMPUTER_DC_CHECK` so the picker works on domain controllers, and a progressive fallback chain (local+domain+GC -> local+domain -> local) for domain-joined machines. Added `DiagnoseInit` method for troubleshooting scope failures because this is an absolute nightmare to debug.

#### New-UiTool

- **Async button actions**: `New-UiTool` crashed when called from a default async `-Action` - WPF windows on the async runspace's STA thread inevitably die. `New-UiButton` AST-detects window-spawners and auto-flips to `-NoAsync` so the spawn lands on the host's dispatcher. (Fixes #22)

#### Other

- **ConvertTo-UiBrush**: Brush cache was null on first call from a freshly hydrated runspace. Now lazy-initialized so Set-UiProgress from button actions doesn't throw. Turns out the module-scope init only fixed half the problem - WPF event handler callbacks resolve to the `Global:` function copy that AsyncExecutor injects, and that copy has its own `$script:` scope where nobody ever created the cache. Moved the lazy-init inside the function body so it doesn't matter which copy you hit.
- **Show-UiInputDialog**: Typing in the dialog could throw "Cannot index into a null array" because the TextChanged handler was calling `ConvertTo-UiBrush` at runtime, hitting the null-cache bug above. Now pre-computes the border brush during creation and captures the frozen object in the closure. No runtime brush lookups in event handlers.
- **New-UiProgress / New-UiButton**: `-WPFProperties Tag` is now rejected with a warning instead of silently overwriting the internal metadata. Custom Tag through `-WPFProperties` was disarming click handlers and breaking severity bookkeeping.
- **Show-UiOutput**: Dispatcher exception handler now logs `InnerException` details instead of the unhelpful `TargetInvocationException` wrapper.
- **New-UiLabel**: Default vertical alignment changed from Top to Center. Labels in stacked layouts may shift slightly.
- **New-UiToggle**: Vertical alignment set to Bottom so checkboxes sit level with labeled controls (Input, Dropdown) in horizontal panels. No visual change in vertical or grid layouts.
- **ControlValueExtractor**: TreeView, DataGrid, and ListView snapshots no longer carry a live WPF control reference under `["Control"]`. That reference crossed runspace boundaries and could deadlock when a background thread accessed it. Nothing in the codebase actually read the key - it was left over from an earlier design. Removed entirely; the snapshot still has SelectedItem, SelectedIndex, SelectedItems, etc.
- **Show-UiOutput**: `Start-Sleep -Milliseconds 500` in the Escape and window-close handlers replaced with a short DispatcherTimer. The sleep was blocking the UI thread while waiting for the Topmost change to render before showing a confirm dialog. Now deferred so the UI stays responsive.
- **Show-UiOutput**: The 50ms host output queue polling timer now stops itself after the executor finishes and both queues are drained. Previously it kept firing 20 times per second for the entire lifetime of the output window, even when idle, burning cycles endlessly until closed.
- **New-UiChildWindow**: The `Add_Loaded` handler called a private function (`Set-UIResources`) by name. WPF event handlers can't see module-private functions even when the script block was defined inside the module - `.GetNewClosure()` carries variable values across, but not the ability to find private functions by name. Manifested as `The term 'Set-UIResources' is not recognized` any time a child window opened without a parent (e.g. `Show-UiGlyphBrowser` from the console). Pre-existing since initial release, surfaced now by the new icon-font test rig exercising the standalone path. Resolves the function ahead of the closure now.
- **Start-PSUiDemo (Standalone tab, Data Grid panel)**: The "Multi-Tab DataSet" card called `Out-Datagrid -DataScriptBlock { New-DataSet ... }`. Neither `-DataScriptBlock` nor `New-DataSet` has ever existed in source - this was aspirational demo code that shipped in the initial release for a feature that was temporarily implemented but never kept. Replaced with a "View Drives" card that uses the real pipeline API.

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
