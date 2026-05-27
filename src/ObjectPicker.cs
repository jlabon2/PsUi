using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace PsUi
{
    // Wrapper for the Windows DSObjectPicker COM component.
    // Shows the classic "Select Users, Computers, or Groups" AD dialog.
    // COM interop with DSObjectPicker is gnarly - the interfaces arent well documented.
    public static class ObjectPicker
    {
        // Object types that can be selected
        [Flags]
        public enum ObjectTypes
        {
            None = 0,
            Users = 1,
            Groups = 2,
            Computers = 4,
            Contacts = 8,
            All = Users | Groups | Computers | Contacts
        }

        // COM interface GUIDs
        private static readonly Guid CLSID_DsObjectPicker = new Guid("17D6CCD8-3B7B-11D2-B9E0-00C04FD8DBF7");

        // Scope type flags
        private const uint DSOP_SCOPE_TYPE_TARGET_COMPUTER = 0x00000001;
        private const uint DSOP_SCOPE_TYPE_UPLEVEL_JOINED_DOMAIN = 0x00000002;
        private const uint DSOP_SCOPE_TYPE_DOWNLEVEL_JOINED_DOMAIN = 0x00000004;
        private const uint DSOP_SCOPE_TYPE_ENTERPRISE_DOMAIN = 0x00000008;
        private const uint DSOP_SCOPE_TYPE_GLOBAL_CATALOG = 0x00000010;
        private const uint DSOP_SCOPE_TYPE_EXTERNAL_UPLEVEL_DOMAIN = 0x00000020;
        private const uint DSOP_SCOPE_TYPE_EXTERNAL_DOWNLEVEL_DOMAIN = 0x00000040;
        private const uint DSOP_SCOPE_TYPE_WORKGROUP = 0x00000080;
        private const uint DSOP_SCOPE_TYPE_USER_ENTERED_UPLEVEL_SCOPE = 0x00000100;
        private const uint DSOP_SCOPE_TYPE_USER_ENTERED_DOWNLEVEL_SCOPE = 0x00000200;

        // Scope init flags
        private const uint DSOP_SCOPE_FLAG_STARTING_SCOPE = 0x00000001;
        private const uint DSOP_SCOPE_FLAG_WANT_PROVIDER_WINNT = 0x00000002;
        private const uint DSOP_SCOPE_FLAG_WANT_PROVIDER_LDAP = 0x00000004;
        private const uint DSOP_SCOPE_FLAG_WANT_PROVIDER_GC = 0x00000008;
        private const uint DSOP_SCOPE_FLAG_WANT_SID_PATH = 0x00000010;
        private const uint DSOP_SCOPE_FLAG_WANT_DOWNLEVEL_BUILTIN_PATH = 0x00000020;
        private const uint DSOP_SCOPE_FLAG_DEFAULT_FILTER_USERS = 0x00000040;
        private const uint DSOP_SCOPE_FLAG_DEFAULT_FILTER_GROUPS = 0x00000080;
        private const uint DSOP_SCOPE_FLAG_DEFAULT_FILTER_COMPUTERS = 0x00000100;
        private const uint DSOP_SCOPE_FLAG_DEFAULT_FILTER_CONTACTS = 0x00000200;

        // Filter flags (uplevel)
        private const uint DSOP_FILTER_INCLUDE_ADVANCED_VIEW = 0x00000001;
        private const uint DSOP_FILTER_USERS = 0x00000002;
        private const uint DSOP_FILTER_BUILTIN_GROUPS = 0x00000004;
        private const uint DSOP_FILTER_WELL_KNOWN_PRINCIPALS = 0x00000008;
        private const uint DSOP_FILTER_UNIVERSAL_GROUPS_DL = 0x00000010;
        private const uint DSOP_FILTER_UNIVERSAL_GROUPS_SE = 0x00000020;
        private const uint DSOP_FILTER_GLOBAL_GROUPS_DL = 0x00000040;
        private const uint DSOP_FILTER_GLOBAL_GROUPS_SE = 0x00000080;
        private const uint DSOP_FILTER_DOMAIN_LOCAL_GROUPS_DL = 0x00000100;
        private const uint DSOP_FILTER_DOMAIN_LOCAL_GROUPS_SE = 0x00000200;
        private const uint DSOP_FILTER_CONTACTS = 0x00000400;
        private const uint DSOP_FILTER_COMPUTERS = 0x00000800;

        // Filter flags (downlevel) - high bit (0x80000000) marks these as downlevel flags per Windows SDK
        private const uint DSOP_DOWNLEVEL_FILTER_USERS = 0x80000001;
        private const uint DSOP_DOWNLEVEL_FILTER_LOCAL_GROUPS = 0x80000002;
        private const uint DSOP_DOWNLEVEL_FILTER_GLOBAL_GROUPS = 0x80000004;
        private const uint DSOP_DOWNLEVEL_FILTER_COMPUTERS = 0x80000008;
        private const uint DSOP_DOWNLEVEL_FILTER_WORLD = 0x80000010;
        private const uint DSOP_DOWNLEVEL_FILTER_AUTHENTICATED_USER = 0x80000020;
        private const uint DSOP_DOWNLEVEL_FILTER_ANONYMOUS = 0x80000040;
        private const uint DSOP_DOWNLEVEL_FILTER_BATCH = 0x80000080;
        private const uint DSOP_DOWNLEVEL_FILTER_CREATOR_OWNER = 0x80000100;
        private const uint DSOP_DOWNLEVEL_FILTER_CREATOR_GROUP = 0x80000200;
        private const uint DSOP_DOWNLEVEL_FILTER_DIALUP = 0x80000400;
        private const uint DSOP_DOWNLEVEL_FILTER_INTERACTIVE = 0x80000800;
        private const uint DSOP_DOWNLEVEL_FILTER_NETWORK = 0x80001000;
        private const uint DSOP_DOWNLEVEL_FILTER_SERVICE = 0x80002000;
        private const uint DSOP_DOWNLEVEL_FILTER_SYSTEM = 0x80004000;
        private const uint DSOP_DOWNLEVEL_FILTER_EXCLUDE_BUILTIN_GROUPS = 0x80008000;
        private const uint DSOP_DOWNLEVEL_FILTER_TERMINAL_SERVER = 0x80010000;
        private const uint DSOP_DOWNLEVEL_FILTER_ALL_WELLKNOWN_SIDS = 0x80020000;
        private const uint DSOP_DOWNLEVEL_FILTER_LOCAL_SERVICE = 0x80040000;
        private const uint DSOP_DOWNLEVEL_FILTER_NETWORK_SERVICE = 0x80080000;
        private const uint DSOP_DOWNLEVEL_FILTER_REMOTE_LOGON = 0x80100000;

        // Init info flags
        private const uint DSOP_FLAG_MULTISELECT = 0x00000001;
        private const uint DSOP_FLAG_SKIP_TARGET_COMPUTER_DC_CHECK = 0x00000002;

        // Clipboard format
        private const string CFSTR_DSOP_DS_SELECTION_LIST = "CFSTR_DSOP_DS_SELECTION_LIST";

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DSOP_SCOPE_INIT_INFO
        {
            public uint cbSize;
            public uint flType;
            public uint flScope;
            public DSOP_FILTER_FLAGS FilterFlags;
            public IntPtr pwzDcName;
            public IntPtr pwzADsPath;
            public int hr;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DSOP_FILTER_FLAGS
        {
            public DSOP_UPLEVEL_FILTER_FLAGS Uplevel;
            public uint flDownlevel;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DSOP_UPLEVEL_FILTER_FLAGS
        {
            public uint flBothModes;
            public uint flMixedModeOnly;
            public uint flNativeModeOnly;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DSOP_INIT_INFO
        {
            public uint cbSize;
            public IntPtr pwzTargetComputer;
            public uint cDsScopeInfos;
            public IntPtr aDsScopeInfos;
            public uint flOptions;
            public uint cAttributesToFetch;
            public IntPtr apwzAttributeNames;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DS_SELECTION
        {
            public IntPtr pwzName;
            public IntPtr pwzADsPath;
            public IntPtr pwzClass;
            public IntPtr pwzUPN;
            public IntPtr pvarFetchedAttributes;
            public uint flScopeType;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DS_SELECTION_LIST
        {
            public uint cItems;
            public uint cFetchedAttributes;
            // DS_SELECTION array follows
        }

        [ComImport, Guid("0C87E64E-3B7A-11D2-B9E0-00C04FD8DBF7"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IDsObjectPicker
        {
            [PreserveSig]
            int Initialize(ref DSOP_INIT_INFO pInitInfo);

            [PreserveSig]
            int InvokeDialog(IntPtr hwndParent, out System.Runtime.InteropServices.ComTypes.IDataObject ppdoSelections);
        }

        [DllImport("ole32.dll")]
        private static extern int CoCreateInstance(
            ref Guid rclsid,
            IntPtr pUnkOuter,
            uint dwClsContext,
            ref Guid riid,
            out IntPtr ppv);

        [DllImport("user32.dll")]
        private static extern ushort RegisterClipboardFormat(string lpszFormat);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetConsoleWindow();

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("kernel32.dll")]
        private static extern IntPtr GlobalLock(IntPtr hMem);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GlobalUnlock(IntPtr hMem);

        [DllImport("netapi32.dll", CharSet = CharSet.Unicode)]
        private static extern int NetGetJoinInformation(
            string server, out IntPtr domain, out int status);

        [DllImport("netapi32.dll")]
        private static extern int NetApiBufferFree(IntPtr buffer);

        private const int NETSETUP_DOMAIN_NAME = 3;

        public static bool IsDomainJoined()
        {
            IntPtr pDomain;
            int joinStatus;
            int hr = NetGetJoinInformation(null, out pDomain, out joinStatus);
            if (hr == 0)
            {
                NetApiBufferFree(pDomain);
                return joinStatus == NETSETUP_DOMAIN_NAME;
            }
            return false;
        }

        // Various diagnostic tests for future debugging, since DSObjectPicker seems to die every other week
        public static string DiagnoseInit(ObjectTypes objectTypes)
        {
            var sb = new StringBuilder();
            sb.AppendLine("ObjectTypes: " + objectTypes.ToString() + " (" + ((int)objectTypes).ToString() + ")");
            sb.AppendLine("Domain joined: " + IsDomainJoined());
            sb.AppendLine("ScopeInfo size: " + Marshal.SizeOf(typeof(DSOP_SCOPE_INIT_INFO)));
            sb.AppendLine("InitInfo size: " + Marshal.SizeOf(typeof(DSOP_INIT_INFO)));
            sb.AppendLine("IntPtr size: " + IntPtr.Size);

            // Build filter flags (local uses SAM-safe filters, no global groups)
            uint localDownlevel = 0;
            uint uplevel = 0;
            if ((objectTypes & ObjectTypes.Users) != 0)
            {
                localDownlevel |= DSOP_DOWNLEVEL_FILTER_USERS;
                uplevel |= DSOP_FILTER_USERS;
            }
            if ((objectTypes & ObjectTypes.Groups) != 0)
            {
                localDownlevel |= DSOP_DOWNLEVEL_FILTER_LOCAL_GROUPS |
                                  DSOP_DOWNLEVEL_FILTER_ALL_WELLKNOWN_SIDS;
                uplevel |= DSOP_FILTER_BUILTIN_GROUPS | DSOP_FILTER_WELL_KNOWN_PRINCIPALS |
                           DSOP_FILTER_GLOBAL_GROUPS_SE | DSOP_FILTER_UNIVERSAL_GROUPS_SE |
                           DSOP_FILTER_DOMAIN_LOCAL_GROUPS_SE;
            }
            if ((objectTypes & ObjectTypes.Computers) != 0)
            {
                localDownlevel |= DSOP_DOWNLEVEL_FILTER_COMPUTERS;
                uplevel |= DSOP_FILTER_COMPUTERS;
            }

            sb.AppendLine("Local downlevel: 0x" + localDownlevel.ToString("X8"));
            sb.AppendLine("Uplevel: 0x" + uplevel.ToString("X8"));

            // Test 1: local scope only with downlevel filter
            sb.AppendLine("Test 1: TARGET_COMPUTER downlevel only");
            sb.AppendLine("  " + TestSingleScope(
                DSOP_SCOPE_TYPE_TARGET_COMPUTER,
                DSOP_SCOPE_FLAG_STARTING_SCOPE | DSOP_SCOPE_FLAG_WANT_PROVIDER_WINNT,
                0, localDownlevel, 0));

            // Test 2: local scope with both uplevel and downlevel
            sb.AppendLine("Test 2: TARGET_COMPUTER both filters");
            sb.AppendLine("  " + TestSingleScope(
                DSOP_SCOPE_TYPE_TARGET_COMPUTER,
                DSOP_SCOPE_FLAG_STARTING_SCOPE | DSOP_SCOPE_FLAG_WANT_PROVIDER_WINNT,
                uplevel, localDownlevel, 0));

            // Test 3: local scope with SKIP_DC_CHECK
            sb.AppendLine("Test 3: TARGET_COMPUTER + SKIP_DC_CHECK");
            sb.AppendLine("  " + TestSingleScope(
                DSOP_SCOPE_TYPE_TARGET_COMPUTER,
                DSOP_SCOPE_FLAG_STARTING_SCOPE | DSOP_SCOPE_FLAG_WANT_PROVIDER_WINNT,
                0, localDownlevel, DSOP_FLAG_SKIP_TARGET_COMPUTER_DC_CHECK));

            // Test 4: combined local+domain scope
            sb.AppendLine("Test 4: TARGET_COMPUTER + UPLEVEL_JOINED + DOWNLEVEL_JOINED");
            sb.AppendLine("  " + TestSingleScope(
                DSOP_SCOPE_TYPE_TARGET_COMPUTER |
                DSOP_SCOPE_TYPE_UPLEVEL_JOINED_DOMAIN |
                DSOP_SCOPE_TYPE_DOWNLEVEL_JOINED_DOMAIN,
                DSOP_SCOPE_FLAG_STARTING_SCOPE |
                DSOP_SCOPE_FLAG_WANT_PROVIDER_WINNT |
                DSOP_SCOPE_FLAG_WANT_PROVIDER_LDAP,
                uplevel, localDownlevel, DSOP_FLAG_SKIP_TARGET_COMPUTER_DC_CHECK));

            return sb.ToString();
        }

        private static string TestSingleScope(uint scopeType, uint scopeFlags, uint uplevel, uint downlevel, uint initOptions)
        {
            IDsObjectPicker picker = null;
            try
            {
                Guid clsid = CLSID_DsObjectPicker;
                Guid iid = typeof(IDsObjectPicker).GUID;
                IntPtr pPicker;
                int hr = CoCreateInstance(ref clsid, IntPtr.Zero, 1, ref iid, out pPicker);
                if (hr != 0) { return "CoCreateInstance failed: 0x" + hr.ToString("X8"); }

                picker = (IDsObjectPicker)Marshal.GetObjectForIUnknown(pPicker);
                Marshal.Release(pPicker);

                int scopeSize = Marshal.SizeOf(typeof(DSOP_SCOPE_INIT_INFO));
                var scope = new DSOP_SCOPE_INIT_INFO();
                scope.cbSize = (uint)scopeSize;
                scope.flType = scopeType;
                scope.flScope = scopeFlags;
                scope.FilterFlags.Uplevel.flBothModes = uplevel;
                scope.FilterFlags.flDownlevel = downlevel;

                IntPtr pScope = Marshal.AllocHGlobal(scopeSize);
                try
                {
                    Marshal.StructureToPtr(scope, pScope, false);

                    var initInfo = new DSOP_INIT_INFO();
                    initInfo.cbSize = (uint)Marshal.SizeOf(typeof(DSOP_INIT_INFO));
                    initInfo.pwzTargetComputer = IntPtr.Zero;
                    initInfo.cDsScopeInfos = 1;
                    initInfo.aDsScopeInfos = pScope;
                    initInfo.flOptions = initOptions;
                    initInfo.cAttributesToFetch = 0;
                    initInfo.apwzAttributeNames = IntPtr.Zero;

                    hr = picker.Initialize(ref initInfo);
                    if (hr == 0) { return "OK"; }
                    return "FAILED: 0x" + hr.ToString("X8");
                }
                finally
                {
                    Marshal.FreeHGlobal(pScope);
                }
            }
            catch (Exception ex)
            {
                return "Exception: " + ex.Message;
            }
            finally
            {
                if (picker != null)
                {
                    try { Marshal.ReleaseComObject(picker); }
                    catch { }
                }
            }
        }

        public static string[] ShowComputerPicker(IntPtr hwndParent, bool multiSelect = false)
        {
            return ShowObjectPicker(hwndParent, ObjectTypes.Computers, multiSelect);
        }

        public static string[] ShowUserPicker(IntPtr hwndParent, bool multiSelect = false)
        {
            return ShowObjectPicker(hwndParent, ObjectTypes.Users, multiSelect);
        }

        public static string[] ShowGroupPicker(IntPtr hwndParent, bool multiSelect = false)
        {
            return ShowObjectPicker(hwndParent, ObjectTypes.Groups, multiSelect);
        }

        // DSObjectPicker requires STA thread - marshals to STA if called from MTA
        public static string[] ShowObjectPicker(IntPtr hwndParent, ObjectTypes objectTypes, bool multiSelect = false)
        {
            // DSObjectPicker COM component requires STA thread
            // If we're on MTA, marshal to a dedicated STA thread
            if (Thread.CurrentThread.GetApartmentState() != ApartmentState.STA)
            {
                string[] staResults = null;
                Exception staException = null;
                
                var staThread = new Thread(() =>
                {
                    try
                    {
                        staResults = ShowObjectPickerCore(hwndParent, objectTypes, multiSelect);
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
                
                if (staException != null)
                {
                    return new string[] { "ERROR: " + staException.Message };
                }
                return staResults ?? new string[0];
            }
            
            return ShowObjectPickerCore(hwndParent, objectTypes, multiSelect);
        }

        // Tries progressively simpler scope configs on E_INVALIDARG: local+domain+GC -> local+domain -> local only.
        // On workgroup machines, skips domain/GC scopes entirely.
        private static string[] ShowObjectPickerCore(IntPtr hwndParent, ObjectTypes objectTypes, bool multiSelect)
        {
            bool domainJoined = IsDomainJoined();
            int startScopes = domainJoined ? 3 : 1;
            string[] lastResults = null;

            for (int maxScopes = startScopes; maxScopes >= 1; maxScopes--)
            {
                lastResults = ShowObjectPickerCoreInternal(hwndParent, objectTypes, multiSelect, maxScopes, !domainJoined);

                if (lastResults.Length == 0 || lastResults[0] == null || !lastResults[0].Contains("0x80070057"))
                {
                    return lastResults;
                }
            }

            return lastResults ?? new string[] { "ERROR: All scope configurations failed (E_INVALIDARG)" };
        }

        private static string[] ShowObjectPickerCoreInternal(IntPtr hwndParent, ObjectTypes objectTypes, bool multiSelect, int maxScopes, bool workgroupMode)
        {
            var results = new List<string>();
            IDsObjectPicker picker = null;

            try
            {
                Guid clsid = CLSID_DsObjectPicker;
                Guid iid = typeof(IDsObjectPicker).GUID;
                IntPtr pPicker;
                int hr = CoCreateInstance(ref clsid, IntPtr.Zero, 1 /* CLSCTX_INPROC_SERVER */, ref iid, out pPicker);

                if (hr != 0)
                {
                    throw new Exception("Failed to create DSObjectPicker: 0x" + hr.ToString("X8"));
                }

                picker = (IDsObjectPicker)Marshal.GetObjectForIUnknown(pPicker);
                Marshal.Release(pPicker);

                // InvokeDialog requires a valid parent window handle (NULL causes E_INVALIDARG)
                if (hwndParent == IntPtr.Zero)
                {
                    hwndParent = GetConsoleWindow();
                }
                if (hwndParent == IntPtr.Zero)
                {
                    hwndParent = GetForegroundWindow();
                }

                // Local downlevel filter: only object types that exist in the local SAM.
                // Global groups are a domain-only concept and cause E_INVALIDARG on workgroup machines.
                uint localDownlevelFilter = 0;
                if ((objectTypes & ObjectTypes.Users) != 0)
                    localDownlevelFilter |= DSOP_DOWNLEVEL_FILTER_USERS;
                if ((objectTypes & ObjectTypes.Groups) != 0)
                    localDownlevelFilter |= DSOP_DOWNLEVEL_FILTER_LOCAL_GROUPS |
                                            DSOP_DOWNLEVEL_FILTER_ALL_WELLKNOWN_SIDS;
                if ((objectTypes & ObjectTypes.Computers) != 0)
                    localDownlevelFilter |= DSOP_DOWNLEVEL_FILTER_COMPUTERS;

                // Domain downlevel filter: adds global groups which only exist in domain context
                uint domainDownlevelFilter = localDownlevelFilter;
                if ((objectTypes & ObjectTypes.Groups) != 0)
                    domainDownlevelFilter |= DSOP_DOWNLEVEL_FILTER_GLOBAL_GROUPS;

                // Uplevel filter (LDAP provider - Active Directory)
                uint uplevelFilter = 0;
                if ((objectTypes & ObjectTypes.Users) != 0)
                    uplevelFilter |= DSOP_FILTER_USERS;
                if ((objectTypes & ObjectTypes.Groups) != 0)
                    uplevelFilter |= DSOP_FILTER_BUILTIN_GROUPS | DSOP_FILTER_WELL_KNOWN_PRINCIPALS |
                                     DSOP_FILTER_GLOBAL_GROUPS_SE | DSOP_FILTER_UNIVERSAL_GROUPS_SE |
                                     DSOP_FILTER_DOMAIN_LOCAL_GROUPS_SE |
                                     DSOP_FILTER_GLOBAL_GROUPS_DL | DSOP_FILTER_UNIVERSAL_GROUPS_DL |
                                     DSOP_FILTER_DOMAIN_LOCAL_GROUPS_DL;
                if ((objectTypes & ObjectTypes.Computers) != 0)
                    uplevelFilter |= DSOP_FILTER_COMPUTERS;

                // GC-safe uplevel: strip domain-local and builtin groups (not replicated to GC)
                uint gcUplevelFilter = 0;
                if ((objectTypes & ObjectTypes.Users) != 0)
                    gcUplevelFilter |= DSOP_FILTER_USERS;
                if ((objectTypes & ObjectTypes.Groups) != 0)
                    gcUplevelFilter |= DSOP_FILTER_WELL_KNOWN_PRINCIPALS |
                                       DSOP_FILTER_GLOBAL_GROUPS_SE | DSOP_FILTER_UNIVERSAL_GROUPS_SE |
                                       DSOP_FILTER_GLOBAL_GROUPS_DL | DSOP_FILTER_UNIVERSAL_GROUPS_DL;
                if ((objectTypes & ObjectTypes.Computers) != 0)
                    gcUplevelFilter |= DSOP_FILTER_COMPUTERS;

                // Pre-check the object type checkboxes in the dialog
                uint defaultFilterFlags = 0;
                if ((objectTypes & ObjectTypes.Users) != 0)
                    defaultFilterFlags |= DSOP_SCOPE_FLAG_DEFAULT_FILTER_USERS;
                if ((objectTypes & ObjectTypes.Groups) != 0)
                    defaultFilterFlags |= DSOP_SCOPE_FLAG_DEFAULT_FILTER_GROUPS;
                if ((objectTypes & ObjectTypes.Computers) != 0)
                    defaultFilterFlags |= DSOP_SCOPE_FLAG_DEFAULT_FILTER_COMPUTERS;

                var scopeList = new List<DSOP_SCOPE_INIT_INFO>();
                int scopeSize = Marshal.SizeOf(typeof(DSOP_SCOPE_INIT_INFO));

                // Scope 1 (always): local computer - uses local SAM filter (no global groups)
                var localScope = new DSOP_SCOPE_INIT_INFO();
                localScope.cbSize = (uint)scopeSize;
                localScope.flType = DSOP_SCOPE_TYPE_TARGET_COMPUTER;
                localScope.flScope = DSOP_SCOPE_FLAG_STARTING_SCOPE |
                                     DSOP_SCOPE_FLAG_WANT_PROVIDER_WINNT |
                                     DSOP_SCOPE_FLAG_WANT_SID_PATH |
                                     DSOP_SCOPE_FLAG_WANT_DOWNLEVEL_BUILTIN_PATH |
                                     defaultFilterFlags;
                // Workgroup machines access TARGET_COMPUTER via WinNT (downlevel only).
                // Non-zero uplevel filters cause the scope to be silently discarded.
                if (!workgroupMode)
                {
                    localScope.FilterFlags.Uplevel.flBothModes = uplevelFilter;
                }
                localScope.FilterFlags.flDownlevel = localDownlevelFilter;
                scopeList.Add(localScope);

                // Scope 2 (if maxScopes >= 2): joined domain - includes global groups
                if (maxScopes >= 2)
                {
                    var domainScope = new DSOP_SCOPE_INIT_INFO();
                    domainScope.cbSize = (uint)scopeSize;
                    domainScope.flType = DSOP_SCOPE_TYPE_UPLEVEL_JOINED_DOMAIN |
                                         DSOP_SCOPE_TYPE_DOWNLEVEL_JOINED_DOMAIN;
                    domainScope.flScope = DSOP_SCOPE_FLAG_WANT_PROVIDER_LDAP | defaultFilterFlags;
                    domainScope.FilterFlags.Uplevel.flBothModes = uplevelFilter;
                    domainScope.FilterFlags.flDownlevel = domainDownlevelFilter;
                    scopeList.Add(domainScope);
                }

                // Scope 3 (if maxScopes >= 3): Global Catalog with GC-safe filter
                if (maxScopes >= 3 && gcUplevelFilter != 0)
                {
                    var gcScope = new DSOP_SCOPE_INIT_INFO();
                    gcScope.cbSize = (uint)scopeSize;
                    gcScope.flType = DSOP_SCOPE_TYPE_GLOBAL_CATALOG;
                    gcScope.flScope = DSOP_SCOPE_FLAG_WANT_PROVIDER_GC | defaultFilterFlags;
                    gcScope.FilterFlags.Uplevel.flBothModes = gcUplevelFilter;
                    scopeList.Add(gcScope);
                }

                System.Runtime.InteropServices.ComTypes.IDataObject dataObject = null;
                IntPtr pScopeInfos = Marshal.AllocHGlobal(scopeSize * scopeList.Count);
                try
                {
                    for (int i = 0; i < scopeList.Count; i++)
                    {
                        IntPtr pScope = new IntPtr(pScopeInfos.ToInt64() + (i * scopeSize));
                        Marshal.StructureToPtr(scopeList[i], pScope, false);
                    }

                    var initInfo = new DSOP_INIT_INFO();
                    initInfo.cbSize = (uint)Marshal.SizeOf(typeof(DSOP_INIT_INFO));
                    initInfo.pwzTargetComputer = IntPtr.Zero;
                    initInfo.cDsScopeInfos = (uint)scopeList.Count;
                    initInfo.aDsScopeInfos = pScopeInfos;
                    initInfo.flOptions = DSOP_FLAG_SKIP_TARGET_COMPUTER_DC_CHECK |
                                         (multiSelect ? DSOP_FLAG_MULTISELECT : 0);
                    initInfo.cAttributesToFetch = 0;
                    initInfo.apwzAttributeNames = IntPtr.Zero;

                    hr = picker.Initialize(ref initInfo);
                    if (hr != 0)
                    {
                        results.Add("ERROR: Initialize returned 0x" + hr.ToString("X8") +
                            " (objectTypes=" + objectTypes.ToString() +
                            ", scopes=" + scopeList.Count +
                            ", uplevel=0x" + uplevelFilter.ToString("X8") +
                            ", localDL=0x" + localDownlevelFilter.ToString("X8") +
                            ", domainDL=0x" + domainDownlevelFilter.ToString("X8") +
                            ", gcUplevel=0x" + gcUplevelFilter.ToString("X8") + ")");
                        return results.ToArray();
                    }

                    // Show the dialog
                    hr = picker.InvokeDialog(hwndParent, out dataObject);
                }
                finally
                {
                    Marshal.FreeHGlobal(pScopeInfos);
                }

                // S_FALSE (1) means user cancelled, S_OK (0) means selection made
                if (hr == 1)
                {
                    // User cancelled
                    return results.ToArray();
                }
                if (hr != 0)
                {
                    results.Add("ERROR: InvokeDialog returned 0x" + hr.ToString("X8"));
                    return results.ToArray();
                }
                if (dataObject == null)
                {
                    results.Add("ERROR: dataObject is null but hr=0");
                    return results.ToArray();
                }

                // Extract selections from the data object
                try
                {
                    ushort cfFormat = RegisterClipboardFormat(CFSTR_DSOP_DS_SELECTION_LIST);

                    var formatEtc = new System.Runtime.InteropServices.ComTypes.FORMATETC();
                    formatEtc.cfFormat = (short)cfFormat;
                    formatEtc.ptd = IntPtr.Zero;
                    formatEtc.dwAspect = System.Runtime.InteropServices.ComTypes.DVASPECT.DVASPECT_CONTENT;
                    formatEtc.lindex = -1;
                    formatEtc.tymed = System.Runtime.InteropServices.ComTypes.TYMED.TYMED_HGLOBAL;

                    System.Runtime.InteropServices.ComTypes.STGMEDIUM stgMedium;
                    dataObject.GetData(ref formatEtc, out stgMedium);

                    if (stgMedium.unionmember != IntPtr.Zero)
                    {
                        IntPtr pData = GlobalLock(stgMedium.unionmember);
                        if (pData != IntPtr.Zero)
                        {
                            try
                            {
                                var selectionList = (DS_SELECTION_LIST)Marshal.PtrToStructure(pData, typeof(DS_SELECTION_LIST));
                                IntPtr pSelections = new IntPtr(pData.ToInt64() + Marshal.SizeOf(typeof(DS_SELECTION_LIST)));

                                for (uint i = 0; i < selectionList.cItems; i++)
                                {
                                    var selection = (DS_SELECTION)Marshal.PtrToStructure(
                                        new IntPtr(pSelections.ToInt64() + (i * Marshal.SizeOf(typeof(DS_SELECTION)))),
                                        typeof(DS_SELECTION));

                                    if (selection.pwzName != IntPtr.Zero)
                                    {
                                        string name = Marshal.PtrToStringUni(selection.pwzName);
                                        if (!string.IsNullOrEmpty(name))
                                        {
                                            results.Add(name);
                                        }
                                    }
                                }
                            }
                            finally
                            {
                                GlobalUnlock(stgMedium.unionmember);
                            }
                        }

                        Marshal.FreeHGlobal(stgMedium.unionmember);
                    }
                }
                finally
                {
                    Marshal.ReleaseComObject(dataObject);
                }
            }
            catch (Exception ex)
            {
                // Return exception info for debugging
                results.Add("ERROR: " + ex.Message);
            }
            finally
            {
                // Ensure COM object is released deterministically (don't rely on GC)
                if (picker != null)
                {
                    try { Marshal.ReleaseComObject(picker); }
                    catch { /* Ignore release errors */ }
                }
            }

            return results.ToArray();
        }
    }
}
