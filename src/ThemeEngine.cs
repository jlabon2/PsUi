using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Markup;
using System.Windows.Media;

namespace PsUi
{
    // Generates ResourceDictionary from PowerShell hashtables. Theme data comes from ThemeDefinitions.ps1.
    public static class ThemeEngine
    {
        private static string _currentThemeName = "Light";
        private static string _modulePath = null;
        private static volatile bool _stylesLoaded = false;
        private static readonly List<WeakReference<FrameworkElement>> _registeredElements;
        private static readonly object _elementsLock = new object();
        private const string ThemeMarkerKey = "__PsUi_ThemeMarker__";
        private const string StyleMarkerKey = "__PsUi_StyleMarker__";
        
        // Fired when theme changes - used by dialogs on separate threads that cant use resource binding
        public static event Action<string> ThemeChanged;

        static ThemeEngine()
        {
            _registeredElements = new List<WeakReference<FrameworkElement>>();
        }

        public static string CurrentTheme
        {
            get { return _currentThemeName; }
        }

        public static void SetModulePath(string modulePath)
        {
            _modulePath = modulePath;
        }

        // Wipe registered elements for a fresh window
        public static void Reset()
        {
            lock (_elementsLock)
            {
                _registeredElements.Clear();
            }
            _stylesLoaded = false;
        }

        private static int _registrationsSincePrune = 0;
        private const int PRUNE_INTERVAL = 100;
        
        // Register element for theme-aware resource binding - calls SetResourceReference on supported properties
        public static void RegisterElement(FrameworkElement element)
        {
            if (element == null) return;
            
            lock (_elementsLock)
            {
                // Prune dead references periodically to prevent unbounded growth
                _registrationsSincePrune++;
                if (_registrationsSincePrune >= PRUNE_INTERVAL)
                {
                    _registrationsSincePrune = 0;
                    _registeredElements.RemoveAll(wr => 
                    {
                        FrameworkElement target;
                        return !wr.TryGetTarget(out target);
                    });
                }
                
                _registeredElements.Add(new WeakReference<FrameworkElement>(element));
            }
            
            // Bind element immediately
            BindElementToResources(element);
        }
        
        // Manually prune dead references - can be called periodically for long-running apps
        public static void PruneDeadReferences()
        {
            lock (_elementsLock)
            {
                _registeredElements.RemoveAll(wr => 
                {
                    FrameworkElement target;
                    return !wr.TryGetTarget(out target);
                });
            }
        }

        // Main entry point - generates all brushes in memory from PS hashtable, no theme XAML files needed
        public static void ApplyTheme(string themeName, IDictionary colors)
        {
            if (colors == null)
            {
                throw new ArgumentNullException("colors", "Theme colors hashtable cannot be null");
            }

            // Create Application if we're running outside normal WPF context
            if (Application.Current == null)
            {
                new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            }

            // Check if dispatcher is still operational (dead thread or explicit shutdown)
            if (Application.Current.Dispatcher.HasShutdownStarted ||
                !Application.Current.Dispatcher.Thread.IsAlive)
            {
                // Dispatcher is dead - apply directly on current thread (we're likely on a new STA thread)
                ApplyThemeOnUIThread(themeName, colors);
                return;
            }

            // Marshal all UI work to the dispatcher thread (critical for PS 5.1)
            // Use timeout to avoid hanging if dispatcher dies between our check and the invoke
            try
            {
                Application.Current.Dispatcher.Invoke(new Action(delegate
                {
                    ApplyThemeOnUIThread(themeName, colors);
                }), TimeSpan.FromSeconds(5));
            }
            catch (TimeoutException)
            {
                // Dispatcher didn't respond in time - apply directly on current thread
                ApplyThemeOnUIThread(themeName, colors);
            }
        }

        // Applies theme on UI thread. Add-first/remove-second order avoids PS 5.1 resource bug.
        private static void ApplyThemeOnUIThread(string themeName, IDictionary colors)
        {
            // Generate the resource dictionary from the hashtable
            ResourceDictionary themeDict = GenerateResourceDictionary(colors);
            themeDict[ThemeMarkerKey] = true;

            var mergedDicts = Application.Current.Resources.MergedDictionaries;
            
            // Identify old theme dictionaries first
            var toRemove = new List<ResourceDictionary>();
            foreach (ResourceDictionary dict in mergedDicts)
            {
                if (dict.Contains(ThemeMarkerKey))
                {
                    toRemove.Add(dict);
                }
            }

            // ADD NEW FIRST - prevents "resource vacuum" where bindings detach in PS 5.1
            // The window sees the new brush immediately, so bindings update instead of breaking
            mergedDicts.Insert(0, themeDict);

            // REMOVE OLD SECOND - safe now because new resources already exist
            foreach (ResourceDictionary dict in toRemove)
            {
                mergedDicts.Remove(dict);
            }
            
            _currentThemeName = themeName;
            
            // Notify listeners on other threads (e.g., KeyCaptureDialog)
            var handler = ThemeChanged;
            if (handler != null)
            {
                try { handler(themeName); }
                catch { /* ignore listener errors */ }
            }

            // Load control styles if not already loaded
            if (!_stylesLoaded)
            {
                LoadStyles();
                _stylesLoaded = true;
            }

            // Re-bind all registered elements to trigger resource refresh
            RefreshRegisteredElements();
        }

        // Generate ResourceDictionary from hashtable - maps short keys (WindowBg) to full names (WindowBackgroundBrush)
        private static ResourceDictionary GenerateResourceDictionary(IDictionary colors)
        {
            var dict = new ResourceDictionary();

            // Brush mappings: source key -> target brush name(s)
            var brushMappings = new Dictionary<string, string[]>
            {
                { "WindowBg", new[] { "WindowBackgroundBrush" } },
                { "WindowFg", new[] { "WindowForegroundBrush" } },
                { "ControlBg", new[] { "ControlBackgroundBrush", "ControlBgBrush" } },
                { "ControlFg", new[] { "ControlForegroundBrush", "ControlFgBrush" } },
                { "ButtonBg", new[] { "ButtonBackgroundBrush" } },
                { "ButtonFg", new[] { "ButtonForegroundBrush" } },
                { "ButtonHover", new[] { "ButtonHoverBackgroundBrush", "ButtonPressedBackgroundBrush" } },
                { "Border", new[] { "BorderBrush" } },
                { "Accent", new[] { "AccentBrush", "AccentHoverBrush" } },
                { "Success", new[] { "SuccessBrush" } },
                { "Warning", new[] { "WarningBrush" } },
                { "Error", new[] { "ErrorBrush" } },
                { "SelectionFg", new[] { "SelectionForegroundBrush", "SelectionTextBrush" } },
                { "GridAlt", new[] { "GridAlternatingRowBrush" } },
                { "HeaderBackground", new[] { "HeaderBackgroundBrush", "GridHeaderBackgroundBrush" } },
                { "HeaderForeground", new[] { "HeaderForegroundBrush", "GridHeaderForegroundBrush" } },
                { "AccentHeaderBg", new[] { "AccentHeaderBackgroundBrush" } },
                { "AccentHeaderFg", new[] { "AccentHeaderForegroundBrush" } },
                { "SelectedTabBg", new[] { "SelectedTabBackgroundBrush" } },
                { "TabHoverBg", new[] { "TabHoverBackgroundBrush" } },
                { "Disabled", new[] { "DisabledForegroundBrush" } },
                { "SecondaryText", new[] { "SecondaryTextBrush" } },
                { "GroupBoxBg", new[] { "GroupBoxBackgroundBrush" } },
                { "GroupBoxBorder", new[] { "GroupBoxBorderBrush" } },
                { "FindHighlight", new[] { "FindHighlightBrush" } }
            };
            
            foreach (var mapping in brushMappings)
            {
                foreach (var targetKey in mapping.Value)
                {
                    AddBrush(dict, colors, mapping.Key, targetKey);
                }
            }
            
            // Selection with fallback to SelectionBackground (which supports transparency)
            if (colors.Contains("SelectionBackground"))
            {
                AddBrush(dict, colors, "SelectionBackground", "SelectionBackgroundBrush");
            }
            else
            {
                AddBrush(dict, colors, "Selection", "SelectionBackgroundBrush");
            }
            
            // GridLine with fallback to Border
            AddBrush(dict, colors, "GridLine", "GridLineBrush");
            if (!colors.Contains("GridLine"))
            {
                AddBrush(dict, colors, "Border", "GridLineBrush");
            }
            
            // Use provided hover color or synthesize a transparent overlay
            if (colors.Contains("WindowControlHover"))
            {
                AddBrush(dict, colors, "WindowControlHover", "WindowControlHoverBrush");
            }
            else
            {
                object themeType = colors.Contains("Type") ? colors["Type"] : "Light";
                bool isDark = themeType != null && themeType.ToString().ToLower() == "dark";
                var hoverBrush = new SolidColorBrush(isDark 
                    ? Color.FromArgb(40, 255, 255, 255)
                    : Color.FromArgb(32, 0, 0, 0));
                hoverBrush.Freeze();
                dict["WindowControlHoverBrush"] = hoverBrush;
            }
            
            // DisabledBackgroundBrush removed - never consumed. WPF uses DisabledOpacity instead.
            
            // ItemHover with cascading fallbacks
            AddBrush(dict, colors, "ItemHover", "ItemHoverBrush");
            if (!colors.Contains("ItemHover"))
            {
                if (colors.Contains("SelectionBackground"))
                {
                    AddBrush(dict, colors, "SelectionBackground", "ItemHoverBrush");
                }
                else
                {
                    AddBrush(dict, colors, "Selection", "ItemHoverBrush");
                }
            }

            // TextHighlight with fallback to Selection
            AddBrush(dict, colors, "TextHighlight", "TextHighlightBrush");
            AddBrush(dict, colors, "TextHighlightFg", "TextHighlightForegroundBrush");
            if (!colors.Contains("TextHighlight"))
            {
                AddBrush(dict, colors, "Selection", "TextHighlightBrush");
            }
            if (!colors.Contains("TextHighlightFg"))
            {
                AddBrush(dict, colors, "SelectionFg", "TextHighlightForegroundBrush");
            }

            // UnselectedTabBackgroundBrush removed - XAML template defaults to Transparent.

            // Color resources (XAML templates need raw colors, not brushes)
            var colorMappings = new Dictionary<string, string[]>
            {
                { "WindowBg", new[] { "WindowBackgroundColor" } },
                { "WindowFg", new[] { "WindowForegroundColor" } },
                { "ControlBg", new[] { "ControlBackgroundColor" } },
                { "ControlFg", new[] { "ControlForegroundColor" } },
                { "ButtonBg", new[] { "ButtonBackgroundColor" } },
                { "ButtonFg", new[] { "ButtonForegroundColor" } },
                { "ButtonHover", new[] { "ButtonHoverBackgroundColor", "ButtonPressedBackgroundColor" } },
                { "Border", new[] { "BorderColor" } },
                { "Accent", new[] { "AccentColor", "AccentHoverColor" } },
                { "Selection", new[] { "SelectionBackgroundColor" } },
                { "SelectionFg", new[] { "SelectionForegroundColor", "SelectionTextColor" } },
                { "GridAlt", new[] { "GridAlternatingRowColor" } },
                { "HeaderBackground", new[] { "HeaderBackgroundColor" } },
                { "HeaderForeground", new[] { "HeaderForegroundColor" } },
                { "AccentHeaderBg", new[] { "AccentHeaderBackgroundColor", "GridHeaderBackgroundColor" } },
                { "AccentHeaderFg", new[] { "AccentHeaderForegroundColor", "GridHeaderForegroundColor" } },
                { "SelectedTabBg", new[] { "SelectedTabBackgroundColor", "TabHoverBackgroundColor" } },
                { "Disabled", new[] { "DisabledForegroundColor" } },
                { "SecondaryText", new[] { "SecondaryTextColor" } },
                { "Success", new[] { "SuccessColor" } },
                { "Warning", new[] { "WarningColor" } },
                { "Error", new[] { "ErrorColor" } }
            };
            
            foreach (var mapping in colorMappings)
            {
                foreach (var targetKey in mapping.Value)
                {
                    AddColor(dict, colors, mapping.Key, targetKey);
                }
            }
            
            // UnselectedTabBackgroundColor removed - tabs default to transparent.

            // Add DisabledOpacity (dark themes use higher opacity for visibility, light themes lower)
            double disabledOpacity = 0.4;  // Default fallback
            if (colors.Contains("DisabledOpacity"))
            {
                object opacityValue = colors["DisabledOpacity"];
                if (opacityValue is double)
                {
                    disabledOpacity = (double)opacityValue;
                }
                else if (opacityValue is int)
                {
                    disabledOpacity = (double)(int)opacityValue;
                }
                else
                {
                    double.TryParse(opacityValue.ToString(), out disabledOpacity);
                }
            }
            dict["DisabledOpacity"] = disabledOpacity;

            return dict;
        }

        private static void AddBrush(ResourceDictionary dict, IDictionary colors, string sourceKey, string targetKey)
        {
            if (!colors.Contains(sourceKey)) return;
            if (dict.Contains(targetKey)) return;  // Don't overwrite existing

            string hexColor = colors[sourceKey] as string;
            if (string.IsNullOrEmpty(hexColor)) return;

            SolidColorBrush brush = CreateFrozenBrush(hexColor);
            if (brush != null)
            {
                dict[targetKey] = brush;
            }
        }

        private static void AddColor(ResourceDictionary dict, IDictionary colors, string sourceKey, string targetKey)
        {
            if (!colors.Contains(sourceKey)) return;
            if (dict.Contains(targetKey)) return;

            string hexColor = colors[sourceKey] as string;
            if (string.IsNullOrEmpty(hexColor)) return;

            try
            {
                Color color = (Color)ColorConverter.ConvertFromString(hexColor);
                dict[targetKey] = color;
            }
            catch (Exception ex)
            {
                DebugHelper.LogException("THEME", string.Format("AddColorResource '{0}' from '{1}'", targetKey, sourceKey), ex);
            }
        }

        // Frozen brushes are thread-safe and more performant
        private static SolidColorBrush CreateFrozenBrush(string hexColor)
        {
            try
            {
                Color color = (Color)ColorConverter.ConvertFromString(hexColor);
                SolidColorBrush brush = new SolidColorBrush(color);
                brush.Freeze();
                return brush;
            }
            catch (Exception ex)
            {
                DebugHelper.LogException("THEME", string.Format("CreateFrozenBrush from '{0}'", hexColor), ex);
                return null;
            }
        }

        // Bind element to theme resources via SetResourceReference - creates live binding that auto-updates
        private static void BindElementToResources(FrameworkElement element)
        {
            if (element == null) return;

            // Window
            if (element is Window)
            {
                Window window = (Window)element;
                
                // Skip background binding for transparent/borderless windows (custom chrome)
                // They need to stay transparent for the shadow effect to work
                if (!window.AllowsTransparency)
                {
                    window.SetResourceReference(Window.BackgroundProperty, "WindowBackgroundBrush");
                }
                window.SetResourceReference(Window.ForegroundProperty, "WindowForegroundBrush");
                
                // Sync DWM title bar with theme colors (Win32 API call required)
                // Only applies to windows with native chrome (not borderless)
                if (window.WindowStyle != WindowStyle.None && 
                    Application.Current != null && Application.Current.Resources != null)
                {
                    var headerBgBrush = Application.Current.Resources["HeaderBackgroundBrush"] as SolidColorBrush;
                    var headerFgBrush = Application.Current.Resources["HeaderForegroundBrush"] as SolidColorBrush;
                    if (headerBgBrush != null && headerFgBrush != null)
                    {
                        WindowManager.SetTitleBarColor(window, headerBgBrush.Color, headerFgBrush.Color);
                    }
                }
            }
            // TextBox
            else if (element is TextBox)
            {
                TextBox textBox = (TextBox)element;
                textBox.SetResourceReference(TextBox.BackgroundProperty, "ControlBackgroundBrush");
                textBox.SetResourceReference(TextBox.ForegroundProperty, "ControlForegroundBrush");
                textBox.SetResourceReference(TextBox.BorderBrushProperty, "BorderBrush");
                textBox.SetResourceReference(TextBox.CaretBrushProperty, "ControlForegroundBrush");
            }
            // PasswordBox
            else if (element is PasswordBox)
            {
                PasswordBox passBox = (PasswordBox)element;
                passBox.SetResourceReference(PasswordBox.BackgroundProperty, "ControlBackgroundBrush");
                passBox.SetResourceReference(PasswordBox.ForegroundProperty, "ControlForegroundBrush");
                passBox.SetResourceReference(PasswordBox.BorderBrushProperty, "BorderBrush");
                passBox.SetResourceReference(PasswordBox.CaretBrushProperty, "ControlForegroundBrush");
            }
            // ComboBox
            else if (element is ComboBox)
            {
                ComboBox comboBox = (ComboBox)element;
                comboBox.SetResourceReference(ComboBox.BackgroundProperty, "ControlBackgroundBrush");
                comboBox.SetResourceReference(ComboBox.ForegroundProperty, "ControlForegroundBrush");
                comboBox.SetResourceReference(ComboBox.BorderBrushProperty, "BorderBrush");
            }
            // ListBox
            else if (element is ListBox)
            {
                ListBox listBox = (ListBox)element;
                listBox.SetResourceReference(ListBox.BackgroundProperty, "ControlBackgroundBrush");
                listBox.SetResourceReference(ListBox.ForegroundProperty, "ControlForegroundBrush");
                listBox.SetResourceReference(ListBox.BorderBrushProperty, "BorderBrush");
            }
            // TreeView
            else if (element is TreeView)
            {
                TreeView treeView = (TreeView)element;
                treeView.SetResourceReference(TreeView.BackgroundProperty, "ControlBackgroundBrush");
                treeView.SetResourceReference(TreeView.ForegroundProperty, "ControlForegroundBrush");
                treeView.SetResourceReference(TreeView.BorderBrushProperty, "BorderBrush");
            }
            // DatePicker
            else if (element is DatePicker)
            {
                DatePicker datePicker = (DatePicker)element;
                datePicker.SetResourceReference(DatePicker.BackgroundProperty, "ControlBackgroundBrush");
                datePicker.SetResourceReference(DatePicker.ForegroundProperty, "ControlForegroundBrush");
                datePicker.SetResourceReference(DatePicker.BorderBrushProperty, "BorderBrush");
            }
            // DataGrid
            else if (element is DataGrid)
            {
                DataGrid dataGrid = (DataGrid)element;
                dataGrid.SetResourceReference(DataGrid.BackgroundProperty, "ControlBackgroundBrush");
                dataGrid.SetResourceReference(DataGrid.ForegroundProperty, "ControlForegroundBrush");
                dataGrid.SetResourceReference(DataGrid.BorderBrushProperty, "BorderBrush");
                dataGrid.SetResourceReference(DataGrid.AlternatingRowBackgroundProperty, "GridAlternatingRowBrush");
                dataGrid.SetResourceReference(DataGrid.RowBackgroundProperty, "WindowBackgroundBrush");
            }
            // TabControl
            else if (element is TabControl)
            {
                TabControl tabControl = (TabControl)element;
                tabControl.Background = Brushes.Transparent;
                tabControl.SetResourceReference(TabControl.ForegroundProperty, "ControlForegroundBrush");
                tabControl.SetResourceReference(TabControl.BorderBrushProperty, "BorderBrush");
            }
            // GroupBox
            else if (element is GroupBox)
            {
                GroupBox groupBox = (GroupBox)element;
                groupBox.SetResourceReference(GroupBox.BorderBrushProperty, "BorderBrush");
                groupBox.SetResourceReference(GroupBox.ForegroundProperty, "ControlForegroundBrush");
            }
            // TextBlock
            else if (element is TextBlock)
            {
                TextBlock textBlock = (TextBlock)element;
                
                // Tag can be a plain string ("AccentBrush") or a hashtable with a BrushTag key
                string brushKey = textBlock.Tag as string;
                if (brushKey == null)
                {
                    Hashtable tagTable = textBlock.Tag as Hashtable;
                    if (tagTable != null && tagTable.ContainsKey("BrushTag"))
                    {
                        brushKey = tagTable["BrushTag"] as string;
                    }
                }
                
                if (string.IsNullOrEmpty(brushKey))
                {
                    brushKey = "ControlForegroundBrush";
                }
                else if (brushKey == "HeaderText" || brushKey == "ThemeButtonIcon")
                {
                    // Map semantic tags to header foreground brush
                    brushKey = "HeaderForegroundBrush";
                }
                else if (brushKey == "ButtonFgBrush" || brushKey == "ComboButtonText")
                {
                    // Map button foreground tag to actual brush resource key
                    brushKey = "ButtonForegroundBrush";
                }
                // Nuke any local value so the resource binding wins
                textBlock.ClearValue(TextBlock.ForegroundProperty);
                textBlock.SetResourceReference(TextBlock.ForegroundProperty, brushKey);
            }
            // Border
            else if (element is Border)
            {
                Border border = (Border)element;
                
                // Check for string tag first (e.g., TimePickerBorder, CardSeparator, HeaderBorder)
                string stringTag = border.Tag as string;
                if (!string.IsNullOrEmpty(stringTag))
                {
                    // TimePicker borders need background and border brush updates
                    if (stringTag == "TimePickerBorder" || stringTag == "TimePickerArrowBorder")
                    {
                        border.ClearValue(Border.BackgroundProperty);
                        border.ClearValue(Border.BorderBrushProperty);
                        border.SetResourceReference(Border.BackgroundProperty, "ControlBackgroundBrush");
                        border.SetResourceReference(Border.BorderBrushProperty, "BorderBrush");
                        return;
                    }
                    // Card separator line
                    if (stringTag == "CardSeparator")
                    {
                        border.ClearValue(Border.BackgroundProperty);
                        border.SetResourceReference(Border.BackgroundProperty, "BorderBrush");
                        return;
                    }
                    // Window/dialog header bars
                    if (stringTag == "HeaderBorder")
                    {
                        border.ClearValue(Border.BackgroundProperty);
                        border.SetResourceReference(Border.BackgroundProperty, "HeaderBackgroundBrush");
                        return;
                    }
                    // Button-styled borders (e.g., peek buttons)
                    if (stringTag == "ButtonBgBrush")
                    {
                        border.ClearValue(Border.BackgroundProperty);
                        border.ClearValue(Border.BorderBrushProperty);
                        border.SetResourceReference(Border.BackgroundProperty, "ButtonBackgroundBrush");
                        border.SetResourceReference(Border.BorderBrushProperty, "BorderBrush");
                        return;
                    }
                }
                
                if (border.Background != null && border.Background != Brushes.Transparent)
                {
                    // Check if this is a card header (set by New-UiCard)
                    string brushKey = "ControlBackgroundBrush";
                    var tag = border.Tag as System.Collections.IDictionary;
                    if (tag != null)
                    {
                        // Check for CardHeader type
                        object typeObj = tag.Contains("Type") ? tag["Type"] : null;
                        bool isCardHeader = typeObj != null && typeObj.ToString() == "CardHeader";
                        
                        object isAccent;
                        if (tag.Contains("IsAccent"))
                        {
                            isAccent = tag["IsAccent"];
                            if (isAccent is bool && (bool)isAccent)
                            {
                                // Check if it has a custom color - if so, don't override
                                object customColor = tag.Contains("CustomColor") ? tag["CustomColor"] : null;
                                if (customColor == null || string.IsNullOrEmpty(customColor as string))
                                {
                                    brushKey = "AccentBrush";
                                }
                                else
                                {
                                    // Has custom color, skip resource binding
                                    brushKey = null;
                                }
                            }
                            else if (isCardHeader)
                            {
                                // Non-accent card header uses GroupBoxBackgroundBrush
                                brushKey = "GroupBoxBackgroundBrush";
                            }
                        }
                        else if (isCardHeader)
                        {
                            // Card header without IsAccent flag uses GroupBoxBackgroundBrush
                            brushKey = "GroupBoxBackgroundBrush";
                        }
                    }
                    if (brushKey != null)
                    {
                        border.ClearValue(Border.BackgroundProperty);
                        border.SetResourceReference(Border.BackgroundProperty, brushKey);
                    }
                }
                border.SetResourceReference(Border.BorderBrushProperty, "BorderBrush");
            }
            // Generic Panel
            else if (element is Panel)
            {
                Panel panel = (Panel)element;
                if (panel.Background != null && panel.Background != Brushes.Transparent)
                {
                    panel.SetResourceReference(Panel.BackgroundProperty, "ControlBackgroundBrush");
                }
            }
            // Button - styles handle most of it, just set foreground
            else if (element is Button)
            {
                Button button = (Button)element;
                
                // Check if this is an accent button (set via Tag.IsAccent)
                var tagDict = button.Tag as IDictionary;
                bool isAccent = false;
                if (tagDict != null && tagDict.Contains("IsAccent"))
                {
                    object isAccentObj = tagDict["IsAccent"];
                    isAccent = isAccentObj is bool && (bool)isAccentObj;
                }
                
                if (isAccent)
                {
                    // Accent buttons use accent color brushes - bind to resources for theme updates
                    button.ClearValue(Button.BackgroundProperty);
                    button.ClearValue(Button.ForegroundProperty);
                    button.ClearValue(Button.BorderBrushProperty);
                    button.SetResourceReference(Button.BackgroundProperty, "AccentBrush");
                    button.SetResourceReference(Button.ForegroundProperty, "AccentHeaderForegroundBrush");
                    button.SetResourceReference(Button.BorderBrushProperty, "AccentBrush");
                    
                    // Also update child TextBlocks
                    UpdateButtonChildForegrounds(button, "AccentHeaderForegroundBrush");
                }
                // Non-accent buttons use styles with DynamicResource - no action needed
            }
            // Slider
            else if (element is Slider)
            {
                Slider slider = (Slider)element;
                slider.SetResourceReference(Slider.ForegroundProperty, "AccentBrush");
                slider.SetResourceReference(Slider.BackgroundProperty, "BorderBrush");
            }
            // CheckBox
            else if (element is CheckBox)
            {
                CheckBox checkBox = (CheckBox)element;
                checkBox.SetResourceReference(CheckBox.ForegroundProperty, "ControlForegroundBrush");
                checkBox.SetResourceReference(CheckBox.BorderBrushProperty, "BorderBrush");
                checkBox.SetResourceReference(CheckBox.BackgroundProperty, "ControlBackgroundBrush");
            }
            // RadioButton
            else if (element is RadioButton)
            {
                RadioButton radioButton = (RadioButton)element;
                radioButton.SetResourceReference(RadioButton.ForegroundProperty, "ControlForegroundBrush");
                radioButton.SetResourceReference(RadioButton.BorderBrushProperty, "BorderBrush");
                radioButton.SetResourceReference(RadioButton.BackgroundProperty, "ControlBackgroundBrush");
            }
            // Label
            else if (element is Label)
            {
                Label label = (Label)element;
                // Clear local override so theme brush applies
                label.ClearValue(Label.ForegroundProperty);
                label.SetResourceReference(Label.ForegroundProperty, "ControlForegroundBrush");
            }
            // ProgressBar
            else if (element is ProgressBar)
            {
                ProgressBar progressBar = (ProgressBar)element;
                progressBar.SetResourceReference(ProgressBar.ForegroundProperty, "AccentBrush");
                progressBar.SetResourceReference(ProgressBar.BackgroundProperty, "BorderBrush");
            }
        }

        private static void UpdateButtonChildForegrounds(Button button, string brushKey)
        {
            if (button.Content == null) return;
            
            if (button.Content is StackPanel)
            {
                StackPanel panel = (StackPanel)button.Content;
                foreach (var child in panel.Children)
                {
                    TextBlock tb = child as TextBlock;
                    if (tb != null)
                    {
                        tb.ClearValue(TextBlock.ForegroundProperty);
                        tb.SetResourceReference(TextBlock.ForegroundProperty, brushKey);
                    }
                }
            }
            else if (button.Content is Viewbox)
            {
                Viewbox viewBox = (Viewbox)button.Content;
                TextBlock tb = viewBox.Child as TextBlock;
                if (tb != null)
                {
                    tb.ClearValue(TextBlock.ForegroundProperty);
                    tb.SetResourceReference(TextBlock.ForegroundProperty, brushKey);
                }
                else
                {
                    StackPanel panel = viewBox.Child as StackPanel;
                    if (panel != null)
                    {
                        foreach (var child in panel.Children)
                        {
                            TextBlock childTb = child as TextBlock;
                            if (childTb != null)
                            {
                                childTb.ClearValue(TextBlock.ForegroundProperty);
                                childTb.SetResourceReference(TextBlock.ForegroundProperty, brushKey);
                            }
                        }
                    }
                }
            }
            else if (button.Content is TextBlock)
            {
                TextBlock tb = (TextBlock)button.Content;
                tb.ClearValue(TextBlock.ForegroundProperty);
                tb.SetResourceReference(TextBlock.ForegroundProperty, brushKey);
            }
        }

        // Re-bind all registered elements, skipping any with dead dispatchers
        private static void RefreshRegisteredElements()
        {
            var toRemove = new List<WeakReference<FrameworkElement>>();
            var snapshot = new List<WeakReference<FrameworkElement>>();
            
            // Take a snapshot under lock to avoid iteration issues
            lock (_elementsLock)
            {
                snapshot.AddRange(_registeredElements);
            }

            foreach (var weakRef in snapshot)
            {
                FrameworkElement element;
                if (weakRef.TryGetTarget(out element))
                {
                    // Skip elements on different threads (child windows from async contexts)
                    if (!element.Dispatcher.CheckAccess())
                    {
                        toRemove.Add(weakRef);
                        continue;
                    }
                    
                    // Skip elements with dead dispatchers
                    if (element.Dispatcher.HasShutdownStarted)
                    {
                        toRemove.Add(weakRef);
                        continue;
                    }
                    
                    RefreshElementAndDescendants(element);
                }
                else
                {
                    toRemove.Add(weakRef);
                }
            }

            // Remove dead refs under lock
            lock (_elementsLock)
            {
                foreach (var dead in toRemove)
                {
                    _registeredElements.Remove(dead);
                }
            }
        }

        // Recursively refresh element and descendants - skips ControlTemplate elements (they have their own DynamicResource)
        private static void RefreshElementAndDescendants(DependencyObject element)
        {
            // Bind this element if it's a FrameworkElement
            FrameworkElement fe = element as FrameworkElement;
            if (fe != null)
            {
                // Skip elements that are part of a ControlTemplate - they handle their own theming
                // via DynamicResource in the template. We only bind "root" elements.
                if (fe.TemplatedParent == null)
                {
                    BindElementToResources(fe);
                }
            }

            // Walk children in the visual tree
            int childCount = VisualTreeHelper.GetChildrenCount(element);
            for (int i = 0; i < childCount; i++)
            {
                DependencyObject child = VisualTreeHelper.GetChild(element, i);
                RefreshElementAndDescendants(child);
            }
        }

        // Load control styles from XAML files - idempotent, skips reload if already present
        public static void LoadStyles()
        {
            if (string.IsNullOrEmpty(_modulePath)) return;
            if (Application.Current == null || Application.Current.Dispatcher.HasShutdownStarted) return;

            var mergedDicts = Application.Current.Resources.MergedDictionaries;
            
            // Check if styles are already loaded - skip reload to avoid disrupting existing controls
            foreach (ResourceDictionary dict in mergedDicts)
            {
                if (dict.Contains(StyleMarkerKey))
                {
                    // Styles already present, nothing to do
                    _stylesLoaded = true;
                    return;
                }
            }

            // Load SharedStyles first (it's in the Themes folder, not Styles)
            try
            {
                string sharedPath = Path.Combine(_modulePath, "Resources", "XAML", "Themes", "SharedStyles.xaml");
                if (File.Exists(sharedPath))
                {
                    using (FileStream stream = new FileStream(sharedPath, FileMode.Open, FileAccess.Read))
                    {
                        ResourceDictionary sharedDict = (ResourceDictionary)XamlReader.Load(stream);
                        sharedDict[StyleMarkerKey] = true;
                        mergedDicts.Add(sharedDict);
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("Failed to load SharedStyles: " + ex.Message);
            }

            // Load style files from Styles folder
            // ContextMenuStyle must load before TextBoxStyle (TextBox uses ContextMenu)
            string[] styleFiles = new string[] 
            { 
                "CommonStyles",
                "ContextMenuStyle",
                "ButtonStyle", 
                "TabControlStyle", 
                "TextBoxStyle", 
                "ComboBoxStyle",
                "DatePickerStyle",
                "DataGridStyle", 
                "GroupBoxStyle",
                "ScrollBarStyle",
                "SliderStyle"
            };
            
            foreach (string styleFile in styleFiles)
            {
                try
                {
                    string xamlPath = Path.Combine(_modulePath, "Resources", "XAML", "Styles", styleFile + ".xaml");
                    if (File.Exists(xamlPath))
                    {
                        using (FileStream stream = new FileStream(xamlPath, FileMode.Open, FileAccess.Read))
                        {
                            ResourceDictionary styleDict = (ResourceDictionary)XamlReader.Load(stream);
                            styleDict[StyleMarkerKey] = true;
                            mergedDicts.Add(styleDict);
                        }
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine("Failed to load style " + styleFile + ": " + ex.Message);
                }
            }
        }

        public static string[] GetAvailableThemes()
        {
            var themes = ModuleContext.Themes;
            if (themes == null || themes.Count == 0)
            {
                return new string[] { "Light", "Dark" };
            }

            var names = new List<string>();
            foreach (string key in themes.Keys)
            {
                names.Add(key);
            }
            return names.ToArray();
        }

        public static Hashtable GetThemeColors(string themeName)
        {
            var themes = ModuleContext.Themes;
            if (themes != null && themes.ContainsKey(themeName))
            {
                return themes[themeName] as Hashtable;
            }
            return null;
        }

        // Legacy compatibility methods

        public static void SetTheme(string themeName)
        {
            Hashtable colors = GetThemeColors(themeName);
            if (colors != null)
            {
                ApplyTheme(themeName, colors);
            }
        }

        public static void ApplyThemeFromFile(string themeName)
        {
            SetTheme(themeName);
        }
    }
}
