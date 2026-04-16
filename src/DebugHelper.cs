using System;

namespace PsUi
{

    // Debug logging when session.DebugMode is true.
    public static class DebugHelper
    {
        public static void Log(string category, string message)
        {
            if (!IsDebugEnabled()) return;
            Console.WriteLine("[{0}] {1}", category, message);
        }

        public static void Log(string category, string format, params object[] args)
        {
            if (!IsDebugEnabled()) return;
            Console.WriteLine("[{0}] {1}", category, string.Format(format, args));
        }

        // Log exception in catch blocks without crashing
        public static void LogException(string category, string context, Exception ex)
        {
            if (!IsDebugEnabled()) return;
            Console.WriteLine("[{0}] {1} failed: {2}", category, context, ex.Message);
        }

        private static bool IsDebugEnabled()
        {
            SessionContext session = SessionManager.Current;
            return session != null && session.DebugMode;
        }
    }
}
