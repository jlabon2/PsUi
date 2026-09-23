using System;
using System.Collections.Generic;
using System.Management.Automation;

namespace PsUi
{
    // Copies the calling script's variables and functions into the window runspace.
    public partial class NewUiWindowCommand
    {
        // Types that misbehave when two threads share one instance, though capture goes ahead regardless and this only warns.
        private static readonly HashSet<string> ThreadUnsafeTypePatterns = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "System.Data.SqlClient.SqlConnection",
            "System.Data.OleDb.OleDbConnection",
            "System.Data.Odbc.OdbcConnection",
            "Microsoft.Data.SqlClient.SqlConnection",
            "System.Data.Common.DbConnection",
            "System.Data.SqlClient.SqlCommand",
            "System.Data.SqlClient.SqlDataReader",
            "System.IO.StreamReader",
            "System.IO.StreamWriter",
            "System.IO.FileStream",
            "System.Net.Sockets.TcpClient",
            "System.Net.Sockets.Socket",
            "System.Runtime.InteropServices.ComObject",
            "__ComObject"
        };

        private static bool IsThreadUnsafeType(Type type)
        {
            if (type == null) return false;

            string typeName = type.FullName;
            if (typeName == null) return false;

            // Check exact matches
            if (ThreadUnsafeTypePatterns.Contains(typeName)) return true;

            // Check for COM objects
            if (typeName.Contains("__ComObject")) return true;

            // Check base types (e.g., SqlConnection inherits from DbConnection)
            Type baseType = type.BaseType;
            while (baseType != null && baseType != typeof(object))
            {
                string baseName = baseType.FullName;
                if (baseName != null && ThreadUnsafeTypePatterns.Contains(baseName)) return true;
                baseType = baseType.BaseType;
            }

            return false;
        }

        private void CaptureCallerVariables()
        {
            var unsafeVars = new List<string>();

            try
            {
                using (var ps = PowerShell.Create(RunspaceMode.CurrentRunspace))
                {
                    ps.AddScript("Get-Variable");
                    var results = ps.Invoke();

                    foreach (var result in results)
                    {
                        if (result == null) continue;
                        var psvariable = result.BaseObject as PSVariable;

                        if (psvariable != null && psvariable.Value != null)
                        {
                            // Skip reserved variables (uses shared Constants)
                            if (Constants.IsReservedVariable(psvariable.Name)) continue;

                            // Skip ReadOnly/Constant variables
                            if ((psvariable.Options & (ScopedItemOptions.ReadOnly | ScopedItemOptions.Constant)) != 0) continue;

                            object value = psvariable.Value;
                            if (value is PSObject)
                            {
                                value = ((PSObject)value).BaseObject;
                            }

                            if (value != null && IsThreadUnsafeType(value.GetType()))
                            {
                                unsafeVars.Add(string.Format("${0} ({1})", psvariable.Name, value.GetType().Name));
                            }

                            _callerVariables[psvariable.Name] = psvariable.Value;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                WriteWarning("Failed to capture variables: " + ex.Message);
            }

            if (unsafeVars.Count > 0)
            {
                WriteWarning(string.Format(
                    "Shared across threads: {0}. These arrive in the action as the same object, so two threads using one at once should be avoided. A COM object is only usable on the thread that made it.",
                    string.Join(", ", unsafeVars)));
            }
        }

        private void CaptureCallerFunctions()
        {
            try
            {
                using (var ps = PowerShell.Create(RunspaceMode.CurrentRunspace))
                {
                    // Filter for user-defined functions only (no Source means not from a module)
                    // Exclude built-in shell functions that shouldn't be copied
                    // Without -ListImported Get-Command walks every module on PSModulePath only for the Source filter to drop the lot, seven seconds on 5.1 against a millisecond, and 31ms on 7.
                    ps.AddScript(@"
                        Get-Command -CommandType Function -ListImported | Where-Object {
                            $_.Source -eq '' -and
                            $_.Name -notmatch '^(prompt|Clear-Host|more|oss|pause|TabExpansion2|cd\.\.|cd\\)$'
                        } | ForEach-Object {
                            [PSCustomObject]@{ Name = $_.Name; Definition = $_.Definition }
                        }
                    ");
                    var results = ps.Invoke();
                    foreach (var result in results)
                    {
                        var psobj = result as PSObject;
                        if (psobj == null) continue;

                        var nameProp = psobj.Properties["Name"];
                        var defProp = psobj.Properties["Definition"];
                        if (nameProp == null || defProp == null) continue;

                        string name = nameProp.Value as string;
                        string definition = defProp.Value as string;
                        if (!string.IsNullOrEmpty(name) && !string.IsNullOrEmpty(definition))
                        {
                            _callerFunctions[name] = definition;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("Failed to capture caller functions: " + ex.Message);
            }
        }
    }
}
