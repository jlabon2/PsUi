using System;
using System.Collections.Generic;
using System.Text;

namespace PsUi
{
    // Builds script fragments for variable injection, localization, and dehydration.
    public static class ScriptBuilder
    {
        // Sets session ID in both C# and PowerShell so async scripts can find their context
        public static string BuildSessionPropagation(Guid sessionId)
        {
            if (sessionId == Guid.Empty) return string.Empty;
            
            return string.Format(
                "$Global:__PsUiSessionId = '{0}'; [PsUi.SessionManager]::SetCurrentSession([Guid]'{0}');",
                sessionId);
        }
        
        // Copies global variables to local scope so scripts can use $varName instead of ${Global:varName}
        public static string BuildLocalizer(IEnumerable<string> variableNames)
        {
            if (variableNames == null) return string.Empty;
            
            var sb = new StringBuilder();
            foreach (string varName in variableNames)
            {
                // Skip invalid names that could cause injection
                if (!Constants.IsValidIdentifier(varName)) continue;
                
                // Use ${name} syntax to support hyphens and special chars
                sb.AppendFormat("${{{0}}} = ${{Global:{0}}}\n", varName);
            }
            return sb.ToString();
        }
        
        // Syncs local variable changes back to globals so UI controls get updated
        public static string BuildDehydrator(IEnumerable<string> variableNames)
        {
            if (variableNames == null) return string.Empty;
            
            var sb = new StringBuilder();
            sb.AppendLine();
            foreach (string varName in variableNames)
            {
                // Skip invalid names that could cause injection
                if (!Constants.IsValidIdentifier(varName)) continue;
                
                // Use ${name} syntax to support hyphens and special chars
                sb.AppendFormat("${{Global:{0}}} = ${{{0}}}\n", varName);
            }
            return sb.ToString();
        }
        
        // Wraps user script with localizer/dehydrator in try/finally.
        public static string WrapUserScript(string userScript, IEnumerable<string> variableNames, Guid sessionId)
        {
            var sb = new StringBuilder();
            
            string hoistedUsings;
            string remainingScript;
            HoistUsingStatements(userScript, out hoistedUsings, out remainingScript);
            
            if (!string.IsNullOrEmpty(hoistedUsings))
            {
                sb.Append(hoistedUsings);
            }
            
            // Session propagation (ensures session ID is set even if cleared)
            if (sessionId != Guid.Empty)
            {
                sb.AppendLine(BuildSessionPropagation(sessionId));
            }
            
            // Copy global vars to local scope so $varName works
            sb.Append(BuildLocalizer(variableNames));
            
            // Wrap user script in try/finally so dehydrator runs even on early return
            sb.AppendLine("try {");
            sb.Append(remainingScript);
            sb.AppendLine();
            sb.AppendLine("} finally {");
            
            // Sync locals back to globals
            sb.Append(BuildDehydrator(variableNames));
            sb.AppendLine("}");
            
            return sb.ToString();
        }
        
        // PowerShell requires 'using' at the top - extract them before prepending our setup code
        private static void HoistUsingStatements(string script, out string hoistedUsings, out string remainingScript)
        {
            if (string.IsNullOrEmpty(script))
            {
                hoistedUsings = string.Empty;
                remainingScript = script ?? string.Empty;
                return;
            }
            
            var usingLines = new StringBuilder();
            var otherLines = new StringBuilder();
            bool stillInUsingBlock = true;
            bool insideBlockComment = false;
            
            // Split by newlines, preserving line endings
            string[] lines = script.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None);
            
            foreach (string line in lines)
            {
                string trimmed = line.TrimStart();
                
                // Track block comment state (<# ... #>)
                if (insideBlockComment)
                {
                    usingLines.AppendLine(line);
                    if (trimmed.Contains("#>"))
                    {
                        insideBlockComment = false;
                    }
                    continue;
                }
                
                // Check for block comment start
                if (stillInUsingBlock && trimmed.StartsWith("<#"))
                {
                    usingLines.AppendLine(line);
                    // Check if block comment ends on same line
                    if (!trimmed.Contains("#>") || trimmed.IndexOf("#>") < trimmed.IndexOf("<#") + 2)
                    {
                        insideBlockComment = !trimmed.Substring(2).Contains("#>");
                    }
                    continue;
                }
                
                // Check if this line is a 'using' statement
                if (stillInUsingBlock && 
                    (trimmed.StartsWith("using namespace ", StringComparison.OrdinalIgnoreCase) ||
                     trimmed.StartsWith("using module ", StringComparison.OrdinalIgnoreCase) ||
                     trimmed.StartsWith("using assembly ", StringComparison.OrdinalIgnoreCase)))
                {
                    usingLines.AppendLine(line);
                }
                else if (stillInUsingBlock && string.IsNullOrWhiteSpace(trimmed))
                {
                    // Allow blank lines at the top before/between using statements
                    usingLines.AppendLine(line);
                }
                else if (stillInUsingBlock && trimmed.StartsWith("#"))
                {
                    // Allow single-line comments before/between using statements
                    usingLines.AppendLine(line);
                }
                else
                {
                    // First non-using, non-blank, non-comment line - switch to remaining script
                    stillInUsingBlock = false;
                    otherLines.AppendLine(line);
                }
            }
            
            hoistedUsings = usingLines.ToString();
            remainingScript = otherLines.ToString();
        }
        
        // Single-variable injection using parameter binding
        public static string BuildVariableInjection(string varName)
        {
            if (!Constants.IsValidIdentifier(varName)) return null;
            return string.Format("${{Global:{0}}} = $args[0]", varName);
        }
        
        // Batch variable injection — one script, one Invoke call for N variables
        public static string BuildBatchVariableInjection(IList<string> varNames)
        {
            if (varNames == null || varNames.Count == 0) return null;
            var sb = new StringBuilder();
            for (int i = 0; i < varNames.Count; i++)
            {
                if (i > 0) sb.Append("\n");
                sb.AppendFormat("${{Global:{0}}} = $args[{1}]", varNames[i], i);
            }
            return sb.ToString();
        }
        
        // Remove temp globals after execution
        public static string BuildVariableCleanup(IEnumerable<string> variableNames)
        {
            if (variableNames == null) return string.Empty;
            
            var sb = new StringBuilder();
            foreach (string varName in variableNames)
            {
                if (Constants.IsReservedVariable(varName)) continue;
                sb.AppendFormat("Remove-Variable -Name '{0}' -Scope Global -ErrorAction SilentlyContinue\n", varName);
            }
            return sb.ToString();
        }
        
        public static string BuildPwdRestore(string originalPath)
        {
            if (string.IsNullOrEmpty(originalPath)) return string.Empty;
            string escapedPath = originalPath.Replace("'", "''");
            return string.Format("Set-Location -LiteralPath '{0}' -ErrorAction SilentlyContinue", escapedPath);
        }
    }
}
