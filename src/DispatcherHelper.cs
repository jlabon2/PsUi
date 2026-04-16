using System;
using System.Diagnostics;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;

namespace PsUi
{
    // Helpers for UI thread dispatching without freezing
    public static class DispatcherHelper
    {
        public static void InvokeOnUI(Action action)
        {
            if (action == null) return;

            if (Application.Current != null && Application.Current.Dispatcher != null && 
                !Application.Current.Dispatcher.HasShutdownStarted &&
                Application.Current.Dispatcher.Thread.IsAlive)
            {
                if (Application.Current.Dispatcher.CheckAccess())
                {
                    try
                    {
                        action();
                    }
                    catch (TaskCanceledException ex) { Debug.WriteLine("[DispatcherHelper] Task canceled: " + ex.Message); }
                    catch (OperationCanceledException ex) { Debug.WriteLine("[DispatcherHelper] Operation canceled: " + ex.Message); }
                    catch (ObjectDisposedException ex) { Debug.WriteLine("[DispatcherHelper] Dispatcher disposed: " + ex.Message); }
                    catch (Exception ex) { Debug.WriteLine("[DispatcherHelper] Unexpected error in InvokeOnUI: " + ex.Message); }
                }
                else
                {
                    try
                    {
                        // Use timeout to avoid hanging if dispatcher dies between check and invoke
                        Application.Current.Dispatcher.Invoke(action, TimeSpan.FromSeconds(5));
                    }
                    catch (TimeoutException ex) 
                    { 
                        // INTENTIONAL: If dispatcher times out (5s), window is likely dying or hung.
                        // Running directly may cause cross-thread exception, but that's preferable to
                        // hanging indefinitely. The catch swallows any such exception - this is cleanup code.
                        Debug.WriteLine("[DispatcherHelper] Invoke timed out, running directly: " + ex.Message);
                        try { action(); } catch { /* swallow - best effort on dying window */ }
                    }
                    catch (TaskCanceledException ex) { Debug.WriteLine("[DispatcherHelper] Task canceled: " + ex.Message); }
                    catch (OperationCanceledException ex) { Debug.WriteLine("[DispatcherHelper] Operation canceled: " + ex.Message); }
                    catch (ObjectDisposedException ex) { Debug.WriteLine("[DispatcherHelper] Dispatcher disposed: " + ex.Message); }
                    catch (Exception ex) { Debug.WriteLine("[DispatcherHelper] Unexpected error in InvokeOnUI: " + ex.Message); }
                }
            }
            else
            {
                // INTENTIONAL: No dispatcher = no WPF application running (console mode, tests, or
                // app shutdown). Running directly works for non-UI operations. UI operations will
                // throw, which is correct - caller shouldn't be touching UI without a dispatcher.
                // AsyncExecutor always has its own dispatcher reference and won't hit this path.
                try
                {
                    action();
                }
                catch (TaskCanceledException ex) { Debug.WriteLine("[DispatcherHelper] Task canceled (fallback): " + ex.Message); }
                catch (OperationCanceledException ex) { Debug.WriteLine("[DispatcherHelper] Operation canceled (fallback): " + ex.Message); }
                catch (ObjectDisposedException ex) { Debug.WriteLine("[DispatcherHelper] Dispatcher disposed (fallback): " + ex.Message); }
                catch (Exception ex) { Debug.WriteLine("[DispatcherHelper] Unexpected error in InvokeOnUI fallback: " + ex.Message); }
            }
        }

        public static void BeginInvokeOnUI(Action action, DispatcherPriority priority = DispatcherPriority.Normal)
        {
            if (action == null) return;

            if (Application.Current != null && Application.Current.Dispatcher != null &&
                !Application.Current.Dispatcher.HasShutdownStarted &&
                Application.Current.Dispatcher.Thread.IsAlive)
            {
                try
                {
                    Application.Current.Dispatcher.BeginInvoke(action, priority);
                }
                catch (TaskCanceledException ex) { Debug.WriteLine("[DispatcherHelper] Task canceled in BeginInvokeOnUI: " + ex.Message); }
                catch (OperationCanceledException ex) { Debug.WriteLine("[DispatcherHelper] Operation canceled in BeginInvokeOnUI: " + ex.Message); }
                catch (ObjectDisposedException ex) { Debug.WriteLine("[DispatcherHelper] Dispatcher disposed in BeginInvokeOnUI: " + ex.Message); }
                catch (Exception ex) { Debug.WriteLine("[DispatcherHelper] Unexpected error in BeginInvokeOnUI: " + ex.Message); }
            }
            else
            {
                // Non-blocking fallback
                try
                {
                    Task.Run(action);
                }
                catch (TaskCanceledException ex) { Debug.WriteLine("[DispatcherHelper] Task canceled in BeginInvokeOnUI fallback: " + ex.Message); }
                catch (OperationCanceledException ex) { Debug.WriteLine("[DispatcherHelper] Operation canceled in BeginInvokeOnUI fallback: " + ex.Message); }
                catch (Exception ex) { Debug.WriteLine("[DispatcherHelper] Unexpected error in BeginInvokeOnUI fallback: " + ex.Message); }
            }
        }
    }
}