# Resources Directory

Runtime resources for the PsUi module - icons and XAML styles.

## Directory Structure

```
resources/
├── CharList.json           # Icon glyph Unicode mappings (Segoe MDL2 Assets)
├── README.md               # This file
└── xaml/
    ├── Themes/
    │   └── SharedStyles.xaml   # Shared style definitions
    └── styles/
        ├── ButtonStyle.xaml        # Button hover/click effects
        ├── ComboBoxStyle.xaml      # Dropdown styling
        ├── CommonStyles.xaml       # Labels, checkboxes, progress bars, lists
        ├── ContextMenuStyle.xaml   # Right-click menus
        ├── DataGridStyle.xaml      # Grid/table styling
        ├── DatePickerStyle.xaml    # Date picker calendar
        ├── GroupBoxStyle.xaml      # Panel/card borders
        ├── ScrollBarStyle.xaml     # Scrollbar appearance
        ├── SliderStyle.xaml        # Slider track/thumb
        ├── TabControlStyle.xaml    # Tab headers and content
        └── TextBoxStyle.xaml       # Text input fields
```

## CharList.json

Maps icon names to Segoe MDL2 Assets Unicode characters. Used by `New-UiGlyph` and any control with an `-Icon` parameter.

```powershell
# Example usage
New-UiButton -Text "Save" -Icon "Save"
New-UiGlyph -Icon "CheckMark" -Size 24
```

To browse available icons:
```powershell
Show-UiGlyphBrowser
```

## XAML Styles

Loaded by `ThemeEngine.cs` at window creation. Each file defines WPF styles that reference theme colors via `DynamicResource`.

### Loading Order

`ThemeEngine.LoadStyles()` loads in this order (dependencies matter):
1. `SharedStyles.xaml` (from Themes/)
2. `CommonStyles.xaml`
3. `ContextMenuStyle.xaml` (before TextBox - TextBox uses ContextMenu)
4. `ButtonStyle.xaml`
5. `TabControlStyle.xaml`
6. `TextBoxStyle.xaml`
7. `ComboBoxStyle.xaml`
8. `DatePickerStyle.xaml`
9. `DataGridStyle.xaml`
10. `GroupBoxStyle.xaml`
11. `ScrollBarStyle.xaml`
12. `SliderStyle.xaml`

### Style Naming Convention

Each style file defines a key style:
- `ModernButtonStyle`
- `ModernTabControlStyle`
- `ModernTextBoxStyle`
- `ModernDataGridStyle`
- `ModernProgressBarStyle` (in CommonStyles.xaml)
- etc.

These are applied by `ControlFactory.cs` or `Set-*Style.ps1` functions.

### Theme Colors

Styles use `DynamicResource` to reference theme colors defined by `ThemeEngine`:

```xml
<Setter Property="Background" Value="{DynamicResource ButtonBackgroundBrush}"/>
<Setter Property="Foreground" Value="{DynamicResource ButtonForegroundBrush}"/>
```

When the theme changes, all controls update automatically.

## Adding New Styles

1. Create `xaml/styles/MyControlStyle.xaml`
2. Define styles using `DynamicResource` for theme colors
3. Add filename to `ThemeEngine.LoadStyles()` array in `src/ThemeEngine.cs`
4. Apply in ControlFactory or create `Set-MyControlStyle.ps1`

## Notes

- C# source is in `/src/`, compiled DLLs in `/PsUi/lib/`
- Themes (color definitions) are in `private/ThemeDefinitions.ps1`, not XAML
- PowerShell 5.1 and 7+ compatible
