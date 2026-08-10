using System;
using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using System.Threading;
using System.Windows.Data;
using System.Windows.Threading;

namespace PsUi
{
    // Thread-safe ObservableCollection using WPFs built-in synchronization.
    // Background threads can add/remove items without crashing the binding.
    public class AsyncObservableCollection<T> : ObservableCollection<T>
    {
        private readonly object _lock = new object();

        // UpdateDispatcher() writes this from the UI thread while worker threads read it via CheckAccess(). 
        // Reference assignment is atomic on the CLR, but without volatile the JIT will happily cache the read indefinitely on a worker thread.
        private volatile Dispatcher _dispatcher;

        // Must be created on the UI thread (or provide a Dispatcher explicitly)
        public AsyncObservableCollection()
        {
            // CurrentDispatcher, not Application.Current.Dispatcher, that one pins to the first window's STA thread, dead or not. The MTA check below only catches raw runspace threads. 
            // PsUi's own action runspaces are STA and slip through, minting a Dispatcher that never runs its message loop. The mutators cover that leg by failing over when the pinned Dispatcher's thread are torn down (see ShutdownFallback).
            if (Thread.CurrentThread.GetApartmentState() != ApartmentState.STA)
            {
                throw new InvalidOperationException(
                    "AsyncObservableCollection() must run on an STA thread (the window's dispatcher thread). "
                    + "From a background runspace, either call Add-UiDataGridItem / Set-UiDataGridItems on an existing grid, "
                    + "construct the collection on the window's thread before the action runs, "
                    + "or use the AsyncObservableCollection(Dispatcher) overload with the window's Dispatcher.");
            }

            _dispatcher = Dispatcher.CurrentDispatcher;

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

        // Seed overloads. Non-generic IEnumerable so an ArrayList or int[] binds without a cast to IEnumerable<object>. Mutating Items directly and single Reset keeps a 10k row seed at one notification instead of 10k. Efficient!
        public AsyncObservableCollection(System.Collections.IEnumerable seed) : this()
        {
            SeedFrom(seed);
        }

        public AsyncObservableCollection(System.Collections.IEnumerable seed, Dispatcher uiDispatcher) : this(uiDispatcher)
        {
            SeedFrom(seed);
        }

        private void SeedFrom(System.Collections.IEnumerable seed)
        {
            if (seed == null) { return; }
            lock (_lock)
            {
                CheckReentrancy();
                foreach (object item in seed) { Items.Add((T)item); }
            }
            OnPropertyChanged(new PropertyChangedEventArgs("Count"));
            OnPropertyChanged(new PropertyChangedEventArgs("Item[]"));
            OnCollectionChanged(new NotifyCollectionChangedEventArgs(NotifyCollectionChangedAction.Reset));
        }

        // Mirror to the user's original collection so their $list still sees helper adds.
        // ArrayList / List<T> are one way. An INotifyCollectionChanged mirror routes back via OnMirrorChanged so outside mutations drive the grid. Loop rules inline at touchpoints.
        private System.Collections.IList _mirror;
        private bool _suppressMirrorEvent;
        private bool _suppressMirrorPush;

        public void AttachMirror(System.Collections.IList mirror)
        {
            lock (_lock)
            {
                // Unhook any previous mirror's CollectionChanged to prevent double fire.
                if (_mirror != null)
                {
                    var prevInpc = _mirror as System.Collections.Specialized.INotifyCollectionChanged;
                    if (prevInpc != null)
                    {
                        prevInpc.CollectionChanged -= OnMirrorChanged;
                    }
                }

                _mirror = mirror;

                if (mirror != null)
                {
                    var inpc = mirror as System.Collections.Specialized.INotifyCollectionChanged;
                    if (inpc != null)
                    {
                        inpc.CollectionChanged += OnMirrorChanged;
                    }
                }
            }
        }

        // The mirror's CollectionChanged delegate pins this AsyncObservableCollection alive for as long as the user's mirror lives. New-UiDataGrid calls this from the window's Closed handler to cut it out of the GC root chain.
        public void DetachMirror()
        {
            lock (_lock)
            {
                if (_mirror == null) { return; }
                var inpc = _mirror as System.Collections.Specialized.INotifyCollectionChanged;
                if (inpc != null)
                {
                    inpc.CollectionChanged -= OnMirrorChanged;
                }
                _mirror = null;
            }
        }

        private void OnMirrorChanged(object sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e)
        {
            // Marshal to the UI thread before taking _lock. Holding it while InsertItem dispatches deadlocks the moment WPF's EnableCollectionSynchronization callback wants _lock for a bound iteration... every off UI mirror mutation hit this.
            if (!_dispatcher.CheckAccess())
            {
                // A dead UI thread blocks Invoke forever without throwing. The window it drew is gone, so drop (same treatment as the shutdown catches below).
                if (_dispatcher.HasShutdownStarted || !_dispatcher.Thread.IsAlive)
                {
                    Debug.WriteLine("OnMirrorChanged: dispatcher unusable, drop");
                    return;
                }
                object capSender = sender;
                System.Collections.Specialized.NotifyCollectionChangedEventArgs capArgs = e;
                try { _dispatcher.Invoke(new Action(() => OnMirrorChanged(capSender, capArgs))); }
                catch (InvalidOperationException) { Debug.WriteLine("OnMirrorChanged: dispatcher shutdown, drop"); }
                catch (System.Threading.Tasks.TaskCanceledException) { Debug.WriteLine("OnMirrorChanged: dispatcher task canceled, drop"); }
                return;
            }

            lock (_lock)
            {
                // A prior local Add already pushed into the mirror. Skip...
                if (_suppressMirrorEvent) { return; }

                _suppressMirrorPush = true;
                try
                {
                    switch (e.Action)
                    {
                        case System.Collections.Specialized.NotifyCollectionChangedAction.Add:
                            if (e.NewItems != null)
                            {
                                // Honour e.NewStartingIndex so a mirror.Insert(0, ...) lands at 0 here instead of getting appended. -1 = "unknown position" , fall back to append.
                                int insertAt = e.NewStartingIndex;
                                if (insertAt >= 0)
                                {
                                    int i = 0;
                                    foreach (object item in e.NewItems)
                                    {
                                        base.InsertItem(insertAt + i, (T)item);
                                        i++;
                                    }
                                }
                                else
                                {
                                    foreach (object item in e.NewItems)
                                    {
                                        base.Add((T)item);
                                    }
                                }
                            }
                            break;

                        case System.Collections.Specialized.NotifyCollectionChangedAction.Remove:
                            if (e.OldItems != null && e.OldStartingIndex >= 0)
                            {
                                // OldStartingIndex is already on the args so no need to scan to find it.
                                for (int k = 0; k < e.OldItems.Count; k++)
                                {
                                    base.RemoveAt(e.OldStartingIndex);
                                }
                            }
                            else if (e.OldItems != null)
                            {
                                foreach (object item in e.OldItems)
                                {
                                    base.Remove((T)item);
                                }
                            }
                            break;

                        case System.Collections.Specialized.NotifyCollectionChangedAction.Reset:
                            base.Clear();
                            // DetachMirror can null _mirror between event fire and the marshaled callback running on the UI thread. Drop the rebuild rather than NRE.
                            if (_mirror != null)
                            {
                                foreach (object item in _mirror)
                                {
                                    base.Add((T)item);
                                }
                            }
                            break;

                        case System.Collections.Specialized.NotifyCollectionChangedAction.Move:
                            if (e.OldStartingIndex >= 0 && e.NewStartingIndex >= 0 &&
                                e.OldStartingIndex < Count && e.NewStartingIndex < Count)
                            {
                                base.Move(e.OldStartingIndex, e.NewStartingIndex);
                            }
                            break;

                        case System.Collections.Specialized.NotifyCollectionChangedAction.Replace:
                            if (e.NewItems != null && e.NewStartingIndex >= 0)
                            {
                                int r = 0;
                                foreach (object item in e.NewItems)
                                {
                                    int at = e.NewStartingIndex + r;
                                    if (at >= 0 && at < Count) { base[at] = (T)item; }
                                    r++;
                                }
                            }
                            break;
                    }
                }
                finally
                {
                    _suppressMirrorPush = false;
                }
            }
        }

        // Expose the lock for batch operations
        public object SyncRoot { get { return _lock; } }

        // Switch to current threads Dispatcher (call from UI thread)
        public void UpdateDispatcher()
        {
            _dispatcher = Dispatcher.CurrentDispatcher;
            Debug.WriteLine("AsyncObservableCollection dispatcher updated to thread: " + System.Threading.Thread.CurrentThread.ManagedThreadId);
        }

        //  Marshaled mutation failed (or is about to be attempted). If the Dispatcher is tearing down (or its thread already died), sorry, but the window is gone or never coming. Apply locally without a notification (nothing left to draw).
        //  Mirror stays in step, return true. The dead thread bit of this matters beyond exceptions: an AsyncObservableCollection built on a worker STA runspace pins that thread's Dispatcher, which never runs, and Invoke against it after the thread returns
        //  blocks forever without throwing. Mutators consult this before dispatching for exactly that case. If the UI thread is still live the failure is genuine, so return false and let the calling code rethrow rather than silently dropping the item;
        //  an on thread mutation would have surfaced it too. Man, this took way more work to research and perfect than anyone will ever know. This whole class, really...
        private bool ShutdownFallback(string operation)
        {
            if (_dispatcher.HasShutdownStarted || !_dispatcher.Thread.IsAlive)
            {
                Debug.WriteLine("AsyncObservableCollection." + operation + ": dispatcher unusable (shutdown or dead thread), applied locally without notification");
                return true;
            }
            Debug.WriteLine("AsyncObservableCollection." + operation + ": dispatcher invoke failed on a live dispatcher, rethrowing");
            return false;
        }

        private void InsertLocalUnderLock(int index, T item)
        {
            if (index < 0 || index > Items.Count) { index = Items.Count; }
            Items.Insert(index, item);
            if (_mirror != null && !_suppressMirrorPush && index <= _mirror.Count)
            {
                _suppressMirrorEvent = true;
                try { _mirror.Insert(index, item); }
                finally { _suppressMirrorEvent = false; }
            }
        }

        private void RemoveAtLocalUnderLock(int index)
        {
            if (index < 0 || index >= Items.Count) { return; }
            Items.RemoveAt(index);
            if (_mirror != null && !_suppressMirrorPush && index < _mirror.Count)
            {
                _suppressMirrorEvent = true;
                try { _mirror.RemoveAt(index); }
                finally { _suppressMirrorEvent = false; }
            }
        }

        private void AddLocal(T item)
        {
            lock (_lock) { InsertLocalUnderLock(Items.Count, item); }
        }

        private void InsertLocal(int index, T item)
        {
            lock (_lock) { InsertLocalUnderLock(index, item); }
        }

        private bool RemoveLocal(T item)
        {
            lock (_lock)
            {
                int index = Items.IndexOf(item);
                if (index < 0) { return false; }
                RemoveAtLocalUnderLock(index);
                return true;
            }
        }

        private void RemoveAtLocal(int index)
        {
            lock (_lock) { RemoveAtLocalUnderLock(index); }
        }

        private void SetLocal(int index, T item)
        {
            lock (_lock)
            {
                if (index < 0 || index >= Items.Count) { return; }
                Items[index] = item;
                if (_mirror != null && !_suppressMirrorPush && index < _mirror.Count)
                {
                    _suppressMirrorEvent = true;
                    try { _mirror[index] = item; }
                    finally { _suppressMirrorEvent = false; }
                }
            }
        }

        private void ClearLocal()
        {
            lock (_lock)
            {
                Items.Clear();
                if (_mirror != null && !_suppressMirrorPush)
                {
                    _suppressMirrorEvent = true;
                    try { _mirror.Clear(); }
                    finally { _suppressMirrorEvent = false; }
                }
            }
        }

        private void ReplaceAllLocal(System.Collections.Generic.IEnumerable<T> items)
        {
            lock (_lock)
            {
                Items.Clear();
                foreach (T item in items) { Items.Add(item); }
                if (_mirror != null && !_suppressMirrorPush)
                {
                    _suppressMirrorEvent = true;
                    try
                    {
                        _mirror.Clear();
                        foreach (T item in Items) { _mirror.Add(item); }
                    }
                    finally { _suppressMirrorEvent = false; }
                }
            }
        }

        private void MoveLocal(int oldIndex, int newIndex)
        {
            lock (_lock)
            {
                if (oldIndex < 0 || oldIndex >= Items.Count || newIndex < 0 || newIndex >= Items.Count) { return; }
                T moved = Items[oldIndex];
                Items.RemoveAt(oldIndex);
                Items.Insert(newIndex, moved);
                if (_mirror != null && !_suppressMirrorPush && oldIndex < _mirror.Count && newIndex < _mirror.Count)
                {
                    _suppressMirrorEvent = true;
                    try
                    {
                        object mirrorMoved = _mirror[oldIndex];
                        _mirror.RemoveAt(oldIndex);
                        _mirror.Insert(newIndex, mirrorMoved);
                    }
                    finally { _suppressMirrorEvent = false; }
                }
            }
        }

        public new void Add(T item)
        {
            if (!_dispatcher.CheckAccess())
            {
                if (ShutdownFallback("Add")) { AddLocal(item); return; }
                try { _dispatcher.Invoke(new Action(() => Add(item))); }
                catch (InvalidOperationException) { if (ShutdownFallback("Add")) { AddLocal(item); } else { throw; } }
                catch (System.Threading.Tasks.TaskCanceledException) { if (ShutdownFallback("Add")) { AddLocal(item); } else { throw; } }
                return;
            }
            base.Add(item);
        }

        public new void Insert(int index, T item)
        {
            if (!_dispatcher.CheckAccess())
            {
                if (ShutdownFallback("Insert")) { InsertLocal(index, item); return; }
                try { _dispatcher.Invoke(new Action(() => Insert(index, item))); }
                catch (InvalidOperationException) { if (ShutdownFallback("Insert")) { InsertLocal(index, item); } else { throw; } }
                catch (System.Threading.Tasks.TaskCanceledException) { if (ShutdownFallback("Insert")) { InsertLocal(index, item); } else { throw; } }
                return;
            }
            base.Insert(index, item);
        }

        public new bool Remove(T item)
        {
            if (!_dispatcher.CheckAccess())
            {
                if (ShutdownFallback("Remove")) { return RemoveLocal(item); }
                bool result = false;
                try { result = (bool)_dispatcher.Invoke(new Func<bool>(() => Remove(item))); }
                catch (InvalidOperationException) { if (ShutdownFallback("Remove")) { result = RemoveLocal(item); } else { throw; } }
                catch (System.Threading.Tasks.TaskCanceledException) { if (ShutdownFallback("Remove")) { result = RemoveLocal(item); } else { throw; } }
                return result;
            }
            return base.Remove(item);
        }

        public new void RemoveAt(int index)
        {
            if (!_dispatcher.CheckAccess())
            {
                if (ShutdownFallback("RemoveAt")) { RemoveAtLocal(index); return; }
                try { _dispatcher.Invoke(new Action(() => RemoveAt(index))); }
                catch (InvalidOperationException) { if (ShutdownFallback("RemoveAt")) { RemoveAtLocal(index); } else { throw; } }
                catch (System.Threading.Tasks.TaskCanceledException) { if (ShutdownFallback("RemoveAt")) { RemoveAtLocal(index); } else { throw; } }
                return;
            }
            base.RemoveAt(index);
        }

        public new void Clear()
        {
            if (!_dispatcher.CheckAccess())
            {
                if (ShutdownFallback("Clear")) { ClearLocal(); return; }
                try { _dispatcher.Invoke(new Action(() => Clear())); }
                catch (InvalidOperationException) { if (ShutdownFallback("Clear")) { ClearLocal(); } else { throw; } }
                catch (System.Threading.Tasks.TaskCanceledException) { if (ShutdownFallback("Clear")) { ClearLocal(); } else { throw; } }
                return;
            }
            base.Clear();
        }

        public new T this[int index]
        {
            get { lock (_lock) { return base[index]; } }
            set
            {
                if (!_dispatcher.CheckAccess())
                {
                    T captured = value;
                    int idx = index;
                    if (ShutdownFallback("set")) { SetLocal(idx, captured); return; }
                    try { _dispatcher.Invoke(new Action(() => this[idx] = captured)); }
                    catch (InvalidOperationException) { if (ShutdownFallback("set")) { SetLocal(idx, captured); } else { throw; } }
                    catch (System.Threading.Tasks.TaskCanceledException) { if (ShutdownFallback("set")) { SetLocal(idx, captured); } else { throw; } }
                    return;
                }
                base[index] = value;
            }
        }

        // Virtual overrides catch any path that skipped the `new` methods above - chiefly C# code holding an IList<T>/Collection<T> reference. Mirror push lives here, next to the mutation it tracks.
        protected override void InsertItem(int index, T item)
        {
            if (!_dispatcher.CheckAccess())
            {
                if (ShutdownFallback("InsertItem")) { InsertLocal(index, item); return; }
                try { _dispatcher.Invoke(new Action(() => InsertItem(index, item))); }
                catch (InvalidOperationException) { if (ShutdownFallback("InsertItem")) { InsertLocal(index, item); } else { throw; } }
                catch (System.Threading.Tasks.TaskCanceledException) { if (ShutdownFallback("InsertItem")) { InsertLocal(index, item); } else { throw; } }
                return;
            }
            lock (_lock)
            {
                base.InsertItem(index, item);
                if (_mirror != null && !_suppressMirrorPush && index >= 0 && index <= _mirror.Count)
                {
                    _suppressMirrorEvent = true;
                    try { _mirror.Insert(index, item); }
                    finally { _suppressMirrorEvent = false; }
                }
            }
        }

        protected override void RemoveItem(int index)
        {
            if (!_dispatcher.CheckAccess())
            {
                if (ShutdownFallback("RemoveItem")) { RemoveAtLocal(index); return; }
                try { _dispatcher.Invoke(new Action(() => RemoveItem(index))); }
                catch (InvalidOperationException) { if (ShutdownFallback("RemoveItem")) { RemoveAtLocal(index); } else { throw; } }
                catch (System.Threading.Tasks.TaskCanceledException) { if (ShutdownFallback("RemoveItem")) { RemoveAtLocal(index); } else { throw; } }
                return;
            }
            lock (_lock)
            {
                base.RemoveItem(index);
                if (_mirror != null && !_suppressMirrorPush && index >= 0 && index < _mirror.Count)
                {
                    _suppressMirrorEvent = true;
                    try { _mirror.RemoveAt(index); }
                    finally { _suppressMirrorEvent = false; }
                }
            }
        }

        protected override void SetItem(int index, T item)
        {
            if (!_dispatcher.CheckAccess())
            {
                if (ShutdownFallback("SetItem")) { SetLocal(index, item); return; }
                try { _dispatcher.Invoke(new Action(() => SetItem(index, item))); }
                catch (InvalidOperationException) { if (ShutdownFallback("SetItem")) { SetLocal(index, item); } else { throw; } }
                catch (System.Threading.Tasks.TaskCanceledException) { if (ShutdownFallback("SetItem")) { SetLocal(index, item); } else { throw; } }
                return;
            }
            lock (_lock)
            {
                base.SetItem(index, item);
                if (_mirror != null && !_suppressMirrorPush && index >= 0 && index < _mirror.Count)
                {
                    _suppressMirrorEvent = true;
                    try { _mirror[index] = item; }
                    finally { _suppressMirrorEvent = false; }
                }
            }
        }

        protected override void ClearItems()
        {
            if (!_dispatcher.CheckAccess())
            {
                if (ShutdownFallback("ClearItems")) { ClearLocal(); return; }
                try { _dispatcher.Invoke(new Action(() => ClearItems())); }
                catch (InvalidOperationException) { if (ShutdownFallback("ClearItems")) { ClearLocal(); } else { throw; } }
                catch (System.Threading.Tasks.TaskCanceledException) { if (ShutdownFallback("ClearItems")) { ClearLocal(); } else { throw; } }
                return;
            }
            lock (_lock)
            {
                base.ClearItems();
                if (_mirror != null && !_suppressMirrorPush)
                {
                    _suppressMirrorEvent = true;
                    try { _mirror.Clear(); }
                    finally { _suppressMirrorEvent = false; }
                }
            }
        }

        // One reset for the whole replacement
        public void ReplaceAll(System.Collections.Generic.IEnumerable<T> items)
        {
            if (items == null) throw new ArgumentNullException("items");
            if (!_dispatcher.CheckAccess())
            {
                if (ShutdownFallback("ReplaceAll")) { ReplaceAllLocal(items); return; }
                try { _dispatcher.Invoke(new Action(() => ReplaceAll(items))); }
                catch (InvalidOperationException) { if (ShutdownFallback("ReplaceAll")) { ReplaceAllLocal(items); } else { throw; } }
                catch (System.Threading.Tasks.TaskCanceledException) { if (ShutdownFallback("ReplaceAll")) { ReplaceAllLocal(items); } else { throw; } }
                return;
            }
            lock (_lock)
            {
                CheckReentrancy();
                Items.Clear();
                foreach (T item in items) { Items.Add(item); }
                if (_mirror != null && !_suppressMirrorPush)
                {
                    _suppressMirrorEvent = true;
                    try
                    {
                        _mirror.Clear();
                        foreach (T item in Items) { _mirror.Add(item); }
                    }
                    finally { _suppressMirrorEvent = false; }
                }
            }
            OnPropertyChanged(new PropertyChangedEventArgs("Count"));
            OnPropertyChanged(new PropertyChangedEventArgs("Item[]"));
            OnCollectionChanged(new NotifyCollectionChangedEventArgs(NotifyCollectionChangedAction.Reset));
        }

        protected override void MoveItem(int oldIndex, int newIndex)
        {
            if (!_dispatcher.CheckAccess())
            {
                if (ShutdownFallback("MoveItem")) { MoveLocal(oldIndex, newIndex); return; }
                try { _dispatcher.Invoke(new Action(() => MoveItem(oldIndex, newIndex))); }
                catch (InvalidOperationException) { if (ShutdownFallback("MoveItem")) { MoveLocal(oldIndex, newIndex); } else { throw; } }
                catch (System.Threading.Tasks.TaskCanceledException) { if (ShutdownFallback("MoveItem")) { MoveLocal(oldIndex, newIndex); } else { throw; } }
                return;
            }
            lock (_lock)
            {
                base.MoveItem(oldIndex, newIndex);
                if (_mirror != null && !_suppressMirrorPush && oldIndex >= 0 && oldIndex < _mirror.Count && newIndex >= 0 && newIndex < _mirror.Count)
                {
                    _suppressMirrorEvent = true;
                    try
                    {
                        object mirrorMoved = _mirror[oldIndex];
                        _mirror.RemoveAt(oldIndex);
                        _mirror.Insert(newIndex, mirrorMoved);
                    }
                    finally { _suppressMirrorEvent = false; }
                }
            }
        }

        // No OnCollectionChanged / OnPropertyChanged overrides. The mutators above guarantee UI thread before base.OnCollectionChanged fires. Don't readd, BeginInvoke marshalling had a race condition
    }

    // Marker subclass so Test-UiDataGridOwned will work
    public sealed class GridOwnedCollection<T> : AsyncObservableCollection<T>
    {
        public GridOwnedCollection() : base() { }
        public GridOwnedCollection(Dispatcher uiDispatcher) : base(uiDispatcher) { }
    }
}
