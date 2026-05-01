# Changelog

All changes to PsUi will be documented in this file.

## [1.0.4] - Unreleased

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
