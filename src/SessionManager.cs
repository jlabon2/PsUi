using System;
using System.Collections.Concurrent;
using System.Threading;

namespace PsUi
{
    // Thread-aware session registry. Each UI window gets a SessionContext keyed by GUID.
    public static class SessionManager
    {
        private static readonly ConcurrentDictionary<Guid, SessionContext> _sessions =
            new ConcurrentDictionary<Guid, SessionContext>();

        // Each thread remembers its own session ID (WPF windows run on dedicated STA threads)
        [ThreadStatic]
        private static Guid? _currentSessionId;

        // Current threads SessionContext, or null if none active
        public static SessionContext Current
        {
            get
            {
                if (_currentSessionId.HasValue &&
                    _sessions.TryGetValue(_currentSessionId.Value, out SessionContext session))
                {
                    return session;
                }
                return null;
            }
        }

        public static Guid CurrentSessionId
        {
            get { return _currentSessionId ?? Guid.Empty; }
        }

        // Create and register a new session - doesnt set as current, call SetCurrentSession for that
        public static Guid CreateSession()
        {
            var id = Guid.NewGuid();
            var session = new SessionContext(id);
            _sessions[id] = session;
            return id;
        }

        // Bind current thread to its session
        public static void SetCurrentSession(Guid id)
        {
            _currentSessionId = id;
        }

        // Get a session by ID from any thread - for cross-thread access when you have the ID
        public static SessionContext GetSession(Guid id)
        {
            SessionContext session;
            _sessions.TryGetValue(id, out session);
            return session;
        }

        // Kill session on window close
        public static void DisposeSession(Guid id)
        {
            SessionContext session;
            if (_sessions.TryRemove(id, out session))
            {
                session.Clear();
            }
            
            // Only clear if this thread owns the session
            // (DisposeSession may be called from a different thread than the session's STA thread)
            if (_currentSessionId.HasValue && _currentSessionId.Value == id)
            {
                _currentSessionId = null;
            }
        }

        // Clear thread-local reference without disposing - for when session might be accessed elsewhere
        public static void ClearCurrentSession()
        {
            _currentSessionId = null;
        }

        public static int ActiveSessionCount
        {
            get { return _sessions.Count; }
        }

        // Dispose all sessions - call during module unload or for testing
        public static void Reset()
        {
            foreach (var kvp in _sessions)
            {
                kvp.Value.Clear();
            }
            _sessions.Clear();
            _currentSessionId = null;
        }
    }
}
