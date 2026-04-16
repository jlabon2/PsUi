using System;
using System.Threading.Tasks;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace PsUi
{
    // Helper for WebView2 initialization, runtime detection, and event routing.
    public static class WebViewHelper
    {
        private static bool? _isRuntimeAvailable;
        private static string _runtimeVersion;

        // Checks if the WebView2 runtime is installed on the system.
        public static bool IsRuntimeAvailable
        {
            get
            {
                if (_isRuntimeAvailable.HasValue)
                {
                    return _isRuntimeAvailable.Value;
                }

                try
                {
                    _runtimeVersion = CoreWebView2Environment.GetAvailableBrowserVersionString();
                    _isRuntimeAvailable = !string.IsNullOrEmpty(_runtimeVersion);
                }
                catch
                {
                    _isRuntimeAvailable = false;
                    _runtimeVersion = null;
                }

                return _isRuntimeAvailable.Value;
            }
        }

        // Gets the installed WebView2 runtime version, or null if not installed.
        public static string RuntimeVersion
        {
            get
            {
                var _ = IsRuntimeAvailable;
                return _runtimeVersion;
            }
        }

        // Creates a WebView2 control and starts async initialization.
        public static WebView2 Create(string userDataFolder = null)
        {
            if (!IsRuntimeAvailable)
            {
                return null;
            }

            var webView = new WebView2();
            
            var dataFolder = userDataFolder;
            if (string.IsNullOrEmpty(dataFolder))
            {
                // Include PID + random suffix to prevent predictable path attacks
                dataFolder = System.IO.Path.Combine(
                    System.IO.Path.GetTempPath(), 
                    "PsUi_WebView2_" + System.Diagnostics.Process.GetCurrentProcess().Id + "_" + Guid.NewGuid().ToString("N").Substring(0, 8));
            }
            
            webView.Loaded += async (s, e) =>
            {
                // async void - must catch everything or unhandled exceptions crash the process
                try
                {
                    var env = await CoreWebView2Environment.CreateAsync(null, dataFolder);
                    await webView.EnsureCoreWebView2Async(env);
                }
                catch (Exception ex)
                {
                    DebugHelper.LogException("WEBVIEW", "EnsureCoreWebView2Async", ex);
                    System.Console.Error.WriteLine("[PsUi] WebView2 init failed: " + ex.Message);
                }
            };

            return webView;
        }

        // Applies security settings to a WebView2 control.
        public static void ApplySecuritySettings(WebView2 webView, bool enableScripts = false, bool enableDevTools = false, bool enableDownloads = false)
        {
            if (webView == null || webView.CoreWebView2 == null)
            {
                return;
            }

            var settings = webView.CoreWebView2.Settings;
            settings.IsScriptEnabled = enableScripts;
            settings.AreDevToolsEnabled = enableDevTools;
            settings.IsGeneralAutofillEnabled = false;
            settings.IsPasswordAutosaveEnabled = false;
            settings.IsStatusBarEnabled = false;
            settings.AreDefaultContextMenusEnabled = true;
            
            if (!enableDownloads)
            {
                webView.CoreWebView2.DownloadStarting += (s, e) => { e.Cancel = true; };
            }
            
            // Block popup windows - scripts with window.open() shouldn't escape the sandbox
            webView.CoreWebView2.NewWindowRequested += (s, e) => { e.Handled = true; };
        }

        // Navigates to HTML content.
        public static void NavigateToHtml(WebView2 webView, string html)
        {
            if (webView == null || webView.CoreWebView2 == null || string.IsNullOrEmpty(html))
            {
                return;
            }

            webView.CoreWebView2.NavigateToString(html);
        }

        // Gets a user-friendly error message when runtime is missing.
        public static string GetMissingRuntimeMessage()
        {
            return "WebView2 runtime is not installed.\n\n" +
                   "Download from: https://developer.microsoft.com/en-us/microsoft-edge/webview2/\n\n" +
                   "Or install via winget:\n  winget install Microsoft.EdgeWebView2Runtime";
        }

        // Cleans up orphaned WebView2 user data folders from previous sessions.
        public static void CleanupOldUserDataFolders()
        {
            Task.Run(() =>
            {
                try
                {
                    var tempPath = System.IO.Path.GetTempPath();
                    var currentPid = System.Diagnostics.Process.GetCurrentProcess().Id.ToString();
                    var dirs = System.IO.Directory.GetDirectories(tempPath, "PsUi_WebView2_*");
                    
                    foreach (var dir in dirs)
                    {
                        // Skip folders belonging to the current process (PsUi_WebView2_PID_RANDOM format)
                        var folderName = System.IO.Path.GetFileName(dir);
                        if (folderName.StartsWith("PsUi_WebView2_" + currentPid + "_")) continue;
                        
                        try { System.IO.Directory.Delete(dir, true); }
                        catch (Exception ex) { DebugHelper.Log("WEBVIEW", "Cleanup skipped " + dir + ": " + ex.Message); }
                    }
                }
                catch (Exception ex) { DebugHelper.Log("WEBVIEW", "Cleanup sweep failed: " + ex.Message); }
            });
        }
    }
}
