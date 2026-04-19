using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace PsUi
{
    // Window building and UI construction - contains RunWindow and helper methods
    public partial class NewUiWindowCommand
    {
        // Main window creation/lifecycle: creates session, runspace, UI, runs event loop
        private Window RunWindow(WindowParameters p, PSHost host, ManualResetEvent windowReady = null, 
            Window[] windowHolder = null, Dictionary<string, object> exportedVariables = null,
            System.Windows.Threading.Dispatcher splashDispatcher = null)
        {
            Window window = null;
            Guid sessionId = Guid.Empty;
            Runspace windowRunspace = null;
            
            try
            {
                // Create session for this thread FIRST
                sessionId = SessionManager.CreateSession();
                SessionManager.SetCurrentSession(sessionId);
                
                var session = SessionManager.Current;
                if (session == null)
                {
                    throw new InvalidOperationException("Failed to create session context");
                }
                
                // Propagate debug mode to session so button actions can access it
                session.DebugMode = p.DebugMode;
                
                // Propagate async apartment mode (MTA uses ThreadPool, STA uses dedicated threads)
                session.UseMtaThreading = string.Equals(p.AsyncApartment, "MTA", StringComparison.OrdinalIgnoreCase);
                
                // Store caller script info for error reporting
                session.CallerScriptName = p.CallerScriptName;
                session.CallerScriptLine = p.CallerScriptLine;
                
                // Store export flag for captured variables
                session.ExportOnClose = p.ExportOnClose;
                
                // Store custom logo path if provided
                session.CustomLogo = p.Logo;

                // Create a runspace for this thread so we can call PowerShell functions
                var initialState = InitialSessionState.CreateDefault();
                windowRunspace = RunspaceFactory.CreateRunspace(host, initialState);
                windowRunspace.ApartmentState = System.Threading.ApartmentState.STA;
                windowRunspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                windowRunspace.Open();
                Runspace.DefaultRunspace = windowRunspace;

                // Import the PsUi module into this runspace
                if (!string.IsNullOrEmpty(p.ModulePath))
                {
                    using (var ps = PowerShell.Create())
                    {
                        ps.Runspace = windowRunspace;
                        ps.AddCommand("Import-Module")
                          .AddParameter("Name", p.ModulePath)
                          .AddParameter("Force", true);
                        ps.Invoke();
                        
                        if (ps.Streams.Error.Count > 0)
                        {
                            DebugLog("WINDOW", "Module import error: " + ps.Streams.Error[0].Exception.Message);
                        }
                    }
                }
                
                // Inject private functions into this runspace
                InjectPrivateFunctions(windowRunspace);
                
                // Inject preference variables for -Debug and -Verbose propagation
                if (p.DebugMode || p.VerboseMode)
                {
                    using (var ps = PowerShell.Create())
                    {
                        ps.Runspace = windowRunspace;
                        if (p.DebugMode)
                        {
                            ps.AddScript("$global:DebugPreference = 'Continue'; Write-Host '[PsUi Debug Mode Enabled]' -ForegroundColor Cyan");
                        }
                        if (p.VerboseMode)
                        {
                            ps.AddScript("$global:VerbosePreference = 'Continue'");
                        }
                        ps.Invoke();
                    }
                }

                // Re-set session after module import (module may have reset it)
                SessionManager.SetCurrentSession(sessionId);

                // Clear stale registered elements from previous windows
                ThemeEngine.Reset();

                // WPF Application must exist on this thread BEFORE theme init.
                // If a previous window's thread died, Application.Current may have a stale dispatcher.
                bool appIsStale = Application.Current != null && 
                    (Application.Current.Dispatcher.HasShutdownStarted ||
                     !Application.Current.Dispatcher.Thread.IsAlive);
                
                if (Application.Current == null)
                {
                    new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
                    DebugLog("APP", "Created new Application instance");
                }
                else if (appIsStale)
                {
                    // Application exists but dispatcher is unusable. WPF doesn't allow creating
                    // a new Application, so we work around it by applying resources directly.
                    DebugLog("APP", "Stale Application detected (dispatcher dead), will apply theme directly");
                }

                // Apply theme XAML resources (use custom JSON if provided)
                Hashtable customColors = null;
                string customThemeName = null;
                if (!string.IsNullOrEmpty(p.ThemePath))
                {
                    customColors = LoadThemeFromJson(p.ThemePath);
                    if (customColors != null)
                    {
                        // Get theme name from filename (LoadThemeFromJson registered it in ModuleContext)
                        customThemeName = Path.GetFileNameWithoutExtension(p.ThemePath);
                        
                        // Determine base theme type from custom colors or default to Light
                        string baseTheme = customColors.ContainsKey("Type") 
                            ? customColors["Type"] as string ?? "Light" 
                            : "Light";
                        DebugLog("THEME", "Loaded custom theme '" + customThemeName + "' from JSON, base type: " + baseTheme);
                        
                        // Apply custom colors directly to ThemeEngine using the actual theme name
                        ThemeEngine.ApplyTheme(customThemeName, customColors);
                        
                        // Set ActiveTheme so child windows (output panels) use the same theme
                        ModuleContext.ActiveTheme = customThemeName;
                    }
                    else
                    {
                        DebugLog("THEME", "Failed to load custom theme, falling back to: " + p.Theme);
                    }
                }
                
                if (customColors == null)
                {
                    try
                    {
                        ThemeEngine.ApplyThemeFromFile(p.Theme);
                    }
                    catch (Exception themeEx)
                    {
                        DebugLog("THEME", "XAML theme load failed, using fallback: " + themeEx.Message);
                        ThemeEngine.SetTheme(p.Theme);
                    }
                }

                // Initialize theme via PowerShell helper (or use custom colors if already loaded)
                Hashtable colors = customColors ?? InitializeTheme(p.Theme, windowRunspace);

                // Build and configure the window with custom chrome
                window = BuildWindow(p, colors);
                
                // Log dispatcher exceptions before suppressing
                window.Dispatcher.UnhandledException += (sender, e) =>
                {
                    DebugLog("DISPATCHER", "Unhandled exception: " + e.Exception.Message);
                    DebugLog("DISPATCHER", "Stack trace: " + e.Exception.StackTrace);
                    e.Handled = true;
                };

                // Get chrome elements from window tag (stored as Hashtable for PS accessibility)
                var chromeInfo = window.Tag as Hashtable;
                if (chromeInfo == null)
                {
                    throw new InvalidOperationException("Window chrome not initialized properly");
                }

                // Add theme button to titlebar if not hidden
                if (!p.HideThemeButton)
                {
                    string currentThemeName = customThemeName ?? p.Theme;
                    AddThemeButton(window, chromeInfo, currentThemeName, windowRunspace);
                }

                // Create content structure inside the ContentArea
                var outerPanel = new DockPanel();
                var contentArea = chromeInfo["ContentArea"] as Border;
                if (contentArea != null) contentArea.Child = outerPanel;

                // Create content area with layout-specific scrolling
                Panel contentPanel = CreateContentPanel(p.LayoutMode);
                
                if (p.AutoSize)
                {
                    // Full auto-size - use ScrollViewer so content scrolls if MaxHeight clips the window
                    var scrollViewer = new ScrollViewer
                    {
                        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                        HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
                    };
                    scrollViewer.Content = contentPanel;
                    outerPanel.Children.Add(scrollViewer);
                }
                else if (p.AutoSizeHeight)
                {
                    // Auto-size height - use ScrollViewer, window will cap height after layout
                    var scrollViewer = new ScrollViewer
                    {
                        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                        HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
                    };
                    scrollViewer.Content = contentPanel;
                    outerPanel.Children.Add(scrollViewer);
                }
                else
                {
                    // Fixed height - use ScrollViewer for overflow
                    var scrollViewer = new ScrollViewer
                    {
                        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                        HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
                    };
                    scrollViewer.Content = contentPanel;
                    outerPanel.Children.Add(scrollViewer);
                }

                // Configure session - store chromeInfo for later access, session accessible via GetSession
                session.Window = window;
                session.CurrentParent = contentPanel;
                session.LayoutMode = p.LayoutMode;
                session.MaxColumns = p.MaxColumns;
                session.TabAlignment = p.TabAlignment;
                session.AddControlSafe("MainWindow", window);

                // Set session ID variable for Get-UiSession
                using (var ps = PowerShell.Create())
                {
                    ps.Runspace = windowRunspace;
                    ps.AddScript(string.Format("$Global:__PsUiSessionId = '{0}'", sessionId));
                    ps.Invoke();
                }

                // Execute user's Content scriptblock
                ExecuteContentScript(p.Content, p.PrivateFunctions, p.CallerVariables, p.CallerFunctions, 
                                     session, windowRunspace, p.DebugMode, p.VerboseMode,
                                     p.CallerScriptName, p.CallerScriptLine);

                // Apply padding if no TabControl present
                ApplyContentPadding(contentPanel);

                // Configure window animations and events
                ConfigureWindowEvents(window, p, windowRunspace, colors, sessionId, splashDispatcher);

                // Apply custom WPF properties
                if (p.WPFProperties != null && p.WPFProperties.Count > 0)
                {
                    ApplyWpfProperties(window, p.WPFProperties);
                }
                
                // Force taskbar icon before showing window
                if (window.Icon != null)
                {
                    var bmpSource = window.Icon as System.Windows.Media.Imaging.BitmapSource;
                    if (bmpSource != null)
                    {
                        WindowManager.SetTaskbarIcon(window, bmpSource);
                    }
                }

                // PassThru mode: show window and run dispatcher loop (non-modal)
                if (p.PassThru)
                {
                    // Shutdown dispatcher when window closes so Dispatcher.Run() returns
                    window.Closed += (s, e) => window.Dispatcher.InvokeShutdown();
                    
                    // Show non-blocking (not modal)
                    window.Show();
                    
                    // Store window reference before signaling (Dispatcher.Run blocks afterward)
                    if (windowHolder != null) { windowHolder[0] = window; }
                    
                    // Signal that window is ready for caller to use
                    if (windowReady != null) { windowReady.Set(); }
                    
                    // Run message loop - blocks this thread but allows Invoke calls
                    System.Windows.Threading.Dispatcher.Run();
                    
                    // Export captured variables for PassThru mode
                    ExportCapturedVariables(sessionId, exportedVariables);
                    
                    return window;
                }

                // Show the window (blocks until closed)
                window.ShowDialog();
                
                // Export captured variables to the shared dictionary for caller to use
                // Must happen BEFORE session disposal
                ExportCapturedVariables(sessionId, exportedVariables);
                
                // Dispose session after export
                if (sessionId != Guid.Empty)
                {
                    SessionManager.DisposeSession(sessionId);
                    sessionId = Guid.Empty;
                }
            }
            catch (Exception ex)
            {
                // Close splash if window creation fails
                if (splashDispatcher != null)
                {
                    try { splashDispatcher.InvokeShutdown(); } catch (Exception splashEx) { System.Diagnostics.Debug.WriteLine("Splash shutdown failed: " + splashEx.Message); }
                }
                
                DebugLog("WINDOW", "Window creation error: " + ex.Message);
                throw;
            }
            finally
            {
                // Always clean up session, even on error
                if (sessionId != Guid.Empty)
                {
                    SessionManager.DisposeSession(sessionId);
                }
                
                if (windowRunspace != null)
                {
                    try
                    {
                        windowRunspace.Close();
                        windowRunspace.Dispose();
                    }
                    catch (Exception ex)
                    {
                        DebugLog("WINDOW", "Runspace cleanup failed: " + ex.Message);
                    }
                }
            }

            return window;
        }
        
        // Exports captured vars back to caller scope when -ExportOnClose is used
        private void ExportCapturedVariables(Guid sessionId, Dictionary<string, object> exportedVariables)
        {
            var session = SessionManager.GetSession(sessionId);
            if (session == null || !session.ExportOnClose) return;
            if (exportedVariables == null) return;
            
            var captured = session.CapturedVariables;
            if (captured == null || captured.Count == 0) return;
            
            DebugLog("EXPORT", string.Format("Exporting {0} captured variable(s) to caller scope", captured.Count));
            
            // Copy captured variables to shared dictionary for caller thread
            foreach (var kvp in captured)
            {
                string varName = kvp.Key;
                object value = kvp.Value;
                
                // Validate name (basic security check)
                if (string.IsNullOrEmpty(varName) || !Constants.IsValidIdentifier(varName))
                {
                    DebugLog("EXPORT", string.Format("Skipped invalid variable name: {0}", varName));
                    continue;
                }
                
                // Store in shared dictionary - caller thread will set in its runspace
                exportedVariables[varName] = value;
                
                DebugLog("EXPORT", string.Format("Exported '{0}' ({1})", varName, 
                    value != null ? value.GetType().Name : "null"));
            }
        }
        
        // Create borderless window with custom chrome (matches Out-DataGrid style)
        private Window BuildWindow(WindowParameters p, Hashtable colors)
        {
            // Shadow adds visual padding around the window
            const int shadowPadding = 16;
            
            // Calculate actual window size including shadow padding
            int totalWidth = p.Width + (shadowPadding * 2);
            int totalHeight = p.Height + (shadowPadding * 2);
            
            // Create borderless transparent window for custom chrome
            var window = new Window
            {
                Title = p.Title,
                MinWidth = 300 + (shadowPadding * 2),
                MinHeight = 150 + (shadowPadding * 2),
                WindowStartupLocation = WindowStartupLocation.CenterScreen,
                FontFamily = new FontFamily("Segoe UI"),
                Background = Brushes.Transparent,
                WindowStyle = WindowStyle.None,
                AllowsTransparency = true,
                ResizeMode = p.NoResize ? ResizeMode.NoResize : ResizeMode.CanResize,
                Opacity = 0  // Start invisible for fade-in
            };
            
            // Calculate screen-aware max height (80% of work area, clamped to user's MaxHeight)
            var workArea = SystemParameters.WorkArea;
            int screenAwareMaxHeight = (int)(workArea.Height * 0.80);
            int effectiveMaxHeight = Math.Min(p.MaxHeight, screenAwareMaxHeight);
            
            // Configure sizing behavior
            if (p.AutoSize)
            {
                window.SizeToContent = SizeToContent.WidthAndHeight;
                window.MaxWidth = p.MaxWidth + (shadowPadding * 2);
                window.MaxHeight = effectiveMaxHeight + (shadowPadding * 2);
                DebugLog("WINDOW", string.Format("Auto-sizing window (max {0}x{1}, screen {2})", p.MaxWidth, effectiveMaxHeight, screenAwareMaxHeight));
            }
            else if (p.AutoSizeHeight)
            {
                window.Width = p.Width + (shadowPadding * 2);
                window.SizeToContent = SizeToContent.Height;
                window.MaxHeight = effectiveMaxHeight + (shadowPadding * 2);
                DebugLog("WINDOW", string.Format("Fixed width {0}, auto-sizing height (max {1}, screen {2})", p.Width, effectiveMaxHeight, screenAwareMaxHeight));
            }
            else
            {
                window.Width = totalWidth;
                window.Height = totalHeight;
                DebugLog("WINDOW", string.Format("Fixed window size: {0}x{1}", p.Width, p.Height));
            }
            
            // Set unique app ID for taskbar identity
            string appId = "PsUi.Window." + Guid.NewGuid().ToString().Substring(0, 8);
            WindowManager.SetWindowAppId(window, appId);
            
            // Enable proper maximize behavior for borderless window (respects taskbar)
            WindowManager.EnableBorderlessMaximize(window);

            // Attach WindowChrome for resize borders on borderless window
            if (!p.NoResize)
            {
                var chrome = new System.Windows.Shell.WindowChrome
                {
                    CaptionHeight = 0,  // We handle titlebar ourselves
                    ResizeBorderThickness = new Thickness(shadowPadding + 4),
                    GlassFrameThickness = new Thickness(0),
                    CornerRadius = new CornerRadius(0)
                };
                System.Windows.Shell.WindowChrome.SetWindowChrome(window, chrome);
            }

            // Build custom chrome structure
            BuildWindowChrome(window, p, colors, shadowPadding);
            
            // Register with ThemeEngine for dynamic switching
            ThemeEngine.RegisterElement(window);
            
            return window;
        }
        
        // Custom chrome: drop shadow + themed titlebar + resize handles
        private void BuildWindowChrome(Window window, WindowParameters p, Hashtable colors, int shadowPadding)
        {
            // Get initial colors from hashtable for immediate rendering
            Brush windowBg = Brushes.White;
            Brush borderBrush = Brushes.Gray;
            if (colors != null)
            {
                object bgVal = colors["WindowBg"];
                object borderVal = colors["Border"];
                if (bgVal != null) windowBg = ConvertToBrush(bgVal);
                if (borderVal != null) borderBrush = ConvertToBrush(borderVal);
            }
            
            // Create shadow border as the root visual
            var shadowBorder = new Border
            {
                Margin = new Thickness(shadowPadding),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(0),
                Background = windowBg,
                BorderBrush = borderBrush
            };
            
            // Also bind to DynamicResource for runtime theme changes
            shadowBorder.SetResourceReference(Border.BackgroundProperty, "WindowBackgroundBrush");
            shadowBorder.SetResourceReference(Border.BorderBrushProperty, "BorderBrush");
            
            // Apply drop shadow effect
            var shadow = new System.Windows.Media.Effects.DropShadowEffect
            {
                BlurRadius = 16,
                ShadowDepth = 2,
                Opacity = 0.3,
                Color = Colors.Black,
                Direction = 270
            };
            shadowBorder.Effect = shadow;
            window.Content = shadowBorder;
            
            // Create main layout grid
            var mainGrid = new Grid();
            mainGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });  // Titlebar
            mainGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });  // Content
            shadowBorder.Child = mainGrid;
            
            // Build custom titlebar and get references to placeholder elements
            ContentControl themeButtonPlaceholder;
            Image titleBarIcon;
            var titleBar = BuildTitleBar(window, p, colors, shadowBorder, shadowPadding, shadow,
                                          p.NoResize, out themeButtonPlaceholder, out titleBarIcon);
            Grid.SetRow(titleBar, 0);
            mainGrid.Children.Add(titleBar);
            
            // Create content area placeholder - will be populated later with actual content
            var contentArea = new Border { Name = "ContentArea" };
            Grid.SetRow(contentArea, 1);
            mainGrid.Children.Add(contentArea);
            
            // Store references for later use (hashtable for PowerShell accessibility)
            window.Tag = new Hashtable
            {
                { "ShadowBorder", shadowBorder },
                { "MainGrid", mainGrid },
                { "ContentArea", contentArea },
                { "TitleBarIcon", titleBarIcon },
                { "ThemeButtonPlaceholder", themeButtonPlaceholder },
                { "ShadowPadding", shadowPadding }
            };
        }
        
        // Titlebar layout: Icon | Title | ThemeButton | Min/Max/Close
        private Border BuildTitleBar(Window window, WindowParameters p, Hashtable colors, 
                                      Border shadowBorder, int shadowPadding,
                                      System.Windows.Media.Effects.DropShadowEffect cachedShadow,
                                      bool noResize,
                                      out ContentControl themeButtonPlaceholderOut,
                                      out Image titleBarIconOut)
        {
            // Titlebar container
            var titleBar = new Border
            {
                Height = 32,
                Tag = "HeaderBorder"
            };
            titleBar.SetResourceReference(Border.BackgroundProperty, "HeaderBackgroundBrush");
            
            // Grid layout: Icon | Title | ThemeButton | WindowControls
            var titleBarGrid = new Grid();
            titleBarGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });  // Icon
            titleBarGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });  // Title
            titleBarGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });  // Theme button
            titleBarGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });  // Window controls
            titleBar.Child = titleBarGrid;
            
            // Window icon placeholder - will be set via SetWindowIcon
            var iconImage = new Image
            {
                Name = "TitleBarIcon",
                Width = 16,
                Height = 16,
                Margin = new Thickness(10, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(iconImage, 0);
            titleBarGrid.Children.Add(iconImage);
            titleBarIconOut = iconImage;
            
            // Title text
            var titleText = new TextBlock
            {
                Text = p.Title,
                FontSize = 13,
                FontWeight = FontWeights.Normal,
                VerticalAlignment = VerticalAlignment.Center,
                TextTrimming = TextTrimming.CharacterEllipsis,
                Margin = new Thickness(8, 0, 0, 0),
                Tag = "HeaderText"
            };
            titleText.SetResourceReference(TextBlock.ForegroundProperty, "HeaderForegroundBrush");
            Grid.SetColumn(titleText, 1);
            titleBarGrid.Children.Add(titleText);
            
            // Theme button placeholder - will be added via PowerShell
            var themeButtonPlaceholder = new ContentControl
            {
                Name = "ThemeButtonPlaceholder",
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 0, 0)
            };
            Grid.SetColumn(themeButtonPlaceholder, 2);
            titleBarGrid.Children.Add(themeButtonPlaceholder);
            themeButtonPlaceholderOut = themeButtonPlaceholder;
            
            // Window control buttons
            var buttonPanel = new StackPanel { Orientation = Orientation.Horizontal };
            Grid.SetColumn(buttonPanel, 3);
            
            // Minimize button
            var minimizeBtn = CreateWindowControlButton("\uE921", false);
            minimizeBtn.Click += (s, e) => window.WindowState = WindowState.Minimized;
            buttonPanel.Children.Add(minimizeBtn);
            
            // Maximize/Restore button (only if resizing is allowed)
            Button maximizeBtn = null;
            if (!noResize)
            {
                maximizeBtn = CreateWindowControlButton("\uE922", false);
                maximizeBtn.Click += (s, e) =>
                {
                    window.WindowState = window.WindowState == WindowState.Maximized 
                        ? WindowState.Normal 
                        : WindowState.Maximized;
                };
                buttonPanel.Children.Add(maximizeBtn);
            }
            
            // Close button
            var closeBtn = CreateWindowControlButton("\uE8BB", true);
            closeBtn.Click += (s, e) =>
            {
                KeyCaptureDialog.CloseCurrentDialog();
                window.Close();
            };
            buttonPanel.Children.Add(closeBtn);
            
            titleBarGrid.Children.Add(buttonPanel);
            
            // Handle window state changes for maximize icon, shadow, and resize borders
            window.StateChanged += (s, e) =>
            {
                var chrome = System.Windows.Shell.WindowChrome.GetWindowChrome(window);
                
                if (window.WindowState == WindowState.Maximized)
                {
                    if (maximizeBtn != null) maximizeBtn.Content = "\uE923";  // Restore icon
                    shadowBorder.Margin = new Thickness(0);
                    shadowBorder.Effect = null;
                    
                    // Remove resize borders when maximized so scrollbars remain clickable
                    if (chrome != null) chrome.ResizeBorderThickness = new Thickness(0);
                }
                else
                {
                    if (maximizeBtn != null) maximizeBtn.Content = "\uE922";  // Maximize icon
                    shadowBorder.Margin = new Thickness(shadowPadding);
                    shadowBorder.Effect = cachedShadow;  // Reuse cached shadow
                    
                    // Restore resize borders for normal window state
                    if (chrome != null) chrome.ResizeBorderThickness = new Thickness(shadowPadding + 4);
                }
            };

            // Drag state for restore-on-drag
            Point? dragStartPoint = null;

            // Enable titlebar drag and double-click maximize (if resizing allowed)
            titleBar.MouseLeftButtonDown += (s, e) =>
            {
                if (e.ClickCount == 2 && !noResize)
                {
                    window.WindowState = window.WindowState == WindowState.Maximized 
                        ? WindowState.Normal 
                        : WindowState.Maximized;
                }
                else if (e.ClickCount == 1)
                {
                    if (window.WindowState == WindowState.Maximized)
                    {
                        // Capture start point - only restore when user actually drags
                        dragStartPoint = e.GetPosition(window);
                        titleBar.CaptureMouse();
                    }
                    else
                    {
                        window.DragMove();
                    }
                }
            };
            
            titleBar.MouseMove += (s, e) =>
            {
                if (dragStartPoint == null) return;
                if (e.LeftButton != System.Windows.Input.MouseButtonState.Pressed) return;
                
                // Check if mouse moved enough to count as a drag (5px threshold)
                var currentPos = e.GetPosition(window);
                double deltaX = Math.Abs(currentPos.X - dragStartPoint.Value.X);
                double deltaY = Math.Abs(currentPos.Y - dragStartPoint.Value.Y);
                
                if (deltaX > 5 || deltaY > 5)
                {
                    titleBar.ReleaseMouseCapture();
                    
                    // Capture screen position and relative X BEFORE restoring
                    var screenPos = window.PointToScreen(dragStartPoint.Value);
                    double relativeX = dragStartPoint.Value.X / window.ActualWidth;
                    
                    window.WindowState = WindowState.Normal;
                    
                    // Position window so mouse stays on titlebar at same relative X
                    window.Left = screenPos.X - (window.ActualWidth * relativeX);
                    window.Top = screenPos.Y - (shadowPadding + 16);
                    
                    dragStartPoint = null;
                    window.DragMove();
                }
            };
            
            titleBar.MouseLeftButtonUp += (s, e) =>
            {
                dragStartPoint = null;
                titleBar.ReleaseMouseCapture();
            };
            
            return titleBar;
        }
        
        // Min/Max/Close button with hover effect (uses XAML template)
        private Button CreateWindowControlButton(string glyph, bool isCloseButton)
        {
            var btn = new Button
            {
                Content = glyph,
                FontFamily = new FontFamily("Segoe MDL2 Assets"),
                FontSize = 10,
                Width = 46,
                Height = 32,
                BorderThickness = new Thickness(0),
                Cursor = System.Windows.Input.Cursors.Arrow,
                Padding = new Thickness(0),
                Tag = "WindowControlButton"
            };
            
            // Don't use SetResourceReference for Foreground - creates local value that 
            // overrides template trigger setters after theme changes. Foreground is set
            // inside the template via DynamicResource binding instead.
            
            string templateXaml = isCloseButton ? CloseButtonTemplate : WindowControlButtonTemplate;
            btn.Template = (ControlTemplate)System.Windows.Markup.XamlReader.Parse(templateXaml);
            
            // Mark button as hit-testable within WindowChrome area
            System.Windows.Shell.WindowChrome.SetIsHitTestVisibleInChrome(btn, true);
            
            return btn;
        }
        
        // Apply theme from XAML resources, falling back to hashtable
        private void ApplyWindowTheme(Window window, Hashtable colors)
        {
            bool colorsApplied = false;
            
            // Try XAML resources first
            if (Application.Current != null && Application.Current.Resources != null)
            {
                var windowBgBrush = Application.Current.TryFindResource("WindowBackgroundBrush") as Brush;
                var windowFgBrush = Application.Current.TryFindResource("WindowForegroundBrush") as Brush;
                
                DebugLog("THEME", "WindowBackgroundBrush found: " + (windowBgBrush != null));
                
                if (windowBgBrush != null)
                {
                    window.Background = windowBgBrush;
                    colorsApplied = true;
                }
                if (windowFgBrush != null)
                {
                    window.Foreground = windowFgBrush;
                }
            }
            
            // Fallback to hashtable colors
            if (!colorsApplied && colors != null)
            {
                DebugLog("THEME", "Using hashtable fallback for window colors");
                object windowBg = colors["WindowBg"];
                object windowFg = colors["WindowFg"];
                if (windowBg != null) window.Background = ConvertToBrush(windowBg);
                if (windowFg != null) window.Foreground = ConvertToBrush(windowFg);
            }
            
            DebugLog("THEME", "Final window.Background: " + window.Background);
        }
        
        // WrapPanel for responsive mode, StackPanel for stack mode
        private Panel CreateContentPanel(string layoutMode)
        {
            if (layoutMode == "Responsive")
            {
                return new WrapPanel
                {
                    Orientation = Orientation.Horizontal,
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    VerticalAlignment = VerticalAlignment.Top
                };
            }
            
            return new StackPanel
            {
                Orientation = Orientation.Vertical,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Top
            };
        }
        
        // Add padding to content area (TabControls have their own padding)
        private void ApplyContentPadding(Panel contentPanel)
        {
            bool hasTabControl = false;
            foreach (UIElement child in contentPanel.Children)
            {
                if (child is TabControl)
                {
                    hasTabControl = true;
                    break;
                }
            }

            if (!hasTabControl)
            {
                contentPanel.Margin = new Thickness(12);
            }
        }
        
        // Fade-in, icon setup, console restore on close
        private void ConfigureWindowEvents(Window window, WindowParameters p, Runspace windowRunspace, 
                                            Hashtable colors, Guid sessionId,
                                            System.Windows.Threading.Dispatcher splashDispatcher = null)
        {
            // Fade-in effect
            window.Opacity = 0;
            window.Loaded += (sender, e) =>
            {
                // Close splash window if it was shown
                if (splashDispatcher != null)
                {
                    try
                    {
                        splashDispatcher.InvokeShutdown();
                    }
                    catch (Exception splashEx) { System.Diagnostics.Debug.WriteLine("Splash shutdown failed: " + splashEx.Message); }
                    
                    // Defer activation until after layout completes (fixes auto-size windows)
                    window.Dispatcher.BeginInvoke(new Action(() =>
                    {
                        window.Activate();
                        window.Focus();
                    }), System.Windows.Threading.DispatcherPriority.Loaded);
                }
                
                // Cap height for auto-size modes after layout is complete
                if (p.AutoSize)
                {
                    // Switch from auto-size to manual so ScrollViewer constrains properly
                    double finalWidth = window.ActualWidth;
                    double finalHeight = window.ActualHeight;
                    window.SizeToContent = SizeToContent.Manual;
                    window.Width = finalWidth;
                    window.Height = finalHeight;
                    window.MaxWidth = double.PositiveInfinity;
                    window.MaxHeight = double.PositiveInfinity;
                    DebugLog("WINDOW", string.Format("AutoSize finalized: {0}x{1}", finalWidth, finalHeight));
                }
                else if (p.AutoSizeHeight && window.ActualHeight > p.MaxHeight)
                {
                    // Switch from auto-size to fixed height so maximize works
                    window.SizeToContent = SizeToContent.Manual;
                    window.Height = p.MaxHeight;
                    DebugLog("WINDOW", string.Format("Capped window height to {0}", p.MaxHeight));
                }
                else if (p.AutoSizeHeight)
                {
                    // Content fits - switch to manual so resizing works normally
                    double finalHeight = window.ActualHeight;
                    window.SizeToContent = SizeToContent.Manual;
                    window.Height = finalHeight;
                }
                
                // Clear MaxHeight constraint so maximize works properly
                if (p.AutoSizeHeight)
                {
                    window.MaxHeight = double.PositiveInfinity;
                }
                
                var animation = new System.Windows.Media.Animation.DoubleAnimation
                {
                    From = 0,
                    To = 1,
                    Duration = TimeSpan.FromMilliseconds(350)
                };
                animation.EasingFunction = new System.Windows.Media.Animation.QuadraticEase
                {
                    EasingMode = System.Windows.Media.Animation.EasingMode.EaseOut
                };
                window.BeginAnimation(UIElement.OpacityProperty, animation);
                
                // Set themed window icon and force taskbar update
                SetWindowIcon(window, windowRunspace, colors, p.Logo);
            };
            
            // Bring owned windows forward when parent is activated (fixes Alt+Tab)
            bool isActivatingChildren = false;
            window.Activated += (sender, e) =>
            {
                // Prevent re-entry during child activation
                if (isActivatingChildren) return;
                
                var parentWindow = sender as Window;
                if (parentWindow == null) return;
                
                isActivatingChildren = true;
                try
                {
                    // Activate all owned windows so they appear with parent
                    foreach (Window owned in parentWindow.OwnedWindows)
                    {
                        if (owned.IsVisible && !owned.IsActive)
                        {
                            owned.Activate();
                        }
                    }
                }
                finally
                {
                    isActivatingChildren = false;
                }
            };
            
            // Set window icon BEFORE showing
            SetWindowIcon(window, windowRunspace, colors, p.Logo);

            // Console minimize/restore
            IntPtr consolePtr = IntPtr.Zero;
            if (p.MinimizeConsole)
            {
                try
                {
                    consolePtr = WindowManager.GetConsoleWindow();
                    if (consolePtr != IntPtr.Zero)
                    {
                        WindowManager.ShowWindow(consolePtr, 6); // SW_MINIMIZE
                    }
                }
                catch (Exception ex)
                {
                    DebugLog("WINDOW", "Console minimize failed: " + ex.Message);
                }
            }

            window.Closed += (sender, e) =>
            {
                // Restore console only for top-level windows (no Owner)
                var closedWindow = sender as Window;
                bool isTopLevel = closedWindow != null && closedWindow.Owner == null;
                
                if (p.MinimizeConsole && consolePtr != IntPtr.Zero && isTopLevel)
                {
                    try
                    {
                        WindowManager.ShowWindow(consolePtr, 9); // SW_RESTORE
                    }
                    catch (Exception ex)
                    {
                        DebugLog("WINDOW", "Console restore failed: " + ex.Message);
                    }
                }

                // Session disposal moved to after ExportCapturedVariables in RunWindow
                window.Dispatcher.InvokeShutdown();
            };
            
            // Wire up window-level hotkey handler for Register-UiHotkey
            WireUpHotkeyHandler(window, windowRunspace, sessionId);
        }
        
        // Handle PreviewKeyDown for registered hotkeys
        private void WireUpHotkeyHandler(Window window, Runspace windowRunspace, Guid sessionId)
        {
            window.PreviewKeyDown += (sender, e) =>
            {
                // Skip if already handled
                if (e.Handled) return;
                
                var focused = System.Windows.Input.Keyboard.FocusedElement as System.Windows.DependencyObject;
                
                // Check if focus is in an editable text control
                bool isEditableText = false;
                if (focused is TextBox)
                {
                    isEditableText = !((TextBox)focused).IsReadOnly;
                }
                else if (focused is System.Windows.Controls.PasswordBox)
                {
                    isEditableText = true;
                }
                else if (focused is System.Windows.Controls.RichTextBox)
                {
                    isEditableText = !((System.Windows.Controls.RichTextBox)focused).IsReadOnly;
                }
                
                if (isEditableText)
                {
                    // Allow text input unless it's a modified key (Ctrl/Alt)
                    bool hasModifier = (System.Windows.Input.Keyboard.Modifiers & 
                        (System.Windows.Input.ModifierKeys.Control | System.Windows.Input.ModifierKeys.Alt)) != 0;
                    if (!hasModifier) return;
                }
                
                // Build normalized key combo string using StringBuilder to reduce allocations
                var mods = System.Windows.Input.Keyboard.Modifiers;
                var key = e.Key == System.Windows.Input.Key.System ? e.SystemKey : e.Key;
                
                // Ignore standalone modifier keys
                if (key == System.Windows.Input.Key.LeftCtrl || key == System.Windows.Input.Key.RightCtrl ||
                    key == System.Windows.Input.Key.LeftAlt || key == System.Windows.Input.Key.RightAlt ||
                    key == System.Windows.Input.Key.LeftShift || key == System.Windows.Input.Key.RightShift)
                {
                    return;
                }
                
                // Use StringBuilder to avoid List<string> and string.Join allocations per keypress
                var keyComboBuilder = new System.Text.StringBuilder(32);
                if ((mods & System.Windows.Input.ModifierKeys.Control) != 0) keyComboBuilder.Append("CTRL+");
                if ((mods & System.Windows.Input.ModifierKeys.Alt) != 0) keyComboBuilder.Append("ALT+");
                if ((mods & System.Windows.Input.ModifierKeys.Shift) != 0) keyComboBuilder.Append("SHIFT+");
                keyComboBuilder.Append(key.ToString().ToUpperInvariant());
                
                string keyCombo = keyComboBuilder.ToString();
                
                DebugLog("HOTKEY", "Key pressed: " + keyCombo);
                
                // Look up registered action in session
                var session = SessionManager.GetSession(sessionId);
                if (session == null)
                {
                    DebugLog("HOTKEY", "Session not found for ID: " + sessionId);
                    return;
                }
                
                var actionContext = session.GetHotkeyAction(keyCombo);
                if (actionContext == null)
                {
                    DebugLog("HOTKEY", "No hotkey registered for: " + keyCombo);
                    return;
                }
                
                DebugLog("HOTKEY", "Executing hotkey action for: " + keyCombo);
                
                e.Handled = true;
                
                // Execute the hotkey action via PowerShell
                try
                {
                    using (var ps = PowerShell.Create())
                    {
                        ps.Runspace = windowRunspace;
                        ps.AddScript("param($ctx) Invoke-UiHotkeyAction -Context $ctx");
                        ps.AddParameter("ctx", actionContext);
                        ps.Invoke();
                    }
                }
                catch (Exception ex)
                {
                    DebugLog("HOTKEY", "Hotkey execution failed: " + ex.Message);
                }
            };
        }
        
        // Set window and taskbar icons via PowerShell helper or custom logo
        private void SetWindowIcon(Window window, Runspace windowRunspace, Hashtable colors, string logoPath = null)
        {
            try
            {
                System.Windows.Media.Imaging.BitmapSource icon = null;
                
                // Try custom logo first
                if (!string.IsNullOrEmpty(logoPath))
                {
                    icon = LoadCustomIcon(logoPath);
                }
                
                // Fall back to generated icon
                if (icon == null)
                {
                    using (var ps = PowerShell.Create())
                    {
                        ps.Runspace = windowRunspace;
                        ps.AddScript("New-WindowIcon -Colors $args[0]").AddArgument(colors);
                        var iconResults = ps.Invoke();
                        if (iconResults != null && iconResults.Count > 0 && iconResults[0] != null)
                        {
                            icon = iconResults[0].BaseObject as System.Windows.Media.Imaging.BitmapSource;
                        }
                        
                        // Log any errors for debugging
                        if (ps.Streams.Error.Count > 0)
                        {
                            DebugLog("ICON", "New-WindowIcon error: " + ps.Streams.Error[0].ToString());
                        }
                    }
                }
                
                if (icon != null)
                {
                    window.Icon = icon;
                    WindowManager.SetTaskbarIcon(window, icon);
                    
                    // Also set the titlebar icon for custom chrome windows
                    var chromeInfo = window.Tag as Hashtable;
                    if (chromeInfo != null && chromeInfo.ContainsKey("TitleBarIcon"))
                    {
                        var titleBarIcon = chromeInfo["TitleBarIcon"] as Image;
                        if (titleBarIcon != null) titleBarIcon.Source = icon;
                    }
                }
            }
            catch (Exception iconEx)
            {
                DebugLog("ICON", "Icon creation failed: " + iconEx.Message);
            }
        }
        
        // Load custom icon from file path
        private System.Windows.Media.Imaging.BitmapSource LoadCustomIcon(string logoPath)
        {
            try
            {
                string resolvedPath = logoPath;
                if (!Path.IsPathRooted(logoPath))
                {
                    resolvedPath = Path.GetFullPath(logoPath);
                }
                
                if (File.Exists(resolvedPath))
                {
                    var bitmap = new System.Windows.Media.Imaging.BitmapImage();
                    bitmap.BeginInit();
                    bitmap.UriSource = new Uri(resolvedPath, UriKind.Absolute);
                    bitmap.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad;
                    bitmap.EndInit();
                    bitmap.Freeze();
                    return bitmap;
                }
            }
            catch (Exception ex)
            {
                DebugLog("ICON", "Failed to load custom logo: " + ex.Message);
            }
            
            return null;
        }

        // Required keys for a valid theme (minimum set for basic rendering)
        private static readonly string[] RequiredThemeKeys = new string[]
        {
            "WindowBg", "WindowFg", "ControlBg", "ControlFg", "ButtonBg", "ButtonFg", "Accent", "Border"
        };

        // Load custom theme from JSON file (validates required keys)
        private Hashtable LoadThemeFromJson(string themePath)
        {
            try
            {
                // Resolve relative paths
                string resolvedPath = themePath;
                if (!Path.IsPathRooted(themePath))
                {
                    resolvedPath = Path.GetFullPath(themePath);
                }

                if (!File.Exists(resolvedPath))
                {
                    // Log error to console since DebugLog may not be visible
                    Console.WriteLine("[PsUi] Theme file not found: " + resolvedPath);
                    DebugLog("THEME", "Theme file not found: " + resolvedPath);
                    return null;
                }
                
                // Cap at 100KB to avoid loading giant files by accident
                var fileInfo = new FileInfo(resolvedPath);
                if (fileInfo.Length > 100 * 1024)
                {
                    Console.WriteLine("[PsUi] Theme file too large (max 100KB): " + resolvedPath);
                    DebugLog("THEME", "Theme file too large: " + fileInfo.Length + " bytes");
                    return null;
                }
                
                string json = File.ReadAllText(resolvedPath);
                DebugLog("THEME", "Read theme JSON: " + json.Length + " chars from " + resolvedPath);
                
                // Parse JSON using PowerShell's ConvertFrom-Json (PS 5.1 compatible)
                using (var ps = PowerShell.Create(RunspaceMode.CurrentRunspace))
                {
                    ps.AddScript("param($json) $json | ConvertFrom-Json");
                    ps.AddParameter("json", json);
                    var results = ps.Invoke();
                    
                    if (ps.Streams.Error.Count > 0)
                    {
                        string parseError = ps.Streams.Error[0].Exception.Message;
                        Console.WriteLine("[PsUi] Invalid JSON in theme file: " + parseError);
                        DebugLog("THEME", "JSON parse error: " + parseError);
                        return null;
                    }
                    
                    if (results != null && results.Count > 0)
                    {
                        var pso = results[0];
                        if (pso == null)
                        {
                            Console.WriteLine("[PsUi] Theme file parsed but returned null");
                            return null;
                        }
                        
                        // Convert PSObject to Hashtable
                        var hashtable = new Hashtable(StringComparer.OrdinalIgnoreCase);
                        foreach (var prop in pso.Properties)
                        {
                            if (prop.Value != null)
                            {
                                hashtable[prop.Name] = prop.Value.ToString();
                            }
                        }
                        
                        // Validate required keys
                        var missingKeys = new List<string>();
                        foreach (string key in RequiredThemeKeys)
                        {
                            if (!hashtable.ContainsKey(key))
                            {
                                missingKeys.Add(key);
                            }
                        }
                        
                        if (missingKeys.Count > 0)
                        {
                            string missing = string.Join(", ", missingKeys.ToArray());
                            Console.WriteLine("[PsUi] Theme file missing required keys: " + missing);
                            DebugLog("THEME", "Missing required keys: " + missing);
                            return null;
                        }
                        
                        // Validate hex color format for all color keys
                        var invalidColors = new List<string>();
                        foreach (DictionaryEntry entry in hashtable)
                        {
                            string key = entry.Key.ToString();
                            string value = entry.Value != null ? entry.Value.ToString() : "";
                            
                            // Skip non-color keys (Type is a string like "Light" or "Dark")
                            if (key.Equals("Type", StringComparison.OrdinalIgnoreCase)) continue;
                            
                            // Validate hex color format: #RGB, #RRGGBB, or #AARRGGBB
                            if (!IsValidHexColor(value))
                            {
                                invalidColors.Add(key + "=" + value);
                            }
                        }
                        
                        if (invalidColors.Count > 0)
                        {
                            string invalid = string.Join(", ", invalidColors.ToArray());
                            Console.WriteLine("[PsUi] Theme file has invalid color values: " + invalid);
                            DebugLog("THEME", "Invalid colors (expected #RGB, #RRGGBB, or #AARRGGBB): " + invalid);
                            return null;
                        }
                        
                        // Determine theme name from filename (without extension)
                        string themeName = Path.GetFileNameWithoutExtension(resolvedPath);
                        
                        // Warn if overriding a built-in theme
                        if (ModuleContext.Themes.ContainsKey(themeName))
                        {
                            Console.WriteLine("[PsUi] Warning: Custom theme '" + themeName + "' overrides a built-in theme");
                        }
                        
                        // Register custom theme using thread-safe method
                        ModuleContext.RegisterTheme(themeName, hashtable);
                        DebugLog("THEME", "Registered custom theme '" + themeName + "' with " + hashtable.Count + " properties");
                        
                        return hashtable;
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("[PsUi] Failed to load theme: " + ex.Message);
                DebugLog("THEME", "Failed to load theme JSON: " + ex.Message);
            }
            return null;
        }

        // Accepts #RGB, #RRGGBB, or #AARRGGBB
        private static bool IsValidHexColor(string value)
        {
            if (string.IsNullOrEmpty(value)) return false;
            if (!value.StartsWith("#")) return false;
            
            string hex = value.Substring(1);
            
            // Valid lengths: 3 (#RGB), 6 (#RRGGBB), or 8 (#AARRGGBB)
            if (hex.Length != 3 && hex.Length != 6 && hex.Length != 8) return false;
            
            // Check all characters are valid hex digits
            foreach (char c in hex)
            {
                if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f')))
                {
                    return false;
                }
            }
            
            return true;
        }

        // Initialize theme via PowerShell and return color hashtable
        private Hashtable InitializeTheme(string theme, Runspace runspace)
        {
            try
            {
                using (var ps = PowerShell.Create())
                {
                    ps.Runspace = runspace;
                    ps.AddCommand("Initialize-UITheme").AddParameter("Theme", theme);
                    var results = ps.Invoke();
                    
                    if (ps.Streams.Error.Count > 0)
                    {
                        foreach (var err in ps.Streams.Error)
                        {
                            DebugLog("THEME", "PowerShell error: " + err.Exception.Message);
                        }
                    }
                    
                    if (results != null && results.Count > 0)
                    {
                        return results[0].BaseObject as Hashtable;
                    }
                }
            }
            catch (Exception ex)
            {
                DebugLog("THEME", "Theme initialization error: " + ex.Message);
            }
            return null;
        }

        // Add theme toggle to titlebar via PowerShell helper
        private void AddThemeButton(Window window, Hashtable chromeInfo, string currentTheme, Runspace runspace)
        {
            var placeholder = chromeInfo["ThemeButtonPlaceholder"] as ContentControl;
            if (placeholder == null)
            {
                DebugLog("THEME", "ThemeButtonPlaceholder not found in chrome info");
                return;
            }
            
            try
            {
                using (var ps = PowerShell.Create())
                {
                    ps.Runspace = runspace;
                    ps.AddCommand("New-ThemePopupButton")
                      .AddParameter("Container", window)
                      .AddParameter("CurrentTheme", currentTheme);
                    var results = ps.Invoke();
                    
                    if (ps.Streams.Error.Count > 0)
                    {
                        foreach (var err in ps.Streams.Error)
                        {
                            DebugLog("THEME", "Theme button error: " + err.Exception.Message);
                        }
                        return;
                    }
                    
                    if (results != null && results.Count > 0)
                    {
                        // New-ThemePopupButton returns a hashtable with Button and Popup keys
                        var resultObj = results[0].BaseObject;
                        Hashtable resultHash = resultObj as Hashtable;
                        
                        FrameworkElement themeButton = null;
                        if (resultHash != null && resultHash.ContainsKey("Button"))
                        {
                            themeButton = resultHash["Button"] as FrameworkElement;
                        }
                        else
                        {
                            // Direct cast - return type may have changed
                            themeButton = resultObj as FrameworkElement;
                        }
                        
                        if (themeButton != null)
                        {
                            placeholder.Content = themeButton;
                            DebugLog("THEME", "Theme button added to titlebar");
                        }
                        else
                        {
                            DebugLog("THEME", "Could not extract theme button from result");
                        }
                    }
                    else
                    {
                        DebugLog("THEME", "New-ThemePopupButton returned no results");
                    }
                }
            }
            catch (Exception ex)
            {
                DebugLog("THEME", "Theme button creation error: " + ex.Message);
            }
        }
        
        // Inject internal helper functions into window runspace
        private void InjectPrivateFunctions(Runspace runspace)
        {
            var privateFuncs = ModuleContext.PrivateFunctions;
            if (privateFuncs == null || privateFuncs.Count == 0)
            {
                DebugLog("INJECT", "No private functions to inject");
                return;
            }
            
            DebugLog("INJECT", "Injecting " + privateFuncs.Count + " private functions");
            
            using (var ps = PowerShell.Create())
            {
                ps.Runspace = runspace;
                
                foreach (DictionaryEntry entry in privateFuncs)
                {
                    string funcName = entry.Key.ToString();
                    string funcBody = entry.Value.ToString();
                    string script = string.Format("function {0} {{ {1} }}", funcName, funcBody);
                    
                    ps.Commands.Clear();
                    ps.AddScript(script);
                    ps.Invoke();
                    
                    if (ps.Streams.Error.Count > 0)
                    {
                        DebugLog("INJECT", "Failed to inject function " + funcName + ": " + ps.Streams.Error[0].Exception.Message);
                    }
                }
            }
        }

        // Run the users -Content scriptblock with injected vars/functions
        private void ExecuteContentScript(ScriptBlock content, Hashtable privateFunctions, 
                                           Dictionary<string, object> callerVariables,
                                           Dictionary<string, string> callerFunctions,
                                           SessionContext session, Runspace runspace,
                                           bool debugMode, bool verboseMode,
                                           string callerScriptName, int callerScriptLine)
        {
            // Inject caller's variables
            if (callerVariables != null && callerVariables.Count > 0)
            {
                foreach (var kvp in callerVariables)
                {
                    try
                    {
                        runspace.SessionStateProxy.SetVariable(kvp.Key, kvp.Value);
                    }
                    catch (Exception ex)
                    {
                        DebugLog("INJECT", "Failed to inject variable " + kvp.Key + ": " + ex.Message);
                    }
                }
            }
            
            // Inject caller's functions
            if (callerFunctions != null && callerFunctions.Count > 0)
            {
                using (var ps = PowerShell.Create())
                {
                    ps.Runspace = runspace;
                    foreach (var kvp in callerFunctions)
                    {
                        try
                        {
                            string funcDef = string.Format("function {0} {{{1}}}", kvp.Key, kvp.Value);
                            ps.AddScript(funcDef);
                        }
                        catch (Exception ex)
                        {
                            DebugLog("INJECT", "Failed to inject function " + kvp.Key + ": " + ex.Message);
                        }
                    }
                    ps.Invoke();
                }
            }

            // Execute the content scriptblock
            // Extract original file and line info from the scriptblock's AST for accurate error reporting
            // Fall back to caller info if AST doesn't have file info (inline scriptblocks)
            string originalFile = "script";
            int originalStartLine = 1;
            try
            {
                // Access Extent properties via reflection to avoid framework-specific interface issues
                var ast = content.Ast;
                if (ast != null)
                {
                    var extentProp = ast.GetType().GetProperty("Extent");
                    if (extentProp != null)
                    {
                        var extent = extentProp.GetValue(ast);
                        if (extent != null)
                        {
                            var fileProp = extent.GetType().GetProperty("File");
                            var lineProp = extent.GetType().GetProperty("StartLineNumber");
                            
                            if (fileProp != null)
                            {
                                var fileVal = fileProp.GetValue(extent) as string;
                                if (!string.IsNullOrEmpty(fileVal))
                                {
                                    originalFile = System.IO.Path.GetFileName(fileVal);
                                }
                            }
                            if (lineProp != null)
                            {
                                originalStartLine = (int)lineProp.GetValue(extent);
                            }
                        }
                    }
                }
            }
            catch { /* AST access failed, use defaults */ }
            
            // If AST didn't have file info, use caller's script info
            if (originalFile == "script" && !string.IsNullOrEmpty(callerScriptName))
            {
                originalFile = System.IO.Path.GetFileName(callerScriptName);
                originalStartLine = callerScriptLine;
            }

            using (var ps = PowerShell.Create())
            {
                ps.Runspace = runspace;
                
                var scriptBuilder = new System.Text.StringBuilder();
                if (debugMode)
                {
                    scriptBuilder.AppendLine("$DebugPreference = 'Continue'");
                    scriptBuilder.AppendLine("Write-Debug '[PsUi] Debug Mode Enabled (Prepend)'");
                }
                if (verboseMode)
                {
                    scriptBuilder.AppendLine("$VerbosePreference = 'Continue'");
                }
                
                // Wrap content in try/catch that preserves error details
                scriptBuilder.AppendLine("try {");
                scriptBuilder.Append(content.ToString());
                scriptBuilder.AppendLine();
                scriptBuilder.AppendLine("} catch {");
                scriptBuilder.AppendLine("    $__psui_err = $_");
                scriptBuilder.AppendLine("    $__psui_msg = $__psui_err.Exception.Message");
                // If error is already formatted (from nested Invoke-UiContent), pass it through
                scriptBuilder.AppendLine("    if ($__psui_msg -match '^\\[.+:\\d+\\]') {");
                scriptBuilder.AppendLine("        throw $__psui_msg");
                scriptBuilder.AppendLine("    }");
                scriptBuilder.AppendLine("    $__psui_info = $__psui_err.InvocationInfo");
                // Use MyCommand.Name since InvocationName is often empty
                scriptBuilder.AppendLine("    $__psui_cmd = 'unknown'");
                scriptBuilder.AppendLine("    if ($__psui_info -and $__psui_info.MyCommand) { $__psui_cmd = $__psui_info.MyCommand.Name }");
                scriptBuilder.AppendLine("    $__psui_relLine = if ($__psui_info) { $__psui_info.ScriptLineNumber } else { 0 }");
                scriptBuilder.AppendFormat("    $__psui_file = '{0}'\n", originalFile.Replace("'", "''"));
                scriptBuilder.AppendFormat("    $__psui_baseLine = {0}\n", originalStartLine);
                scriptBuilder.AppendLine("    $__psui_actualLine = $__psui_baseLine + $__psui_relLine - 1");
                scriptBuilder.AppendLine("    $__psui_formatted = \"[$__psui_file`:$__psui_actualLine] Error in '$__psui_cmd': $__psui_msg\"");
                scriptBuilder.AppendLine("    throw $__psui_formatted");
                scriptBuilder.AppendLine("}");
                
                ps.AddScript(scriptBuilder.ToString());
                ps.Invoke();

                if (ps.Streams.Error.Count > 0)
                {
                    var error = ps.Streams.Error[0];
                    string errorMsg = error.Exception != null ? error.Exception.Message : error.ToString();
                    throw new RuntimeException(errorMsg, error.Exception);
                }
            }
        }

        // Convert string/Color/Brush to WPF Brush
        private Brush ConvertToBrush(object value)
        {
            if (value == null) return null;
            if (value is Brush) return (Brush)value;
            if (value is Color) return new SolidColorBrush((Color)value);
            if (value is string)
            {
                try
                {
                    return (Brush)new BrushConverter().ConvertFromString((string)value);
                }
                catch (Exception ex)
                {
                    DebugLog("THEME", "ConvertToBrush failed for '" + value + "': " + ex.Message);
                }
            }
            return null;
        }

        // Apply -WPFProperties hashtable values via reflection
        private void ApplyWpfProperties(FrameworkElement element, Hashtable properties)
        {
            if (element == null || properties == null) return;

            foreach (DictionaryEntry kvp in properties)
            {
                try
                {
                    string propName = kvp.Key.ToString();
                    object propValue = kvp.Value;

                    var propInfo = element.GetType().GetProperty(propName);
                    if (propInfo != null && propInfo.CanWrite)
                    {
                        propInfo.SetValue(element, propValue);
                    }
                }
                catch (Exception ex)
                {
                    DebugLog("WINDOW", "ApplyWpfProperties failed for '" + kvp.Key + "': " + ex.Message);
                }
            }
        }
        
        // Window control button templates - kept here to declutter CreateWindowControlButton
        private const string CloseButtonTemplate = @"
<ControlTemplate xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation""
                 xmlns:x=""http://schemas.microsoft.com/winfx/2006/xaml""
                 TargetType=""Button"">
    <Border x:Name=""border"" Background=""Transparent"">
        <ContentPresenter x:Name=""content"" HorizontalAlignment=""Center"" VerticalAlignment=""Center""
                          TextElement.Foreground=""{DynamicResource HeaderForegroundBrush}""/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property=""IsMouseOver"" Value=""True"">
            <Setter TargetName=""border"" Property=""Background"" Value=""#E81123""/>
            <Setter TargetName=""content"" Property=""TextElement.Foreground"" Value=""White""/>
        </Trigger>
        <Trigger Property=""IsPressed"" Value=""True"">
            <Setter TargetName=""border"" Property=""Background"" Value=""#C50F1F""/>
            <Setter TargetName=""content"" Property=""TextElement.Foreground"" Value=""White""/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>";

        private const string WindowControlButtonTemplate = @"
<ControlTemplate xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation""
                 xmlns:x=""http://schemas.microsoft.com/winfx/2006/xaml""
                 TargetType=""Button"">
    <Border x:Name=""border"" Background=""Transparent"">
        <ContentPresenter HorizontalAlignment=""Center"" VerticalAlignment=""Center""
                          TextElement.Foreground=""{DynamicResource HeaderForegroundBrush}""/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property=""IsMouseOver"" Value=""True"">
            <Setter TargetName=""border"" Property=""Background"" Value=""{DynamicResource WindowControlHoverBrush}""/>
        </Trigger>
        <Trigger Property=""IsPressed"" Value=""True"">
            <Setter TargetName=""border"" Property=""Background"" Value=""{DynamicResource WindowControlHoverBrush}""/>
            <Setter TargetName=""border"" Property=""Opacity"" Value=""0.7""/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>";

        // Splash window displayed while main window loads
        private Window BuildSplashWindow(WindowParameters p, Hashtable colors, ManualResetEvent splashReady)
        {
            const int splashWidth = 280;
            const int splashHeight = 180;
            const int shadowPad = 12;
            
            // Parse theme colors for splash styling
            Color bgColor = Color.FromRgb(255, 255, 255);
            Color fgColor = Color.FromRgb(30, 30, 30);
            Color accentColor = Color.FromRgb(71, 85, 105);
            
            if (colors != null)
            {
                bgColor = ParseHexColor(colors["WindowBg"] as string, bgColor);
                fgColor = ParseHexColor(colors["WindowFg"] as string, fgColor);
                accentColor = ParseHexColor(colors["Accent"] as string, accentColor);
            }
            
            var bgBrush = new SolidColorBrush(bgColor);
            var fgBrush = new SolidColorBrush(fgColor);
            var accentBrush = new SolidColorBrush(accentColor);
            
            // Create borderless splash window
            var splash = new Window
            {
                Title = p.Title,
                Width = splashWidth + (shadowPad * 2),
                Height = splashHeight + (shadowPad * 2),
                WindowStyle = WindowStyle.None,
                AllowsTransparency = true,
                Background = Brushes.Transparent,
                WindowStartupLocation = WindowStartupLocation.CenterScreen,
                ShowInTaskbar = false,
                Topmost = true,
                ResizeMode = ResizeMode.NoResize
            };
            
            // Shadow container
            var shadowBorder = new Border
            {
                Margin = new Thickness(shadowPad),
                Background = bgBrush,
                CornerRadius = new CornerRadius(8),
                Effect = new System.Windows.Media.Effects.DropShadowEffect
                {
                    Color = Colors.Black,
                    BlurRadius = 20,
                    ShadowDepth = 0,
                    Opacity = 0.35
                }
            };
            splash.Content = shadowBorder;
            
            // Main layout: title at top, logo in center, progress at bottom
            var mainPanel = new Grid();
            mainPanel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            mainPanel.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            mainPanel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            shadowBorder.Child = mainPanel;
            
            // Title text at top
            var titleText = new TextBlock
            {
                Text = p.Title,
                FontSize = 14,
                FontWeight = FontWeights.SemiBold,
                Foreground = fgBrush,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 16, 0, 0)
            };
            Grid.SetRow(titleText, 0);
            mainPanel.Children.Add(titleText);
            
            // Logo in center - either custom image or generated icon
            UIElement logoElement = CreateSplashLogo(p.Logo, accentBrush, fgBrush);
            Grid.SetRow(logoElement, 1);
            mainPanel.Children.Add(logoElement);
            
            // Indeterminate progress bar at bottom
            var progressBar = new ProgressBar
            {
                IsIndeterminate = true,
                Height = 3,
                Margin = new Thickness(24, 0, 24, 16),
                Background = new SolidColorBrush(Color.FromArgb(40, fgColor.R, fgColor.G, fgColor.B)),
                Foreground = accentBrush,
                BorderThickness = new Thickness(0)
            };
            Grid.SetRow(progressBar, 2);
            mainPanel.Children.Add(progressBar);
            
            // Signal that splash is ready (shown) after layout
            splash.Loaded += (s, e) =>
            {
                if (splashReady != null) { splashReady.Set(); }
            };
            
            return splash;
        }
        
        // Create logo element for splash screen
        private UIElement CreateSplashLogo(string logoPath, SolidColorBrush accentBrush, SolidColorBrush fgBrush)
        {
            // If custom logo path provided, try to load it
            if (!string.IsNullOrEmpty(logoPath))
            {
                try
                {
                    string resolvedPath = logoPath;
                    if (!Path.IsPathRooted(logoPath))
                    {
                        resolvedPath = Path.GetFullPath(logoPath);
                    }
                    
                    if (File.Exists(resolvedPath))
                    {
                        var bitmap = new System.Windows.Media.Imaging.BitmapImage();
                        bitmap.BeginInit();
                        bitmap.UriSource = new Uri(resolvedPath, UriKind.Absolute);
                        bitmap.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad;
                        bitmap.EndInit();
                        bitmap.Freeze();
                        
                        return new Image
                        {
                            Source = bitmap,
                            Width = 64,
                            Height = 64,
                            HorizontalAlignment = HorizontalAlignment.Center,
                            VerticalAlignment = VerticalAlignment.Center
                        };
                    }
                }
                catch (Exception ex)
                {
                    DebugLog("SPLASH", "Failed to load custom logo: " + ex.Message);
                }
            }
            
            // Default: generate the >_ icon at larger size
            return CreateDefaultSplashIcon(accentBrush);
        }
        
        // Generate the default >_ terminal icon for splash
        private UIElement CreateDefaultSplashIcon(SolidColorBrush accentBrush)
        {
            // Use DrawingVisual to create the icon (similar to New-WindowIcon but inline)
            var iconVisual = new DrawingVisual();
            using (var dc = iconVisual.RenderOpen())
            {
                // Draw rounded rectangle background
                var bgRect = new Rect(0, 0, 48, 48);
                dc.DrawRoundedRectangle(accentBrush, null, bgRect, 8, 8);
                
                // Calculate contrast color for chevron
                var bgColor = accentBrush.Color;
                double luminance = (0.299 * bgColor.R + 0.587 * bgColor.G + 0.114 * bgColor.B) / 255;
                var fgColor = luminance > 0.5 ? Colors.Black : Colors.White;
                var fgBrush = new SolidColorBrush(fgColor);
                
                // Draw chevron ">"
                var chevron = Geometry.Parse("M 10,9 L 27,21 L 10,33 Z");
                dc.DrawGeometry(fgBrush, null, chevron);
                
                // Draw underscore "_"
                var underscore = new Rect(27, 30, 14, 4);
                dc.DrawRectangle(fgBrush, null, underscore);
            }
            
            // Render to bitmap at 4x for crisp display
            var renderTarget = new System.Windows.Media.Imaging.RenderTargetBitmap(
                192, 192, 96, 96, PixelFormats.Pbgra32);
            
            var scaledVisual = new DrawingVisual();
            using (var dc = scaledVisual.RenderOpen())
            {
                dc.PushTransform(new ScaleTransform(4, 4));
                dc.DrawDrawing(iconVisual.Drawing);
                dc.Pop();
            }
            
            renderTarget.Render(scaledVisual);
            renderTarget.Freeze();
            
            return new Image
            {
                Source = renderTarget,
                Width = 64,
                Height = 64,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
        }
        
        // Parse hex color string to Color, with fallback
        private static Color ParseHexColor(string hex, Color fallback)
        {
            if (string.IsNullOrEmpty(hex)) { return fallback; }
            
            try
            {
                if (hex.StartsWith("#")) { hex = hex.Substring(1); }
                if (hex.Length == 6)
                {
                    byte r = Convert.ToByte(hex.Substring(0, 2), 16);
                    byte g = Convert.ToByte(hex.Substring(2, 2), 16);
                    byte b = Convert.ToByte(hex.Substring(4, 2), 16);
                    return Color.FromRgb(r, g, b);
                }
            }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine("ParseHexColor failed: " + ex.Message); }
            
            return fallback;
        }
    }
}
