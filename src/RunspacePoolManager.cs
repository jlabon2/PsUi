using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Management.Automation.Runspaces;
using System.Security;
using System.Threading;

namespace PsUi
{
    // Manages a pool of pre-warmed runspaces for fast async execution.
    //
    // Pool needs a custom PSHost to intercept Write-Host/Write-Progress. PSHost and PSHostUserInterface
    // are abstract classes with ~15 members each - impractical with PS's limited class syntax.
    //
    // Runspaces are recycled instead of created/destroyed per button click, cutting latency from
    // ~50-100ms to sub-10ms. MinimalHost routes output through AsyncExecutor.CurrentExecutor (thread-local).
    //
    // Pool health: The Pool getter checks RunspacePoolStateInfo before returning. If the pool
    // enters a Broken/Closed state (e.g. from a script that corrupted runspace state), it gets
    // recycled automatically. For critical scenarios, use dedicated runspaces via
    // -NoInteractive:$false which creates fresh runspaces per execution.
    public static class RunspacePoolManager
    {
        private static readonly object _lock = new object();
        private static RunspacePool _pool;
        private static bool _isInitialized;
        
        private const int MinRunspaces = 1;
        private const int MaxRunspaces = 8;

        public static RunspacePool Pool
        {
            get
            {
                EnsureInitialized();
                
                // Capture locally to avoid race with concurrent Reset()/Shutdown()
                var pool = _pool;
                if (pool == null) return null;
                
                // Verify pool hasn't entered a broken/closed state
                if (pool.RunspacePoolStateInfo.State != RunspacePoolState.Opened)
                {
                    lock (_lock)
                    {
                        if (_pool != null && _pool.RunspacePoolStateInfo.State != RunspacePoolState.Opened)
                        {
                            Console.Error.WriteLine("[PsUi] RunspacePool in state " + _pool.RunspacePoolStateInfo.State + ", recycling");
                            Shutdown();
                            EnsureInitialized();
                        }
                    }
                }
                
                return _pool;
            }
        }

        public static void EnsureInitialized()
        {
            if (_isInitialized) return;
            
            lock (_lock)
            {
                if (_isInitialized) return;
                
                var iss = InitialSessionState.CreateDefault();
                _pool = RunspaceFactory.CreateRunspacePool(MinRunspaces, MaxRunspaces, iss, new MinimalHost());
                _pool.ApartmentState = ApartmentState.STA;
                _pool.ThreadOptions = PSThreadOptions.ReuseThread;
                _pool.Open();
                _isInitialized = true;
            }
        }

        /// <summary>
        /// Tears down and recreates the pool. Call if scripts have corrupted runspace state.
        /// </summary>
        public static void Reset()
        {
            Shutdown();
            EnsureInitialized();
        }

        public static void Shutdown()
        {
            lock (_lock)
            {
                if (_pool == null) return;
                
                try { _pool.Close(); }
                catch (Exception ex) { DebugHelper.LogException("RUNSPACE", "Pool.Close", ex); }
                
                try { _pool.Dispose(); }
                catch (Exception ex) { DebugHelper.LogException("RUNSPACE", "Pool.Dispose", ex); }
                
                _pool = null;
                _isInitialized = false;
            }
        }
    }
    
    // Minimal PSHost for pooled runspaces - routes output through AsyncExecutor.CurrentExecutor (thread-local)
    public class MinimalHost : PSHost
    {
        private readonly MinimalHostUI _ui = new MinimalHostUI();
        private readonly Guid _instanceId = Guid.NewGuid();
        
        public override PSHostUserInterface UI { get { return _ui; } }
        public override string Name { get { return "PsUi MinimalHost"; } }
        public override Version Version { get { return new Version(1, 0); } }
        public override Guid InstanceId { get { return _instanceId; } }
        public override CultureInfo CurrentCulture { get { return Thread.CurrentThread.CurrentCulture; } }
        public override CultureInfo CurrentUICulture { get { return Thread.CurrentThread.CurrentUICulture; } }
        
        public override void SetShouldExit(int exitCode) { }
        public override void EnterNestedPrompt() { }
        public override void ExitNestedPrompt() { }
        public override void NotifyBeginApplication() { }
        public override void NotifyEndApplication() { }
    }
    
    // Minimal PSHostUserInterface - Write methods route through AsyncExecutor.CurrentExecutor when available
    // Interactive input returns defaults - use dedicated runspaces for interactive scripts
    public class MinimalHostUI : PSHostUserInterface
    {
        private readonly MinimalRawUI _rawUI = new MinimalRawUI();
        
        public override PSHostRawUserInterface RawUI { get { return _rawUI; } }
        
        // Route Write calls through thread-local executor for Out-Host support
        public override void Write(string value)
        {
            var executor = AsyncExecutor.CurrentExecutor;
            if (executor != null && !string.IsNullOrEmpty(value))
            {
                executor.RaiseOnHost(value, null, true);
            }
        }
        
        public override void WriteLine(string value)
        {
            var executor = AsyncExecutor.CurrentExecutor;
            if (executor != null)
            {
                executor.RaiseOnHost(value ?? string.Empty);
            }
        }
        
        public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value)
        {
            var executor = AsyncExecutor.CurrentExecutor;
            if (executor != null && !string.IsNullOrEmpty(value))
            {
                executor.RaiseOnHost(value, foregroundColor, true);
            }
        }
        
        // Error/Warning/Verbose/Debug are captured via ps.Streams handlers - no-op here
        public override void WriteErrorLine(string value) { }
        public override void WriteWarningLine(string value) { }
        public override void WriteVerboseLine(string value) { }
        public override void WriteDebugLine(string value) { }
        
        public override void WriteProgress(long sourceId, ProgressRecord record)
        {
            var executor = AsyncExecutor.CurrentExecutor;
            if (executor != null)
            {
                executor.RaiseOnProgress(record);
            }
        }
        
        // Interactive input - route through executor if available, otherwise return defaults
        public override string ReadLine() 
        { 
            var executor = AsyncExecutor.CurrentExecutor;
            if (executor != null)
            {
                return executor.RaiseOnReadLine(null);
            }
            return string.Empty; 
        }
        
        public override SecureString ReadLineAsSecureString() 
        { 
            var executor = AsyncExecutor.CurrentExecutor;
            if (executor != null)
            {
                return executor.RaiseOnReadLineAsSecureString(null);
            }
            return new SecureString(); 
        }
        
        public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions)
        {
            var executor = AsyncExecutor.CurrentExecutor;
            if (executor != null)
            {
                return executor.RaiseOnPrompt(caption, message, descriptions);
            }
            return new Dictionary<string, PSObject>();
        }
        
        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice)
        {
            var executor = AsyncExecutor.CurrentExecutor;
            if (executor != null)
            {
                return executor.RaiseOnPromptForChoice(caption, message, choices, defaultChoice);
            }
            return defaultChoice;
        }
        
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName)
        {
            var executor = AsyncExecutor.CurrentExecutor;
            if (executor != null)
            {
                return executor.RaiseOnPromptForCredential(caption, message, userName, targetName);
            }
            return null;
        }
        
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes allowedCredentialTypes, PSCredentialUIOptions options)
        {
            var executor = AsyncExecutor.CurrentExecutor;
            if (executor != null)
            {
                return executor.RaiseOnPromptForCredential(caption, message, userName, targetName);
            }
            return null;
        }
    }
    
    public class MinimalRawUI : PSHostRawUserInterface
    {
        private Size _bufferSize = new Size(120, 50);
        private Size _windowSize = new Size(120, 50);
        
        public override ConsoleColor BackgroundColor { get; set; }
        public override ConsoleColor ForegroundColor { get; set; }
        public override Size BufferSize { get { return _bufferSize; } set { _bufferSize = value; } }
        public override Coordinates CursorPosition { get; set; }
        public override int CursorSize { get; set; }
        public override Size MaxPhysicalWindowSize { get { return new Size(int.MaxValue, int.MaxValue); } }
        public override Size MaxWindowSize { get { return new Size(int.MaxValue, int.MaxValue); } }
        public override Size WindowSize { get { return _windowSize; } set { _windowSize = value; } }
        public override Coordinates WindowPosition { get; set; }
        public override string WindowTitle { get; set; }
        public override bool KeyAvailable { get { return false; } }
        
        public override KeyInfo ReadKey(ReadKeyOptions options)
        {
            // Route through the executor's key capture dialog if available
            var executor = AsyncExecutor.CurrentExecutor;
            if (executor != null)
            {
                return executor.RaiseOnReadKey(options);
            }
            // No executor - return Enter key (non-interactive mode)
            return new KeyInfo(13, '\r', ControlKeyStates.NumLockOn, true);
        }
        
        public override void FlushInputBuffer() { }
        public override BufferCell[,] GetBufferContents(Rectangle rectangle) { return new BufferCell[0, 0]; }
        public override void ScrollBufferContents(Rectangle source, Coordinates destination, Rectangle clip, BufferCell fill) { }
        public override void SetBufferContents(Rectangle rectangle, BufferCell fill) { }
        public override void SetBufferContents(Coordinates origin, BufferCell[,] contents) { }
    }
}
