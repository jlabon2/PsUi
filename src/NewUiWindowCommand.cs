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
        public string Theme { get; set; } = "Light";

        [Parameter]
        public string ThemePath { get; set; }

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

            // Check if -Debug or -Verbose was passed
            bool debugMode = MyInvocation.BoundParameters.ContainsKey("Debug");
            bool verboseMode = MyInvocation.BoundParameters.ContainsKey("Verbose");
            
            // Check if user explicitly provided Width/Height - if not, auto-size to content
            bool hasExplicitWidth = MyInvocation.BoundParameters.ContainsKey("Width");
            bool hasExplicitHeight = MyInvocation.BoundParameters.ContainsKey("Height");
            bool autoSize = !hasExplicitWidth && !hasExplicitHeight;
            bool autoSizeHeight = hasExplicitWidth && !hasExplicitHeight;
            
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
                CallerScriptName = MyInvocation.ScriptName,
                CallerScriptLine = MyInvocation.ScriptLineNumber,
                ExportOnClose = ExportOnClose.IsPresent,
                Splash = Splash.IsPresent,
                Logo = Logo
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
                    createdWindow = RunWindow(windowParams, host, windowReady, windowHolder, exportedVariables, splashDispatcherCapture);
                }
                catch (Exception ex)
                {
                    threadError = ex;
                    // Signal ready even on error so caller doesn't hang
                    if (windowReady != null) { windowReady.Set(); }
                }
            });
            windowThread.SetApartmentState(ApartmentState.STA);
            windowThread.IsBackground = false; // Keep alive until window closes
            windowThread.Name = "PsUi-Window-" + Guid.NewGuid().ToString().Substring(0, 8);
            windowThread.Start();

            // With -PassThru, return immediately after window spawns (dont wait for close)
            if (windowParams.PassThru)
            {
                windowReady.WaitOne();
                windowReady.Dispose();
                
                if (threadError != null)
                {
                    ThrowTerminatingError(new ErrorRecord(
                        threadError, 
                        "WindowError", 
                        ErrorCategory.OperationStopped, 
                        null));
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
                    ThrowTerminatingError(new ErrorRecord(
                        threadError, 
                        "WindowError", 
                        ErrorCategory.OperationStopped, 
                        null));
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
            // Export captured variables to global scope on window close
            public bool ExportOnClose { get; set; }
            // Show splash screen while loading
            public bool Splash { get; set; }
            public string Logo { get; set; }
        }
    }
}
