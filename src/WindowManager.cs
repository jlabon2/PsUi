using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Interop;

namespace PsUi
{
    // Win32 calls for the polish layer that WPF doesn't expose. This is kinda ugly.
    // Without these tho, the console window visible behind UI, white titlebar in dark mode,
    // window grouped with powershell.exe in taskbar. 
    public static class WindowManager
    {
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] private static extern int SetForegroundWindow(IntPtr hWnd);
        [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
        
        // Icon-related Win32 APIs
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
        
        [DllImport("user32.dll")]
        private static extern bool DestroyIcon(IntPtr hIcon);
        
        // AppUserModelID - allows window to have its own taskbar identity separate from PowerShell
        [DllImport("shell32.dll", SetLastError = true)]
        private static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object propertyStore);
        
        private const int WM_SETICON = 0x0080;
        private const int ICON_SMALL = 0;
        private const int ICON_BIG = 1;
        private const int ICON_SMALL2 = 2;  // Used by Windows 10/11 for titlebar icon
        
        private static readonly Guid PKEY_AppUserModel_ID = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
        private const int VT_LPWSTR = 31;

        private const int SW_HIDE = 0;
        private const int SW_SHOW = 5;
        
        // FlashWindowEx for taskbar attention flash
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FlashWindowEx(ref FLASHWINFO pwfi);
        
        // SetWindowLongPtr for setting owner window (keeps dialog above parent)
        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
        
        [DllImport("user32.dll", SetLastError = true, EntryPoint = "SetWindowLong")]
        private static extern IntPtr SetWindowLong32(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
        
        private const int GWL_HWNDPARENT = -8;
        
        [StructLayout(LayoutKind.Sequential)]
        private struct FLASHWINFO
        {
            public uint cbSize;
            public IntPtr hwnd;
            public uint dwFlags;
            public uint uCount;
            public uint dwTimeout;
        }
        
        private const uint FLASHW_STOP = 0;
        private const uint FLASHW_CAPTION = 1;
        private const uint FLASHW_TRAY = 2;
        private const uint FLASHW_ALL = 3;
        private const uint FLASHW_TIMER = 4;
        private const uint FLASHW_TIMERNOFG = 12;
        
        // DWM Attributes
        private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
        private const int DWMWA_CAPTION_COLOR = 35;
        private const int DWMWA_TEXT_COLOR = 36;
        
        // WM_GETMINMAXINFO for borderless maximize - used in ShowUI-Output (respects taskbar)
        private const int WM_GETMINMAXINFO = 0x0024;
        
        // Track minimum sizes for borderless windows (hwnd -> minWidth, minHeight)
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<IntPtr, POINT> _windowMinSizes = 
            new System.Collections.Concurrent.ConcurrentDictionary<IntPtr, POINT>();
        
        // Track icon handles per window to clean up on repeated SetTaskbarIcon calls
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<IntPtr, IntPtr[]> _windowIconHandles =
            new System.Collections.Concurrent.ConcurrentDictionary<IntPtr, IntPtr[]>();
        
        [DllImport("user32.dll")]
        private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);
        
        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);
        
        private const uint MONITOR_DEFAULTTONEAREST = 2;
        
        [StructLayout(LayoutKind.Sequential)]
        private struct POINT
        {
            public int x;
            public int y;
        }
        
        [StructLayout(LayoutKind.Sequential)]
        private struct MINMAXINFO
        {
            public POINT ptReserved;
            public POINT ptMaxSize;
            public POINT ptMaxPosition;
            public POINT ptMinTrackSize;
            public POINT ptMaxTrackSize;
        }
        
        [StructLayout(LayoutKind.Sequential)]
        private struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }
        
        [StructLayout(LayoutKind.Sequential)]
        private struct MONITORINFO
        {
            public int cbSize;
            public RECT rcMonitor;
            public RECT rcWork;
            public uint dwFlags;
        }

        public static void HideConsole() { ShowWindow(GetConsoleWindow(), SW_HIDE); }
        public static void ShowConsole() { ShowWindow(GetConsoleWindow(), SW_SHOW); SetForegroundWindow(GetConsoleWindow()); }
        
        // Get the work area (excludes taskbar) for the monitor containing a specific window
        public static Rect GetWorkAreaForWindow(IntPtr hwnd)
        {
            try
            {
                if (hwnd == IntPtr.Zero) return SystemParameters.WorkArea;
                
                var monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
                if (monitor == IntPtr.Zero) return SystemParameters.WorkArea;
                
                var info = new MONITORINFO();
                info.cbSize = Marshal.SizeOf(info);
                
                if (GetMonitorInfo(monitor, ref info))
                {
                    var work = info.rcWork;
                    return new Rect(work.Left, work.Top, work.Right - work.Left, work.Bottom - work.Top);
                }
            }
            catch { /* fall through to default */ }
            
            return SystemParameters.WorkArea;
        }

        // Own taskbar icon - without this, Windows groups us with pwsh.exe
        // Call before Show() or the HWND won't exist yet
        public static void SetWindowAppId(Window window, string appId)
        {
            try
            {
                var helper = new WindowInteropHelper(window);
                IntPtr hWnd = helper.EnsureHandle();
                
                // Set AppUserModelID via IPropertyStore
                Guid IID_IPropertyStore = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
                object propStoreObj;
                int hr = SHGetPropertyStoreForWindow(hWnd, ref IID_IPropertyStore, out propStoreObj);
                
                if (hr == 0 && propStoreObj != null)
                {
                    // Reflection avoids defining the full COM interface
                    var propStore = propStoreObj as IPropertyStore;
                    if (propStore != null)
                    {
                        var key = new PROPERTYKEY { fmtid = PKEY_AppUserModel_ID, pid = 5 };
                        var value = new PROPVARIANT { vt = VT_LPWSTR, pwszVal = Marshal.StringToCoTaskMemUni(appId) };
                        propStore.SetValue(ref key, ref value);
                        propStore.Commit();
                        Marshal.FreeCoTaskMem(value.pwszVal);
                    }
                    Marshal.ReleaseComObject(propStoreObj);
                }
                
                System.Diagnostics.Debug.WriteLine("SetWindowAppId: " + appId + " hr=" + hr);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("SetWindowAppId failed: " + ex.Message);
            }
        }
        
        [ComImport]
        [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IPropertyStore
        {
            int GetCount(out uint cProps);
            int GetAt(uint iProp, out PROPERTYKEY pkey);
            int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
            int SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
            int Commit();
        }
        
        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        private struct PROPERTYKEY
        {
            public Guid fmtid;
            public uint pid;
        }
        
        [StructLayout(LayoutKind.Sequential)]
        private struct PROPVARIANT
        {
            public ushort vt;
            public ushort wReserved1;
            public ushort wReserved2;
            public ushort wReserved3;
            public IntPtr pwszVal;
        }

        // Sets OS-level title bar color (Win11+ full color, Win10 falls back to dark/light mode)
        public static void SetTitleBarColor(Window window, Color backgroundColor, Color foregroundColor)
        {
            var helper = new WindowInteropHelper(window);
            // Force HWND creation if called before Show()
            IntPtr hWnd = helper.EnsureHandle();

            // Dark mode affects the system min/max/close button icons
            bool isDark = IsColorDark(backgroundColor);
            int useDarkMode = isDark ? 1 : 0;
            
            // Apply Immersive Dark Mode (Works on Win10 1809+ and Win11)
            DwmSetWindowAttribute(hWnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ref useDarkMode, sizeof(int));

            // Custom title bar colors (Win11 only)
            if (Environment.OSVersion.Version.Build >= 22000) 
            {
                // Convert Color to DWM COLORREF format (0x00BBGGRR)
                int bg = (backgroundColor.B << 16) | (backgroundColor.G << 8) | backgroundColor.R;
                int fg = (foregroundColor.B << 16) | (foregroundColor.G << 8) | foregroundColor.R;
                
                DwmSetWindowAttribute(hWnd, DWMWA_CAPTION_COLOR, ref bg, sizeof(int));
                DwmSetWindowAttribute(hWnd, DWMWA_TEXT_COLOR, ref fg, sizeof(int));
            }
        }
        
        private static bool IsColorDark(Color color)
        {
            // Standard luminance formula
            double luminance = (0.299 * color.R + 0.587 * color.G + 0.114 * color.B) / 255;
            return luminance < 0.5;
        }

        // Force taskbar to use our icon instead of PowerShell default
        public static void SetTaskbarIcon(Window window, BitmapSource iconSource)
        {
            if (iconSource == null) return;
            
            try
            {
                var helper = new WindowInteropHelper(window);
                IntPtr hWnd = helper.EnsureHandle();
                if (hWnd == IntPtr.Zero) return;
                
                // Destroy previous icon handles if this is a repeated call (prevents handle leak)
                IntPtr[] previousHandles;
                if (_windowIconHandles.TryGetValue(hWnd, out previousHandles))
                {
                    foreach (var handle in previousHandles)
                    {
                        if (handle != IntPtr.Zero) DestroyIcon(handle);
                    }
                }
                
                // Create HICON from BitmapSource using GDI interop
                // Scale to standard icon sizes: small (16x16) and big (32x32)
                var smallIcon = CreateHIcon(iconSource, 16, 16);
                var bigIcon = CreateHIcon(iconSource, 32, 32);
                
                if (smallIcon != IntPtr.Zero)
                {
                    SendMessage(hWnd, WM_SETICON, (IntPtr)ICON_SMALL, smallIcon);
                    // ICON_SMALL2 is used by Windows 10/11 for the titlebar icon
                    SendMessage(hWnd, WM_SETICON, (IntPtr)ICON_SMALL2, smallIcon);
                }
                
                if (bigIcon != IntPtr.Zero)
                {
                    SendMessage(hWnd, WM_SETICON, (IntPtr)ICON_BIG, bigIcon);
                }
                
                // Track handles for cleanup on window close or repeated calls
                var iconHandles = new IntPtr[] { smallIcon, bigIcon };
                
                // Register cleanup handler once (only on first call for this window).
                // If the process crashes without firing Closed, we leak 2 icon handles. Big deal -
                // that's 64 bytes per window. A weak-ref + finalizer pattern isn't worth the hassle.
                bool isFirstCall = previousHandles == null;
                _windowIconHandles[hWnd] = iconHandles;
                
                if (isFirstCall)
                {
                    window.Closed += (sender, args) =>
                    {
                        var closedWindow = sender as Window;
                        if (closedWindow == null) return;
                        
                        var closedHelper = new WindowInteropHelper(closedWindow);
                        IntPtr closedHwnd = closedHelper.Handle;
                        
                        IntPtr[] handles;
                        if (_windowIconHandles.TryGetValue(closedHwnd, out handles))
                        {
                            foreach (var handle in handles)
                            {
                                if (handle != IntPtr.Zero) DestroyIcon(handle);
                            }
                            IntPtr[] removed;
                            _windowIconHandles.TryRemove(closedHwnd, out removed);
                        }
                    };
                }
                
                System.Diagnostics.Debug.WriteLine("SetTaskbarIcon: small=" + smallIcon + ", big=" + bigIcon);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("SetTaskbarIcon failed: " + ex.Message);
            }
        }

        // Small badge on taskbar icon (for status indication)
        public static void SetTaskbarOverlay(Window window, ImageSource overlayIcon, string description = null)
        {
            if (window == null) return;
            
            try
            {
                // Create TaskbarItemInfo on first use
                if (window.TaskbarItemInfo == null)
                {
                    window.TaskbarItemInfo = new System.Windows.Shell.TaskbarItemInfo();
                }
                
                window.TaskbarItemInfo.Overlay = overlayIcon;
                window.TaskbarItemInfo.Description = description ?? string.Empty;
                
                System.Diagnostics.Debug.WriteLine("SetTaskbarOverlay: " + (overlayIcon != null ? "set" : "cleared"));
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("SetTaskbarOverlay failed: " + ex.Message);
            }
        }

        public static void ClearTaskbarOverlay(Window window)
        {
            SetTaskbarOverlay(window, null, null);
        }
        
        private static IntPtr CreateHIcon(BitmapSource source, int width, int height)
        {
            if (source == null) return IntPtr.Zero;
            
            try
            {
                // Scale to target size
                var scaled = new TransformedBitmap(source, 
                    new ScaleTransform(
                        (double)width / source.PixelWidth, 
                        (double)height / source.PixelHeight));
                
                // Convert to Pbgra32 format for GDI compatibility
                var formatted = new FormatConvertedBitmap(scaled, PixelFormats.Pbgra32, null, 0);
                
                // Get pixels into a writable bitmap
                int stride = width * 4;
                byte[] pixels = new byte[height * stride];
                formatted.CopyPixels(pixels, stride, 0);
                
                // Create GDI bitmap from pixels
                var bmp = new System.Drawing.Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
                IntPtr hIcon;
                try
                {
                    var bmpData = bmp.LockBits(
                        new System.Drawing.Rectangle(0, 0, width, height),
                        System.Drawing.Imaging.ImageLockMode.WriteOnly,
                        System.Drawing.Imaging.PixelFormat.Format32bppArgb);
                    
                    Marshal.Copy(pixels, 0, bmpData.Scan0, pixels.Length);
                    bmp.UnlockBits(bmpData);
                    
                    // Get HICON from bitmap
                    hIcon = bmp.GetHicon();
                }
                finally
                {
                    bmp.Dispose();
                }
                return hIcon;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("CreateHIcon failed: " + ex.Message);
                return IntPtr.Zero;
            }
        }

        public static Window CreateWindow(WindowConfig config)
        {
            var window = new Window
            {
                Title = config.Title ?? "Script Menu",
                Width = config.Width > 0 ? config.Width : 400,
                Height = config.Height > 0 ? config.Height : 600,
                MinWidth = config.MinWidth > 0 ? config.MinWidth : config.Width,
                MinHeight = config.MinHeight > 0 ? config.MinHeight : config.Height,
                FontFamily = new FontFamily("Segoe UI"),
                WindowStartupLocation = WindowStartupLocation.CenterScreen,
                WindowState = WindowState.Minimized, 
            };

            if (config.NoResize) window.ResizeMode = ResizeMode.NoResize;
            else window.ResizeMode = ResizeMode.CanResizeWithGrip;

            if (config.SizeToContent) window.SizeToContent = SizeToContent.Height;

            // Apply the theme immediately (which should also handle title bar logic now)
            ApplyTheme(window, config.Theme ?? "Light");

            var mainGrid = new Grid { Background = Brushes.Transparent };
            window.Content = mainGrid;

            window.Opacity = 0;

            window.Loaded += (sender, e) =>
            {
                window.WindowState = WindowState.Normal;
                CenterWindowOnCurrentScreen(window);
                
                var fadeIn = new System.Windows.Media.Animation.DoubleAnimation
                {
                    From = 0,
                    To = 1,
                    Duration = TimeSpan.FromMilliseconds(250)
                };
                window.BeginAnimation(Window.OpacityProperty, fadeIn);
            };

            return window;
        }

        // Hook WM_GETMINMAXINFO so borderless windows respect taskbar when maximized
        public static void EnableBorderlessMaximize(Window window)
        {
            var helper = new WindowInteropHelper(window);
            helper.EnsureHandle();
            IntPtr hwnd = helper.Handle;
            
            // Store minimum size for this window handle
            var minSize = new POINT
            {
                x = (int)window.MinWidth,
                y = (int)window.MinHeight
            };
            _windowMinSizes[hwnd] = minSize;
            
            // Clean up when window closes
            window.Closed += (s, e) => { POINT unused; _windowMinSizes.TryRemove(hwnd, out unused); };
            
            HwndSource source = HwndSource.FromHwnd(hwnd);
            if (source != null)
            {
                source.AddHook(BorderlessMaximizeHook);
            }
        }
        
        private static IntPtr BorderlessMaximizeHook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_GETMINMAXINFO)
            {
                MINMAXINFO mmi = (MINMAXINFO)Marshal.PtrToStructure(lParam, typeof(MINMAXINFO));
                
                // Enforce minimum size if registered
                POINT minSize;
                if (_windowMinSizes.TryGetValue(hwnd, out minSize))
                {
                    mmi.ptMinTrackSize.x = minSize.x;
                    mmi.ptMinTrackSize.y = minSize.y;
                }
                
                // Get the monitor this window is on for maximize constraints
                IntPtr monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
                if (monitor != IntPtr.Zero)
                {
                    MONITORINFO monitorInfo = new MONITORINFO();
                    monitorInfo.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
                    
                    if (GetMonitorInfo(monitor, ref monitorInfo))
                    {
                        // Get the work area (excludes taskbar)
                        RECT work = monitorInfo.rcWork;
                        RECT full = monitorInfo.rcMonitor;
                        
                        mmi.ptMaxPosition.x = work.Left - full.Left;
                        mmi.ptMaxPosition.y = work.Top - full.Top;
                        mmi.ptMaxSize.x = work.Right - work.Left;
                        mmi.ptMaxSize.y = work.Bottom - work.Top;
                    }
                }
                
                Marshal.StructureToPtr(mmi, lParam, true);
                handled = true;
            }
            return IntPtr.Zero;
        }

        public static void CenterWindowOnCurrentScreen(Window window)
        {
            var workArea = GetMonitorWorkArea(window);
            window.Left = workArea.Left + (workArea.Width - window.Width) / 2;
            window.Top = workArea.Top + (workArea.Height - window.Height) / 2;
        }

        // Get the work area of the monitor containing the specified window
        private static Rect GetMonitorWorkArea(Window window)
        {
            if (window == null)
            {
                return SystemParameters.WorkArea;
            }

            try
            {
                var helper = new WindowInteropHelper(window);
                IntPtr hwnd = helper.Handle;

                // If window isn't shown yet, there's no HWND
                if (hwnd == IntPtr.Zero)
                {
                    return SystemParameters.WorkArea;
                }

                IntPtr monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
                if (monitor != IntPtr.Zero)
                {
                    MONITORINFO monitorInfo = new MONITORINFO();
                    monitorInfo.cbSize = Marshal.SizeOf(typeof(MONITORINFO));

                    if (GetMonitorInfo(monitor, ref monitorInfo))
                    {
                        RECT work = monitorInfo.rcWork;
                        return new Rect(work.Left, work.Top, work.Right - work.Left, work.Bottom - work.Top);
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("GetMonitorWorkArea failed: " + ex.Message);
            }

            return SystemParameters.WorkArea;
        }

        // Center dialog over parent window (handles cross-thread access)
        public static void CenterOnParent(Window dialog, Window parent)
        {
            if (dialog == null || parent == null) return;
            
            // Set to manual positioning
            dialog.WindowStartupLocation = WindowStartupLocation.Manual;
            
            // Get parent window bounds (may be on different thread)
            double parentLeft = 0, parentTop = 0, parentWidth = 0, parentHeight = 0;
            bool parentIsMaximized = false;
            bool gotBounds = false;
            
            try
            {
                if (parent.Dispatcher.CheckAccess())
                {
                    parentIsMaximized = parent.WindowState == WindowState.Maximized;
                    parentLeft = parent.Left;
                    parentTop = parent.Top;
                    parentWidth = parent.ActualWidth;
                    parentHeight = parent.ActualHeight;
                    gotBounds = true;
                }
                else
                {
                    parent.Dispatcher.Invoke(new Action(delegate
                    {
                        parentIsMaximized = parent.WindowState == WindowState.Maximized;
                        parentLeft = parent.Left;
                        parentTop = parent.Top;
                        parentWidth = parent.ActualWidth;
                        parentHeight = parent.ActualHeight;
                    }), TimeSpan.FromSeconds(2));
                    gotBounds = true;
                }
            }
            catch
            {
                // Parent dispatcher unavailable, fall back to screen center
                gotBounds = false;
            }
            
            if (gotBounds && parentWidth > 0 && parentHeight > 0)
            {
                // Calculate center position relative to parent
                double dialogWidth = dialog.Width;
                double dialogHeight = dialog.Height;
                
                // Handle NaN (auto-sized dialogs) - use reasonable defaults
                if (double.IsNaN(dialogWidth)) dialogWidth = 400;
                if (double.IsNaN(dialogHeight)) dialogHeight = 200;
                
                // When parent is maximized, its Left/Top are often negative due to window chrome
                // extending beyond the screen edge. Use the work area instead.
                if (parentIsMaximized)
                {
                    // Use the work area of the monitor containing the parent window
                    var workArea = GetMonitorWorkArea(parent);
                    parentLeft = workArea.Left;
                    parentTop = workArea.Top;
                    parentWidth = workArea.Width;
                    parentHeight = workArea.Height;
                    
                    // For maximized parent, there's no visible shadow margin, so center directly
                    // but the dialog still has its own shadow margin
                    const double dialogShadowMargin = 16.0;
                    double visibleDialogWidth = dialogWidth - (dialogShadowMargin * 2);
                    double visibleDialogHeight = dialogHeight - (dialogShadowMargin * 2);
                    
                    // Center the visible dialog content on the work area
                    double visibleDialogLeft = parentLeft + (parentWidth - visibleDialogWidth) / 2;
                    double visibleDialogTop = parentTop + (parentHeight - visibleDialogHeight) / 2;
                    
                    dialog.Left = visibleDialogLeft - dialogShadowMargin;
                    dialog.Top = visibleDialogTop - dialogShadowMargin;
                }
                else
                {
                    // Normal window: both parent and dialog have 16px shadow margins
                    // We need to center the visible content areas, not the outer window bounds.
                    const double shadowMargin = 16.0;
                    double visibleParentWidth = parentWidth - (shadowMargin * 2);
                    double visibleParentHeight = parentHeight - (shadowMargin * 2);
                    double visibleDialogWidth = dialogWidth - (shadowMargin * 2);
                    double visibleDialogHeight = dialogHeight - (shadowMargin * 2);
                    
                    double visibleParentLeft = parentLeft + shadowMargin;
                    double visibleParentTop = parentTop + shadowMargin;
                    
                    double visibleDialogLeft = visibleParentLeft + (visibleParentWidth - visibleDialogWidth) / 2;
                    double visibleDialogTop = visibleParentTop + (visibleParentHeight - visibleDialogHeight) / 2;
                    
                    dialog.Left = visibleDialogLeft - shadowMargin;
                    dialog.Top = visibleDialogTop - shadowMargin;
                }
                
                // Clamp to screen bounds
                double screenWidth = SystemParameters.VirtualScreenWidth;
                double screenHeight = SystemParameters.VirtualScreenHeight;
                double screenLeft = SystemParameters.VirtualScreenLeft;
                double screenTop = SystemParameters.VirtualScreenTop;
                
                if (dialog.Left < screenLeft) dialog.Left = screenLeft;
                if (dialog.Top < screenTop) dialog.Top = screenTop;
                if (dialog.Left + dialogWidth > screenLeft + screenWidth)
                    dialog.Left = screenLeft + screenWidth - dialogWidth;
                if (dialog.Top + dialogHeight > screenTop + screenHeight)
                    dialog.Top = screenTop + screenHeight - dialogHeight;
            }
            else
            {
                // Fallback to screen center
                dialog.WindowStartupLocation = WindowStartupLocation.CenterScreen;
            }
        }

        public static void ApplyTheme(Window window, string themeName)
        {
            // Register the window with ThemeEngine so it gets updated on theme switch
            ThemeEngine.RegisterElement(window);
            
            // Use SetResourceReference for dynamic theme binding
            window.SetResourceReference(Window.BackgroundProperty, "WindowBackgroundBrush");
            window.SetResourceReference(Window.ForegroundProperty, "WindowForegroundBrush");
            
            // For title bar colors, we need the actual color values
            var headerBgBrush = Application.Current.Resources["HeaderBackgroundBrush"] as SolidColorBrush;
            var headerFgBrush = Application.Current.Resources["HeaderForegroundBrush"] as SolidColorBrush;
            if (headerBgBrush != null && headerFgBrush != null)
            {
                SetTitleBarColor(window, headerBgBrush.Color, headerFgBrush.Color);
            }
        }

        public static bool? ShowDialogSafe(Window window)
        {
            HideConsole();
            try
            {
                return window.Dispatcher.Invoke(new Func<bool?>(delegate { return window.ShowDialog(); }));
            }
            finally { ShowConsole(); }
        }
        
        // Flash the taskbar button to get user attention
        // Flashes until window receives focus or StopFlash is called
        public static void FlashTaskbar(Window window)
        {
            if (window == null) return;
            
            try
            {
                var helper = new WindowInteropHelper(window);
                var hwnd = helper.Handle;
                if (hwnd == IntPtr.Zero) return;
                
                var fi = new FLASHWINFO();
                fi.cbSize = (uint)Marshal.SizeOf(fi);
                fi.hwnd = hwnd;
                fi.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;  // Flash until foreground
                fi.uCount = uint.MaxValue;  // Keep flashing
                fi.dwTimeout = 0;  // Use default cursor blink rate
                
                FlashWindowEx(ref fi);
            }
            catch { /* ignore - flash is optional */ }
        }
        
        // Stop flashing the taskbar button
        public static void StopFlashTaskbar(Window window)
        {
            if (window == null) return;
            
            try
            {
                var helper = new WindowInteropHelper(window);
                var hwnd = helper.Handle;
                if (hwnd == IntPtr.Zero) return;
                
                var fi = new FLASHWINFO();
                fi.cbSize = (uint)Marshal.SizeOf(fi);
                fi.hwnd = hwnd;
                fi.dwFlags = FLASHW_STOP;
                fi.uCount = 0;
                fi.dwTimeout = 0;
                
                FlashWindowEx(ref fi);
            }
            catch { /* ignore */ }
        }
        
        // Set the owner window via Win32 - makes child stay above owner without being system-wide Topmost.
        // This works across threads unlike WPF's Owner property.
        public static void SetOwnerWindow(IntPtr childHwnd, IntPtr ownerHwnd)
        {
            if (childHwnd == IntPtr.Zero || ownerHwnd == IntPtr.Zero) return;
            
            try
            {
                // Use SetWindowLong on 32-bit, SetWindowLongPtr on 64-bit
                if (IntPtr.Size == 8)
                {
                    SetWindowLongPtr(childHwnd, GWL_HWNDPARENT, ownerHwnd);
                }
                else
                {
                    SetWindowLong32(childHwnd, GWL_HWNDPARENT, ownerHwnd);
                }
            }
            catch { /* ignore */ }
        }
    }

    public class WindowConfig
    {
        public string Title { get; set; }
        public double Width { get; set; }
        public double Height { get; set; }
        public double MinWidth { get; set; }
        public double MinHeight { get; set; }
        public bool NoResize { get; set; }
        public bool SizeToContent { get; set; }
        public string Theme { get; set; }
        public string IconPath { get; set; }

        public WindowConfig()
        {
            Title = null; Width = 400; Height = 600; MinWidth = 0; MinHeight = 0;
            NoResize = false; SizeToContent = false; Theme = "Light"; IconPath = null;
        }
    }
}