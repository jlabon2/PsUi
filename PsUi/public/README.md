# PsUi Public API

User-facing functions exported by the PsUi module, organized by category.

## Folder Structure

| Folder | Purpose |
|--------|---------|
| `controls/` | Input controls (buttons, textboxes, dropdowns, etc.) |
| `dialogs/` | Modal dialogs and file pickers |
| `layout/` | Container and layout controls |
| `list/` | ListBox manipulation functions |
| `output/` | Data presentation (Out-DataGrid, Out-TextEditor) |
| `session/` | Session state and async execution |
| `tool/` | Command-to-UI generator |
| `window/` | Child window creation |

---

## controls/ (18 functions)

| Function | Description |
|----------|-------------|
| `New-UiAction` | Creates a silent button (no output window) |
| `New-UiButton` | Creates a themed button with optional async action |
| `New-UiCredential` | Creates username/password input pair |
| `New-UiDatePicker` | Creates a date selection control |
| `New-UiDropdown` | Creates a dropdown selection control |
| `New-UiDropdownButton` | Creates a button with dropdown menu |
| `New-UiGlyph` | Creates an icon from Segoe MDL2 Assets |
| `New-UiImage` | Creates an image control from file or base64 |
| `New-UiInput` | Creates a labeled text input field |
| `New-UiLabel` | Creates a text label |
| `New-UiProgress` | Creates a progress bar control |
| `New-UiRadioGroup` | Creates a group of radio button options |
| `New-UiSeparator` | Creates a visual separator line |
| `New-UiSlider` | Creates a slider control |
| `New-UiTextArea` | Creates a multi-line text input |
| `New-UiTimePicker` | Creates a time selection control |
| `New-UiToggle` | Creates a checkbox/toggle control |
| `Set-UiProgress` | Updates progress bar value and status |

---

## dialogs/ (12 functions)

| Function | Description |
|----------|-------------|
| `Show-UiChoiceDialog` | Shows a dialog with multiple choice buttons |
| `Show-UiConfirmDialog` | Shows a Yes/No confirmation dialog |
| `Show-UiCredentialDialog` | Shows a credential prompt dialog |
| `Show-UiDialog` | Creates a custom modal dialog |
| `Show-UiFilePicker` | Shows a file open dialog |
| `Show-UiFolderPicker` | Shows a folder browser dialog |
| `Show-UiGlyphBrowser` | Shows a searchable icon browser |
| `Show-UiInputDialog` | Shows a single-input prompt dialog |
| `Show-UiMessageDialog` | Shows an information message dialog |
| `Show-UiPromptDialog` | Shows a multi-field input dialog |
| `Show-UiSaveDialog` | Shows a file save dialog |
| `Show-WindowsObjectPicker` | Shows the Windows AD object picker |

---

## layout/ (6 functions)

| Function | Description |
|----------|-------------|
| `New-UiActionCard` | Creates a silent action card (no output window) |
| `New-UiButtonCard` | Creates a card with action button and output window |
| `New-UiCard` | Creates a bordered card container |
| `New-UiGrid` | Creates a Grid layout with columns/rows |
| `New-UiPanel` | Creates a panel container for child controls |
| `New-UiTab` | Creates a tab item within a TabControl |

---

## list/ (5 functions)

| Function | Description |
|----------|-------------|
| `Add-UiListItem` | Adds an item to a ListBox |
| `Clear-UiList` | Removes all items from a ListBox |
| `Get-UiListItems` | Gets all items from a ListBox |
| `New-UiList` | Creates a ListBox control |
| `Remove-UiListItem` | Removes an item from a ListBox |

---

## output/ (3 functions)

| Function | Description |
|----------|-------------|
| `Out-CSVDataGrid` | Displays CSV file in a DataGrid window |
| `Out-Datagrid` | Displays pipeline objects in a DataGrid window |
| `Out-TextEditor` | Displays text/script in an editor window |

---

## session/ (2 functions)

| Function | Description |
|----------|-------------|
| `Invoke-UiAsync` | Executes a scriptblock asynchronously |
| `Reset-UiSession` | Clears the current UI session state |

---

## tool/ (1 function)

| Function | Description |
|----------|-------------|
| `New-UiTool` | Generates a UI form from command parameters |

---

## window/ (1 function)

| Function | Description |
|----------|-------------|
| `New-UiChildWindow` | Creates a child window inheriting parent's theme |

---

## Binary Cmdlet

### New-UiWindow

Creates a themed WPF window with automatic session management. Implemented in C# for STA thread spawning and session isolation.

```powershell
New-UiWindow [-Title] <string> [-Content] <scriptblock> 
    [-Width <int>] [-Height <int>] [-Theme <string>]
    [-NoResize] [-Icon <string>] [-LayoutMode <string>]
    [-MaxColumns <int>] [-TabAlignment <string>]
    [-MinimizeConsole] [-HideThemeButton] [-WPFProperties <hashtable>]
```
