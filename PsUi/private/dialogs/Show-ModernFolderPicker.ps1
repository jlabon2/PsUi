function Show-ModernFolderPicker {
    <#
    .SYNOPSIS
        Modern folder picker using Windows Shell IFileOpenDialog COM interface.
    #>
    param(
        [string]$Title,
        [string]$InitialDirectory,
        [switch]$Multiselect
    )
    
    # IFileOpenDialog COM interop for Vista-style folder picker (works in PS 5.1 and 7+)
    $showDialog = {
        param($dialogTitle, $initialDir, $allowMulti)
        
        # Add the COM interop types for IFileOpenDialog
        $comTypes = @'
using System;
using System.Runtime.InteropServices;

namespace PsUiDialogs
{
    [ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
    internal class FileOpenDialog { }

    [ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IFileOpenDialog
    {
        [PreserveSig] int Show(IntPtr hwndOwner);
        void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
        void SetFileTypeIndex(uint iFileType);
        void GetFileTypeIndex(out uint piFileType);
        void Advise(IntPtr pfde, out uint pdwCookie);
        void Unadvise(uint dwCookie);
        void SetOptions(uint fos);
        void GetOptions(out uint pfos);
        void SetDefaultFolder(IShellItem psi);
        void SetFolder(IShellItem psi);
        void GetFolder(out IShellItem ppsi);
        void GetCurrentSelection(out IShellItem ppsi);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void GetResult(out IShellItem ppsi);
        void AddPlace(IShellItem psi, int fdap);
        void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
        void Close(int hr);
        void SetClientGuid(ref Guid guid);
        void ClearClientData();
        void SetFilter(IntPtr pFilter);
        void GetResults(out IShellItemArray ppenum);
        void GetSelectedItems(out IShellItemArray ppsai);
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellItem
    {
        void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
        void GetParent(out IShellItem ppsi);
        void GetDisplayName(uint sigdnName, [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
        void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
        void Compare(IShellItem psi, uint hint, out int piOrder);
    }

    [ComImport, Guid("b63ea76d-1f85-456f-a19c-48159efa858b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellItemArray
    {
        void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppvOut);
        void GetPropertyStore(int flags, ref Guid riid, out IntPtr ppv);
        void GetPropertyDescriptionList(IntPtr keyType, ref Guid riid, out IntPtr ppv);
        void GetAttributes(int AttribFlags, uint sfgaoMask, out uint psfgaoAttribs);
        void GetCount(out uint pdwNumItems);
        void GetItemAt(uint dwIndex, out IShellItem ppsi);
        void EnumItems(out IntPtr ppenumShellItems);
    }

    public static class FolderPicker
    {
        private const uint FOS_PICKFOLDERS = 0x00000020;
        private const uint FOS_ALLOWMULTISELECT = 0x00000200;
        private const uint FOS_FORCEFILESYSTEM = 0x00000040;
        private const uint SIGDN_FILESYSPATH = 0x80058000;

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        private static extern void SHCreateItemFromParsingName(
            [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
            IntPtr pbc,
            [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
            out IShellItem ppv);

        public static string[] ShowDialog(IntPtr hwnd, string title, string initialDir, bool multiSelect)
        {
            IFileOpenDialog dialog = null;
            try
            {
                dialog = (IFileOpenDialog)new FileOpenDialog();

                uint options = FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM;
                if (multiSelect) options |= FOS_ALLOWMULTISELECT;
                dialog.SetOptions(options);

                if (!string.IsNullOrEmpty(title))
                    dialog.SetTitle(title);

                IShellItem initialFolder = null;
                if (!string.IsNullOrEmpty(initialDir) && System.IO.Directory.Exists(initialDir))
                {
                    SHCreateItemFromParsingName(initialDir, IntPtr.Zero, typeof(IShellItem).GUID, out initialFolder);
                    if (initialFolder != null)
                        dialog.SetFolder(initialFolder);
                }

                int hr = dialog.Show(hwnd);
                if (hr != 0)
                {
                    if (initialFolder != null) Marshal.ReleaseComObject(initialFolder);
                    return null;
                }

                if (multiSelect)
                {
                    IShellItemArray results;
                    dialog.GetResults(out results);
                    uint count;
                    results.GetCount(out count);
                    string[] paths = new string[count];
                    for (uint i = 0; i < count; i++)
                    {
                        IShellItem item;
                        results.GetItemAt(i, out item);
                        string path;
                        item.GetDisplayName(SIGDN_FILESYSPATH, out path);
                        paths[i] = path;
                        if (item != null) Marshal.ReleaseComObject(item);
                    }
                    if (results != null) Marshal.ReleaseComObject(results);
                    if (initialFolder != null) Marshal.ReleaseComObject(initialFolder);
                    return paths;
                }
                else
                {
                    IShellItem result;
                    dialog.GetResult(out result);
                    string path;
                    result.GetDisplayName(SIGDN_FILESYSPATH, out path);
                    if (result != null) Marshal.ReleaseComObject(result);
                    if (initialFolder != null) Marshal.ReleaseComObject(initialFolder);
                    return new string[] { path };
                }
            }
            catch
            {
                return null;
            }
            finally
            {
                if (dialog != null)
                    Marshal.ReleaseComObject(dialog);
            }
        }
    }
}
'@
        
        # Compile COM interop types if not loaded (SilentlyContinue handles module reload)
        if (!([System.Management.Automation.PSTypeName]'PsUiDialogs.FolderPicker').Type) {
            Add-Type -TypeDefinition $comTypes -Language CSharp -ErrorAction SilentlyContinue
        }
        
        $result = [PsUiDialogs.FolderPicker]::ShowDialog([IntPtr]::Zero, $dialogTitle, $initialDir, $allowMulti)
        
        if ($result -and $result.Count -gt 0) {
            if ($allowMulti) { return $result }
            else { return $result[0] }
        }
        return $null
    }

    # If we're inside a PsUi window, use its dispatcher to show the dialog
    $session = Get-UiSession -ErrorAction SilentlyContinue
    if ($session -and $session.Window) {
        return $session.Window.Dispatcher.Invoke([Func[object]]{
            & $showDialog $Title $InitialDirectory $Multiselect.IsPresent
        })
    }

    # No UI context - run in STA runspace (COM dialogs require STA)
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($showDialog)
    [void]$ps.AddArgument($Title)
    [void]$ps.AddArgument($InitialDirectory)
    [void]$ps.AddArgument($Multiselect.IsPresent)

    try {
        $result = $ps.Invoke()
        return $result
    }
    finally {
        $ps.Dispose()
        $runspace.Dispose()
    }
}
