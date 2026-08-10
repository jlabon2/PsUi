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
            "state", "session",

            // Per window session marker, set by NewUiWindowCommand per window runspace.
            // CaptureCallerVariables must skip it or a nested New-UiWindow inherits the parent's session ID and Add(child) blows up on WPF thread affinity.
            "__PsUiSessionId"
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
                // Query failure leaves AlwaysReserved as the baseline
            }

            return result;
        }

        public static bool IsReservedVariable(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return true;
            return ReservedVariables.Contains(name);
        }
        
        // Valid PS variable identifiers (blocks injection). Hyphens stay in - ScriptBuilder emits ${name} = ${Global:name} so hyphenated -Variable names hydrate (bare $my-var parses as subtraction). Rejecting them silently killed v2.x names.
        private static readonly System.Text.RegularExpressions.Regex ValidIdentifierPattern =
            new System.Text.RegularExpressions.Regex(@"^[a-zA-Z_][a-zA-Z0-9_-]*$",
                System.Text.RegularExpressions.RegexOptions.Compiled);

        // Validates name is safe for generated PS code - prevents injection via semicolons, braces, backticks, etc.
        public static bool IsValidIdentifier(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return false;
            return ValidIdentifierPattern.IsMatch(name);
        }

        // Verb-Noun function names share the identifier rule (hyphens already admitted). Kept as a named entry point for the `function Global:{0} { ... }` call sites so the two can diverge later without touching those call sites.
        public static bool IsValidFunctionName(string name)
        {
            return IsValidIdentifier(name);
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
