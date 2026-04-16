using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

namespace PsUi
{
    public static class Constants
    {
        private static HashSet<string> _reservedVariables;
        private static readonly object _lock = new object();

        // Always reserved - automatic variables that may not show ReadOnly/Constant but still shouldnt be overwritten
        private static readonly HashSet<string> AlwaysReserved = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            // Core automatic variables (may not be marked ReadOnly but shouldn't be touched)
            "args", "input", "this", "_", "PSItem", "PSCmdlet", "PSBoundParameters",
            "MyInvocation", "PSScriptRoot", "PSCommandPath", "Matches", "LastExitCode",
            "ForEach", "Switch", "Event", "EventArgs", "EventSubscriber", 
            "Sender", "SourceArgs", "SourceEventArgs", "StackTrace",
            
            // Special tokens that aren't marked as variables
            "null",
            
            // Preference variables (writable but should preserve user settings)
            "ConfirmPreference", "DebugPreference", "ErrorActionPreference",
            "InformationPreference", "ProgressPreference", "VerbosePreference",
            "WarningPreference", "WhatIfPreference", "OFS", "OutputEncoding",
            
            // Environment and special
            "env", "NestedPromptLevel", "Profile", "PWD",
            
            // PsUi internal
            "state", "session"
        };

        // PS variable names that shouldnt be touched during hydration - built dynamically from host + known automatic vars
        public static HashSet<string> ReservedVariables
        {
            get
            {
                if (_reservedVariables == null)
                {
                    lock (_lock)
                    {
                        if (_reservedVariables == null)
                        {
                            _reservedVariables = BuildReservedVariableSet();
                        }
                    }
                }
                return _reservedVariables;
            }
        }

        private static HashSet<string> BuildReservedVariableSet()
        {
            var result = new HashSet<string>(AlwaysReserved, StringComparer.OrdinalIgnoreCase);

            try
            {
                // Query the default runspace for read-only and constant variables
                using (var ps = PowerShell.Create())
                {
                    // Create a fresh runspace to get default variable state
                    using (var runspace = RunspaceFactory.CreateRunspace())
                    {
                        runspace.Open();
                        ps.Runspace = runspace;

                        ps.AddScript(@"
                            Get-Variable | Where-Object { 
                                $_.Options -band [System.Management.Automation.ScopedItemOptions]::ReadOnly -or 
                                $_.Options -band [System.Management.Automation.ScopedItemOptions]::Constant 
                            } | Select-Object -ExpandProperty Name
                        ");

                        var output = ps.Invoke();
                        foreach (var item in output)
                        {
                            if (item == null) continue;
                            var name = item.BaseObject as string;
                            if (name != null)
                            {
                                result.Add(name);
                            }
                        }
                    }
                }
            }
            catch (Exception)
            {
                // If query fails, we still have AlwaysReserved as a baseline
            }

            return result;
        }

        public static bool IsReservedVariable(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return true;
            return ReservedVariables.Contains(name);
        }
        
        // Regex pattern for valid PowerShell identifiers (prevents injection attacks)
        // Allows: letters, digits, underscore, hyphen. Must start with letter or underscore.
        private static readonly System.Text.RegularExpressions.Regex ValidIdentifierPattern = 
            new System.Text.RegularExpressions.Regex(@"^[a-zA-Z_][a-zA-Z0-9_-]*$", 
                System.Text.RegularExpressions.RegexOptions.Compiled);
        
        // Validates name is safe for generated PS code - prevents injection via semicolons, braces, backticks, etc.
        public static bool IsValidIdentifier(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return false;
            return ValidIdentifierPattern.IsMatch(name);
        }
        
        public static string ValidateIdentifier(string name, string context = null)
        {
            if (string.IsNullOrWhiteSpace(name)) return null;
            if (!IsValidIdentifier(name))
            {
                SessionContext session = SessionManager.Current;
                if (session != null && session.DebugMode)
                {
                    Console.WriteLine("[SECURITY] Rejected invalid identifier '{0}'{1}", 
                        name, context != null ? " in " + context : "");
                }
                return null;
            }
            return name;
        }
    }
}
