using System;
using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using System.Windows.Data;
using System.Windows.Threading;

namespace PsUi
{
    // Thread-safe ObservableCollection using WPFs built-in synchronization.
    // Background threads can add/remove items without crashing the binding.
    public class AsyncObservableCollection<T> : ObservableCollection<T>
    {
        private readonly object _lock = new object();
        private Dispatcher _dispatcher;

        // Must be created on the UI thread (or provide dispatcher explicitly)
        public AsyncObservableCollection()
        {
            // Get the UI dispatcher - prefer Application.Current if available (guaranteed UI thread)
            if (System.Windows.Application.Current != null && System.Windows.Application.Current.Dispatcher != null)
            {
                _dispatcher = System.Windows.Application.Current.Dispatcher;
            }
            else
            {
                _dispatcher = Dispatcher.CurrentDispatcher;
            }
            
            // Enable WPF collection synchronization
            BindingOperations.EnableCollectionSynchronization(this, _lock);
            Debug.WriteLine("AsyncObservableCollection created with synchronization, thread: " + _dispatcher.Thread.ManagedThreadId);
        }

        // Use this when creating from a background thread
        public AsyncObservableCollection(Dispatcher uiDispatcher)
        {
            if (uiDispatcher == null) throw new ArgumentNullException("uiDispatcher");
            _dispatcher = uiDispatcher;
            
            // Enable WPF collection synchronization
            BindingOperations.EnableCollectionSynchronization(this, _lock);
            Debug.WriteLine("AsyncObservableCollection created with explicit dispatcher and synchronization, thread: " + _dispatcher.Thread.ManagedThreadId);
        }
        
        // Expose the lock for batch operations
        public object SyncRoot { get { return _lock; } }

        // Switch to current threads dispatcher (call from UI thread)
        public void UpdateDispatcher()
        {
            _dispatcher = Dispatcher.CurrentDispatcher;
            Debug.WriteLine("AsyncObservableCollection dispatcher updated to thread: " + System.Threading.Thread.CurrentThread.ManagedThreadId);
        }
        
        public new void Add(T item)
        {
            lock (_lock) { base.Add(item); }
        }
        
        public new void Insert(int index, T item)
        {
            lock (_lock) { base.Insert(index, item); }
        }
        
        public new bool Remove(T item)
        {
            lock (_lock) { return base.Remove(item); }
        }
        
        public new void RemoveAt(int index)
        {
            lock (_lock) { base.RemoveAt(index); }
        }
        
        public new void Clear()
        {
            lock (_lock) { base.Clear(); }
        }
        
        public new T this[int index]
        {
            get { lock (_lock) { return base[index]; } }
            set { lock (_lock) { base[index] = value; } }
        }

        protected override void OnCollectionChanged(NotifyCollectionChangedEventArgs e)
        {
            // EnableCollectionSynchronization handles the lock, but we still need UI thread
            if (_dispatcher.CheckAccess())
            {
                base.OnCollectionChanged(e);
            }
            else
            {
                try
                {
                    _dispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(() => {
                        try { base.OnCollectionChanged(e); }
                        catch (InvalidOperationException) { /* collection state changed - ignore */ }
                    }));
                }
                catch (InvalidOperationException)
                {
                    // Dispatcher shut down between check and invoke - ignore
                }
            }
        }

        protected override void OnPropertyChanged(PropertyChangedEventArgs e)
        {
            if (_dispatcher.CheckAccess())
            {
                base.OnPropertyChanged(e);
            }
            else
            {
                try
                {
                    _dispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(() => base.OnPropertyChanged(e)));
                }
                catch (InvalidOperationException)
                {
                    // Dispatcher shut down - ignore
                }
            }
        }
    }
}