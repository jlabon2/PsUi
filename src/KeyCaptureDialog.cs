using System;
using System.Management.Automation.Host;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace PsUi
{
    // Non-modal key capture dialog for $host.UI.RawUI.ReadKey() calls.
    // Shows a small "waiting for input" window that doesnt steal focus.
    // Closing via X returns Escape to signal cancellation.
    public class KeyCaptureDialog : Window
    {
        // Layout and sizing
        private const double DialogWidth = 360;
        private const double DialogHeight = 120;
        private const double TitleBarHeight = 28;
        private const double BottomCornerRadius = 8;
        private const double ScreenEdgePadding = 20;
        
        // Typography
        private const double PromptFontSize = 14;
        private const double HintFontSize = 11;
        private const double TitleFontSize = 11;
        private const double IconFontSize = 12;
        private const double CloseButtonSize = 28;
        
        // Animation timing
        private const int KeyFlashDurationMs = 180;
        private const double CursorBlinkIntervalMs = 530;
        private const int SlideAnimationMs = 150;
        
        // Timeouts
        private const int DialogReadyTimeoutMs = 15000;
        
        private KeyInfo _capturedKey;
        private bool _keyWasCaptured;
        private readonly TextBlock _promptText;
        private readonly TextBlock _hintText;
        
        // Parent window tracking for attached behavior
        private Dispatcher _parentDispatcher;
        private IntPtr _parentHwnd;
        private bool _parentMinimized;
        private bool _initiallyMaximized;
        
        // Track the current open dialog so it can be closed externally
        private static KeyCaptureDialog _currentDialog;
        private static readonly object _dialogLock = new object();
        
        // Session-based cancellation to prevent cross-session interference
        // Each BeginInputSession gets a new ID, CancelInputSession only affects that ID
        private static volatile int _currentSessionId = 0;
        private static volatile int _cancelledSessionId = -1;
        private static System.Threading.ManualResetEventSlim _cancelEvent = new System.Threading.ManualResetEventSlim(false);
        
        // Call this at the START of an async action to allow ReadKey calls
        // Returns a session ID that should be passed to CancelInputSession
        public static int BeginInputSession()
        {
            var newId = System.Threading.Interlocked.Increment(ref _currentSessionId);
            _cancelEvent.Reset();
            return newId;
        }
        
        // Call this when the output window is closing to cancel ALL pending ReadKey calls
        public static void CancelInputSession()
        {
            _cancelledSessionId = _currentSessionId;
            _cancelEvent.Set();
        }
        
        // Check if current session is cancelled
        private static bool IsSessionCancelled()
        {
            return _cancelledSessionId >= _currentSessionId;
        }
        
        // Theme colors - set at creation time from main app resources
        private Color _backgroundColor;
        private Color _titleBarColor;
        private Color _borderColor;
        private Color _accentColor;
        private Color _foregroundColor;
        
        // References for runtime theme updates
        private Border _mainBorder;
        private Border _titleBarBorder;
        private TextBlock _cursorText;
        private DispatcherTimer _cursorTimer;
        private DispatcherTimer _parentTrackTimer;
        private TextBlock _iconText;
        private TextBlock _titleText;
        
        // Peek mode - hold button to see through dialog
        private const double PeekOpacity = 0.15;
        private const double NormalOpacity = 1.0;
        private Border _peekButton;
        
        // Hint pulse animation when unfocused
        private System.Windows.Media.Animation.Storyboard _hintPulse;
        
        // Window icon for taskbar (must be stored for Loaded event)
        private BitmapSource _windowIcon;
        
        // Thread safety flag - prevents updates after dialog is closed
        private volatile bool _disposed;
        
        // Fallback dark theme colors
        private static readonly Color DefaultBackgroundColor = Color.FromRgb(30, 30, 30);
        private static readonly Color DefaultTitleBarColor = Color.FromRgb(45, 45, 48);
        private static readonly Color DefaultBorderColor = Color.FromRgb(63, 63, 70);
        private static readonly Color DefaultAccentColor = Color.FromRgb(0, 122, 204);
        private static readonly Color DefaultForegroundColor = Colors.White;
        
        // Remembered position when user drags the dialog (persists across calls in same session)
        private static double? _rememberedLeft = null;
        private static double? _rememberedTop = null;
        private static bool _positionWasSet = false;
        
        // Fire-and-forget close for any open dialog (call before closing parent window)
        public static void CloseCurrentDialog()
        {
            // Mark current session as cancelled so future ReadKey calls return immediately
            CancelInputSession();
            
            KeyCaptureDialog dialog;
            lock (_dialogLock)
            {
                dialog = _currentDialog;
                _currentDialog = null;
            }
            
            if (dialog == null) return;
            try
            {
                // Fire and forget - don't block the UI thread at all
                dialog.Dispatcher.BeginInvoke(new Action(() =>
                {
                    try { dialog.Close(); }
                    catch { /* ignore */ }
                }));
            }
            catch { /* ignore */ }
        }
        
        // Bring current dialog back to front (e.g. after confirmation dialog was shown)
        public static void BringToFront()
        {
            KeyCaptureDialog dialog;
            lock (_dialogLock)
            {
                dialog = _currentDialog;
            }
            
            if (dialog == null) return;
            
            try
            {
                dialog.Dispatcher.BeginInvoke(new Action(() =>
                {
                    try
                    {
                        dialog.Topmost = true;
                        dialog.Activate();
                        dialog.Focus();
                    }
                    catch { /* ignore */ }
                }));
            }
            catch { /* ignore */ }
        }
        
        public KeyInfo CapturedKey { get { return _capturedKey; } }
        
        // False if dialog was closed/cancelled without capturing a key
        public bool KeyWasCaptured { get { return _keyWasCaptured; } }
        
        public KeyCaptureDialog(string prompt = null) : this(prompt, null, null, null, IntPtr.Zero, null, false) { }
        
        public KeyCaptureDialog(string prompt, ThemeColors colors) : this(prompt, colors, null, null, IntPtr.Zero, null, false) { }
        
        public KeyCaptureDialog(string prompt, ThemeColors colors, BitmapSource windowIcon) : this(prompt, colors, windowIcon, null, IntPtr.Zero, null, false) { }
        
        public KeyCaptureDialog(string prompt, ThemeColors colors, BitmapSource windowIcon, Rect? parentBounds) : this(prompt, colors, windowIcon, parentBounds, IntPtr.Zero, null, false) { }
        
        public KeyCaptureDialog(string prompt, ThemeColors colors, BitmapSource windowIcon, Rect? parentBounds, IntPtr parentHwnd, Dispatcher parentDispatcher, bool parentMaximized)
        {
            // Store parent tracking info
            _parentHwnd = parentHwnd;
            _parentDispatcher = parentDispatcher;
            _parentMinimized = false;
            _initiallyMaximized = parentMaximized;
            
            // Apply theme colors or use defaults
            if (colors != null)
            {
                _backgroundColor = colors.Background;
                _titleBarColor = colors.TitleBar;
                _borderColor = colors.Border;
                _accentColor = colors.Accent;
                _foregroundColor = colors.Foreground;
            }
            else
            {
                _backgroundColor = DefaultBackgroundColor;
                _titleBarColor = DefaultTitleBarColor;
                _borderColor = DefaultBorderColor;
                _accentColor = DefaultAccentColor;
                _foregroundColor = DefaultForegroundColor;
            }
            
            // Determine if we're attached to a parent window
            bool isAttached = (parentHwnd != IntPtr.Zero && parentBounds.HasValue);
            
            // Window setup - borderless with custom chrome
            Title = "Waiting for Input";
            Width = DialogWidth;
            Height = DialogHeight;
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = !isAttached;  // Hide from taskbar when attached to parent
            Topmost = true;  // Temp - cleared in SourceInitialized once owner is set
            Background = Brushes.Transparent;
            
            // Set the window icon if provided
            if (windowIcon != null)
            {
                _windowIcon = windowIcon;
                Icon = windowIcon;
            }
            
            // Position the dialog: overlay inside parent, or standalone fallback
            WindowStartupLocation = WindowStartupLocation.Manual;
            if (isAttached && parentBounds.HasValue)
            {
                // Position as overlay inside parent window near bottom
                var pb = parentBounds.Value;
                
                // For maximized windows, use work area of parent's monitor
                if (_initiallyMaximized)
                {
                    var workArea = WindowManager.GetWorkAreaForWindow(_parentHwnd);
                    Left = workArea.Left + (workArea.Width - Width) / 2;
                    Top = workArea.Top + workArea.Height - Height - 60;
                }
                else
                {
                    Left = pb.Left + (pb.Width - Width) / 2;
                    Top = pb.Top + pb.Height - Height - 60;
                }
            }
            else if (_rememberedLeft.HasValue && _rememberedTop.HasValue)
            {
                Left = _rememberedLeft.Value;
                Top = _rememberedTop.Value;
            }
            else if (parentBounds.HasValue)
            {
                // Fallback: position centered below parent (standalone mode)
                var pb = parentBounds.Value;
                Left = pb.Left + (pb.Width - Width) / 2;
                Top = pb.Bottom;
                
                // If that would go off-screen, position above parent bottom instead
                var screenBottom = SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight;
                if (Top + Height > screenBottom)
                {
                    Top = pb.Bottom - Height;
                }
            }
            else
            {
                // Default to bottom-right corner of primary screen with some padding
                var workArea = SystemParameters.WorkArea;
                Left = workArea.Right - Width - ScreenEdgePadding;
                Top = workArea.Bottom - Height - ScreenEdgePadding;
            }
            
            // Validate position is within visible screen bounds (handles monitor changes)
            EnsureOnScreen();
            
            // Main border - always rounded for overlay appearance
            _mainBorder = new Border
            {
                Background = new SolidColorBrush(_backgroundColor),
                BorderBrush = new SolidColorBrush(_borderColor),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(BottomCornerRadius)
            };
            
            // Outer grid - include title bar only in standalone mode
            var outerGrid = new Grid();
            if (!isAttached)
            {
                outerGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(TitleBarHeight) });
            }
            outerGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            
            // Custom title bar - only in standalone mode
            if (!isAttached)
            {
                _titleBarBorder = CreateTitleBar(prompt);
                Grid.SetRow(_titleBarBorder, 0);
                outerGrid.Children.Add(_titleBarBorder);
            }
            
            // Content area with three rows: prompt, cursor, hint
            var contentGrid = new Grid();
            contentGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            contentGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            contentGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            Grid.SetRow(contentGrid, isAttached ? 0 : 1);
            
            // Prompt text
            _promptText = new TextBlock
            {
                Text = string.IsNullOrEmpty(prompt) ? "Press any key to continue..." : prompt,
                FontSize = PromptFontSize,
                Foreground = new SolidColorBrush(_foregroundColor),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Bottom,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(20, 15, 20, 5)
            };
            Grid.SetRow(_promptText, 0);
            contentGrid.Children.Add(_promptText);
            
            // Blinking cursor - terminal style
            _cursorText = new TextBlock
            {
                Text = "_",
                FontSize = 24,
                FontFamily = new FontFamily("Consolas, Courier New"),
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(_accentColor),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetRow(_cursorText, 1);
            contentGrid.Children.Add(_cursorText);
            
            // Hint panel with escape text
            var hintPanel = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 0, 0, 15)
            };
            
            // Peek button - hold to see through dialog
            _peekButton = new Border
            {
                Width = 22,
                Height = 18,
                CornerRadius = new CornerRadius(3),
                Background = new SolidColorBrush(Color.FromArgb(0, 128, 128, 128)),
                Margin = new Thickness(0, 0, 8, 0),
                Cursor = System.Windows.Input.Cursors.Hand,
                ToolTip = "Hold to peek behind"
            };
            var peekIcon = new TextBlock
            {
                Text = "\uE7B3",  // Eye icon
                FontFamily = new FontFamily("Segoe MDL2 Assets"),
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromRgb(128, 128, 128)),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
            _peekButton.Child = peekIcon;
            
            // Hover effect
            _peekButton.MouseEnter += delegate { _peekButton.Background = new SolidColorBrush(Color.FromArgb(40, 128, 128, 128)); };
            _peekButton.MouseLeave += delegate { 
                _peekButton.Background = new SolidColorBrush(Color.FromArgb(0, 128, 128, 128));
                Opacity = NormalOpacity;  // Ensure we restore on leave
            };
            
            // Hold to peek
            _peekButton.MouseLeftButtonDown += delegate { Opacity = PeekOpacity; };
            _peekButton.MouseLeftButtonUp += delegate { Opacity = NormalOpacity; };
            
            hintPanel.Children.Add(_peekButton);
            
            // Hint text
            _hintText = new TextBlock
            {
                Text = "Press any key",
                FontSize = HintFontSize,
                Foreground = new SolidColorBrush(Color.FromRgb(128, 128, 128)),
            };
            hintPanel.Children.Add(_hintText);
            
            // Separator dot
            var separatorDot = new TextBlock
            {
                Text = "  \u00b7  ",
                FontSize = HintFontSize,
                Foreground = new SolidColorBrush(Color.FromRgb(90, 90, 90)),
            };
            hintPanel.Children.Add(separatorDot);
            
            // Escape hint
            var escapeHint = new TextBlock
            {
                Text = "Esc to cancel",
                FontSize = HintFontSize,
                Foreground = new SolidColorBrush(Color.FromRgb(160, 160, 160)),
            };
            hintPanel.Children.Add(escapeHint);
            
            Grid.SetRow(hintPanel, 2);
            contentGrid.Children.Add(hintPanel);
            
            outerGrid.Children.Add(contentGrid);
            _mainBorder.Child = outerGrid;
            Content = _mainBorder;
            
            // Setup blinking cursor timer
            CreateCursorBlink();
            
            // Handle key events - use both PreviewKeyDown and PreviewKeyUp for modifier keys
            PreviewKeyDown += OnPreviewKeyDown;
            PreviewKeyUp += OnPreviewKeyUp;
            
            // Subscribe to theme changes for runtime updates
            ThemeEngine.ThemeChanged += OnThemeChanged;
            
            // Mark disposed and unsubscribe when dialog closes
            Closed += delegate 
            { 
                _disposed = true;
                ThemeEngine.ThemeChanged -= OnThemeChanged;
                StopCursorBlink();
                StopParentTracking();
                
                // Remember position if user dragged the dialog (standalone mode only)
                if (_positionWasSet && _parentHwnd == IntPtr.Zero)
                {
                    _rememberedLeft = Left;
                    _rememberedTop = Top;
                }
            };
            
            // Track when user moves the dialog
            LocationChanged += delegate { _positionWasSet = true; };
            
            // Set owner via Win32 before window renders (SourceInitialized = HWND exists, not yet visible)
            // Must happen here, not in Loaded - by then Windows has already assigned focus
            SourceInitialized += delegate
            {
                if (_parentHwnd != IntPtr.Zero)
                {
                    var myHwnd = new System.Windows.Interop.WindowInteropHelper(this).Handle;
                    WindowManager.SetOwnerWindow(myHwnd, _parentHwnd);
                    
                    // Owner relationship handles Z-order, so drop Topmost
                    Topmost = false;
                }
            };
            
            // Initial focus on load, and set taskbar icon properly
            Loaded += delegate 
            { 
                // Set unique AppUserModelID to separate from PowerShell in taskbar
                if (ShowInTaskbar)
                {
                    var appId = "PsUi.KeyCapture." + Guid.NewGuid().ToString("N").Substring(0, 8);
                    WindowManager.SetWindowAppId(this, appId);
                    
                    // Force taskbar to use our icon via WM_SETICON
                    if (_windowIcon != null)
                    {
                        WindowManager.SetTaskbarIcon(this, _windowIcon);
                    }
                    
                    // Add keyboard overlay icon to indicate this is a key capture dialog
                    try
                    {
                        var overlayIcon = CreateOverlayIcon('\uE765', _accentColor);
                        if (overlayIcon != null)
                        {
                            WindowManager.SetTaskbarOverlay(this, overlayIcon, "Waiting for keypress");
                        }
                    }
                    catch { /* overlay is optional */ }
                }
                
                // Start parent tracking if we're attached (owner was already set in SourceInitialized)
                if (_parentHwnd != IntPtr.Zero)
                {
                    StartParentTracking();
                    PlaySlideInAnimation();
                }
                
                // Start cursor blinking
                StartCursorBlink();
                
                Activate();
                Focus();
            };
            
            // Visual feedback when dialog loses focus
            Deactivated += delegate
            {
                // Show hint that dialog needs focus
                _hintText.Text = "Click here to capture keypress";
                _hintText.Foreground = new SolidColorBrush(_accentColor);
                
                // Start slow pulse on hint text
                StartHintPulse();
                
                // Pause cursor
                StopCursorBlink();
                if (_cursorText != null) _cursorText.Opacity = 0.3;
                
                // Flash taskbar to get attention
                WindowManager.FlashTaskbar(this);
            };
            
            Activated += delegate
            {
                // Stop pulse and reset hint
                StopHintPulse();
                _hintText.Text = "Press any key";
                _hintText.Foreground = new SolidColorBrush(Color.FromRgb(128, 128, 128));
                _hintText.Opacity = 1.0;
                
                // Resume cursor
                if (_cursorText != null) _cursorText.Opacity = 1.0;
                StartCursorBlink();
                
                // Stop flashing
                WindowManager.StopFlashTaskbar(this);
            };
        }
        
        // Custom title bar with icon, drag support, and close button
        private Border CreateTitleBar(string prompt)
        {
            var titleBar = new Border
            {
                Background = new SolidColorBrush(_titleBarColor),
                CornerRadius = new CornerRadius(0, 0, 0, 0)
            };
            
            var titleGrid = new Grid();
            titleGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            titleGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            titleGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            
            // Icon (keyboard glyph)
            _iconText = new TextBlock
            {
                Text = "\uE765",  // Keyboard icon
                FontFamily = new FontFamily("Segoe MDL2 Assets"),
                FontSize = IconFontSize,
                Foreground = new SolidColorBrush(_accentColor),
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(12, 0, 8, 0)
            };
            Grid.SetColumn(_iconText, 0);
            titleGrid.Children.Add(_iconText);
            
            // Title text
            _titleText = new TextBlock
            {
                Text = "Waiting for Input",
                FontSize = TitleFontSize,
                Foreground = new SolidColorBrush(_foregroundColor),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(_titleText, 1);
            titleGrid.Children.Add(_titleText);
            
            // Close button
            var closeButton = new Button
            {
                Content = "\uE8BB",
                FontFamily = new FontFamily("Segoe MDL2 Assets"),
                FontSize = 10,
                Width = CloseButtonSize,
                Height = CloseButtonSize,
                Background = Brushes.Transparent,
                Foreground = new SolidColorBrush(Color.FromRgb(160, 160, 160)),
                BorderThickness = new Thickness(0),
                Cursor = Cursors.Hand
            };
            closeButton.Click += delegate 
            { 
                // Return Escape key when dialog is closed via X button
                // This signals cancellation to menu scripts
                _capturedKey = new KeyInfo(27, (char)27, ControlKeyStates.NumLockOn, true);
                _keyWasCaptured = true;
                Close(); 
            };
            Grid.SetColumn(closeButton, 2);
            titleGrid.Children.Add(closeButton);
            
            // Enable window dragging from title bar
            titleBar.MouseLeftButtonDown += delegate(object sender, MouseButtonEventArgs e)
            {
                if (e.ClickCount == 1) DragMove();
            };
            
            titleBar.Child = titleGrid;
            return titleBar;
        }
        
        // Runtime theme switch handler - uses async pattern to avoid deadlock
        private void OnThemeChanged(string themeName)
        {
            // Early exit if already disposed
            if (_disposed) return;
            
            // Capture colors on main UI thread first, then post update to dialog thread
            // This avoids deadlock from nested Invoke calls between threads
            try
            {
                if (Application.Current == null || Application.Current.Dispatcher == null) return;
                
                Application.Current.Dispatcher.BeginInvoke(new Action(() =>
                {
                    if (_disposed) return;
                    
                    ThemeColors newColors = null;
                    try
                    {
                        newColors = CaptureCurrentTheme();
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine("KeyCaptureDialog: Failed to capture theme: " + ex.Message);
                        return;
                    }
                    
                    // Now post the UI update to the dialog's thread
                    Dispatcher.BeginInvoke(new Action(() => ApplyThemeColors(newColors)));
                }));
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("KeyCaptureDialog: OnThemeChanged failed: " + ex.Message);
            }
        }
        
        // Update UI elements with new theme colors (must be on dialog thread)
        private void ApplyThemeColors(ThemeColors newColors)
        {
            if (_disposed || newColors == null) return;
            
            // Update stored colors
            _backgroundColor = newColors.Background;
            _titleBarColor = newColors.TitleBar;
            _borderColor = newColors.Border;
            _accentColor = newColors.Accent;
            _foregroundColor = newColors.Foreground;
            
            // Update UI elements with frozen brushes
            if (_mainBorder != null)
            {
                var bgBrush = new SolidColorBrush(_backgroundColor);
                var borderBrush = new SolidColorBrush(_borderColor);
                bgBrush.Freeze();
                borderBrush.Freeze();
                _mainBorder.Background = bgBrush;
                _mainBorder.BorderBrush = borderBrush;
            }
            if (_titleBarBorder != null)
            {
                var titleBrush = new SolidColorBrush(_titleBarColor);
                titleBrush.Freeze();
                _titleBarBorder.Background = titleBrush;
            }
            if (_iconText != null)
            {
                var accentBrush = new SolidColorBrush(_accentColor);
                accentBrush.Freeze();
                _iconText.Foreground = accentBrush;
            }
            if (_titleText != null)
            {
                var fgBrush = new SolidColorBrush(_foregroundColor);
                fgBrush.Freeze();
                _titleText.Foreground = fgBrush;
            }
            if (_promptText != null)
            {
                var promptBrush = new SolidColorBrush(_foregroundColor);
                promptBrush.Freeze();
                _promptText.Foreground = promptBrush;
            }
            
            // Update cursor accent color
            if (_cursorText != null)
            {
                var cursorBrush = new SolidColorBrush(_accentColor);
                cursorBrush.Freeze();
                _cursorText.Foreground = cursorBrush;
            }
        }
        
        private void OnPreviewKeyDown(object sender, KeyEventArgs e)
        {
            // Resolve system key (Alt combinations report as Key.System)
            Key actualKey = e.Key == Key.System ? e.SystemKey : e.Key;
            
            // Escape = instant close without flash
            if (actualKey == Key.Escape)
            {
                _capturedKey = new KeyInfo(27, (char)27, ControlKeyStates.NumLockOn, true);
                _keyWasCaptured = true;
                e.Handled = true;
                Close();
                return;
            }
            
            // Convert WPF Key to virtual key code
            int virtualKeyCode = KeyInterop.VirtualKeyFromKey(actualKey);
            
            // Get the character (if printable)
            char keyChar = GetCharFromKey(actualKey);
            
            // Build control key states - check both current modifiers and the key itself
            ControlKeyStates controlKeys = ControlKeyStates.NumLockOn;
            
            // Set modifier flags based on current state OR if the key is a modifier
            if ((Keyboard.Modifiers & ModifierKeys.Shift) != 0 || actualKey == Key.LeftShift || actualKey == Key.RightShift)
                controlKeys |= ControlKeyStates.ShiftPressed;
            if ((Keyboard.Modifiers & ModifierKeys.Control) != 0 || actualKey == Key.LeftCtrl || actualKey == Key.RightCtrl)
                controlKeys |= ControlKeyStates.LeftCtrlPressed;
            if ((Keyboard.Modifiers & ModifierKeys.Alt) != 0 || actualKey == Key.LeftAlt || actualKey == Key.RightAlt)
                controlKeys |= ControlKeyStates.LeftAltPressed;
            
            // Create KeyInfo
            _capturedKey = new KeyInfo(virtualKeyCode, keyChar, controlKeys, true);
            _keyWasCaptured = true;
            
            // Show flash feedback with the captured key
            ShowKeyFlash(actualKey);
            
            // Mark as handled - dialog will close after flash completes
            e.Handled = true;
        }
        
        // Capture modifier keys on KeyUp since PreviewKeyDown isnt reliable for them
        private void OnPreviewKeyUp(object sender, KeyEventArgs e)
        {
            // Only handle if we haven't captured a key yet and this is a modifier key
            if (_keyWasCaptured) return;
            
            Key actualKey = e.Key == Key.System ? e.SystemKey : e.Key;
            
            // Only handle modifier keys on KeyUp - regular keys are handled on KeyDown
            if (!IsModifierKey(actualKey)) return;
            
            int virtualKeyCode = KeyInterop.VirtualKeyFromKey(actualKey);
            
            // Build control key states for the modifier that was released
            ControlKeyStates controlKeys = ControlKeyStates.NumLockOn;
            if (actualKey == Key.LeftShift || actualKey == Key.RightShift)
                controlKeys |= ControlKeyStates.ShiftPressed;
            if (actualKey == Key.LeftCtrl || actualKey == Key.RightCtrl)
                controlKeys |= ControlKeyStates.LeftCtrlPressed;
            if (actualKey == Key.LeftAlt || actualKey == Key.RightAlt)
                controlKeys |= ControlKeyStates.LeftAltPressed;
            
            _capturedKey = new KeyInfo(virtualKeyCode, '\0', controlKeys, true);
            _keyWasCaptured = true;
            
            // Show flash feedback with the captured key
            ShowKeyFlash(actualKey);
            
            e.Handled = true;
        }
        
        private static bool IsModifierKey(Key key)
        {
            return key == Key.LeftCtrl || key == Key.RightCtrl ||
                   key == Key.LeftShift || key == Key.RightShift ||
                   key == Key.LeftAlt || key == Key.RightAlt;
        }
        
        // Convert WPF Key to printable char (returns null char for non-printables)
        private static char GetCharFromKey(Key key)
        {
            // Special keys
            switch (key)
            {
                case Key.Enter: return '\r';
                case Key.Tab: return '\t';
                case Key.Space: return ' ';
                case Key.Back: return '\b';
                case Key.Escape: return (char)27;
            }
            
            // Letter keys
            if (key >= Key.A && key <= Key.Z)
            {
                bool shift = (Keyboard.Modifiers & ModifierKeys.Shift) != 0;
                bool caps = Keyboard.IsKeyToggled(Key.CapsLock);
                char c = (char)('a' + (key - Key.A));
                if (shift ^ caps) c = char.ToUpper(c);
                return c;
            }
            
            // Number keys
            if (key >= Key.D0 && key <= Key.D9)
            {
                return (char)('0' + (key - Key.D0));
            }
            
            // Numpad
            if (key >= Key.NumPad0 && key <= Key.NumPad9)
            {
                return (char)('0' + (key - Key.NumPad0));
            }
            
            // Return null char for non-printable keys (arrows, function keys, etc.)
            return '\0';
        }
        
        // Validates dialog position is within visible screen area
        // Handles cases where monitors change between sessions
        private void EnsureOnScreen()
        {
            var virtualLeft   = SystemParameters.VirtualScreenLeft;
            var virtualTop    = SystemParameters.VirtualScreenTop;
            var virtualRight  = virtualLeft + SystemParameters.VirtualScreenWidth;
            var virtualBottom = virtualTop + SystemParameters.VirtualScreenHeight;
            
            // Clamp to visible area with padding
            if (Left < virtualLeft) Left = virtualLeft + ScreenEdgePadding;
            if (Top < virtualTop) Top = virtualTop + ScreenEdgePadding;
            if (Left + Width > virtualRight) Left = virtualRight - Width - ScreenEdgePadding;
            if (Top + Height > virtualBottom) Top = virtualBottom - Height - ScreenEdgePadding;
        }
        
        // Creates a blinking cursor timer
        private void CreateCursorBlink()
        {
            _cursorTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(CursorBlinkIntervalMs)
            };
            _cursorTimer.Tick += delegate
            {
                if (_cursorText != null)
                {
                    _cursorText.Opacity = _cursorText.Opacity > 0.5 ? 0.0 : 1.0;
                }
            };
        }
        
        private void StartCursorBlink()
        {
            if (_cursorTimer == null || _cursorText == null) return;
            _cursorText.Opacity = 1.0;
            try { _cursorTimer.Start(); }
            catch { /* timer may be disposed */ }
        }
        
        private void StopCursorBlink()
        {
            if (_cursorTimer == null) return;
            try { _cursorTimer.Stop(); }
            catch { /* timer may be disposed */ }
        }
        
        // Slow opacity pulse on hint text when dialog is unfocused
        private void StartHintPulse()
        {
            if (_hintText == null) return;
            
            StopHintPulse();
            
            var fadeOut = new System.Windows.Media.Animation.DoubleAnimation
            {
                From = 1.0,
                To = 0.4,
                Duration = TimeSpan.FromMilliseconds(1200),
                AutoReverse = true,
                RepeatBehavior = System.Windows.Media.Animation.RepeatBehavior.Forever,
                EasingFunction = new System.Windows.Media.Animation.SineEase()
            };
            
            _hintPulse = new System.Windows.Media.Animation.Storyboard();
            _hintPulse.Children.Add(fadeOut);
            System.Windows.Media.Animation.Storyboard.SetTarget(fadeOut, _hintText);
            System.Windows.Media.Animation.Storyboard.SetTargetProperty(fadeOut, 
                new PropertyPath(TextBlock.OpacityProperty));
            
            _hintPulse.Begin();
        }
        
        private void StopHintPulse()
        {
            if (_hintPulse == null) return;
            try 
            { 
                _hintPulse.Stop();
                _hintPulse = null;
            }
            catch { /* storyboard may be gone */ }
        }
        
        // Starts a timer that tracks parent window position/state
        private void StartParentTracking()
        {
            if (_parentHwnd == IntPtr.Zero) return;
            
            _parentTrackTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(50)
            };
            
            _parentTrackTimer.Tick += delegate
            {
                if (_disposed || _parentHwnd == IntPtr.Zero) return;
                
                // Check if session was cancelled (e.g., user pressed Escape in parent window)
                if (IsSessionCancelled())
                {
                    Close();
                    return;
                }
                
                // Get parent's current position and state via dispatcher
                Rect? parentBounds = null;
                bool parentMinimized = false;
                bool parentFound = true;  // Assume found unless we confirm otherwise
                
                try
                {
                    if (_parentDispatcher != null && !_parentDispatcher.HasShutdownStarted)
                    {
                        _parentDispatcher.Invoke(new Action(() =>
                        {
                            if (Application.Current == null)
                            {
                                parentFound = false;
                                return;
                            }
                            
                            // Find the Window object by HWND in the main app's windows
                            bool foundInLoop = false;
                            foreach (Window w in Application.Current.Windows)
                            {
                                var hwnd = new System.Windows.Interop.WindowInteropHelper(w).Handle;
                                if (hwnd == _parentHwnd)
                                {
                                    foundInLoop = true;
                                    parentMinimized = (w.WindowState == WindowState.Minimized);
                                    bool isMaximized = (w.WindowState == WindowState.Maximized);
                                    
                                    if (!parentMinimized && w.IsVisible)
                                    {
                                        if (isMaximized)
                                        {
                                            // Use work area of parent's monitor for maximized
                                            var workArea = WindowManager.GetWorkAreaForWindow(_parentHwnd);
                                            parentBounds = workArea;
                                        }
                                        else
                                        {
                                            parentBounds = new Rect(w.Left, w.Top, w.ActualWidth, w.ActualHeight);
                                        }
                                    }
                                    break;
                                }
                            }
                            parentFound = foundInLoop;
                        }));
                    }
                }
                catch
                {
                    // Cross-thread call failed - don't close, just skip this tick
                    return;
                }
                
                // Only close if we confirmed the parent window is gone
                if (!parentFound)
                {
                    Close();
                    return;
                }
                
                // Mirror minimize state - hide when parent minimizes
                if (parentMinimized && !_parentMinimized)
                {
                    _parentMinimized = true;
                    Visibility = Visibility.Collapsed;
                }
                else if (!parentMinimized && _parentMinimized)
                {
                    _parentMinimized = false;
                    Visibility = Visibility.Visible;
                    Topmost = true;  // Force to front
                    Activate();
                    Topmost = false;
                }
                
                // Update position to stay centered in parent
                if (parentBounds.HasValue && !_parentMinimized)
                {
                    var pb = parentBounds.Value;
                    var newLeft = pb.Left + (pb.Width - Width) / 2;
                    var newTop = pb.Top + pb.Height - Height - 60;
                    
                    // Only update if position actually changed (avoids jitter)
                    if (Math.Abs(Left - newLeft) > 1 || Math.Abs(Top - newTop) > 1)
                    {
                        Left = newLeft;
                        Top = newTop;
                    }
                }
            };
            
            _parentTrackTimer.Start();
        }
        
        // Stops tracking parent window
        private void StopParentTracking()
        {
            if (_parentTrackTimer == null) return;
            try { _parentTrackTimer.Stop(); }
            catch { /* timer may be disposed */ }
        }
        
        // Slide-in animation from below when attached to parent
        private void PlaySlideInAnimation()
        {
            if (_mainBorder == null) return;
            
            // Start with dialog translated down by its height (off-screen)
            var transform = new TranslateTransform(0, Height);
            _mainBorder.RenderTransform = transform;
            
            // Animate up to normal position
            var animation = new System.Windows.Media.Animation.DoubleAnimation
            {
                From = Height,
                To = 0,
                Duration = TimeSpan.FromMilliseconds(SlideAnimationMs),
                EasingFunction = new System.Windows.Media.Animation.QuadraticEase 
                { 
                    EasingMode = System.Windows.Media.Animation.EasingMode.EaseOut 
                }
            };
            
            transform.BeginAnimation(TranslateTransform.YProperty, animation);
        }
        
        // Shows a brief flash with the captured key name before closing
        private void ShowKeyFlash(Key key)
        {
            StopCursorBlink();
            
            // Hide cursor and show key name
            if (_cursorText != null) _cursorText.Visibility = Visibility.Collapsed;
            
            // Update prompt to show which key was pressed
            var keyName = GetKeyDisplayName(key);
            _promptText.Text = keyName;
            _promptText.FontSize = PromptFontSize + 4;
            _promptText.FontWeight = FontWeights.SemiBold;
            _promptText.VerticalAlignment = VerticalAlignment.Center;
            
            // Delay then close
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(KeyFlashDurationMs) };
            timer.Tick += delegate
            {
                timer.Stop();
                Close();
            };
            timer.Start();
        }
        
        // Human-friendly key names for flash display
        private static string GetKeyDisplayName(Key key)
        {
            switch (key)
            {
                case Key.Enter:  return "Enter";
                case Key.Escape: return "Esc";
                case Key.Space:  return "Space";
                case Key.Back:   return "Backspace";
                case Key.Tab:    return "Tab";
                case Key.Delete: return "Delete";
                case Key.Insert: return "Insert";
                case Key.Home:   return "Home";
                case Key.End:    return "End";
                case Key.PageUp:   return "Page Up";
                case Key.PageDown: return "Page Down";
                case Key.Left:   return "\u2190";  // Left arrow
                case Key.Right:  return "\u2192";  // Right arrow
                case Key.Up:     return "\u2191";  // Up arrow
                case Key.Down:   return "\u2193";  // Down arrow
                case Key.LeftCtrl:  return "Ctrl";
                case Key.RightCtrl: return "Ctrl";
                case Key.LeftAlt:   return "Alt";
                case Key.RightAlt:  return "Alt";
                case Key.LeftShift:  return "Shift";
                case Key.RightShift: return "Shift";
                case Key.F1:  return "F1";
                case Key.F2:  return "F2";
                case Key.F3:  return "F3";
                case Key.F4:  return "F4";
                case Key.F5:  return "F5";
                case Key.F6:  return "F6";
                case Key.F7:  return "F7";
                case Key.F8:  return "F8";
                case Key.F9:  return "F9";
                case Key.F10: return "F10";
                case Key.F11: return "F11";
                case Key.F12: return "F12";
            }
            
            // Letter keys
            if (key >= Key.A && key <= Key.Z)
            {
                return key.ToString();
            }
            
            // Number keys (strip the D prefix)
            if (key >= Key.D0 && key <= Key.D9)
            {
                return ((int)(key - Key.D0)).ToString();
            }
            
            // Numpad
            if (key >= Key.NumPad0 && key <= Key.NumPad9)
            {
                return ((int)(key - Key.NumPad0)).ToString();
            }
            
            // Fallback to the enum name
            return key.ToString();
        }
        
        // Shows dialog on separate STA thread so main UI stays responsive.
        // X button returns Escape to signal cancellation.
        public static KeyInfo ShowAndCapture(string prompt = null)
        {
            KeyInfo result = new KeyInfo(27, (char)27, ControlKeyStates.NumLockOn, true);
            
            // If session is already cancelled, throw to terminate the script
            // This prevents tight loops in scripts that keep calling ReadKey
            if (IsSessionCancelled())
            {
                throw new System.Management.Automation.PipelineStoppedException("Input session cancelled");
            }
            
            KeyCaptureDialog dialogRef = null;
            var completedEvent = new System.Threading.ManualResetEventSlim(false);
            var dialogReadyEvent = new System.Threading.ManualResetEventSlim(false);
            
            // Capture theme colors and icon from UI thread
            ThemeColors themeColors = null;
            BitmapSource windowIcon = null;
            Window[] currentWindows = null;
            Rect? parentBounds = null;
            IntPtr parentHwnd = IntPtr.Zero;
            Dispatcher parentDispatcher = null;
            bool parentMaximized = false;
            
            try
            {
                if (Application.Current != null && Application.Current.Dispatcher != null)
                {
                    Application.Current.Dispatcher.Invoke(new Action(() =>
                    {
                        themeColors = CaptureCurrentTheme();
                        
                        // Capture all current windows and grab the icon from the first one
                        var windowList = new System.Collections.Generic.List<Window>();
                        Window activeWindow = null;
                        
                        // Prefer ActiveDialogParent - it's set before the output window is shown,
                        // avoiding the race where IsActive is still false during Loaded
                        var session = SessionManager.Current;
                        if (session != null && session.ActiveDialogParent != null)
                        {
                            var dialogParent = session.ActiveDialogParent;
                            if (dialogParent.IsVisible && dialogParent.WindowState != WindowState.Minimized)
                            {
                                activeWindow = dialogParent;
                            }
                        }
                        
                        foreach (Window w in Application.Current.Windows)
                        {
                            windowList.Add(w);
                            
                            // Fallback to IsActive if no ActiveDialogParent
                            if (activeWindow == null && w.IsActive)
                            {
                                activeWindow = w;
                            }
                            
                            // Grab the icon from the first window that has one
                            if (windowIcon == null && w.Icon != null)
                            {
                                var icon = w.Icon as BitmapSource;
                                if (icon != null)
                                {
                                    try
                                    {
                                        // Clone to a format that can be frozen and used across threads
                                        // RenderTargetBitmap can't always be frozen directly
                                        if (icon.IsFrozen)
                                        {
                                            windowIcon = icon;
                                        }
                                        else if (icon.CanFreeze)
                                        {
                                            var clone = icon.Clone();
                                            clone.Freeze();
                                            windowIcon = clone;
                                        }
                                        else
                                        {
                                            // Convert to a freezable format via BitmapFrame
                                            var frame = BitmapFrame.Create(icon);
                                            frame.Freeze();
                                            windowIcon = frame;
                                        }
                                    }
                                    catch
                                    {
                                        // RenderTargetBitmap or BitmapFrame creation can fail on certain
                                        // graphics configurations - continue without icon rather than crash
                                        windowIcon = null;
                                    }
                                }
                            }
                        }
                        currentWindows = windowList.ToArray();
                        
                        // Capture active window info for attached positioning
                        if (activeWindow != null && activeWindow.WindowState != WindowState.Minimized)
                        {
                            parentBounds = new Rect(activeWindow.Left, activeWindow.Top, 
                                                    activeWindow.ActualWidth, activeWindow.ActualHeight);
                            parentHwnd = new System.Windows.Interop.WindowInteropHelper(activeWindow).Handle;
                            parentDispatcher = activeWindow.Dispatcher;
                            parentMaximized = (activeWindow.WindowState == WindowState.Maximized);
                        }
                    }));
                }
            }
            catch { /* Application may be shutting down or not yet started - use default theme */ }
            
            // Run dialog on its own STA thread to avoid blocking the main UI thread
            var dialogThread = new System.Threading.Thread(() =>
            {
                var dialog = new KeyCaptureDialog(prompt, themeColors, windowIcon, parentBounds, parentHwnd, parentDispatcher, parentMaximized);
                dialogRef = dialog;
                
                // Track this dialog as current for external close
                lock (_dialogLock)
                {
                    _currentDialog = dialog;
                }
                
                // Signal that dialog reference is ready
                dialogReadyEvent.Set();
                
                dialog.Closed += delegate
                {
                    // Clear the current dialog reference
                    lock (_dialogLock)
                    {
                        if (_currentDialog == dialog)
                            _currentDialog = null;
                    }
                    
                    if (dialog.KeyWasCaptured)
                    {
                        result = dialog.CapturedKey;
                    }
                    completedEvent.Set();
                    
                    // Shutdown this thread's dispatcher
                    Dispatcher.CurrentDispatcher.BeginInvokeShutdown(DispatcherPriority.Background);
                };
                dialog.Show();
                Dispatcher.Run();
            });
            
            dialogThread.SetApartmentState(System.Threading.ApartmentState.STA);
            dialogThread.IsBackground = true;
            dialogThread.Start();
            
            // Wait for dialogRef to be set using proper synchronization
            dialogReadyEvent.Wait(DialogReadyTimeoutMs);
            dialogReadyEvent.Dispose();
            
            // Subscribe to window Closed events on the UI thread (fire-and-forget)
            EventHandler closeHandler = null;
            Window[] windowsToCleanup = null;
            
            if (currentWindows != null && currentWindows.Length > 0 && dialogRef != null)
            {
                var dialogToClose = dialogRef;
                var eventToSignal = completedEvent;
                windowsToCleanup = currentWindows;
                closeHandler = delegate
                {
                    // Signal completion immediately so the waiting thread can proceed
                    // Close first or we hang
                    try { eventToSignal.Set(); } catch { /* already disposed */ }
                    
                    // Then try to close the dialog (fire-and-forget, ignore errors)
                    try
                    {
                        if (dialogToClose.Dispatcher != null && !dialogToClose.Dispatcher.HasShutdownStarted)
                        {
                            dialogToClose.Dispatcher.BeginInvoke(new Action(() =>
                            {
                                try { dialogToClose.Close(); }
                                catch { /* dialog already closed */ }
                            }));
                        }
                    }
                    catch { /* dispatcher gone, that's fine */ }
                };
                
                try
                {
                    // Use BeginInvoke so we don't block
                    Application.Current.Dispatcher.BeginInvoke(new Action(() =>
                    {
                        foreach (var w in currentWindows)
                        {
                            try { w.Closed += closeHandler; }
                            catch { /* window might be gone */ }
                        }
                    }));
                }
                catch { /* ignore */ }
            }
            
            // Wait for dialog completion OR external cancellation
            // Uses WaitAny to respond to either event immediately
            try
            {
                var waitHandles = new System.Threading.WaitHandle[] 
                { 
                    completedEvent.WaitHandle, 
                    _cancelEvent.WaitHandle 
                };
                System.Threading.WaitHandle.WaitAny(waitHandles);
                
                // Check if cancelled after waking up - throw to terminate the script
                if (IsSessionCancelled())
                {
                    throw new System.Management.Automation.PipelineStoppedException("Input session cancelled");
                }
            }
            catch (ObjectDisposedException) { /* event was disposed, that's OK */ }
            
            try { completedEvent.Dispose(); } catch { /* already disposed */ }
            
            // Unhook close handlers so we don't leak
            if (closeHandler != null && windowsToCleanup != null)
            {
                try
                {
                    if (Application.Current != null && Application.Current.Dispatcher != null 
                        && !Application.Current.Dispatcher.HasShutdownStarted)
                    {
                        Application.Current.Dispatcher.BeginInvoke(new Action(() =>
                        {
                            foreach (var w in windowsToCleanup)
                            {
                                try { w.Closed -= closeHandler; }
                                catch { /* window might be gone */ }
                            }
                        }));
                    }
                }
                catch { /* ignore */ }
            }
            
            return result;
        }
        
        // Circular overlay icon for taskbar badge
        private static BitmapSource CreateOverlayIcon(char glyphChar, Color foregroundColor)
        {
            const int size = 16;
            
            var visual = new DrawingVisual();
            using (var dc = visual.RenderOpen())
            {
                var center = new Point(size / 2.0, size / 2.0);
                var radius = (size / 2.0) - 0.5;
                
                // Draw shadow ring for contrast
                var shadowPen = new Pen(new SolidColorBrush(Color.FromArgb(100, 0, 0, 0)), 1.0);
                dc.DrawEllipse(null, shadowPen, center, radius, radius);
                
                // Draw white background circle
                var bgBrush = new SolidColorBrush(Colors.White);
                var innerRadius = radius - 0.5;
                dc.DrawEllipse(bgBrush, null, center, innerRadius, innerRadius);
                
                // Create typeface for glyph
                var typeface = new Typeface(
                    new FontFamily("Segoe MDL2 Assets"),
                    FontStyles.Normal,
                    FontWeights.Normal,
                    FontStretches.Normal
                );
                
                // Create formatted text
                var fontSize = size * 0.60;
                var fgBrush = new SolidColorBrush(foregroundColor);
                var formattedText = new FormattedText(
                    glyphChar.ToString(),
                    System.Globalization.CultureInfo.CurrentCulture,
                    FlowDirection.LeftToRight,
                    typeface,
                    fontSize,
                    fgBrush,
                    96
                );
                
                // Center the glyph
                var x = (size - formattedText.Width) / 2;
                var y = (size - formattedText.Height) / 2;
                dc.DrawText(formattedText, new Point(x, y));
            }
            
            // Render to bitmap
            var renderTarget = new System.Windows.Media.Imaging.RenderTargetBitmap(
                size, size, 96, 96, PixelFormats.Pbgra32
            );
            renderTarget.Render(visual);
            renderTarget.Freeze();
            
            return renderTarget;
        }
        
        // Grab colors from app resources (must be on UI thread)
        private static ThemeColors CaptureCurrentTheme()
        {
            var colors = new ThemeColors();
            
            try
            {
                if (Application.Current == null || Application.Current.Resources == null)
                    return colors;
                
                var resources = Application.Current.Resources;
                
                // Background - use WindowBackgroundBrush as primary, ControlBackgroundBrush as fallback
                var bgBrush = resources["WindowBackgroundBrush"] as SolidColorBrush;
                if (bgBrush == null) bgBrush = resources["ControlBackgroundBrush"] as SolidColorBrush;
                if (bgBrush != null) colors.Background = bgBrush.Color;
                
                // Title bar
                var headerBgBrush = resources["HeaderBackgroundBrush"] as SolidColorBrush;
                if (headerBgBrush != null) colors.TitleBar = headerBgBrush.Color;
                
                // Border
                var borderBrush = resources["BorderBrush"] as SolidColorBrush;
                if (borderBrush != null) colors.Border = borderBrush.Color;
                
                // Accent
                var accentBrush = resources["AccentBrush"] as SolidColorBrush;
                if (accentBrush != null) colors.Accent = accentBrush.Color;
                
                // Foreground
                var fgBrush = resources["WindowForegroundBrush"] as SolidColorBrush;
                if (fgBrush == null) fgBrush = resources["ControlForegroundBrush"] as SolidColorBrush;
                if (fgBrush != null) colors.Foreground = fgBrush.Color;
            }
            catch { /* ignore - use defaults */ }
            
            return colors;
        }
        
        public class ThemeColors
        {
            public Color Background = DefaultBackgroundColor;
            public Color TitleBar = DefaultTitleBarColor;
            public Color Border = DefaultBorderColor;
            public Color Accent = DefaultAccentColor;
            public Color Foreground = DefaultForegroundColor;
        }
    }
}
