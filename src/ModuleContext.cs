using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;

namespace PsUi
{
    // Module-wide state (replaces $Script: variables).
    // Thread-safety notes:
    //   - Icons: ConcurrentDictionary, fully thread-safe
    //   - Themes, PrivateFunctions, PublicFunctions: Regular Hashtables, but write-once at module
    //     load time then read-only. Safe because module init is single-threaded.
    //   - ActiveTheme: volatile string, atomic reads/writes
    public static class ModuleContext
    {
        private static volatile bool _isInitialized = false;
        private static string _modulePath = "";
        private static readonly object _modulePathLock = new object();
        private static ConcurrentDictionary<string, string> _icons = new ConcurrentDictionary<string, string>();
        private static Hashtable _themes = new Hashtable();
        private static readonly object _themesLock = new object();
        private static volatile string _activeTheme = "Light";
        private static Hashtable _privateFunctions = new Hashtable();
        private static readonly object _privateFunctionsLock = new object();
        private static Hashtable _themeUpdateVisited = new Hashtable();
        private static int _themeUpdateDepth = 0;

        public static bool IsInitialized
        {
            get { return _isInitialized; }
            set { _isInitialized = value; }
        }

        public static string ModulePath
        {
            get { lock (_modulePathLock) { return _modulePath; } }
            set { if (!string.IsNullOrEmpty(value)) { lock (_modulePathLock) { _modulePath = value; } } }
        }

        public static ConcurrentDictionary<string, string> Icons
        {
            get { return _icons; }
        }

        // No lock needed - this gets set once at module load, then it's read-only forever.
        public static Hashtable Themes
        {
            get { return _themes; }
            set { if (value != null) _themes = value; }
        }

        public static string ActiveTheme
        {
            get { return _activeTheme; }
            set { if (!string.IsNullOrEmpty(value)) _activeTheme = value; }
        }

        public static Hashtable PrivateFunctions
        {
            get { return _privateFunctions; }
            set { if (value != null) _privateFunctions = value; }
        }

        private static Hashtable _publicFunctions = new Hashtable();
        
        // Public functions commonly used in button actions (not all public funcs)
        public static Hashtable PublicFunctions
        {
            get { return _publicFunctions; }
            set { if (value != null) _publicFunctions = value; }
        }
        
        // Visited set for theme traversal (avoids cycles)
        public static Hashtable ThemeUpdateVisited
        {
            get { return _themeUpdateVisited; }
            set { _themeUpdateVisited = value ?? new Hashtable(); }
        }
        
        public static int ThemeUpdateDepth
        {
            get { return _themeUpdateDepth; }
            set { _themeUpdateDepth = value < 0 ? 0 : value; }
        }

        public static void Initialize(Dictionary<string, string> icons)
        {
            if (icons != null)
            {
                // Thread-safe: create new ConcurrentDictionary from source
                _icons = new ConcurrentDictionary<string, string>(icons);
            }
            _isInitialized = true;
        }

        public static string GetIcon(string name)
        {
            if (string.IsNullOrEmpty(name))
            {
                return string.Empty;
            }
            
            string icon;
            if (_icons.TryGetValue(name, out icon))
            {
                return icon;
            }
            return string.Empty;
        }

        public static void Reset()
        {
            _isInitialized = false;
            _icons = new ConcurrentDictionary<string, string>();
            lock (_themesLock)
            {
                _themes = new Hashtable();
            }
            _activeTheme = "Light";
            lock (_privateFunctionsLock)
            {
                _privateFunctions = new Hashtable();
            }
            _themeUpdateDepth = 0;
        }

        // Thread-safe theme registration without PowerShell runspace (used by JSON theme loading)
        public static void RegisterTheme(string themeName, Hashtable colors)
        {
            if (string.IsNullOrEmpty(themeName) || colors == null) return;
            
            lock (_themesLock)
            {
                _themes[themeName] = colors;
            }
        }
    }
}
