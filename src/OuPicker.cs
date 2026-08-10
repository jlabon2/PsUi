using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;

namespace PsUi
{
    // Wraps DsBrowseForContainerW - in practice its most the same OU picker ADUC
    // and GPMC use.
    //
    // Reference used for this monstrosity:
    // https://learn.microsoft.com/en-us/windows/win32/api/dsclient/nf-dsclient-dsbrowseforcontainerw
    //
    // It works, but it lazy-loads children on expand. If an OU has no child
    // OUs, clicking the + just collapses it back - no way to show the actual
    // objects underneath. We'll eventually swap this for a custom WPF tree.
    //
    // STA required because COM. We handle that internally. Credentials go
    // through pUserName/pPassword in the native struct, no impersonation.
    // All string marshaling is manual because [MarshalAs] calls ClearNative
    // on return and that crashes during impersonation. The struct has to die.
    public static class OuPicker
    {
        private const uint DSBI_NOBUTTONS         = 0x00000001;
        private const uint DSBI_INCLUDEHIDDEN     = 0x00020000;
        private const uint DSBI_ENTIREDIRECTORY   = 0x00090000;
        private const uint DSBI_EXPANDONOPEN      = 0x00040000;
        private const uint DSBI_IGNORETREATASLEAF = 0x00400000;
        private const uint DSBI_HASCREDENTIALS    = 0x00200000;

        // All string fields are IntPtr. Letting .NET auto-marshal them causes
        // ClearNative to fire after the P/Invoke, which AVs when impersonated.
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DSBROWSEINFOW
        {
            public uint   cbStruct;
            public IntPtr hwndOwner;
            public IntPtr pszCaption;
            public IntPtr pszTitle;
            public IntPtr pszRoot;
            public IntPtr pszPath;
            public uint   cchPath;
            public uint   dwFlags;
            public IntPtr pfnCallback;
            public IntPtr lParam;
            public uint   dwReturnFormat;
            public IntPtr pUserName;
            public IntPtr pPassword;
            public IntPtr pszObjectClass;
            public uint   cchObjectClass;
        }

        [DllImport("dsuiext.dll", CharSet = CharSet.Unicode, EntryPoint = "DsBrowseForContainerW", SetLastError = true)]
        private static extern int DsBrowseForContainerW(ref DSBROWSEINFOW pInfo);

        [DllImport("ole32.dll")]
        private static extern int OleInitialize(IntPtr pvReserved);

        [DllImport("ole32.dll")]
        private static extern void OleUninitialize();

        /// <summary>
        /// Shows the OU picker and returns the ADsPath, or null if cancelled.
        /// Pass credUserName/credPassword to browse a different domain.
        /// STA is handled internally - if the calling thread is MTA we spin one up.
        /// </summary>
        public static string Show(IntPtr hwndOwner, string title, string caption, string rootAdsPath,
                                  bool includeEntireDir, bool includeHidden, bool noButtons,
                                  bool ignoreTreatAsLeaf,
                                  string credUserName = null, string credPassword = null)
        {
            // DsBrowseForContainerW uses COM internally - won't render on MTA
            if (Thread.CurrentThread.GetApartmentState() != ApartmentState.STA)
            {
                string staResult = null;
                Exception staException = null;
                // Strings are immutable, closure capture is safe here
                var staThread = new Thread(() =>
                {
                    try
                    {
                        staResult = ShowCore(hwndOwner, title, caption, rootAdsPath,
                                             includeEntireDir, includeHidden, noButtons,
                                             ignoreTreatAsLeaf, credUserName, credPassword);
                    }
                    catch (Exception ex)
                    {
                        staException = ex;
                    }
                });
                staThread.SetApartmentState(ApartmentState.STA);
                staThread.IsBackground = true;
                staThread.Start();
                staThread.Join();
                if (staException != null) { throw staException; }
                return staResult;
            }

            return ShowCore(hwndOwner, title, caption, rootAdsPath,
                            includeEntireDir, includeHidden, noButtons,
                            ignoreTreatAsLeaf, credUserName, credPassword);
        }

        private static string ShowCore(IntPtr hwndOwner, string title, string caption, string rootAdsPath,
                                       bool includeEntireDir, bool includeHidden, bool noButtons,
                                       bool ignoreTreatAsLeaf,
                                       string credUserName, string credPassword)
        {
            const int bufferChars = 260;
            IntPtr pathBuffer   = Marshal.AllocHGlobal(bufferChars * 2);
            IntPtr pCaption     = IntPtr.Zero;
            IntPtr pTitle       = IntPtr.Zero;
            IntPtr pRoot        = IntPtr.Zero;
            IntPtr pUser        = IntPtr.Zero;
            IntPtr pPass        = IntPtr.Zero;
            bool oleInitialized = false;
            try
            {
                int oleHr = OleInitialize(IntPtr.Zero);
                if (oleHr < 0) { throw new COMException("OleInitialize failed", oleHr); }
                oleInitialized = true;

                Marshal.WriteInt16(pathBuffer, 0);

                uint flags = 0;
                if (includeEntireDir)  { flags |= DSBI_ENTIREDIRECTORY; }
                if (includeHidden)     { flags |= DSBI_INCLUDEHIDDEN; }
                if (noButtons)         { flags |= DSBI_NOBUTTONS; }
                if (ignoreTreatAsLeaf) { flags |= DSBI_IGNORETREATASLEAF; }
                if (!string.IsNullOrEmpty(credUserName)) { flags |= DSBI_HASCREDENTIALS; }

                // PowerShell passes $null as empty string for string params
                string effectiveRoot = string.IsNullOrEmpty(rootAdsPath) ? null : rootAdsPath;

                // Marshal strings to unmanaged memory by hand. The alternative
                // ([MarshalAs(UnmanagedType.LPWStr)]) lets .NET call ClearNative
                // after the P/Invoke, which is where the AVs come from.
                if (caption       != null) { pCaption = Marshal.StringToHGlobalUni(caption); }
                if (title         != null) { pTitle   = Marshal.StringToHGlobalUni(title); }
                if (effectiveRoot != null) { pRoot    = Marshal.StringToHGlobalUni(effectiveRoot); }
                if (!string.IsNullOrEmpty(credUserName)) { pUser = Marshal.StringToHGlobalUni(credUserName); }
                if (credPassword  != null)               { pPass = Marshal.StringToHGlobalUni(credPassword); }

                DSBROWSEINFOW info = new DSBROWSEINFOW();
                info.cbStruct       = (uint)Marshal.SizeOf(typeof(DSBROWSEINFOW));
                info.hwndOwner      = hwndOwner;
                info.pszCaption     = pCaption;
                info.pszTitle       = pTitle;
                info.pszRoot        = pRoot;
                info.pszPath        = pathBuffer;
                info.cchPath        = (uint)bufferChars;
                info.dwFlags        = flags;
                info.pUserName      = pUser;
                info.pPassword      = pPass;

                int result = DsBrowseForContainerW(ref info);

                if (result == -1)
                {
                    int lastError = Marshal.GetLastWin32Error();
                    if (lastError == 0)
                    {
                        string credNote = !string.IsNullOrEmpty(credUserName)
                            ? " Credentials were supplied - verify the username, password, and domain."
                            : "";
                        throw new InvalidOperationException(
                            "DsBrowseForContainerW returned -1 with no Win32 error code. " +
                            "This usually means the root ADsPath could not be bound to. " +
                            "Verify the server is reachable, the DN exists, and the current " +
                            "user has read access." + credNote +
                            " Root passed: '" + (effectiveRoot ?? "<null>") + "'.");
                    }
                    string message = new Win32Exception(lastError).Message;
                    throw new Win32Exception(lastError,
                        "DsBrowseForContainerW failed. GetLastError=" + lastError +
                        " (0x" + lastError.ToString("X8") + "): " + message);
                }
                if (result != 1) { return null; }

                return Marshal.PtrToStringUni(pathBuffer);
            }
            finally
            {
                if (oleInitialized) { OleUninitialize(); }
                if (pUser    != IntPtr.Zero) { Marshal.FreeHGlobal(pUser); }
                if (pPass    != IntPtr.Zero) { Marshal.FreeHGlobal(pPass); }
                if (pCaption != IntPtr.Zero) { Marshal.FreeHGlobal(pCaption); }
                if (pTitle   != IntPtr.Zero) { Marshal.FreeHGlobal(pTitle); }
                if (pRoot    != IntPtr.Zero) { Marshal.FreeHGlobal(pRoot); }
                Marshal.FreeHGlobal(pathBuffer);
            }
        }
    }
}
