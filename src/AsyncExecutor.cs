using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Management.Automation.Runspaces;
using System.Security;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Data;
using System.Windows.Threading;

namespace PsUi
{
    // Runs PS scripts on background threads, routes Write-Host/Progress/etc to WPF via events.
    // Partial classes: Routing.cs (event handlers), Setup.cs (proxy function injection)
    //
    // Complexity warning: running PS on a background thread breaks Write-Host, Read-Host,
    // progress bars, and Get-Credential. We intercept all of them, marshal to the UI thread,
    // and handle backpressure when output floods in. The batching and queue modes exist because
    // we've seen scripts emit 50k lines in seconds - without throttling, the dispatcher queue
    // grows unbounded and the UI shits the bed.
    public partial class AsyncExecutor : IDisposable
    {
        public event Action<PSErrorRecord> OnError;
        public event Action<string> OnWarning;
        public event Action<string> OnVerbose;
        public event Action<string> OnDebug;
        public event Action<HostOutputRecord> OnHost;
        public event Action<List<HostOutputRecord>> OnHostBatch;
        public event Action<ProgressRecord> OnProgress;
        public event Action<object> OnPipelineOutput;
        public event Action OnComplete;
        public event Action OnCancelled;
        public event Action<string> OnWindowTitle;
        
        // Fires when execution is queued waiting for a thread slot
        public event Action OnQueued;
        // Fires when execution starts (thread slot acquired)
        public event Action OnStarted;
        // Fires when internal framework operations fail (dehydration, capture, cleanup).
        // These aren't script errors - they're problems in PsUi itself. Wire this up
        // if you need to debug why a variable didn't sync back to a control.
        public event Action<string> OnFrameworkError;
        
        public ScriptBlock InputProvider { get; set; }
        public ScriptBlock SecureInputProvider { get; set; }
        public ScriptBlock ChoiceProvider { get; set; }
        public ScriptBlock CredentialProvider { get; set; }
        public ScriptBlock PromptProvider { get; set; }
        public ScriptBlock ReadKeyProvider { get; set; }
        public ScriptBlock ClearHostProvider { get; set; }
        public ScriptBlock PauseProvider { get; set; }
        
        private PowerShell _powershell;
        private CancellationTokenSource _cts;
        private readonly object _ctsLock = new object();
        private volatile Dispatcher _uiDispatcher;
        
        public Dispatcher UiDispatcher 
        { 
            get 
            {
                if (_uiDispatcher == null) _uiDispatcher = CaptureDispatcher();
                return _uiDispatcher;
            }
            set { _uiDispatcher = value; }
        }

        private DateTime _lastProgressUpdate = DateTime.MinValue;
        private readonly object _progressLock = new object();
        private const int PROGRESS_THROTTLE_MS = 100;
        
        // Host output batching - prevents dispatcher from getting flooded
        private List<HostOutputRecord> _hostBatch = new List<HostOutputRecord>();
        private readonly object _hostBatchLock = new object();
        private DateTime _lastHostFlush = DateTime.MinValue;
        private const int HOST_BATCH_SIZE = 50;
        private const int HOST_FLUSH_MS = 50;
        
        // Queue-based output for polling (avoids dispatcher flooding)
        private System.Collections.Concurrent.ConcurrentQueue<HostOutputRecord> _hostQueue = new System.Collections.Concurrent.ConcurrentQueue<HostOutputRecord>();
        public bool UseQueueMode { get; set; }
        
        // Queue-based pipeline output (avoids dispatcher saturation with large result sets)
        private System.Collections.Concurrent.ConcurrentQueue<object> _pipelineQueue = new System.Collections.Concurrent.ConcurrentQueue<object>();
        public bool UsePipelineQueueMode { get; set; }
        
        // Variables to capture from runspace after script finishes
        public string[] CaptureVariables { get; set; }
        
        // Session ID from UI thread - passed to background runspaces
        private Guid _capturedSessionId;
        
        // Debug mode - when true, writes debug output to console
        public static bool DebugMode { get; set; }
        
        // Throttle delay in ms - slows down script execution to let UI breathe
        public int HostThrottleMs { get; set; }
        
        // Volatile ensures cross-thread visibility without a full lock
        private volatile bool _isRunning;
        public bool IsRunning
        {
            get { return _isRunning; }
            private set { _isRunning = value; }
        }
        
        // Thread-local reference for MinimalHost output routing
        [ThreadStatic]
        private static AsyncExecutor _currentExecutor;
        
        public static AsyncExecutor CurrentExecutor
        {
            get { return _currentExecutor; }
            set { _currentExecutor = value; }
        }
        
        // Semaphore to throttle thread creation - prevents spawning more threads than runspaces.
        // Yeah, ThreadPool threads block on Wait() when all 8 slots are taken. That's fine - the
        // pool grows dynamically and we cap at 8 waiters max. Without this gate, mashing a button
        // spawns unlimited runspaces and you OOM. Ask me how I know.
        private static readonly SemaphoreSlim _threadGate = new SemaphoreSlim(8, 8);
        
        // STA thread for WinForms dialogs, COM objects, clipboard, etc.
        private static void RunOnStaThread(Action action)
        {
            var thread = new Thread(() => action())
            {
                IsBackground = true
            };
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
        }
        
        // Background thread with STA/MTA based on session. Semaphore gates thread
        // creation to match pool size - prevents "thread bomb" from rapid button clicks.
        private void RunOnBackgroundThread(Action action)
        {
            // Check session for threading preference
            var session = SessionManager.GetSession(_capturedSessionId);
            bool useMta = session != null && session.UseMtaThreading;
            
            // Queue the work through ThreadPool first, then gate actual execution
            ThreadPool.QueueUserWorkItem(delegate
            {
                // Try to get a slot immediately - if not available, notify UI we're queued
                bool gotSlot = _threadGate.Wait(0);
                if (!gotSlot)
                {
                    // Let the UI know we're waiting in line
                    RaiseOnQueued();
                    if (!_threadGate.Wait(TimeSpan.FromSeconds(60)))
                    {
                        RaiseOnError("Async execution timed out waiting for a thread slot (all 8 slots occupied for 60s). Cancel a running task and try again.");
                        return;
                    }
                }
                
                // Got a slot - notify UI we're starting
                RaiseOnStarted();
                
                try
                {
                    if (useMta)
                    {
                        // MTA mode: already on ThreadPool, just run
                        action();
                    }
                    else
                    {
                        // STA mode: spawn dedicated thread for COM compatibility
                        // But now we're gated - max 8 STA threads at a time
                        var staThread = new Thread(() =>
                        {
                            try { action(); }
                            finally { _threadGate.Release(); }
                        })
                        {
                            IsBackground = true
                        };
                        staThread.SetApartmentState(ApartmentState.STA);
                        
                        try
                        {
                            staThread.Start();
                        }
                        catch
                        {
                            // If Start() fails (rare - e.g., out of memory), release the slot
                            _threadGate.Release();
                            throw;
                        }
                        return; // Don't release here - STA thread will release in finally
                    }
                }
                finally
                {
                    // Only release if we didn't spawn an STA thread (MTA path)
                    if (useMta)
                    {
                        _threadGate.Release();
                    }
                }
            });
        }
        
        private void RaiseOnQueued()
        {
            var handler = OnQueued;
            if (handler != null && UiDispatcher != null)
            {
                UiDispatcher.BeginInvoke(handler);
            }
        }
        
        private void RaiseOnStarted()
        {
            var handler = OnStarted;
            if (handler != null && UiDispatcher != null)
            {
                UiDispatcher.BeginInvoke(handler);
            }
        }
        
        private void RaiseFrameworkError(string context, Exception ex)
        {
            string msg = string.Format("[{0}] {1}", context, ex.Message);
            Debug.WriteLine("AsyncExecutor " + msg);
            
            var handler = OnFrameworkError;
            if (handler != null && UiDispatcher != null)
            {
                UiDispatcher.BeginInvoke(new Action(() => handler(msg)));
            }
        }
        
        public AsyncExecutor()
        {
            _uiDispatcher = CaptureDispatcher();
            // Capture session ID from UI thread for propagation to background threads
            _capturedSessionId = SessionManager.CurrentSessionId;
            // Pre-warm the pool on first AsyncExecutor creation
            RunspacePoolManager.EnsureInitialized();
        }
        
        private static bool IsReservedVariable(string name)
        {
            return Constants.IsReservedVariable(name);
        }
        
        private static Dispatcher CaptureDispatcher()
        {
            try
            {
                if (System.Windows.Application.Current != null && 
                    System.Windows.Application.Current.Dispatcher != null)
                {
                    return System.Windows.Application.Current.Dispatcher;
                }
            }
            catch (Exception ex) 
            { 
                System.Diagnostics.Debug.WriteLine("CaptureDispatcher failed: " + ex.Message);
            }
            return null;
        }
        
        // Accepts modulesToLoad, uses RunspacePool for speed
        public void ExecuteAsync(ScriptBlock script, Hashtable parameters, IDictionary variablesToDefine = null, IDictionary functionsToDefine = null, IEnumerable<string> modulesToLoad = null, bool debugEnabled = false)
        {
            if (IsRunning) return;
            
            // Reset disposed flag so a previously-cancelled executor can be reused
            _disposed = false;
            
            // Reset input session state so ReadKey calls work (cleared on window close)
            KeyCaptureDialog.BeginInputSession();
            
            // Dispose existing CTS before creating new one (synchronized to prevent race conditions)
            lock (_ctsLock)
            {
                if (_cts != null)
                {
                    try { _cts.Dispose(); } catch (ObjectDisposedException) { }
                    _cts = null;
                }
                
                _cts = new CancellationTokenSource();
            }
            IsRunning = true;
            
            // Determine execution mode: use dedicated runspace only if we need host interception
            // (Read-Host, PromptForChoice, etc.) - otherwise use faster pooled execution
            bool needsHostInterception = InputProvider != null || SecureInputProvider != null || 
                                          ChoiceProvider != null || CredentialProvider != null ||
                                          PromptProvider != null || ReadKeyProvider != null;
            
            if (needsHostInterception)
            {
                // Use dedicated runspace with custom host for interactive features
                ExecuteWithDedicatedRunspace(script, parameters, variablesToDefine, functionsToDefine, modulesToLoad, debugEnabled);
            }
            else
            {
                // Use fast pooled execution
                ExecuteWithPool(script, parameters, variablesToDefine, functionsToDefine, modulesToLoad, debugEnabled);
            }
        }
        
        private void ExecuteWithPool(ScriptBlock script, Hashtable parameters, IDictionary variablesToDefine, IDictionary functionsToDefine, IEnumerable<string> modulesToLoad, bool debugEnabled)
        {
            // Use session-configured threading (STA default, MTA opt-in)
            RunOnBackgroundThread(delegate
            {
                // Background thread needs session ID or Get-UiSession returns null
                if (_capturedSessionId != Guid.Empty)
                {
                    SessionManager.SetCurrentSession(_capturedSessionId);
                }
                
                PowerShell ps = null;
                Dictionary<string, object> hydratedValues = null;
                string originalPwd = null;
                HashSet<string> definedVarNames = null;

                try
                {
                    var cts = _cts;
                    if (cts == null || cts.IsCancellationRequested) return;
                    
                    ps = PowerShell.Create();
                    ps.RunspacePool = RunspacePoolManager.Pool;
                    _powershell = ps;
                    
                    // Set thread-local executor so MinimalHost can route output
                    AsyncExecutor.CurrentExecutor = this;
                    
                    // Wire up functions, modules, and propagate session ID
                    ExecuteSetupPhase(ps, functionsToDefine, modulesToLoad, debugEnabled);
                    
                    // Inject user-defined variables from LinkedVariables
                    definedVarNames = InjectUserVariables(ps, variablesToDefine, out var definedVarValues);
                    
                    // Hydrate UI control values as PowerShell variables
                    hydratedValues = StateHydrationEngine.HydrateViaScript(ps, definedVarNames);
                    MergeDefinedVariables(hydratedValues, definedVarValues);
                    
                    // Inject executor reference so Write-Host routes to UI
                    InjectAsyncExecutorReference(ps);
                    
                    // Snapshot PWD so we can restore it after execution
                    originalPwd = SnapshotWorkingDirectory(ps);
                    
                    // Build wrapped script with localizer/dehydrator
                    string wrappedScript = ScriptBuilder.WrapUserScript(
                        script.ToString(), 
                        hydratedValues != null ? hydratedValues.Keys : null, 
                        _capturedSessionId);
                    
                    // Execute the user's script
                    ExecuteUserScript(ps, wrappedScript, parameters);
                }
                catch (Exception ex)
                {
                    var cts = _cts;
                    if (cts == null || !cts.IsCancellationRequested)
                    {
                        RaiseOnError(ex);
                    }
                }
                finally
                {
                    // ExecuteCleanupPhase handles OnComplete firing and session cleanup
                    ExecuteCleanupPhase(ps, originalPwd, hydratedValues, variablesToDefine);
                }
            });
        }
        
        // Setup phase: inject functions, import modules, propagate session ID
        private void ExecuteSetupPhase(PowerShell ps, IDictionary functionsToDefine, IEnumerable<string> modulesToLoad, bool debugEnabled)
        {
            string setupScript = BuildSetupScript(functionsToDefine, modulesToLoad, debugEnabled);
            
            // Prepend session propagation
            if (_capturedSessionId != Guid.Empty)
            {
                setupScript = ScriptBuilder.BuildSessionPropagation(_capturedSessionId) + "\n" + setupScript;
            }
            
            if (!string.IsNullOrEmpty(setupScript))
            {
                ps.AddScript(setupScript);
                ps.Invoke();
                ps.Commands.Clear();
            }
        }
        
        // Inject user variables from -LinkedVariables. Returns names for collision detection.
        private HashSet<string> InjectUserVariables(PowerShell ps, IDictionary variablesToDefine, out Dictionary<string, object> definedVarValues)
        {
            var definedVarNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            definedVarValues = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
            
            if (variablesToDefine == null) return definedVarNames;
            
            // Collect valid variables first
            var validVars = new List<KeyValuePair<string, object>>();
            foreach (DictionaryEntry kvp in variablesToDefine)
            {
                string varName = kvp.Key.ToString();
                if (IsReservedVariable(varName)) continue;
                
                if (!Constants.IsValidIdentifier(varName))
                {
                    if (OnError != null) RaiseOnError(string.Format("Invalid variable name '{0}': must contain only letters, digits, underscore, or hyphen", varName));
                    continue;
                }
                
                validVars.Add(new KeyValuePair<string, object>(varName, kvp.Value));
            }
            
            // Batch inject all variables in a single Invoke call
            if (validVars.Count > 0)
            {
                var varNames = new List<string>(validVars.Count);
                foreach (var kv in validVars) varNames.Add(kv.Key);
                
                string batchScript = ScriptBuilder.BuildBatchVariableInjection(varNames);
                if (batchScript != null)
                {
                    ps.AddScript(batchScript);
                    foreach (var kv in validVars) ps.AddArgument(kv.Value);
                    ps.Invoke();
                    ps.Commands.Clear();
                }
                
                foreach (var kv in validVars)
                {
                    definedVarNames.Add(kv.Key);
                    definedVarValues[kv.Key] = kv.Value;
                }
            }
            
            return definedVarNames;
        }
        
        // Add LinkedVariables to hydrated set for dehydration tracking
        private static void MergeDefinedVariables(Dictionary<string, object> hydratedValues, Dictionary<string, object> definedVarValues)
        {
            if (hydratedValues == null || definedVarValues == null) return;
            
            foreach (var kvp in definedVarValues)
            {
                if (!hydratedValues.ContainsKey(kvp.Key))
                {
                    hydratedValues[kvp.Key] = kvp.Value;
                }
            }
        }
        
        private void InjectAsyncExecutorReference(PowerShell ps)
        {
            ps.AddScript("$Global:AsyncExecutor = $args[0]");
            ps.AddArgument(this);
            ps.Invoke();
            ps.Commands.Clear();
        }
        
        // Grab PWD before user script runs so we can restore it after
        private static string SnapshotWorkingDirectory(PowerShell ps)
        {
            try
            {
                ps.Commands.Clear();
                ps.AddScript("$PWD.Path");
                var pwdResult = ps.Invoke();
                ps.Commands.Clear();
                
                if (pwdResult != null && pwdResult.Count > 0 && pwdResult[0] != null)
                {
                    return pwdResult[0].ToString();
                }
            }
            catch (Exception ex) 
            { 
                Debug.WriteLine("AsyncExecutor PWD snapshot error: " + ex.Message); 
            }
            return null;
        }
        
        private void ExecuteUserScript(PowerShell ps, string wrappedScript, Hashtable parameters)
        {
            ps.AddScript(wrappedScript);
            
            if (parameters != null)
            {
                foreach (object key in parameters.Keys)
                {
                    ps.AddParameter(key.ToString(), parameters[key]);
                }
            }
            
            // Wire up stream handlers
            WireStreamHandlers(ps);
            
            // Execute and process results
            foreach (PSObject result in ps.Invoke())
            {
                var cts = _cts;
                if (cts != null && cts.IsCancellationRequested) break;
                
                if (result != null)
                {
                    object safeOutput = result;
                    if (result.BaseObject != null && !(result.BaseObject is PSCustomObject))
                    {
                        safeOutput = result.BaseObject;
                    }
                    
                    if (UsePipelineQueueMode)
                    {
                        _pipelineQueue.Enqueue(safeOutput);
                    }
                    else if (OnPipelineOutput != null)
                    {
                        MarshalToUi(delegate { if (OnPipelineOutput != null) OnPipelineOutput(safeOutput); });
                    }
                }
            }
        }
        
        // Hook all PowerShell streams to route output to our UI handlers
        private void WireStreamHandlers(PowerShell ps)
        {
            ps.Streams.Error.DataAdded += delegate(object sender, DataAddedEventArgs e) 
            { 
                RaiseOnError(ps.Streams.Error[e.Index]); 
            };
            ps.Streams.Warning.DataAdded += delegate(object sender, DataAddedEventArgs e) 
            { 
                RaiseOnWarning(ps.Streams.Warning[e.Index].ToString()); 
            };
            ps.Streams.Verbose.DataAdded += delegate(object sender, DataAddedEventArgs e) 
            { 
                RaiseOnVerbose(ps.Streams.Verbose[e.Index].ToString()); 
            };
            ps.Streams.Debug.DataAdded += delegate(object sender, DataAddedEventArgs e) 
            { 
                RaiseOnDebug(ps.Streams.Debug[e.Index].ToString()); 
            };
            ps.Streams.Progress.DataAdded += delegate(object sender, DataAddedEventArgs e) 
            { 
                RaiseOnProgress(ps.Streams.Progress[e.Index]); 
            };
            
            // Information stream: process Write-Information, skip Write-Host (handled by global override)
            ps.Streams.Information.DataAdded += delegate(object sender, DataAddedEventArgs e)
            {
                var info = ps.Streams.Information[e.Index];
                if (info != null && info.MessageData != null)
                {
                    if (string.Equals(info.Source, "Write-Host", StringComparison.OrdinalIgnoreCase)) return;
                    RaiseOnHost(info.MessageData.ToString());
                }
            };
        }
        
        // Restore state and sync variables back to controls
        private void ExecuteCleanupPhase(PowerShell ps, string originalPwd, Dictionary<string, object> hydratedValues, IDictionary variablesToDefine)
        {
            IsRunning = false;
            
            // Clear thread-local executor reference
            AsyncExecutor.CurrentExecutor = null;
            
            // Put PWD back where we found it
            if (ps != null && originalPwd != null)
            {
                try
                {
                    ps.Commands.Clear();
                    ps.AddScript(ScriptBuilder.BuildPwdRestore(originalPwd));
                    ps.Invoke();
                    ps.Commands.Clear();
                }
                catch (Exception ex) { RaiseFrameworkError("PWD restore", ex); }
            }
            
            // Push changed values back to UI controls
            if (ps != null && hydratedValues != null && hydratedValues.Count > 0)
            {
                try
                {
                    StateHydrationEngine.DehydrateViaScript(ps, hydratedValues);
                }
                catch (Exception ex) { RaiseFrameworkError("Dehydration", ex); }
            }
            
            // Capture specified variables to SessionContext for cross-button access
            if (ps != null && CaptureVariables != null && CaptureVariables.Length > 0)
            {
                try
                {
                    StateHydrationEngine.CaptureVariablesToSession(ps, CaptureVariables, _capturedSessionId);
                }
                catch (Exception ex) { RaiseFrameworkError("Variable capture", ex); }
            }
            
            // Cleanup hydrated variables
            if (ps != null && hydratedValues != null && hydratedValues.Count > 0)
            {
                try
                {
                    StateHydrationEngine.CleanupHydratedVariables(ps, hydratedValues);
                }
                catch (Exception ex) { RaiseFrameworkError("Cleanup", ex); }
            }
            
            // Cleanup user-defined variables
            if (ps != null && variablesToDefine != null && variablesToDefine.Count > 0)
            {
                try
                {
                    ps.Commands.Clear();
                    var varNames = new List<string>();
                    foreach (DictionaryEntry kvp in variablesToDefine)
                    {
                        varNames.Add(kvp.Key.ToString());
                    }
                    string cleanupScript = ScriptBuilder.BuildVariableCleanup(varNames);
                    if (!string.IsNullOrEmpty(cleanupScript))
                    {
                        ps.AddScript(cleanupScript);
                        ps.Invoke();
                    }
                }
                catch (Exception ex) { Debug.WriteLine("AsyncExecutor Cleanup Script Error: " + ex.Message); }
            }
            
            // Sweep any leftover user-created globals from the pooled runspace.
            // Without this, $Global:secret set in Window A's button leaks to Window B's next action.
            if (ps != null)
            {
                try
                {
                    ps.Commands.Clear();
                    ps.AddScript(
                        "$__psui_reserved = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)\n" +
                        "[PsUi.Constants]::ReservedVariables | ForEach-Object { [void]$__psui_reserved.Add($_) }\n" +
                        "'__psui_reserved','AsyncExecutor','PSVersionTable','PSEdition','IsCoreCLR','IsLinux','IsMacOS','IsWindows','PSHOME','HOME','PID','ShellId','StackTrace','true','false','null','Error','WarningPreference','VerbosePreference','DebugPreference','ErrorActionPreference','InformationPreference','ConfirmPreference','WhatIfPreference','PSDefaultParameterValues','PSModuleAutoLoadingPreference','MaximumHistoryCount','ProgressPreference','FormatEnumerationLimit','OutputEncoding','input','PSCulture','PSUICulture','PSCommandPath','PSScriptRoot','MyInvocation','ExecutionContext','Host' | ForEach-Object { [void]$__psui_reserved.Add($_) }\n" +
                        "Get-Variable -Scope Global | Where-Object { !$__psui_reserved.Contains($_.Name) -and $_.Name -notlike '__psui_*' -and $_.Options -notmatch 'Constant|ReadOnly' } | Remove-Variable -Scope Global -Force -ErrorAction SilentlyContinue\n" +
                        "Remove-Variable -Name __psui_reserved -Scope Local -ErrorAction SilentlyContinue"
                    );
                    ps.Invoke();
                }
                catch (Exception ex) { Debug.WriteLine("AsyncExecutor global sweep error: " + ex.Message); }
                ps.Dispose();
            }
            _powershell = null;
            
            // Flush batched output
            FlushHostBatch();
            
            if (DebugMode)
            {
                var ctsRef = _cts;
                System.Console.WriteLine("OnComplete firing, null: {0}, cancelled: {1}",
                    OnComplete == null,
                    ctsRef != null && ctsRef.IsCancellationRequested);
            }
            
            // Fire completion event
            var ctsSnap = _cts;
            if (OnComplete != null && (ctsSnap == null || !ctsSnap.IsCancellationRequested))
            {
                if (DebugMode) System.Console.WriteLine("Marshaling OnComplete to UI");
                MarshalToUi(delegate
                {
                    if (DebugMode) System.Console.WriteLine("OnComplete executing on UI");
                    try
                    {
                        if (OnComplete != null) OnComplete();
                    }
                    catch (Exception ex)
                    {
                        // PS engine throws NullRef in CheckActionPreference when invoking scriptblocks as delegates.
                        // The callback still executes successfully - this is safe to ignore.
                        System.Diagnostics.Debug.WriteLine("OnComplete exception (ignored): " + ex.Message);
                    }
                });
            }
            
            // Clear thread-local session ID before returning to pool
            SessionManager.ClearCurrentSession();
        }
        
        // BuildSetupScript moved to AsyncExecutor.Setup.cs
        
        private void ExecuteWithDedicatedRunspace(ScriptBlock script, Hashtable parameters, IDictionary variablesToDefine, IDictionary functionsToDefine, IEnumerable<string> modulesToLoad, bool debugEnabled)
        {
            // Use session-configured threading (STA default, MTA opt-in)
            RunOnBackgroundThread(delegate
            {
                // Background thread needs session ID or Get-UiSession fails
                if (_capturedSessionId != Guid.Empty)
                {
                    SessionManager.SetCurrentSession(_capturedSessionId);
                }
                
                Runspace rs = null;
                PowerShell ps = null;
                Dictionary<string, object> hydratedValues = null;

                try
                {
                    var cts = _cts;
                    if (cts == null || cts.IsCancellationRequested) return;
                    
                    InitialSessionState iss = InitialSessionState.CreateDefault();
                    rs = RunspaceFactory.CreateRunspace(new StreamingHost(this), iss);
                    rs.ApartmentState = System.Threading.ApartmentState.STA;
                    rs.Open();

                    rs.SessionStateProxy.PSVariable.Set("AsyncExecutor", this);

                    // Push session ID so Get-UiSession works
                    if (_capturedSessionId != Guid.Empty)
                    {
                        rs.SessionStateProxy.SetVariable("null", null); // Poke the proxy to wake it up
                        using (PowerShell psSession = PowerShell.Create())
                        {
                            psSession.Runspace = rs;
                            psSession.AddScript(string.Format(
                                "$Global:__PsUiSessionId = '{0}'; [PsUi.SessionManager]::SetCurrentSession([Guid]'{0}')", 
                                _capturedSessionId));
                            psSession.Invoke();
                        }
                    }

                    using (PowerShell psSetup = PowerShell.Create())
                    {
                        psSetup.Runspace = rs;
                        
                        // Use the same cached setup script as the pooled path
                        string setupScript = BuildSetupScript(functionsToDefine, modulesToLoad, debugEnabled);
                        psSetup.AddScript(setupScript);

                        try { psSetup.Invoke(); } catch (Exception ex) { Debug.WriteLine("AsyncExecutor Setup Script Error: " + ex.Message); }
                    }
                        
                    // Hydrate Variables (skip reserved names to avoid read-only errors)
                    // Track which variables we define so hydration can skip them (collision detection)
                    // Also store initial values for dehydration tracking
                    var definedVarNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    var definedVarValues = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                    if (variablesToDefine != null)
                    {
                        foreach (DictionaryEntry kvp in variablesToDefine)
                        {
                            string varName = kvp.Key.ToString();
                            if (IsReservedVariable(varName)) continue;
                            
                            try
                            {
                                rs.SessionStateProxy.PSVariable.Set(varName, kvp.Value);
                                definedVarNames.Add(varName);
                                definedVarValues[varName] = kvp.Value;
                            }
                            catch (Exception ex)
                            {
                                if (OnError != null) RaiseOnError(string.Format("Failed to link variable '{0}': {1}", varName, ex.Message));
                            }
                        }
                    }
                    
                    // Inject control values as PS variables (skip names already defined via LinkedVariables)
                    hydratedValues = StateHydrationEngine.Hydrate(rs, definedVarNames);
                    
                    // Include LinkedVariable values in the set we'll sync back later
                    foreach (var kvp in definedVarValues)
                    {
                        if (!hydratedValues.ContainsKey(kvp.Key))
                        {
                            hydratedValues[kvp.Key] = kvp.Value;
                        }
                    }
                    
                    ps = PowerShell.Create();
                    _powershell = ps;
                    ps.Runspace = rs;
                    ps.AddScript(script.ToString());
                    
                    if (parameters != null)
                    {
                        foreach (object key in parameters.Keys)
                        {
                            ps.AddParameter(key.ToString(), parameters[key]);
                        }
                    }
                    
                    ps.Streams.Error.DataAdded += delegate(object sender, DataAddedEventArgs e) { RaiseOnError(ps.Streams.Error[e.Index]); };
                    ps.Streams.Warning.DataAdded += delegate(object sender, DataAddedEventArgs e) { RaiseOnWarning(ps.Streams.Warning[e.Index].ToString()); };
                    ps.Streams.Verbose.DataAdded += delegate(object sender, DataAddedEventArgs e) { RaiseOnVerbose(ps.Streams.Verbose[e.Index].ToString()); };
                    ps.Streams.Debug.DataAdded += delegate(object sender, DataAddedEventArgs e) { RaiseOnDebug(ps.Streams.Debug[e.Index].ToString()); };
                    ps.Streams.Progress.DataAdded += delegate(object sender, DataAddedEventArgs e) { RaiseOnProgress(ps.Streams.Progress[e.Index]); };
                    // Information stream: Only process Write-Information, skip Write-Host (handled by global override)
                    ps.Streams.Information.DataAdded += delegate(object sender, DataAddedEventArgs e) 
                    { 
                        var info = ps.Streams.Information[e.Index];
                        if (info != null && info.MessageData != null)
                        {
                            // Skip Write-Host - already handled by our global Write-Host function override
                            if (string.Equals(info.Source, "Write-Host", StringComparison.OrdinalIgnoreCase)) return;
                            RaiseOnHost(info.MessageData.ToString());
                        }
                    };
                    
                    if (DebugMode) System.Console.WriteLine("Invoke() starting, QueueMode={0}", UsePipelineQueueMode);
                    foreach (PSObject result in ps.Invoke())
                    {
                        var cts2 = _cts;
                        if (cts2 != null && cts2.IsCancellationRequested) break;
                        
                        if (result != null)
                        {
                            object safeOutput = result;
                            if (result.BaseObject != null && !(result.BaseObject is PSCustomObject))
                            {
                                safeOutput = result.BaseObject;
                            }
                            
                            // Queue mode: enqueue for UI timer to drain (prevents dispatcher saturation)
                            // Push mode: marshal immediately (legacy behavior for small result sets)
                            if (UsePipelineQueueMode)
                            {
                                _pipelineQueue.Enqueue(safeOutput);
                            }
                            else if (OnPipelineOutput != null) 
                            {
                                MarshalToUi(delegate { if (OnPipelineOutput != null) OnPipelineOutput(safeOutput); });
                            }
                        }
                    }
                    if (DebugMode) System.Console.WriteLine("Invoke() done, queue: {0}", _pipelineQueue.Count);
                }
                catch (Exception ex)
                {
                    var cts = _cts;
                    if (cts == null || !cts.IsCancellationRequested)
                    {
                        RaiseOnError(ex);
                    }
                }
                finally
                {
                    IsRunning = false;
                    
                    // Push modified values back to their controls
                    if (rs != null && hydratedValues != null && hydratedValues.Count > 0)
                    {
                        try
                        {
                            StateHydrationEngine.Dehydrate(rs, hydratedValues);
                        }
                        catch (Exception ex) { RaiseFrameworkError("Dedicated runspace dehydration", ex); }
                    }
                    
                    // Capture specified variables to SessionContext for cross-button access
                    if (rs != null && CaptureVariables != null && CaptureVariables.Length > 0)
                    {
                        try
                        {
                            StateHydrationEngine.CaptureVariablesToSessionFromRunspace(rs, CaptureVariables, _capturedSessionId);
                        }
                        catch (Exception ex) { RaiseFrameworkError("Dedicated runspace capture", ex); }
                    }
                    
                    if (ps != null) { ps.Dispose(); ps = null; }
                    if (rs != null) { rs.Dispose(); }
                    _powershell = null;

                    // Flush any remaining batched output before signaling complete
                    FlushHostBatch();
                    
                    if (DebugMode) System.Console.WriteLine("Marshal OnComplete, queue: {0}", _pipelineQueue.Count);
                    var ctsFinally = _cts;
                    if (OnComplete != null && (ctsFinally == null || !ctsFinally.IsCancellationRequested))
                    {
                         MarshalToUi(delegate { 
                             if (DebugMode) System.Console.WriteLine("OnComplete on UI thread");
                             if (OnComplete != null) OnComplete(); 
                         });
                    }
                    
                    // Clear thread-local session ID for consistency (even though dedicated runspace is disposed)
                    SessionManager.ClearCurrentSession();
                }
            });
        }
        
        // Volatile ensures visibility across threads without full lock
        private volatile bool _disposed = false;
        
        public void Cancel()
        {
            _disposed = true;  // Prevent any further UI marshaling
            var dispatcher = _uiDispatcher;
            _uiDispatcher = null;  // Clear dispatcher reference immediately
            IsRunning = false;
            
            // Fire OnCancelled event on UI thread
            var handler = OnCancelled;
            if (handler != null && dispatcher != null)
            {
                try { dispatcher.BeginInvoke(handler); }
                catch { /* ignore - dispatcher may be shut down */ }
            }
            
            // Cancel token (synchronized with ExecuteAsync)
            lock (_ctsLock)
            {
                if (_cts != null)
                {
                    try { _cts.Cancel(); }
                    catch { /* ignore */ }
                }
            }
            
            // Stop PowerShell asynchronously to avoid blocking the UI thread
            // Avoids deadlock if script is waiting on UI operations
            var ps = _powershell;
            if (ps != null)
            {
                System.Threading.ThreadPool.QueueUserWorkItem(delegate
                {
                    try { ps.Stop(); }
                    catch (Exception ex) { Debug.WriteLine("AsyncExecutor Cancel failed: " + ex.Message); }
                });
            }
        }

        public void Dispose()
        {
            _disposed = true;
            _uiDispatcher = null;
            
            // Dispose managed resources
            if (_cts != null) { try { _cts.Dispose(); } catch (Exception ex) { Debug.WriteLine("AsyncExecutor Dispose CTS Error: " + ex.Message); } _cts = null; }
            if (_powershell != null) { try { _powershell.Dispose(); } catch (Exception ex) { Debug.WriteLine("AsyncExecutor Dispose PS Error: " + ex.Message); } _powershell = null; }
            
            // Null out event handlers to break reference cycles and allow GC
            OnError = null;
            OnWarning = null;
            OnVerbose = null;
            OnDebug = null;
            OnHost = null;
            OnHostBatch = null;
            OnProgress = null;
            OnPipelineOutput = null;
            OnComplete = null;
            OnCancelled = null;
            OnWindowTitle = null;
            OnQueued = null;
            OnStarted = null;
            OnFrameworkError = null;
            
            IsRunning = false;
            
            // Suppress finalizer since we cleaned up
            GC.SuppressFinalize(this);
        }
        
        // MarshalToUi, RaiseOn*, Drain* methods moved to AsyncExecutor.Routing.cs
    }
    
    // StreamingHost classes moved to StreamingHost.cs


    // Converters moved to Converters.cs
}