using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace PsUi
{
    // Binary cmdlet replacement for New-UiWindow.ps1. Spawns dedicated STA thread per window.
    // Split across partial classes: NewUiWindowCommand.Capture.cs, NewUiWindowCommand.Builder.cs
    //
    // Binary cmdlet gives clean lifecycle hooks (BeginProcessing, EndProcessing), parameter validation
    // attributes, and faster startup. STA thread spawning + SessionManager integration cleaner in C#.
    [Cmdlet(VerbsCommon.New, "UiWindow")]
    public partial class NewUiWindowCommand : PSCmdlet
    {
        [Parameter(Position = 0)]
        public string Title { get; set; } = "PowerShell GUI";

        [Parameter(Mandatory = true)]
        public ScriptBlock Content { get; set; }

        [Parameter]
        [ValidateRange(200, 2000)]
        public int? Width { get; set; }

        [Parameter]
        [ValidateRange(150, 1500)]
        public int? Height { get; set; }

        [Parameter]
        [ValidateRange(300, 2000)]
        public int MaxWidth { get; set; } = 800;

        [Parameter]
        [ValidateRange(200, 1500)]
        public int MaxHeight { get; set; } = 900;

        [Parameter]
        public string Theme { get; set; } = "Auto";

        [Parameter]
        public string ThemePath { get; set; }

        [Parameter(HelpMessage = "Icon font for this window: Inherit (default - keep whatever Set-PsUiIconFont last established), Auto (re-detect), SegoeMDL2, or SegoeFluentIcons. Restored to the previous active font on window close.")]
        [ValidateSet("Inherit", "Auto", "SegoeMDL2", "SegoeFluentIcons")]
        public string IconFont { get; set; } = "Inherit";

        [Parameter(HelpMessage = "Pin the chosen icon font with no WPF fallback chain. Glyphs missing from the chosen font render as tofu. On a Win10 box with only MDL2 installed this is a rendering no-op (no secondary to fall back to); its remaining effect is tighter IntelliSense for -Icon names.")]
        public SwitchParameter NoIconFontFallback { get; set; }

        [Parameter]
        public SwitchParameter NoResize { get; set; }

        [Parameter]
        public string Icon { get; set; }

        [Parameter]
        [ValidateSet("Responsive", "Stack")]
        public string LayoutMode { get; set; } = "Stack";

        [Parameter]
        [ValidateRange(1, 4)]
        public int MaxColumns { get; set; } = 2;

        [Parameter]
        [ValidateSet("Left", "Center")]
        public string TabAlignment { get; set; } = "Left";

        [Parameter]
        public SwitchParameter MinimizeConsole { get; set; }

        [Parameter]
        public Hashtable WPFProperties { get; set; }

        [Parameter]
        public SwitchParameter HideThemeButton { get; set; }

        [Parameter]
        [ValidateSet("STA", "MTA")]
        public string AsyncApartment { get; set; } = "MTA";

        [Parameter]
        [Alias("NoCapture")]
        public SwitchParameter NoImplicitCapture { get; set; }

        [Parameter]
        public SwitchParameter PassThru { get; set; }
        
        [Parameter]
        public SwitchParameter ExportOnClose { get; set; }

        [Parameter]
        [Alias("Loading")]
        public SwitchParameter Splash { get; set; }

        [Parameter]
        public string Logo { get; set; }

        // Captured from caller's session for script execution
        private Hashtable _privateFunctions;
        private string _modulePath;
        private Runspace _callerRunspace;
        private Dictionary<string, object> _callerVariables;
        private Dictionary<string, string> _callerFunctions;

        private static void DebugLog(string category, string message)
        {
            SessionContext session = SessionManager.Current;
            if (session != null && session.DebugMode)
            {
                Console.WriteLine("[{0}] {1}", category, message);
            }
        }

        protected override void BeginProcessing()
        {
            // Capture module context before spawning thread
            _privateFunctions = ModuleContext.PrivateFunctions;
            _modulePath = ModuleContext.ModulePath;
            _callerRunspace = Runspace.DefaultRunspace;
            
            // Capture caller's variables for injection into window runspace
            _callerVariables = new Dictionary<string, object>();
            _callerFunctions = new Dictionary<string, string>();
            
            // Skip capture if user opted out (performance optimization for large variable sets)
            if (NoImplicitCapture.IsPresent)
            {
                DebugLog("CAPTURE", "Skipping variable/function capture (-NoImplicitCapture specified)");
            }
            else
            {
                // CaptureCallerVariables and CaptureCallerFunctions in NewUiWindowCommand.Capture.cs
                CaptureCallerVariables();
                CaptureCallerFunctions();
            }
        }

        protected override void ProcessRecord()
        {
            // Reject empty content scriptblocks early with a clear error
            string contentText = Content.ToString();
            if (string.IsNullOrWhiteSpace(contentText))
            {
                ThrowTerminatingError(new ErrorRecord(
                    new ArgumentException("The -Content scriptblock is empty. Add UI controls inside the block, e.g.: New-UiWindow -Content { New-UiButton -Text 'Hello' }"),
                    "EmptyContent",
                    ErrorCategory.InvalidArgument,
                    Content));
                return;
            }

            // Warn when the caller named a specific icon font that isn't installed - matches
            // Set-PsUiIconFont so the per-window override doesn't silently fall back. Auto and
            // Inherit stay silent. Done here (not in RunWindow) because RunWindow is on a worker
            // thread and WriteWarning is only safe on the cmdlet processing thread.
            if (string.Equals(IconFont, "SegoeMDL2", StringComparison.OrdinalIgnoreCase)
                || string.Equals(IconFont, "SegoeFluentIcons", StringComparison.OrdinalIgnoreCase))
            {
                string resolvedIconFont = ModuleContext.ResolveIconFontToken(IconFont);
                if (!ModuleContext.IsFontInstalled(resolvedIconFont))
                {
                    WriteWarning(resolvedIconFont + " is not installed. Falling back to " + ModuleContext.FontNameMDL2 + ".");
                }
            }

            // Check if -Debug or -Verbose was passed
            bool debugMode = MyInvocation.BoundParameters.ContainsKey("Debug");
            bool verboseMode = MyInvocation.BoundParameters.ContainsKey("Verbose");
            
            // Check if user explicitly provided Width/Height - if not, auto-size to content
            bool hasExplicitWidth = MyInvocation.BoundParameters.ContainsKey("Width");
            bool hasExplicitHeight = MyInvocation.BoundParameters.ContainsKey("Height");
            bool autoSize = !hasExplicitWidth && !hasExplicitHeight;
            bool autoSizeHeight = hasExplicitWidth && !hasExplicitHeight;

            // Called from another window, this runs in generated text without a file
            string callerScriptName = MyInvocation.ScriptName;
            int callerScriptLine = MyInvocation.ScriptLineNumber;
            int outerContentLine = 0;
            SessionContext outerSession = SessionManager.Current;
            if (string.IsNullOrEmpty(callerScriptName) && outerSession != null && !string.IsNullOrEmpty(outerSession.CallerScriptName)
                && outerSession.Window != null && outerSession.Window.Dispatcher.CheckAccess())
            {
                callerScriptName = outerSession.CallerScriptName;
                outerContentLine = outerSession.CallerScriptLine;
                callerScriptLine = outerContentLine + callerScriptLine - 1;
            }

            // Capture all parameters for the thread closure
            var windowParams = new WindowParameters
            {
                Title = Title,
                Content = Content,
                Width = Width ?? 450,
                Height = Height ?? 600,
                MaxWidth = MaxWidth,
                MaxHeight = MaxHeight,
                AutoSize = autoSize,
                AutoSizeHeight = autoSizeHeight,
                Theme = Theme,
                ThemePath = ThemePath,
                IconFont = IconFont,
                NoIconFontFallback = NoIconFontFallback.IsPresent,
                NoIconFontFallbackBound = MyInvocation.BoundParameters.ContainsKey("NoIconFontFallback"),
                NoResize = NoResize.IsPresent,
                Icon = Icon,
                LayoutMode = LayoutMode,
                MaxColumns = MaxColumns,
                TabAlignment = TabAlignment,
                MinimizeConsole = MinimizeConsole.IsPresent,
                WPFProperties = WPFProperties,
                HideThemeButton = HideThemeButton.IsPresent,
                PassThru = PassThru.IsPresent,
                AsyncApartment = AsyncApartment,
                PrivateFunctions = _privateFunctions,
                ModulePath = _modulePath,
                CallerVariables = _callerVariables,
                CallerFunctions = _callerFunctions,
                DebugMode = debugMode,
                VerboseMode = verboseMode,
                // Capture caller location for error reporting
                CallerScriptName = callerScriptName,
                CallerScriptLine = callerScriptLine,
                OuterContentLine = outerContentLine,
                ExportOnClose = ExportOnClose.IsPresent,
                Splash = Splash.IsPresent,
                Logo = Logo,
                ContentErrorAction = GetContentErrorAction()
            };

            // Capture the host for Write-Host routing
            var host = Host;
            Exception threadError = null;
            Window createdWindow = null;
            ManualResetEvent windowReady = windowParams.PassThru ? new ManualResetEvent(false) : null;
            
            // Holder for passing window back before Dispatcher.Run() blocks
            Window[] windowHolder = windowParams.PassThru ? new Window[1] : null;
            
            // Holder for captured variables to export after window closes
            Dictionary<string, object> exportedVariables = windowParams.ExportOnClose 
                ? new Dictionary<string, object>() 
                : null;

            var contentErrors = new ContentErrorRelay();

            // Splash window runs on its own STA thread while main window loads
            Thread splashThread = null;
            System.Windows.Threading.Dispatcher splashDispatcher = null;
            ManualResetEvent splashShown = null;
            
            if (windowParams.Splash)
            {
                splashShown = new ManualResetEvent(false);
                var splashShownCapture = splashShown;
                
                // Pre-fetch theme colors for splash (ThemeEngine has static color definitions)
                Hashtable splashColors = ThemeEngine.GetThemeColors(windowParams.Theme);
                
                splashThread = new Thread(() =>
                {
                    try
                    {
                        var splash = BuildSplashWindow(windowParams, splashColors, splashShownCapture);
                        splashDispatcher = splash.Dispatcher;
                        splash.Show();
                        System.Windows.Threading.Dispatcher.Run();
                    }
                    catch
                    {
                        // Splash failure should not block main window
                        splashShownCapture.Set();
                    }
                });
                splashThread.SetApartmentState(ApartmentState.STA);
                splashThread.IsBackground = true;
                splashThread.Name = "PsUi-Splash";
                splashThread.Start();
                
                // Wait for splash to be visible before building main window
                splashShown.WaitOne(2000);
            }

            // Create dedicated STA thread for this window
            var splashDispatcherCapture = splashDispatcher;
            var windowThread = new Thread(() => 
            {
                try
                {
                    createdWindow = RunWindow(windowParams, host, contentErrors, windowReady, windowHolder, exportedVariables, splashDispatcherCapture);
                }
                catch (Exception ex)
                {
                    threadError = ex;
                    // Signal ready even on error so caller doesn't hang
                    if (windowReady != null) { windowReady.Set(); }
                }
                finally
                {
                    // If the build dies early, it would wait forever for the next error
                    contentErrors.Finish();
                }
            });
            windowThread.SetApartmentState(ApartmentState.STA);
            windowThread.IsBackground = false; // Keep alive until window closes
            windowThread.Name = "PsUi-Window-" + Guid.NewGuid().ToString().Substring(0, 8);
            windowThread.Start();

            // Under Stop, only commands told to carry on still reach the relay
            if (windowParams.ContentErrorAction == ActionPreference.Stop)
            {
                SetErrorAction(ActionPreference.Continue);
            }
            else if ((debugMode || verboseMode) && !MyInvocation.BoundParameters.ContainsKey("ErrorAction"))
            {
                // 5.1 reads -Debug on New-UiWindow as ErrorAction Inquire and -Verbose as Continue, where 7 keeps the script's preference
                SetErrorAction(windowParams.ContentErrorAction);
            }

            // Ahead of both waits, since the window thread blocks on each error
            try
            {
                contentErrors.Pump(WriteError);
            }
            catch
            {
                // WriteError throws when the pipeline stops or an Inquire gets Halt, and the window thread sees Halted before it shows
                windowThread.Join();
                if (windowReady != null) { windowReady.Dispose(); }
                throw;
            }

            // With -PassThru, return immediately after window spawns (dont wait for close)
            if (windowParams.PassThru)
            {
                windowReady.WaitOne();
                windowReady.Dispose();
                
                if (threadError != null)
                {
                    StopWindow(threadError, windowParams.ContentErrorAction);
                }

                // Get window from holder (set before Dispatcher.Run() blocked)
                if (windowHolder[0] != null)
                {
                    WriteObject(windowHolder[0]);
                }
            }
            else
            {
                // Normal mode: wait for window to close
                windowThread.Join();

                if (threadError != null)
                {
                    StopWindow(threadError, windowParams.ContentErrorAction);
                }

                // Export captured variables to caller's scope
                if (exportedVariables != null && exportedVariables.Count > 0)
                {
                    foreach (var kvp in exportedVariables)
                    {
                        SessionState.PSVariable.Set(kvp.Key, kvp.Value);
                    }
                }
            }
        }
        
        // RunWindow and helper methods moved to NewUiWindowCommand.Builder.cs

        // 7 labels a thrown error 'Exception' instead of saying which command threw it
        private static ErrorRecord WindowError(Exception threadError)
        {
            RuntimeException thrown = threadError as RuntimeException;
            if (thrown != null) { thrown.WasThrownFromThrowStatement = false; }
            return new ErrorRecord(threadError, "WindowError", ErrorCategory.OperationStopped, null);
        }

        // WriteError under Stop ends the script, not just the statement
        private void StopWindow(Exception threadError, ActionPreference contentErrorAction)
        {
            ErrorRecord record = WindowError(threadError);
            if (contentErrorAction == ActionPreference.Stop && SetErrorAction(ActionPreference.Stop))
            {
                WriteError(record);
            }
            ThrowTerminatingError(record);
        }

        // Starts on -ErrorAction if passed, else the calling script's preference
        private ActionPreference GetContentErrorAction()
        {
            object preference;
            if (!MyInvocation.BoundParameters.TryGetValue("ErrorAction", out preference))
            {
                preference = SessionState.PSVariable.GetValue("ErrorActionPreference");
            }
            if (preference == null) { return ActionPreference.Continue; }

            try
            {
                return (ActionPreference)LanguagePrimitives.ConvertTo(preference, typeof(ActionPreference),
                    System.Globalization.CultureInfo.InvariantCulture);
            }
            catch (PSInvalidCastException)
            {
                return ActionPreference.Continue;
            }
        }

        // ErrorAction is internal, and this is the setter -ErrorAction uses
        private bool SetErrorAction(ActionPreference errorAction)
        {
            try
            {
                System.Reflection.PropertyInfo errorActionProperty = CommandRuntime.GetType().GetProperty("ErrorAction",
                    System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
                if (errorActionProperty == null || !errorActionProperty.CanWrite) { return false; }
                errorActionProperty.SetValue(CommandRuntime, errorAction, null);
                return true;
            }
            catch (Exception ex)
            {
                DebugLog("CONTENT", "Setting New-UiWindow's ErrorAction to " + errorAction + " failed: " + ex.Message);
                return false;
            }
        }

        // Container for thread closure (avoids capturing 'this')
        private class WindowParameters
        {
            public string Title { get; set; }
            public ScriptBlock Content { get; set; }
            public int Width { get; set; }
            public int Height { get; set; }
            public int MaxWidth { get; set; }
            public int MaxHeight { get; set; }
            public bool AutoSize { get; set; }
            public bool AutoSizeHeight { get; set; }
            public string Theme { get; set; }
            public string ThemePath { get; set; }
            public string IconFont { get; set; }
            public bool NoIconFontFallback { get; set; }
            public bool NoIconFontFallbackBound { get; set; }
            public bool NoResize { get; set; }
            public string Icon { get; set; }
            public string LayoutMode { get; set; }
            public int MaxColumns { get; set; }
            public string TabAlignment { get; set; }
            public bool MinimizeConsole { get; set; }
            public Hashtable WPFProperties { get; set; }
            public bool HideThemeButton { get; set; }
            public bool PassThru { get; set; }
            public string AsyncApartment { get; set; }
            public Hashtable PrivateFunctions { get; set; }
            public string ModulePath { get; set; }
            public Dictionary<string, object> CallerVariables { get; set; }
            public Dictionary<string, string> CallerFunctions { get; set; }
            public bool DebugMode { get; set; }
            public bool VerboseMode { get; set; }
            // Caller location info for accurate error reporting
            public string CallerScriptName { get; set; }
            public int CallerScriptLine { get; set; }
            // Zero unless this window opened from inside another one
            public int OuterContentLine { get; set; }
            // Export captured variables to global scope on window close
            public bool ExportOnClose { get; set; }
            // Show splash screen while loading
            public bool Splash { get; set; }
            public string Logo { get; set; }
            public ActionPreference ContentErrorAction { get; set; }
        }

        // WriteError only runs on the cmdlet thread, and Post waits for it
        private sealed class ContentErrorRelay
        {
            private readonly object _gate = new object();
            private ErrorRecord _pending;
            private bool _finished;
            private bool _halted;

            // Set once a WriteError throws
            public bool Halted
            {
                get { lock (_gate) { return _halted; } }
            }

            // Window thread. False once the cmdlet side has stopped taking records.
            public bool Post(ErrorRecord record)
            {
                lock (_gate)
                {
                    if (_halted || _finished) { return false; }
                    _pending = record;
                    Monitor.PulseAll(_gate);
                    while (_pending != null && !_halted) { Monitor.Wait(_gate); }
                    return !_halted;
                }
            }

            public void Finish()
            {
                lock (_gate)
                {
                    _finished = true;
                    Monitor.PulseAll(_gate);
                }
            }

            // Cmdlet thread. A throwing write halts the relay and carries on up.
            public void Pump(Action<ErrorRecord> write)
            {
                while (true)
                {
                    ErrorRecord record;
                    lock (_gate)
                    {
                        while (_pending == null && !_finished) { Monitor.Wait(_gate); }
                        if (_pending == null) { return; }
                        record = _pending;
                    }

                    bool written = false;
                    try
                    {
                        write(record);
                        written = true;
                    }
                    finally
                    {
                        lock (_gate)
                        {
                            _pending = null;
                            if (!written) { _halted = true; }
                            Monitor.PulseAll(_gate);
                        }
                    }
                }
            }
        }
    }
}
