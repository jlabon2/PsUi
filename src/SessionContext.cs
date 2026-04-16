using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Concurrent; 
using System.Windows;
using System.Windows.Controls;

namespace PsUi
{
    public class SessionContext
    {
        // Per-instance list collections (no longer static - each window has its own)
        private readonly ConcurrentDictionary<string, IList> _listCollections = 
            new ConcurrentDictionary<string, IList>();
        
        private readonly ConcurrentDictionary<string, string> _listDisplayFormats = 
            new ConcurrentDictionary<string, string>();
        
        // Button registry for -SubmitButton feature (Enter key triggers button)
        private readonly ConcurrentDictionary<string, System.Windows.Controls.Primitives.ButtonBase> _registeredButtons =
            new ConcurrentDictionary<string, System.Windows.Controls.Primitives.ButtonBase>();

        // Hotkey registry for window-level keyboard shortcuts
        private readonly ConcurrentDictionary<string, object> _registeredHotkeys =
            new ConcurrentDictionary<string, object>();

        // Register a list collection for this session
        public void RegisterListCollection(string name, IList collection)
        {
            _listCollections[name] = collection;
        }
        
        // Store display format template for a list
        public void RegisterListDisplayFormat(string name, string format)
        {
            if (!string.IsNullOrEmpty(format))
            {
                _listDisplayFormats[name] = format;
            }
        }
        
        public string GetListDisplayFormat(string name)
        {
            string result = null;
            _listDisplayFormats.TryGetValue(name, out result);
            return result;
        }

        public IList GetListCollection(string name)
        {
            IList result = null;
            _listCollections.TryGetValue(name, out result);
            return result;
        }

        public string[] GetAllListKeys()
        {
            var keys = new List<string>(_listCollections.Keys);
            return keys.ToArray();
        }

        public void ClearListRegistry()
        {
            _listCollections.Clear();
            _listDisplayFormats.Clear();
        }
        
        // Register a button for -SubmitButton lookup (Enter key triggers button)
        public void RegisterButton(string name, System.Windows.Controls.Primitives.ButtonBase button)
        {
            if (string.IsNullOrEmpty(name) || button == null) return;
            _registeredButtons[name] = button;
        }
        
        public System.Windows.Controls.Primitives.ButtonBase GetRegisteredButton(string name)
        {
            System.Windows.Controls.Primitives.ButtonBase button = null;
            if (!string.IsNullOrEmpty(name))
            {
                _registeredButtons.TryGetValue(name, out button);
            }
            return button;
        }
        
        // Register a keyboard shortcut with an action (ScriptBlock stored as object)
        public void RegisterHotkey(string keyCombo, object action)
        {
            if (string.IsNullOrEmpty(keyCombo) || action == null) return;
            _registeredHotkeys[keyCombo.ToUpperInvariant()] = action;
        }
        
        // Lookup a hotkey action by key combination
        public object GetHotkeyAction(string keyCombo)
        {
            object action = null;
            if (!string.IsNullOrEmpty(keyCombo))
            {
                _registeredHotkeys.TryGetValue(keyCombo.ToUpperInvariant(), out action);
            }
            return action;
        }
        
        // Get all registered hotkey combinations (for help display or debugging)
        public string[] GetRegisteredHotkeys()
        {
            var keys = new List<string>(_registeredHotkeys.Keys);
            return keys.ToArray();
        }

        private readonly ConcurrentDictionary<string, object> _variables;
        private readonly ConcurrentDictionary<string, object> _controls;
        private readonly ConcurrentDictionary<string, ThreadSafeControlProxy> _safeVariables;
        private readonly ConcurrentDictionary<string, object> _capturedVariables;
        private readonly Hashtable _syncTable;
        
        // Tracks controls bound to session variables via -EnabledWhen (variable -> controls that respond to changes)
        private readonly ConcurrentDictionary<string, List<FrameworkElement>> _variableBindings;
        
        // Fired when a captured variable changes - used by -EnabledWhen bindings
        public event Action<string, object> OnCapturedVariableChanged;

        public string Id { get; set; }
        public DateTime Created { get; set; }
        public Window Window { get; set; }
        
        // Child window for dialog centering
        public Window ActiveDialogParent { get; set; }
        
        public TabControl TabControl { get; set; }
        public object CurrentParent { get; set; }
        public Stack<object> ParentStack { get; private set; }

        public string LayoutMode { get; set; } 
        public string TabAlignment { get; set; }
        public int MaxColumns { get; set; }
        
        // True when window created with -Debug flag
        public bool DebugMode { get; set; }
        
        // True = MTA (ThreadPool), False = STA threads. STA is better for WinForms/COM compatibility.
        public bool UseMtaThreading { get; set; }
        
        // Current UI definition schema - allows buttons/handlers to access without closures
        public object CurrentDefinition { get; set; }
        
        // Caller script file - for error reporting when AST doesnt have file info
        public string CallerScriptName { get; set; }
        
        // Caller script line - for calculating actual line numbers in error reports
        public int CallerScriptLine { get; set; }
        
        // When true, CapturedVariables are exported to global scope on window close
        public bool ExportOnClose { get; set; }
        
        // Custom logo path for window icon (overrides default themed icon)
        public string CustomLogo { get; set; }
        
        // Currently running async executor (for Stop-UiAsync cancellation)
        public AsyncExecutor ActiveExecutor { get; set; }
        
        public Guid SessionId { get; private set; }

        // Use SessionManager.CreateSession() instead of calling this directly
        public SessionContext(Guid sessionId)
        {
            SessionId = sessionId;
            _variables = new ConcurrentDictionary<string, object>();
            _controls = new ConcurrentDictionary<string, object>();
            _safeVariables = new ConcurrentDictionary<string, ThreadSafeControlProxy>();
            _capturedVariables = new ConcurrentDictionary<string, object>();
            _variableBindings = new ConcurrentDictionary<string, List<FrameworkElement>>();
            _syncTable = Hashtable.Synchronized(new Hashtable());
            ParentStack = new Stack<object>();
            Id = sessionId.ToString().Substring(0, 8);
            Created = DateTime.Now;
            LayoutMode = "Responsive"; 
            TabAlignment = "Left";
            MaxColumns = 2;
        }

        public ConcurrentDictionary<string, object> Variables { get { return _variables; } }
        public ConcurrentDictionary<string, object> Controls { get { return _controls; } }
        public ConcurrentDictionary<string, ThreadSafeControlProxy> SafeVariables { get { return _safeVariables; } }
        public ConcurrentDictionary<string, object> CapturedVariables { get { return _capturedVariables; } }
        public Hashtable SyncTable { get { return _syncTable; } }

        public void AddControl(string name, object control)
        {
            _controls[name] = control;
        }

        public object GetControl(string name)
        {
            object val;
            if (_controls.TryGetValue(name, out val)) return val;
            return null;
        }

        // Add control with automatic thread-safe proxy - the preferred way to register controls accessed from bg threads
        public void AddControlSafe(string name, FrameworkElement control)
        {
            if (string.IsNullOrEmpty(name))
                throw new ArgumentException("Control name cannot be null or empty", "name");
            
            if (control == null)
                throw new ArgumentNullException("control");

            // Store in both dictionaries
            _variables[name] = control;
            _controls[name] = control;
            
            // Create thread-safe proxy
            ThreadSafeControlProxy proxy = new ThreadSafeControlProxy(control, name);
            _safeVariables[name] = proxy;
        }

        public ThreadSafeControlProxy GetSafeVariable(string name)
        {
            ThreadSafeControlProxy proxy;
            if (_safeVariables.TryGetValue(name, out proxy))
                return proxy;
            return null;
        }
        
        // Register a control for -EnabledWhen binding (control enables/disables when variable changes)
        public void RegisterVariableBinding(string variableName, FrameworkElement control)
        {
            if (string.IsNullOrEmpty(variableName) || control == null) return;
            
            List<FrameworkElement> bindings = _variableBindings.GetOrAdd(variableName, key => new List<FrameworkElement>());
            
            bool shouldEnable;
            lock (bindings)
            {
                if (!bindings.Contains(control))
                {
                    bindings.Add(control);
                }
                
                // Check initial state inside lock to avoid race with SetCapturedVariable
                object currentValue;
                bool hasValue = _capturedVariables.TryGetValue(variableName, out currentValue);
                shouldEnable = hasValue && IsTruthy(currentValue);
            }
            
            SetControlEnabled(control, shouldEnable);
        }
        
        // Set a captured variable and notify bound controls - use instead of CapturedVariables[] directly
        public void SetCapturedVariable(string name, object value)
        {
            if (string.IsNullOrEmpty(name)) return;
            
            _capturedVariables[name] = value;
            
            // Notify bindings
            NotifyVariableBindings(name, value);
            
            // Fire event for any external listeners
            Action<string, object> handler = OnCapturedVariableChanged;
            if (handler != null)
            {
                handler(name, value);
            }
        }
        
        public object GetCapturedVariable(string name)
        {
            object value;
            if (_capturedVariables.TryGetValue(name, out value))
            {
                return value;
            }
            return null;
        }
        
        private void NotifyVariableBindings(string variableName, object value)
        {
            List<FrameworkElement> bindings;
            if (!_variableBindings.TryGetValue(variableName, out bindings)) return;
            
            bool shouldEnable = IsTruthy(value);
            
            lock (bindings)
            {
                foreach (FrameworkElement control in bindings)
                {
                    // Skip null controls only - don't check IsLoaded since tabs
                    // that haven't been viewed yet are still valid targets
                    if (control == null) continue;
                    
                    SetControlEnabled(control, shouldEnable);
                }
            }
        }
        
        private void SetControlEnabled(FrameworkElement control, bool enabled)
        {
            if (control == null) return;
            
            if (control.Dispatcher.CheckAccess())
            {
                control.IsEnabled = enabled;
            }
            else
            {
                control.Dispatcher.BeginInvoke(new Action(() => control.IsEnabled = enabled));
            }
        }
        
        // Is value non-null, non-empty, and non-zero? (for -EnabledWhen bindings)
        private static bool IsTruthy(object value)
        {
            if (value == null) return false;
            
            // Handle PSObject wrapper
            if (value is System.Management.Automation.PSObject)
            {
                value = ((System.Management.Automation.PSObject)value).BaseObject;
                if (value == null) return false;
            }
            
            // Boolean
            if (value is bool) return (bool)value;
            
            // String - non-null non-empty
            string strVal = value as string;
            if (strVal != null) return !string.IsNullOrEmpty(strVal);
            
            // Numeric - non-zero
            if (value is int) return (int)value != 0;
            if (value is long) return (long)value != 0;
            if (value is double) return (double)value != 0.0;
            if (value is float) return (float)value != 0.0f;
            if (value is decimal) return (decimal)value != 0m;
            
            // Collection - non-empty
            ICollection collection = value as ICollection;
            if (collection != null) return collection.Count > 0;
            
            // Any other non-null object is truthy
            return true;
        }
        
        public void Clear()
        {
            _variables.Clear();
            _controls.Clear();
            _safeVariables.Clear();
            _capturedVariables.Clear();
            _variableBindings.Clear();
            _syncTable.Clear();
            _registeredButtons.Clear();
            _registeredHotkeys.Clear();
            ClearListRegistry();
            ActiveExecutor = null;
            Window = null;
            CurrentParent = null;
            TabControl = null;
            CurrentDefinition = null;
            if (ParentStack != null)
            {
                ParentStack.Clear();
            }
        }
    }
}