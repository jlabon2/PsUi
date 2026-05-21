# Changelog

All changes to PsUi will be documented in this file.

## [Unreleased]

### Added
- **New-UiProgress**: New progress bar control with severity tints (Info, Success, Warning, Error), optional label, and percentage/value display. Supports `-Indeterminate` for marquee mode, custom min/max ranges, and format strings for the value text.
- **Set-UiProgress**: Update value, increment, label, severity, or indeterminate mode on a live progress bar from a background runspace. No-op short-circuit when no params are bound so tight loops don't thrash the dispatcher.
- **Tests**: 14 new Pester tests covering New-UiProgress and Set-UiProgress - indeterminate, clamping, severity metadata, label/value blocks, Tag guard, no-op behavior, and missing-control handling.
- **Show-UiOuPicker**: New function wrapping DsBrowseForContainerW - the same native OU picker ADUC and GPMC use. Returns a PSCustomObject with Name, DistinguishedName, and AdsPath. Supports alternate credentials, custom root DN, hidden containers, and targeting a specific domain controller. Works from both UI and background runspace threads. It's pretty horrendous, though - it lazy-loads containers, so will always show a (+) icon even when a container or an OU is empty. It's more of a placeholder than anything and inevitably will be replaced alongside the native dialog objectpicker with modern replacements.
- **New-UiWindow**: `-Theme Auto` (now the default) detects the system's light/dark preference from the registry and applies the matching theme at window creation. Falls back to Light if the registry key is missing or unreadable.
- **New-UiDropdown**: `-OnChange` parameter fires a scriptblock when the selection changes. Receives the new value as a parameter, same pattern as New-UiDropdownButton.
- **New-UiDropdown**: Items are now managed via `AsyncObservableCollection` + `ItemsSource`. Existing list helper functions (`Add-UiListItem`, `Remove-UiListItem`, `Clear-UiList`, `Get-UiListItems`) work on dropdowns, including from background threads.
### Fixed
- **ConvertTo-UiBrush**: Brush cache was null on first call from a freshly hydrated runspace (the `if (!$script:_brushCache)` guard never ran). Now lazy-initialized so Set-UiProgress from button actions doesn't throw.
- **Set-ProgressBarStyle**: Severity tints now survive theme switches. Bars use SetResourceReference instead of frozen brushes, and ThemeEngine inspects Tag.BrushTag to rebind Foreground on theme change.
- **Set-ProgressBarStyle**: Indeterminate bars register with ThemeEngine so the marquee accent tracks theme switches.
- **New-UiProgress**: `-WPFProperties Tag` is now rejected with a warning instead of silently overwriting the metadata hashtable that makes label/severity/value bookkeeping work.
- **New-UiButton**: Same Tag guard - custom Tag through -WPFProperties no longer disarms the click handler.
- **Set-UiProgress**: `-Severity` binding no longer requires the meta hashtable to be present. Works on bars created without our Tag (third-party or future variants).
- **Set-UiProgress**: `-Indeterminate` switched from `[Nullable[bool]]` to `[bool]` with PSBoundParameters detection. Nullable bool was binding `$false from captured variables oddly.

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
