using System;
using System.Windows.Threading;

namespace PsUi
{
    // UI-thread debouncer using DispatcherTimer. Only use for UI operations.
    // For background debouncing, youd need a Task.Delay + CancellationToken approach instead.
    public class UiDebouncer : IDisposable
    {
        private DispatcherTimer _timer;
        private Action _action;
        private bool _disposed;

        public void Debounce(int milliseconds, Action action)
        {
            if (_disposed) return;
            
            _action = action;
            if (_timer == null)
            {
                _timer = new DispatcherTimer();
                _timer.Tick += OnTimerTick;
            }
            _timer.Interval = TimeSpan.FromMilliseconds(milliseconds);
            _timer.Stop(); 
            _timer.Start();
        }
        
        private void OnTimerTick(object sender, EventArgs e)
        {
            _timer.Stop();
            if (_action != null) _action();
        }
        
        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            
            if (_timer != null)
            {
                _timer.Stop();
                _timer.Tick -= OnTimerTick;
                _timer = null;
            }
            _action = null;
        }
    }
}