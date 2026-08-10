using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;

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
        public const string FontNameMDL2 = "Segoe MDL2 Assets";
        public const string FontNameFluent = "Segoe Fluent Icons";

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

        // Icon font state
        private static string _activeIconFontName = FontNameMDL2;
        private static FontFamily _activeIconFontFamily;
        private static bool _iconFontNoFallback = false;
        // volatile - this gets read without the lock from IsGlyphAvailable on hot paths.
        private static volatile bool _noIconFontInstalled = false;
        private static readonly object _iconFontLock = new object();

        // Per-font glyph cache: each font's CharacterToGlyphMap is built once and reused.
        // Maps font name -> set of supported code points. Keyed case-insensitive.
        private static Dictionary<string, HashSet<int>> _glyphCaches =
            new Dictionary<string, HashSet<int>>(StringComparer.OrdinalIgnoreCase);

        // Per-font install-state cache. Enumerating Fonts.SystemFontFamilies (~300 fonts on a
        // typical box) on every IsFontInstalled call torches the glyph browser - 1500 glyphs x 2
        // fonts = 3000 enumerations on first open. Caches are session-stable; users don't install
        // fonts mid-session.
        private static Dictionary<string, bool> _installedFontCache =
            new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);

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

            // Auto-detect the best icon font for this system
            SetIconFont(DetectDefaultIconFont());

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
            lock (_iconFontLock)
            {
                _activeIconFontFamily = null;
                _iconFontNoFallback = false;
                _glyphCaches.Clear();
                _installedFontCache.Clear();
            }
            // Re-detect so _noIconFontInstalled and _activeIconFontName match the current box.
            // Hard-coding MDL2 + _noIconFontInstalled=false here was a lie on machines that don't
            // have MDL2 (rare, but not impossible on stripped Server SKUs). The lock above is
            // already released, so SetIconFont reacquires cleanly.
            SetIconFont(DetectDefaultIconFont(), false);
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

        // Active icon font name (FontNameMDL2 or FontNameFluent)
        public static string ActiveIconFontName
        {
            get { lock (_iconFontLock) { return _activeIconFontName; } }
        }

        // Cached FontFamily for the active icon font.
        // By default this is a WPF font-fallback chain ("Primary, Secondary") so glyphs missing
        // from the primary font fall through to the other - lets old scripts keep rendering when
        // a script upgrades from MDL2-default to Fluent-default. Set IconFontNoFallback to true
        // to pin to the primary font only (missing glyphs render as tofu).
        public static FontFamily ActiveIconFontFamily
        {
            get
            {
                lock (_iconFontLock)
                {
                    if (_activeIconFontFamily == null)
                    {
                        string source = _activeIconFontName;
                        if (!_iconFontNoFallback)
                        {
                            // Case-insensitive: defensive against future code paths that might store
                            // the name with non-canonical casing.
                            string secondary = string.Equals(_activeIconFontName, FontNameFluent, StringComparison.OrdinalIgnoreCase)
                                ? FontNameMDL2
                                : FontNameFluent;
                            source = _activeIconFontName + ", " + secondary;
                        }
                        _activeIconFontFamily = new FontFamily(source);
                    }
                    return _activeIconFontFamily;
                }
            }
        }

        // When true the active font is pinned - no fallback to the other icon font.
        public static bool IconFontNoFallback
        {
            get { lock (_iconFontLock) { return _iconFontNoFallback; } }
        }

        // Switch the active icon font. Falls back to MDL2 if the requested font isn't installed -
        // the caller (Set-PsUiIconFont / NewUiWindowCommand) is responsible for surfacing a warning
        // before calling this, since the C# layer has no PS host to write to.
        // Install checks happen outside the lock (IsFontInstalled is cached) so we only hold the
        // lock for the state mutation.
        public static void SetIconFont(string fontName, bool noFallback)
        {
            if (string.IsNullOrEmpty(fontName)) return;

            bool installed = IsFontInstalled(fontName);
            if (!installed)
            {
                fontName = FontNameMDL2;
                installed = IsFontInstalled(fontName);
            }

            lock (_iconFontLock)
            {
                _activeIconFontName = fontName;
                _iconFontNoFallback = noFallback;
                _activeIconFontFamily = null;   // forces rebuild next access (chain or single)
                _noIconFontInstalled = !installed;
                // Per-font glyph caches stay - the underlying font maps don't change at runtime.
            }
        }

        // Convenience overload: keeps existing fallback setting.
        public static void SetIconFont(string fontName)
        {
            bool current;
            lock (_iconFontLock) { current = _iconFontNoFallback; }
            SetIconFont(fontName, current);
        }

        // Toggle the fallback chain without changing the active font - lets callers flip just the
        // fallback setting (e.g. New-UiWindow -NoIconFontFallback without -IconFont).
        public static void SetIconFontNoFallback(bool noFallback)
        {
            lock (_iconFontLock)
            {
                if (_iconFontNoFallback == noFallback) return;
                _iconFontNoFallback = noFallback;
                _activeIconFontFamily = null;
            }
        }

        // True when neither Segoe MDL2 Assets nor Segoe Fluent Icons is installed (WinPE, stripped images)
        public static bool NoIconFontInstalled
        {
            get { return _noIconFontInstalled; }
        }

        // Returns the best icon font for this system. Side-effect free - call SetIconFont with the
        // result to actually apply it. Defaults to MDL2 even when neither font is installed so
        // callers have a non-null name; NoIconFontInstalled (set by SetIconFont) tells you whether
        // the result is real.
        public static string DetectDefaultIconFont()
        {
            if (IsFontInstalled(FontNameFluent)) return FontNameFluent;
            return FontNameMDL2;
        }

        // Resolve a friendly icon-font token (the PS-side enum values) to a real font family name.
        // Returns null when the caller asked to inherit; the caller decides whether that means
        // "skip the override entirely" or "keep current". Unknown tokens pass through unchanged so
        // callers can also accept literal font family names.
        public static string ResolveIconFontToken(string token)
        {
            if (string.IsNullOrEmpty(token)) return null;
            if (string.Equals(token, "Inherit", StringComparison.OrdinalIgnoreCase)) return null;
            if (string.Equals(token, "Auto", StringComparison.OrdinalIgnoreCase)) return DetectDefaultIconFont();
            if (string.Equals(token, "SegoeMDL2", StringComparison.OrdinalIgnoreCase)) return FontNameMDL2;
            if (string.Equals(token, "SegoeFluentIcons", StringComparison.OrdinalIgnoreCase)) return FontNameFluent;
            return token;
        }

        // Snapshot of the active icon-font state. Pair with RestoreIconFontState to undo any
        // overrides applied between snapshot and restore - lets per-window -IconFont overrides
        // return the global state to its previous value when the window closes.
        public class IconFontSnapshot
        {
            public string FontName { get; set; }
            public bool NoFallback { get; set; }
        }

        public static IconFontSnapshot SnapshotIconFontState()
        {
            lock (_iconFontLock)
            {
                return new IconFontSnapshot
                {
                    FontName = _activeIconFontName,
                    NoFallback = _iconFontNoFallback
                };
            }
        }

        // Apply a snapshot taken by SnapshotIconFontState. No-op when the snapshot is null.
        // Routes through SetIconFont so cache invalidation + install re-check happen on the way back.
        public static void RestoreIconFontState(IconFontSnapshot snapshot)
        {
            if (snapshot == null) return;
            SetIconFont(snapshot.FontName, snapshot.NoFallback);
        }

        // Check whether a named font family is installed on this machine.
        // Cached per-name; enumeration is the slow part (~300 fonts on a typical box).
        public static bool IsFontInstalled(string fontName)
        {
            if (string.IsNullOrEmpty(fontName)) return false;

            lock (_iconFontLock)
            {
                bool cached;
                if (_installedFontCache.TryGetValue(fontName, out cached))
                {
                    return cached;
                }
            }

            bool found = false;
            try
            {
                foreach (FontFamily family in Fonts.SystemFontFamilies)
                {
                    if (string.Equals(family.Source, fontName, StringComparison.OrdinalIgnoreCase))
                    {
                        found = true;
                        break;
                    }
                }
            }
            catch
            {
                // Font enumeration can fail in headless or WinPE environments
            }

            // Two threads racing to the same uncached name both write the same value - harmless.
            lock (_iconFontLock)
            {
                _installedFontCache[fontName] = found;
            }
            return found;
        }

        // Check whether a glyph exists in a specific font (not necessarily the active one).
        // Used by the glyph browser to badge per-tile availability and by Test-PsUiIcon for explicit lookups.
        public static bool IsGlyphAvailableInFont(string iconName, string fontName)
        {
            string character = GetIcon(iconName);
            if (string.IsNullOrEmpty(character)) return false;
            if (string.IsNullOrEmpty(fontName)) return false;
            if (!IsFontInstalled(fontName)) return false;

            int codePoint = char.ConvertToUtf32(character, 0);
            var cache = GetOrBuildGlyphCache(fontName);
            if (cache != null) return cache.Contains(codePoint);
            // Cache build failed for an explicitly-named font - be honest, not optimistic.
            return false;
        }

        // Check whether a specific icon glyph will render under the active font.
        // When the fallback chain is on we also consult the secondary font - the WPF
        // FontFamily we hand to controls is "primary, secondary", so glyphs missing from
        // primary still render via the other icon font and we should report them as available.
        public static bool IsGlyphAvailable(string iconName)
        {
            string character = GetIcon(iconName);
            if (string.IsNullOrEmpty(character)) return false;

            // No icon font installed at all (WinPE, stripped Server images) - nothing renders.
            // Without this check the typeface lookup quietly fails and we'd return optimistic true,
            // which leaves the glyph browser showing ~1500 empty boxes with nothing dimmed.
            if (_noIconFontInstalled) return false;

            int codePoint = char.ConvertToUtf32(character, 0);

            // Snapshot under the lock so we evaluate against a consistent (font, fallback) pair.
            string primary;
            bool noFallback;
            lock (_iconFontLock)
            {
                primary = _activeIconFontName;
                noFallback = _iconFontNoFallback;
            }

            var primaryCache = GetOrBuildGlyphCache(primary);
            if (primaryCache != null && primaryCache.Contains(codePoint)) return true;

            HashSet<int> secondaryCache = null;
            if (!noFallback)
            {
                string secondary = string.Equals(primary, FontNameFluent, StringComparison.OrdinalIgnoreCase)
                    ? FontNameMDL2
                    : FontNameFluent;
                secondaryCache = GetOrBuildGlyphCache(secondary);
                if (secondaryCache != null && secondaryCache.Contains(codePoint)) return true;
            }

            // Reached here = none of the caches we consulted contained the glyph. Definitive false
            // only when every consulted cache built cleanly. If a cache build failed (no
            // GlyphTypeface) be optimstic - WPF can still render via its own fallback path; dimming
            // every glyph in the browser is worse UX than the occasional false positive.
            if (primaryCache != null && (noFallback || secondaryCache != null)) return false;
            return true;
        }

        // Get-or-build the glyph cache for the given font. Returns null if the typeface introspection
        // fails. Per-font caches are stable for the session - font glyph maps don't change at runtime.
        private static HashSet<int> GetOrBuildGlyphCache(string fontName)
        {
            lock (_iconFontLock)
            {
                HashSet<int> cache;
                if (_glyphCaches.TryGetValue(fontName, out cache))
                {
                    return cache;
                }

                try
                {
                    var fontFamily = new FontFamily(fontName);
                    var typeface = new Typeface(fontFamily, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
                    GlyphTypeface glyphTypeface;
                    if (typeface.TryGetGlyphTypeface(out glyphTypeface))
                    {
                        cache = new HashSet<int>(glyphTypeface.CharacterToGlyphMap.Keys);
                        _glyphCaches[fontName] = cache;
                        return cache;
                    }
                }
                catch
                {
                    // Typeface introspection unavailable - fall through to null.
                }
                return null;
            }
        }
    }
}
