using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Security;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

namespace PsUi
{
    // State sync between WPF controls and PowerShell variables.
    // Hydrate = inject control values as variables before script runs.
    // Dehydrate = sync changed variables back to controls after.
    //
    // This is intentionally by-value, not by-reference. We're copying UI state (strings,
    // booleans, selected items) into the runspace, not proxying arbitrary .NET objects.
    // Complex SDK objects won't round-trip well - that's by design. If you need to mutate
    // a heavy object across button clicks, store it in $session.Variables directly and
    // manage it yourself.. The hydration layer is for form data, not object graphs.
    //
    // Two buttons clicking simultaneously can both dehydrate and
    // last-write-wins. This is inherent to async UI. Don't be a jackass and build forms where 
    // two buttons fight over the same control value.
    public static class StateHydrationEngine
    {
        private static void DebugLog(string category, string message)
        {
            SessionContext session = SessionManager.Current;
            if (session != null && session.DebugMode)
            {
                Console.WriteLine("[{0}] {1}", category, message);
            }
        }
        
        private static void DebugLog(string category, string format, params object[] args)
        {
            SessionContext session = SessionManager.Current;
            if (session != null && session.DebugMode)
            {
                Console.WriteLine("[{0}] {1}", category, string.Format(format, args));
            }
        }
        
        // Catches certain issues: user creates SQL connection in Button A, tries to use it
        // in Button B, and wonders why it shit the bed. These types dont survive runspace boundaries
        // because theyre serialized/deserialized, not passed by reference. We warn so users dont
        // spend 3 hours debugging "connection is closed" errors.
        private static bool IsLiveObjectType(object value)
        {
            if (value == null) return false;
            
            Type t = value.GetType();
            string typeName = t.FullName ?? "";
            
            // Database connections, streams, sockets, COM crap - all gonna die on the trip
            if (typeName.Contains("System.Data.SqlClient") ||
                typeName.Contains("System.Data.Common.DbConnection") ||
                typeName.Contains("System.IO.Stream") ||
                typeName.Contains("System.Net.Sockets") ||
                typeName.Contains("System.__ComObject") ||
                typeName.Contains("Microsoft.Office.Interop"))
            {
                return true;
            }
            
            // IDisposable thats not a known-safe type = probably holding a native handle
            if (value is IDisposable && !(value is PSCredential) && !(value is SecureString))
            {
                return true;
            }
            
            return false;
        }
        
        // Validate variable name for PS injection - rejects empty, reserved, or unsafe names
        private static string ValidateVariableName(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return null;
            
            // Skip reserved variables (uses shared Constants)
            if (Constants.IsReservedVariable(name)) return null;
            
            // Reject anything that smells like injection
            if (!Constants.IsValidIdentifier(name))
            {
                DebugLog("SECURITY", "Rejected invalid variable name: {0}", name);
                return null;
            }
            
            return name;
        }

        // Hydrate runspace with all registered control values - call BEFORE user script runs
        // Returns initial values for dehydration comparison
        public static Dictionary<string, object> Hydrate(Runspace runspace, HashSet<string> alreadyDefinedVariables = null)
        {
            var initialValues = new Dictionary<string, object>();
            SessionContext session = SessionManager.Current;
            if (session == null) return initialValues;

            // Get the dispatcher for UI thread access
            System.Windows.Threading.Dispatcher dispatcher = null;
            if (session.Window != null)
            {
                dispatcher = session.Window.Dispatcher;
            }

            // Track collisions for warning
            var collisions = new List<string>();
            
            // Build list of controls to read (filtering invalid/collision names first)
            var controlsToRead = new List<KeyValuePair<string, FrameworkElement>>();
            foreach (var kvp in session.SafeVariables)
            {
                string varName = kvp.Key;
                
                // Skip reserved or invalid variable names
                string validName = ValidateVariableName(varName);
                if (validName == null) continue;
                
                // Skip variables already defined (collision - LinkedVariable wins)
                if (alreadyDefinedVariables != null && alreadyDefinedVariables.Contains(validName))
                {
                    collisions.Add(validName);
                    continue;
                }
                
                ThreadSafeControlProxy proxy = kvp.Value;
                if (proxy.Control != null)
                {
                    controlsToRead.Add(new KeyValuePair<string, FrameworkElement>(validName, proxy.Control));
                }
            }
            
            // Pull all values in one dispatcher call
            if (controlsToRead.Count > 0)
            {
                initialValues = ControlValueExtractor.ExtractAll(controlsToRead, dispatcher);
                
                // Inject into runspace
                foreach (var kvp in initialValues)
                {
                    try
                    {
                        runspace.SessionStateProxy.PSVariable.Set(kvp.Key, kvp.Value);
                    }
                    catch (Exception ex)
                    {
                        DebugLog("HYDRATION", "Failed to inject '{0}': {1}", kvp.Key, ex.Message);
                    }
                }
            }
            
            // Log collisions when debug mode is enabled
            if (collisions.Count > 0)
            {
                DebugLog("HYDRATION", "Skipped {0} control(s) due to collision with LinkedVariables: {1}", 
                    collisions.Count, string.Join(", ", collisions));
            }

            // Inject list collections directly so $listName.Add() works
            HydrateListCollections(runspace);
            
            // Inject previously captured variables for cross-button access
            HydrateCapturedVariables(runspace, alreadyDefinedVariables, initialValues);

            return initialValues;
        }

        // Hydrate via PS instance for pooled runspaces - injects all values in one script call
        public static Dictionary<string, object> HydrateViaScript(PowerShell ps, HashSet<string> alreadyDefinedVariables = null)
        {
            var initialValues = new Dictionary<string, object>();
            SessionContext session = SessionManager.Current;
            if (session == null) return initialValues;

            System.Windows.Threading.Dispatcher dispatcher = null;
            if (session.Window != null)
            {
                dispatcher = session.Window.Dispatcher;
            }

            // Track collisions for warning
            var collisions = new List<string>();

            // Build list of controls to read (filtering invalid/collision names first)
            var controlsToRead = new List<KeyValuePair<string, FrameworkElement>>();
            foreach (var kvp in session.SafeVariables)
            {
                string varName = kvp.Key;
                
                // Skip reserved or invalid variable names
                string validName = ValidateVariableName(varName);
                if (validName == null) continue;
                
                // Skip variables already defined (collision - LinkedVariable wins)
                if (alreadyDefinedVariables != null && alreadyDefinedVariables.Contains(validName))
                {
                    collisions.Add(validName);
                    continue;
                }
                
                ThreadSafeControlProxy proxy = kvp.Value;
                if (proxy.Control != null)
                {
                    controlsToRead.Add(new KeyValuePair<string, FrameworkElement>(validName, proxy.Control));
                }
            }
            
            // Grab all control values in one dispatcher round-trip
            if (controlsToRead.Count > 0)
            {
                initialValues = ControlValueExtractor.ExtractAll(controlsToRead, dispatcher);
            }
            
            // Log collisions when debug mode is enabled
            if (collisions.Count > 0)
            {
                DebugLog("HYDRATION", "Skipped {0} control(s) due to collision with LinkedVariables: {1}", 
                    collisions.Count, string.Join(", ", collisions));
            }

            // Build list of values to inject (separating SecureStrings)
            var valuesToInject = new List<KeyValuePair<string, object>>();
            foreach (var kvp in initialValues)
            {
                valuesToInject.Add(kvp);
            }

            // Inject all variables in a single round-trip
            if (valuesToInject.Count > 0)
            {
                // Separate SecureStrings - they need special handling via Runspace directly
                var secureStrings = new List<KeyValuePair<string, SecureString>>();
                var regularValues = new List<KeyValuePair<string, object>>();
                
                foreach (var kvp in valuesToInject)
                {
                    if (kvp.Value is SecureString)
                    {
                        secureStrings.Add(new KeyValuePair<string, SecureString>(kvp.Key, (SecureString)kvp.Value));
                    }
                    else
                    {
                        regularValues.Add(kvp);
                    }
                }
                
                // Inject SecureStrings directly via Runspace (bypasses serialization issues)
                if (secureStrings.Count > 0 && ps.Runspace != null)
                {
                    foreach (var kvp in secureStrings)
                    {
                        try
                        {
                            ps.Runspace.SessionStateProxy.PSVariable.Set(kvp.Key, kvp.Value);
                        }
                        catch (Exception ex)
                        {
                            DebugLog("HYDRATION", "SecureString injection failed: {0}", ex.Message);
                        }
                    }
                }
                
                // Inject regular values via param block script.
                // We use Global scope because the alternative is passing 15+ parameters to every
                // button action. Users want to just write $userName and have it work. The scope
                // pollution is contained - this runspace dies when the button click finishes,
                // and we block reserved names like $Path, $HOME, etc. in Constants.cs.
                if (regularValues.Count > 0)
                {
                    ps.Commands.Clear();
                    var sb = new System.Text.StringBuilder();
                    sb.Append("param(");
                    for (int i = 0; i < regularValues.Count; i++)
                    {
                        if (i > 0) sb.Append(", ");
                        sb.AppendFormat("$p{0}", i);
                    }
                    sb.AppendLine(")");
                    
                    for (int i = 0; i < regularValues.Count; i++)
                    {
                        // Use ${Global:name} syntax to support hyphens and special chars
                        sb.AppendFormat("${{Global:{0}}} = $p{1}\n", regularValues[i].Key, i);
                    }
                    
                    ps.AddScript(sb.ToString());
                    foreach (var kvp in regularValues)
                    {
                        ps.AddArgument(kvp.Value);
                    }
                    
                    try 
                    { 
                        ps.Invoke();
                    }
                    catch (Exception ex)
                    {
                        DebugLog("HYDRATION", "Batch variable injection failed: {0}", ex.Message);
                    }
                    ps.Commands.Clear();
                }
            }

            // Inject list collections directly so $listName.Add() works
            HydrateListCollectionsViaScript(ps);
            
            // Inject PSCredential objects from credential wrappers stored in session.Variables
            HydrateCredentialsViaScript(ps, alreadyDefinedVariables, initialValues);
            
            // Inject previously captured variables so they're available in subsequent button actions
            HydrateCapturedVariablesViaScript(ps, alreadyDefinedVariables, initialValues);

            return initialValues;
        }

        // Inject list collections so $listName.Add() works. Skips if control exists (selected items take precedence).
        private static void HydrateListCollections(Runspace runspace)
        {
            SessionContext session = SessionManager.Current;
            if (session == null) return;
            
            string[] listKeys = session.GetAllListKeys();
            foreach (string key in listKeys)
            {
                string validName = ValidateVariableName(key);
                if (validName == null) continue;
                
                // Skip if a control exists with this name - the control value (selected items)
                // should take precedence over the raw collection
                ThreadSafeControlProxy proxy = session.GetSafeVariable(key);
                if (proxy != null) continue;
                
                IList collection = session.GetListCollection(key);
                if (collection != null)
                {
                    try
                    {
                        runspace.SessionStateProxy.PSVariable.Set(validName, collection);
                    }
                    catch (Exception ex)
                    {
                        DebugHelper.LogException("HYDRATION", string.Format("Inject list collection '{0}'", validName), ex);
                    }
                }
            }
        }
        
        // Inject previously captured variables for cross-button access
        private static void HydrateCapturedVariables(Runspace runspace, HashSet<string> alreadyDefinedVariables, Dictionary<string, object> initialValues)
        {
            SessionContext session = SessionManager.Current;
            if (session == null) return;
            
            var capturedVars = session.CapturedVariables;
            if (capturedVars == null || capturedVars.Count == 0) return;
            
            foreach (var kvp in capturedVars)
            {
                string varName = kvp.Key;
                
                // Skip if already defined by LinkedVariables
                if (alreadyDefinedVariables != null && alreadyDefinedVariables.Contains(varName)) continue;
                
                string validName = ValidateVariableName(varName);
                if (validName == null) continue;
                
                try
                {
                    runspace.SessionStateProxy.PSVariable.Set(validName, kvp.Value);
                    
                    // Track for dehydration
                    if (!initialValues.ContainsKey(validName))
                    {
                        initialValues[validName] = kvp.Value;
                    }
                    
                    DebugLog("HYDRATION", "Injected captured variable '{0}'", validName);
                }
                catch (Exception ex)
                {
                    DebugLog("HYDRATION", "Failed to inject captured variable '{0}': {1}", validName, ex.Message);
                }
            }
        }

        // Inject list collections via script for pooled execution
        private static void HydrateListCollectionsViaScript(PowerShell ps)
        {
            SessionContext session = SessionManager.Current;
            if (session == null) return;
            
            string[] listKeys = session.GetAllListKeys();
            var collectionsToInject = new List<KeyValuePair<string, IList>>();
            
            foreach (string key in listKeys)
            {
                string validName = ValidateVariableName(key);
                if (validName == null) continue;
                
                // Skip if a control exists - control value takes precedence
                ThreadSafeControlProxy proxy = session.GetSafeVariable(key);
                if (proxy != null) continue;
                
                IList collection = session.GetListCollection(key);
                if (collection != null)
                {
                    collectionsToInject.Add(new KeyValuePair<string, IList>(validName, collection));
                }
            }
            
            if (collectionsToInject.Count == 0) return;
            
            ps.Commands.Clear();
            var sb = new System.Text.StringBuilder();
            sb.Append("param(");
            for (int i = 0; i < collectionsToInject.Count; i++)
            {
                if (i > 0) sb.Append(", ");
                sb.AppendFormat("$c{0}", i);
            }
            sb.AppendLine(")");
            
            for (int i = 0; i < collectionsToInject.Count; i++)
            {
                // Use ${Global:name} syntax to support hyphens and special chars
                sb.AppendFormat("${{Global:{0}}} = $c{1}\n", collectionsToInject[i].Key, i);
            }
            
            ps.AddScript(sb.ToString());
            foreach (var kvp in collectionsToInject)
            {
                ps.AddArgument(kvp.Value);
            }
            
            try
            {
                ps.Invoke();
            }
            catch (Exception ex)
            {
                DebugHelper.LogException("HYDRATION", "HydrateListCollectionsViaScript Invoke", ex);
            }
            ps.Commands.Clear();
        }
        
        // Inject PSCredential from PsUi.CredentialControl wrappers stored in session.Variables
        private static void HydrateCredentialsViaScript(PowerShell ps, HashSet<string> alreadyDefinedVariables, Dictionary<string, object> initialValues)
        {
            SessionContext session = SessionManager.Current;
            if (session == null) return;
            
            System.Windows.Threading.Dispatcher dispatcher = null;
            if (session.Window != null)
            {
                dispatcher = session.Window.Dispatcher;
            }
            
            // Find credential wrappers in session.Variables
            var credentialsToInject = new List<KeyValuePair<string, PSCredential>>();
            
            foreach (var kvp in session.Variables)
            {
                string varName = kvp.Key;
                object value = kvp.Value;
                
                // Skip if already defined by LinkedVariables
                if (alreadyDefinedVariables != null && alreadyDefinedVariables.Contains(varName)) continue;
                
                // Skip invalid variable names
                string validName = ValidateVariableName(varName);
                if (validName == null) continue;
                
                // Wrap in PSObject if not already (PSCustomObject may be stored unwrapped)
                PSObject psObj = value as PSObject;
                if (psObj == null && value != null)
                {
                    psObj = PSObject.AsPSObject(value);
                }
                if (psObj == null) continue;
                
                // Check type names for PsUi.CredentialControl
                bool isCredential = false;
                foreach (string typeName in psObj.TypeNames)
                {
                    if (typeName == "PsUi.CredentialControl")
                    {
                        isCredential = true;
                        break;
                    }
                }
                
                // Also detect via duck-typing if TypeNames doesn't have it
                if (!isCredential)
                {
                    PSPropertyInfo userProp = psObj.Properties["UsernameBox"];
                    PSPropertyInfo passProp = psObj.Properties["PasswordBox"];
                    if (userProp != null && passProp != null)
                    {
                        isCredential = true;
                        DebugLog("HYDRATION", "Detected credential wrapper via property check");
                    }
                }
                
                if (!isCredential) continue;
                
                // Extract username and password from the wrapper
                try
                {
                    // Get the UsernameBox and PasswordBox properties
                    PSPropertyInfo userBoxProp = psObj.Properties["UsernameBox"];
                    PSPropertyInfo passBoxProp = psObj.Properties["PasswordBox"];
                    
                    if (userBoxProp == null || passBoxProp == null) continue;
                    
                    TextBox userBox = userBoxProp.Value as TextBox;
                    PasswordBox passBox = passBoxProp.Value as PasswordBox;
                    
                    if (userBox == null || passBox == null) continue;
                    
                    // Read values from UI thread
                    string username = null;
                    SecureString password = null;
                    
                    if (dispatcher != null && !dispatcher.CheckAccess())
                    {
                        dispatcher.Invoke(new Action(() =>
                        {
                            username = userBox.Text;
                            password = passBox.SecurePassword.Copy();
                            password.MakeReadOnly();
                        }));
                    }
                    else
                    {
                        username = userBox.Text;
                        password = passBox.SecurePassword.Copy();
                        password.MakeReadOnly();
                    }
                    
                    // Create PSCredential if we have both username and password
                    if (!string.IsNullOrEmpty(username) && password != null && password.Length > 0)
                    {
                        PSCredential credential = new PSCredential(username, password);
                        credentialsToInject.Add(new KeyValuePair<string, PSCredential>(validName, credential));
                        
                        // Track for dehydration (store the wrapper, not the credential)
                        if (!initialValues.ContainsKey(validName))
                        {
                            initialValues[validName] = credential;
                        }
                    }
                    else
                    {
                        // Dispose the copied SecureString if we're not using it
                        if (password != null) password.Dispose();
                    }
                }
                catch (Exception ex)
                {
                    DebugLog("HYDRATION", "Failed to extract credential: {0}", ex.Message);
                }
            }
            
            if (credentialsToInject.Count == 0) return;
            
            // Inject credentials into runspace
            ps.Commands.Clear();
            var sb = new System.Text.StringBuilder();
            sb.Append("param(");
            for (int i = 0; i < credentialsToInject.Count; i++)
            {
                if (i > 0) sb.Append(", ");
                sb.AppendFormat("$cred{0}", i);
            }
            sb.AppendLine(")");
            
            for (int i = 0; i < credentialsToInject.Count; i++)
            {
                sb.AppendFormat("${{Global:{0}}} = $cred{1}\n", credentialsToInject[i].Key, i);
            }
            
            ps.AddScript(sb.ToString());
            foreach (var kvp in credentialsToInject)
            {
                ps.AddArgument(kvp.Value);
            }
            
            try
            {
                ps.Invoke();
                DebugLog("HYDRATION", "Credential injection complete");
            }
            catch (Exception ex)
            {
                DebugHelper.LogException("HYDRATION", "HydrateCredentialsViaScript Invoke", ex);
            }
            ps.Commands.Clear();
        }
        
        // Inject captured variables for cross-button sharing (Button A captures $data, Button B can use it)
        private static void HydrateCapturedVariablesViaScript(PowerShell ps, HashSet<string> alreadyDefinedVariables, Dictionary<string, object> initialValues)
        {
            SessionContext session = SessionManager.Current;
            if (session == null) return;
            
            var capturedVars = session.CapturedVariables;
            if (capturedVars == null || capturedVars.Count == 0) return;
            
            var varsToInject = new List<KeyValuePair<string, object>>();
            
            foreach (var kvp in capturedVars)
            {
                string varName = kvp.Key;
                
                // Skip if already defined by LinkedVariables (explicit wins over captured)
                if (alreadyDefinedVariables != null && alreadyDefinedVariables.Contains(varName)) continue;
                
                // Skip invalid variable names
                string validName = ValidateVariableName(varName);
                if (validName == null) continue;
                
                // Warn if this looks like a live object that wont survive the trip
                if (IsLiveObjectType(kvp.Value))
                {
                    DebugLog("HYDRATION", "Heads up: '{0}' looks like a live object ({1}). " +
                        "These get serialized across runspace boundaries and will probably be dead on arrival. " +
                        "SQL connections, streams, COM objects - none of em make it.", 
                        validName, kvp.Value.GetType().Name);
                }
                
                varsToInject.Add(new KeyValuePair<string, object>(validName, kvp.Value));
                
                // Track for dehydration so changes can be captured again
                if (!initialValues.ContainsKey(validName))
                {
                    initialValues[validName] = kvp.Value;
                }
            }
            
            if (varsToInject.Count == 0) return;
            
            // Inject via param block (same pattern as other hydration)
            ps.Commands.Clear();
            var sb = new System.Text.StringBuilder();
            sb.Append("param(");
            for (int i = 0; i < varsToInject.Count; i++)
            {
                if (i > 0) sb.Append(", ");
                sb.AppendFormat("$cap{0}", i);
            }
            sb.AppendLine(")");
            
            for (int i = 0; i < varsToInject.Count; i++)
            {
                sb.AppendFormat("${{Global:{0}}} = $cap{1}\n", varsToInject[i].Key, i);
            }
            
            ps.AddScript(sb.ToString());
            foreach (var kvp in varsToInject)
            {
                ps.AddArgument(kvp.Value);
            }
            
            try
            {
                ps.Invoke();
                DebugLog("HYDRATION", "Injected {0} captured variable(s)", varsToInject.Count);
            }
            catch (Exception ex)
            {
                DebugHelper.LogException("HYDRATION", "HydrateCapturedVariablesViaScript Invoke", ex);
            }
            ps.Commands.Clear();
        }

        // Sync changed values back to UI controls - call AFTER script execution completes
        public static void Dehydrate(Runspace runspace, Dictionary<string, object> initialValues)
        {
            if (initialValues == null || initialValues.Count == 0) return;
            
            SessionContext session = SessionManager.Current;
            if (session == null) return;

            System.Windows.Threading.Dispatcher dispatcher = null;
            if (session.Window != null)
            {
                dispatcher = session.Window.Dispatcher;
            }

            foreach (var kvp in initialValues)
            {
                string varName = kvp.Key;
                object initialValue = kvp.Value;

                try
                {
                    // Get current value from runspace
                    PSVariable psVar = runspace.SessionStateProxy.PSVariable.Get(varName);
                    if (psVar == null) continue;
                    
                    object currentValue = psVar.Value;
                    
                    // Unwrap PSObject if necessary
                    if (currentValue is PSObject)
                    {
                        currentValue = ((PSObject)currentValue).BaseObject;
                    }

                    // Check if value changed
                    if (!ValuesEqual(initialValue, currentValue))
                    {
                        // Update UI control
                        ThreadSafeControlProxy proxy = session.GetSafeVariable(varName);
                        if (proxy != null)
                        {
                            ControlValueApplicator.ApplyToProxy(proxy, currentValue, dispatcher);
                        }
                    }
                }
                catch (Exception ex)
                {
                    DebugLog("DEHYDRATION", "Failed to sync '{0}' back to UI: {1}", varName, ex.Message);
                }
            }
        }

        // Sync changed vars back to UI - pulls all values in one script call
        public static void DehydrateViaScript(PowerShell ps, Dictionary<string, object> initialValues)
        {
            if (initialValues == null || initialValues.Count == 0) return;
            
            SessionContext session = SessionManager.Current;
            if (session == null) return;

            System.Windows.Threading.Dispatcher dispatcher = null;
            if (session.Window != null)
            {
                dispatcher = session.Window.Dispatcher;
            }

            // Grab all variable values with one Invoke
            var varNames = new List<string>(initialValues.Keys);
            
            ps.Commands.Clear();
            var sb = new System.Text.StringBuilder();
            sb.AppendLine("$__results = @{}");
            foreach (string varName in varNames)
            {
                // Use ${Global:name} syntax to support hyphens and special chars
                sb.AppendFormat("$__results['{0}'] = ${{Global:{0}}}\n", varName);
            }
            sb.AppendLine("$__results");
            
            ps.AddScript(sb.ToString());
            
            Hashtable currentValues = null;
            try
            {
                var results = ps.Invoke();
                if (results != null && results.Count > 0 && results[0] != null)
                {
                    currentValues = results[0].BaseObject as Hashtable;
                }
            }
            catch (Exception ex)
            {
                DebugHelper.LogException("DEHYDRATION", "DehydrateViaScript read variables", ex);
            }
            
            ps.Commands.Clear();
            
            if (currentValues == null) return;

            // Compare and apply changes
            foreach (var kvp in initialValues)
            {
                string varName = kvp.Key;
                object initialValue = kvp.Value;

                try
                {
                    object currentValue = currentValues.ContainsKey(varName) ? currentValues[varName] : null;
                    
                    // Unwrap PSObject if necessary
                    if (currentValue is PSObject)
                    {
                        currentValue = ((PSObject)currentValue).BaseObject;
                    }

                    // Check if value changed
                    if (!ValuesEqual(initialValue, currentValue))
                    {
                        ThreadSafeControlProxy proxy = session.GetSafeVariable(varName);
                        if (proxy != null)
                        {
                            ControlValueApplicator.ApplyToProxy(proxy, currentValue, dispatcher);
                        }
                    }
                }
                catch (Exception ex)
                {
                    DebugLog("DEHYDRATION", "Failed to sync '{0}' back to UI: {1}", varName, ex.Message);
                }
            }
        }
        
        // Clean up hydrated variables from global scope - MUST call before returning pooled runspace
        public static void CleanupHydratedVariables(PowerShell ps, Dictionary<string, object> hydratedVariables)
        {
            if (ps == null || hydratedVariables == null || hydratedVariables.Count == 0) return;
            
            // Nuke all the temp variables in one go
            ps.Commands.Clear();
            var sb = new System.Text.StringBuilder();
            foreach (string varName in hydratedVariables.Keys)
            {
                sb.AppendFormat("Remove-Variable -Name '{0}' -Scope Global -ErrorAction SilentlyContinue\n", varName);
            }
            
            ps.AddScript(sb.ToString());
            try
            {
                ps.Invoke();
            }
            catch (Exception ex)
            {
                DebugHelper.LogException("HYDRATION", "CleanupHydratedVariables", ex);
            }
            ps.Commands.Clear();
        }

        // Capture variables from PS instance and store in SessionContext for cross-button sharing
        public static void CaptureVariablesToSession(PowerShell ps, string[] variableNames, Guid sessionId)
        {
            if (ps == null || variableNames == null || variableNames.Length == 0) return;
            
            SessionContext session = SessionManager.GetSession(sessionId);
            if (session == null)
            {
                DebugLog("CAPTURE", "No session found for ID {0}", sessionId);
                return;
            }
            
            // Build script to read all requested variables in one call
            ps.Commands.Clear();
            var sb = new System.Text.StringBuilder();
            sb.AppendLine("$__captureResults = @{}");
            
            foreach (string varName in variableNames)
            {
                // Validate variable name
                string validName = ValidateVariableName(varName);
                if (validName == null)
                {
                    DebugLog("CAPTURE", "Skipped invalid variable name: {0}", varName);
                    continue;
                }
                sb.AppendFormat("if (Test-Path Variable:Global:{0}) {{ $__captureResults['{0}'] = ${{Global:{0}}} }}\n", validName);
            }
            sb.AppendLine("$__captureResults");
            
            ps.AddScript(sb.ToString());
            
            Hashtable capturedValues = null;
            try
            {
                var results = ps.Invoke();
                if (results != null && results.Count > 0 && results[0] != null)
                {
                    capturedValues = results[0].BaseObject as Hashtable;
                }
            }
            catch (Exception ex)
            {
                DebugHelper.LogException("CAPTURE", "CaptureVariablesToSession read", ex);
            }
            
            ps.Commands.Clear();
            
            if (capturedValues == null || capturedValues.Count == 0)
            {
                DebugLog("CAPTURE", "No variables captured (none existed or all were null)");
                return;
            }
            
            // Store captured values in session - use SetCapturedVariable to notify bindings
            foreach (DictionaryEntry entry in capturedValues)
            {
                string varName = entry.Key.ToString();
                object value = entry.Value;
                
                // Preserve type - don't unwrap PSObject
                session.SetCapturedVariable(varName, value);
                DebugLog("CAPTURE", "Captured '{0}' = {1}", varName, value != null ? value.GetType().Name : "null");
            }
            
            DebugLog("CAPTURE", "Captured {0} variable(s) to session", capturedValues.Count);
        }
        
        // Capture from Runspace (for dedicated runspace execution)
        public static void CaptureVariablesToSessionFromRunspace(Runspace runspace, string[] variableNames, Guid sessionId)
        {
            if (runspace == null || variableNames == null || variableNames.Length == 0) return;
            
            SessionContext session = SessionManager.GetSession(sessionId);
            if (session == null)
            {
                DebugLog("CAPTURE", "No session found for ID {0}", sessionId);
                return;
            }
            
            foreach (string varName in variableNames)
            {
                // Validate variable name
                string validName = ValidateVariableName(varName);
                if (validName == null)
                {
                    DebugLog("CAPTURE", "Skipped invalid variable name: {0}", varName);
                    continue;
                }
                
                try
                {
                    PSVariable psVar = runspace.SessionStateProxy.PSVariable.Get(validName);
                    if (psVar != null)
                    {
                        // Preserve type - don't unwrap PSObject. Use SetCapturedVariable for bindings.
                        session.SetCapturedVariable(validName, psVar.Value);
                        DebugLog("CAPTURE", "Captured '{0}' from runspace", validName);
                    }
                    else
                    {
                        DebugLog("CAPTURE", "Variable '{0}' not found in runspace", validName);
                    }
                }
                catch (Exception ex)
                {
                    DebugLog("CAPTURE", "Failed to capture '{0}': {1}", validName, ex.Message);
                }
            }
        }

        private static bool ValuesEqual(object a, object b)
        {
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            
            // Never compare SecureString contents (defeats the purpose) - just check identity
            if (a is SecureString || b is SecureString)
            {
                return object.ReferenceEquals(a, b);
            }
            
            // Handle arrays and collections - compare contents, not reference
            IList listA = a as IList;
            IList listB = b as IList;
            if (listA != null && listB != null)
            {
                if (listA.Count != listB.Count) return false;
                for (int i = 0; i < listA.Count; i++)
                {
                    if (!ValuesEqual(listA[i], listB[i])) return false;
                }
                return true;
            }
            
            // If only one is a collection, they're not equal
            if (listA != null || listB != null) return false;
            
            // Handle string comparison
            if (a is string || b is string)
            {
                return string.Equals(a.ToString(), b.ToString(), StringComparison.Ordinal);
            }

            // Handle numeric comparison with tolerance
            if (IsNumeric(a) && IsNumeric(b))
            {
                double da = Convert.ToDouble(a);
                double db = Convert.ToDouble(b);
                return Math.Abs(da - db) < 0.0001;
            }

            // Handle bool
            if (a is bool && b is bool)
            {
                return (bool)a == (bool)b;
            }

            // Handle DateTime
            if (a is DateTime && b is DateTime)
            {
                return (DateTime)a == (DateTime)b;
            }

            // Handle TimeSpan
            if (a is TimeSpan && b is TimeSpan)
            {
                return (TimeSpan)a == (TimeSpan)b;
            }

            return a.Equals(b);
        }

        private static bool IsNumeric(object value)
        {
            return value is int || value is double || value is float || 
                   value is decimal || value is long || value is short ||
                   value is byte || value is uint || value is ulong;
        }
    }
}
