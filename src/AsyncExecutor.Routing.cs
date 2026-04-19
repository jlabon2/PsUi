using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
using System.Windows.Threading;

namespace PsUi
{
    // Thrown when UI dispatch times out - distinguishes from legitimate null returns
    public class UiDispatchTimeoutException : TimeoutException
    {
        public UiDispatchTimeoutException() : base("UI dispatch timed out after 5 minutes - the window may be unresponsive or closed.") { }
        public UiDispatchTimeoutException(string message) : base(message) { }
    }

    // Output routing: Write-Host batching, error/progress handling, interactive prompts.
    public partial class AsyncExecutor
    {
        // Drain queued host records for UI timer consumption
        public List<HostOutputRecord> DrainHostQueue(int maxItems = 100)
        {
            var result = new List<HostOutputRecord>();
            HostOutputRecord item;
            int count = 0;
            while (count < maxItems && _hostQueue.TryDequeue(out item))
            {
                result.Add(item);
                count++;
            }
            return result;
        }

        public int HostQueueCount { get { return _hostQueue.Count; } }

        // Drain queued pipeline objects for UI timer consumption
        public List<object> DrainPipelineQueue(int maxItems = 100)
        {
            var result = new List<object>();
            object item;
            int count = 0;
            while (count < maxItems && _pipelineQueue.TryDequeue(out item))
            {
                result.Add(item);
                count++;
            }
            return result;
        }

        public int PipelineQueueCount { get { return _pipelineQueue.Count; } }

        // Fire-and-forget UI thread dispatch. Uses BeginInvoke to avoid blocking.
        private void MarshalToUi(Action action)
        {
            if (action == null) return;
            
            // Capture references atomically to avoid race with Cancel()
            bool disposed = _disposed;
            var cts = _cts;
            var dispatcher = _uiDispatcher;
            
            if (disposed) return;
            if (cts != null && cts.IsCancellationRequested) return;

            try
            {
                if (dispatcher != null)
                {
                    dispatcher.BeginInvoke(action);
                }
                else
                {
                    DispatcherHelper.BeginInvokeOnUI(action);
                }
            }
            catch (Exception ex) { Debug.WriteLine("AsyncExecutor MarshalToUi Error: " + ex.Message); }
        }

        // Blocking UI dispatch that returns a result. Needed for Read-Host, Get-Credential.
        // Uses BeginInvoke + ManualResetEvent to avoid deadlock with modal dialogs.
        private T MarshalToUiWait<T>(Func<T> action)
        {
            if (action == null) return default(T);

            try
            {
                Dispatcher dispatcher = _uiDispatcher;
                if (dispatcher == null) dispatcher = CaptureDispatcher();

                if (dispatcher == null)
                {
                    // No dispatcher available - execute directly (may fail if UI required)
                    return action();
                }
                
                // If already on UI thread, execute directly to avoid deadlock
                if (dispatcher.CheckAccess())
                {
                    return action();
                }
                
                // Use BeginInvoke + wait to avoid deadlock with modal dialogs
                // Dispatcher.Invoke would deadlock if UI thread shows ShowDialog
                T result = default(T);
                Exception caughtException = null;
                
                using (var waitHandle = new System.Threading.ManualResetEventSlim(false))
                {
                    dispatcher.BeginInvoke(new Action(() =>
                    {
                        try
                        {
                            result = action();
                        }
                        catch (Exception ex)
                        {
                            caughtException = ex;
                        }
                        finally
                        {
                            waitHandle.Set();
                        }
                    }));
                    
                    // Block until UI op finishes, but wake up quickly if cancelled/disposed.
                    // Poll every 250ms so window close (which sets _disposed) unblocks within ~250ms
                    // instead of hanging for the full 5-minute timeout.
                    bool signaled = false;
                    var deadline = DateTime.UtcNow.AddMinutes(5);
                    while (!signaled && DateTime.UtcNow < deadline)
                    {
                        if (_disposed) break;
                        var cts = _cts;
                        if (cts != null && cts.IsCancellationRequested) break;
                        signaled = waitHandle.Wait(250);
                    }

                    if (!signaled)
                    {
                        // Window was closed/cancelled, or genuine 5-min timeout
                        if (_disposed)
                            return default(T);
                        throw new UiDispatchTimeoutException();
                    }
                }
                
                if (caughtException != null)
                {
                    if (DebugMode) System.Console.WriteLine("MarshalToUiWait action failed: " + caughtException.Message);
                    return default(T);
                }
                
                return result;
            }
            catch (UiDispatchTimeoutException)
            {
                // Let timeout exceptions propagate - caller needs to handle this distinctly from null
                throw;
            }
            catch (Exception ex)
            {
                if (DebugMode) System.Console.WriteLine("MarshalToUiWait failed: " + ex.Message);
                return default(T);
            }
        }

        // Route Write-Host with optional batching. Three modes: queue (polled), batch, individual.
        public void RaiseOnHost(string value)
        {
            RaiseOnHost(value, null, null, false);
        }

        public void RaiseOnHost(string value, ConsoleColor? foregroundColor)
        {
            RaiseOnHost(value, foregroundColor, null, false);
        }

        public void RaiseOnHost(string value, ConsoleColor? foregroundColor, bool noNewLine)
        {
            RaiseOnHost(value, foregroundColor, null, noNewLine);
        }

        public void RaiseOnHost(string value, ConsoleColor? foregroundColor, ConsoleColor? backgroundColor, bool noNewLine)
        {
            // Local capture prevents TOCTOU race if _cts is disposed between the null check and property read
            var cts = _cts;
            if (cts != null && cts.IsCancellationRequested) return;
            var record = new HostOutputRecord(value, foregroundColor, backgroundColor, noNewLine);

            // Queue mode: add to queue for UI timer to poll
            if (UseQueueMode)
            {
                _hostQueue.Enqueue(record);
                if (DebugMode)
                {
                    string preview = value != null && value.Length > 30 ? value.Substring(0, 30) : value;
                    System.Console.WriteLine("Host queued: " + _hostQueue.Count + " - " + preview);
                }

                // Backpressure throttling when queue is getting large
                int queueSize = _hostQueue.Count;
                if (queueSize > 500)
                {
                    // Aggressive backpressure when queue is very large
                    System.Threading.Thread.Sleep(5);
                }
                else if (queueSize > 100)
                {
                    // Light backpressure when queue is moderately full
                    System.Threading.Thread.Sleep(1);
                }
                return;
            }

            // Batch mode: accumulate records and flush periodically
            if (OnHostBatch != null)
            {
                bool shouldFlush = false;
                List<HostOutputRecord> toFlush = null;

                lock (_hostBatchLock)
                {
                    _hostBatch.Add(record);
                    var now = DateTime.Now;
                    var elapsed = (now - _lastHostFlush).TotalMilliseconds;

                    if (_hostBatch.Count >= HOST_BATCH_SIZE || elapsed >= HOST_FLUSH_MS)
                    {
                        toFlush = _hostBatch;
                        _hostBatch = new List<HostOutputRecord>();
                        _lastHostFlush = now;
                        shouldFlush = true;
                    }
                }

                if (shouldFlush && toFlush != null && toFlush.Count > 0)
                {
                    MarshalToUi(delegate { if (OnHostBatch != null) OnHostBatch(toFlush); });
                }
            }
            else
            {
                // Individual message mode (legacy)
                MarshalToUi(delegate { if (OnHost != null) OnHost(record); });
            }
        }

        internal void FlushHostBatch()
        {
            List<HostOutputRecord> toFlush = null;
            lock (_hostBatchLock)
            {
                if (_hostBatch.Count > 0)
                {
                    toFlush = _hostBatch;
                    _hostBatch = new List<HostOutputRecord>();
                    _lastHostFlush = DateTime.Now;
                }
            }

            if (toFlush != null && toFlush.Count > 0 && OnHostBatch != null)
            {
                MarshalToUi(delegate { if (OnHostBatch != null) OnHostBatch(toFlush); });
            }
        }

        internal void RaiseOnError(PSErrorRecord errorRecord)
        {
            var cts = _cts;
            if (cts != null && cts.IsCancellationRequested) return;
            MarshalToUi(delegate { if (OnError != null) OnError(errorRecord); });
        }

        internal void RaiseOnError(ErrorRecord error)
        {
            RaiseOnError(PSErrorRecord.FromErrorRecord(error));
        }

        internal void RaiseOnError(Exception ex)
        {
            RaiseOnError(PSErrorRecord.FromException(ex));
        }

        internal void RaiseOnError(string message)
        {
            RaiseOnError(new PSErrorRecord { Message = message, Timestamp = DateTime.Now, Category = "OperationalError" });
        }

        internal void RaiseOnWarning(string value)
        {
            var cts = _cts;
            if (cts != null && cts.IsCancellationRequested) return;
            MarshalToUi(delegate { if (OnWarning != null) OnWarning(value); });
        }

        internal void RaiseOnVerbose(string value)
        {
            var cts = _cts;
            if (cts != null && cts.IsCancellationRequested) return;
            MarshalToUi(delegate { if (OnVerbose != null) OnVerbose(value); });
        }

        internal void RaiseOnDebug(string value)
        {
            var cts = _cts;
            if (cts != null && cts.IsCancellationRequested) return;
            MarshalToUi(delegate { if (OnDebug != null) OnDebug(value); });
        }

        // Progress with throttling - always fires for completion, otherwise throttled
        internal void RaiseOnProgress(ProgressRecord record)
        {
            if (OnProgress == null) return;

            lock (_progressLock)
            {
                // Always fire for completion, otherwise throttle
                bool isComplete = record.PercentComplete == 100 || record.RecordType == ProgressRecordType.Completed;
                bool throttleElapsed = (DateTime.Now - _lastProgressUpdate).TotalMilliseconds > PROGRESS_THROTTLE_MS;

                if (isComplete || throttleElapsed)
                {
                    _lastProgressUpdate = DateTime.Now;

                    // Clone record to avoid cross-thread issues
                    var clone = new ProgressRecord(record.ActivityId, record.Activity, record.StatusDescription);
                    clone.PercentComplete = record.PercentComplete;
                    clone.RecordType = record.RecordType;
                    clone.CurrentOperation = record.CurrentOperation;
                    clone.ParentActivityId = record.ParentActivityId;
                    clone.SecondsRemaining = record.SecondsRemaining;

                    MarshalToUi(delegate { if (OnProgress != null) OnProgress(clone); });
                }
            }
        }

        // Blocks background thread until user provides input via UI
        public string RaiseOnReadLine(string prompt = null)
        {
            if (InputProvider == null) return string.Empty;

            return MarshalToUiWait<string>(delegate
            {
                try
                {
                    object result = InputProvider.InvokeReturnAsIs(new object[] { prompt });
                    if (result is PSObject) result = ((PSObject)result).BaseObject;
                    return result as string;
                }
                catch (Exception ex)
                {
                    if (DebugMode) System.Console.WriteLine("RaiseOnReadLine failed: " + ex.Message);
                    return string.Empty;
                }
            });
        }

        // Read-Host -AsSecureString handler
        public SecureString RaiseOnReadLineAsSecureString(string prompt = null)
        {
            if (SecureInputProvider == null) return new SecureString();

            return MarshalToUiWait<SecureString>(delegate
            {
                try
                {
                    object result = SecureInputProvider.InvokeReturnAsIs(new object[] { prompt });
                    if (result is PSObject) result = ((PSObject)result).BaseObject;
                    return result as SecureString;
                }
                catch (Exception ex)
                {
                    if (DebugMode) System.Console.WriteLine("RaiseOnReadLineAsSecureString failed: " + ex.Message);
                    return new SecureString();
                }
            });
        }

        // $host.UI.PromptForChoice handler - returns selected index
        public int RaiseOnPromptForChoice(string caption, string message, System.Collections.ObjectModel.Collection<ChoiceDescription> choices, int defaultChoice)
        {
            if (ChoiceProvider == null) return defaultChoice;

            return MarshalToUiWait<int>(delegate
            {
                try
                {
                    object result = ChoiceProvider.InvokeReturnAsIs(new object[] { caption, message, choices, defaultChoice });
                    if (result is PSObject) result = ((PSObject)result).BaseObject;
                    if (result is int) return (int)result;

                    int parsed;
                    if (result != null && int.TryParse(result.ToString(), out parsed)) return parsed;
                    return defaultChoice;
                }
                catch (Exception ex)
                {
                    if (DebugMode) System.Console.WriteLine("RaiseOnPromptForChoice failed: " + ex.Message);
                    return defaultChoice;
                }
            });
        }

        // Get-Credential handler
        public PSCredential RaiseOnPromptForCredential(string caption, string message, string userName, string targetName)
        {
            if (CredentialProvider == null) return null;

            return MarshalToUiWait<PSCredential>(delegate
            {
                try
                {
                    object result = CredentialProvider.InvokeReturnAsIs(new object[] { caption, message, userName, targetName });
                    if (result is PSObject) result = ((PSObject)result).BaseObject;
                    return result as PSCredential;
                }
                catch (Exception)
                {
                    if (DebugMode) System.Console.WriteLine("RaiseOnPromptForCredential failed (details suppressed for security)");
                    return null;
                }
            });
        }

        // $host.UI.Prompt handler for multi-field dialogs
        public Dictionary<string, PSObject> RaiseOnPrompt(string caption, string message, System.Collections.ObjectModel.Collection<FieldDescription> descriptions)
        {
            if (PromptProvider == null) return new Dictionary<string, PSObject>();

            return MarshalToUiWait<Dictionary<string, PSObject>>(delegate
            {
                try
                {
                    object result = PromptProvider.InvokeReturnAsIs(new object[] { caption, message, descriptions });
                    if (result is PSObject) result = ((PSObject)result).BaseObject;
                    return result as Dictionary<string, PSObject>;
                }
                catch (Exception ex)
                {
                    if (DebugMode) System.Console.WriteLine("RaiseOnPrompt failed: " + ex.Message);
                    return new Dictionary<string, PSObject>();
                }
            });
        }

        // $host.UI.RawUI.ReadKey handler - shows key capture dialog on its own STA thread.
        // Doesnt marshal to main UI thread since the dialog handles its own threading.
        public KeyInfo RaiseOnReadKey(ReadKeyOptions options)
        {
            // Dialog runs on its own STA thread, so we call directly from background thread
            // This keeps the main UI thread responsive
            // Note: PipelineStoppedException is NOT caught here - it propagates to stop the script
            return KeyCaptureDialog.ShowAndCapture("Press any key...");
        }

        // Clear-Host handler - clears the output panel
        public void RaiseOnClearHost()
        {
            if (ClearHostProvider == null) return;

            MarshalToUiWait<object>(delegate
            {
                try
                {
                    ClearHostProvider.InvokeReturnAsIs(new object[0]);
                }
                catch (Exception ex)
                {
                    if (DebugMode) System.Console.WriteLine("RaiseOnClearHost failed: " + ex.Message);
                }
                return null;
            });
        }
        
        // WindowTitle setter handler - used for output window subtitles
        public void RaiseOnWindowTitle(string title)
        {
            var handler = OnWindowTitle;
            if (handler != null)
            {
                MarshalToUi(delegate { handler(title); });
            }
        }
        
        // Pause command - shows a "click to continue" overlay
        public void RaiseOnPause()
        {
            if (PauseProvider == null) return;

            MarshalToUiWait<object>(delegate
            {
                try
                {
                    PauseProvider.InvokeReturnAsIs(new object[0]);
                }
                catch (Exception ex)
                {
                    if (DebugMode) System.Console.WriteLine("RaiseOnPause failed: " + ex.Message);
                }
                return null;
            });
        }
    }
}
