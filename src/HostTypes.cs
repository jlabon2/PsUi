using System;
using System.Management.Automation;

namespace PsUi
{
    // Flattened error record with all the diagnostic info you need for debugging.
    // PowerShell's ErrorRecord is a nested mess - this captures everything up front.
    public class PSErrorRecord
    {
        public string Message { get; set; }
        public string ScriptStackTrace { get; set; }
        public string ScriptName { get; set; }
        public int LineNumber { get; set; }
        public string Line { get; set; }
        public string Category { get; set; }
        public string FullyQualifiedErrorId { get; set; }
        public object TargetObject { get; set; }
        public DateTime Timestamp { get; set; }
        public string InnerException { get; set; }
        public ErrorRecord RawRecord { get; set; }
        
        // Flatten a PowerShell ErrorRecord into something useable
        public static PSErrorRecord FromErrorRecord(ErrorRecord error)
        {
            if (error == null) return new PSErrorRecord { Message = "Unknown error", Timestamp = DateTime.Now };
            
            var record = new PSErrorRecord { Timestamp = DateTime.Now, RawRecord = error };
            
            // Extract message from exception or fallback to ToString
            if (error.Exception != null)
            {
                record.Message = error.Exception.Message ?? error.ToString();
                record.InnerException = error.Exception.InnerException != null ? error.Exception.InnerException.Message : null;
            }
            else
            {
                record.Message = error.ToString();
            }
            
            // Extract stack trace
            record.ScriptStackTrace = error.ScriptStackTrace;
            
            // Extract invocation info (script location)
            if (error.InvocationInfo != null)
            {
                record.ScriptName = error.InvocationInfo.ScriptName;
                record.LineNumber = error.InvocationInfo.ScriptLineNumber;
                record.Line = error.InvocationInfo.Line != null ? error.InvocationInfo.Line.Trim() : null;
            }
            
            // Extract category info
            if (error.CategoryInfo != null)
            {
                record.Category = error.CategoryInfo.Category.ToString();
            }
            
            // Extract error ID and target
            record.FullyQualifiedErrorId = error.FullyQualifiedErrorId;
            record.TargetObject = error.TargetObject;
            
            return record;
        }
        
        // Wrap a raw CLR exception for non-PowerShell errors
        public static PSErrorRecord FromException(Exception ex)
        {
            return new PSErrorRecord
            {
                Message = ex != null ? ex.Message : "Unknown error",
                InnerException = (ex != null && ex.InnerException != null) ? ex.InnerException.Message : null,
                ScriptStackTrace = ex != null ? ex.StackTrace : null,
                Timestamp = DateTime.Now,
                Category = "CLRException"
            };
        }
        
        // One-liner for console output
        public string ToDisplayString()
        {
            var sb = new System.Text.StringBuilder();
            sb.Append(Message);
            
            if (LineNumber > 0)
            {
                sb.AppendFormat(" (line {0}", LineNumber);
                if (!string.IsNullOrEmpty(ScriptName))
                {
                    sb.AppendFormat(" in {0}", System.IO.Path.GetFileName(ScriptName));
                }
                sb.Append(")");
            }
            
            return sb.ToString();
        }
        
        // Multi-line dump for debugging
        public string ToDetailedString()
        {
            var sb = new System.Text.StringBuilder();
            sb.AppendLine("═══════════════════════════════════════════════════════════════");
            sb.AppendFormat("ERROR: {0}\n", Message);
            sb.AppendFormat("Time: {0:HH:mm:ss.fff}\n", Timestamp);
            
            if (LineNumber > 0)
            {
                sb.AppendFormat("Location: Line {0}", LineNumber);
                if (!string.IsNullOrEmpty(ScriptName)) sb.AppendFormat(" in {0}", ScriptName);
                sb.AppendLine();
            }
            
            if (!string.IsNullOrEmpty(Line))
            {
                sb.AppendFormat("Code: {0}\n", Line);
            }
            
            if (!string.IsNullOrEmpty(Category))
            {
                sb.AppendFormat("Category: {0}\n", Category);
            }
            
            if (!string.IsNullOrEmpty(FullyQualifiedErrorId))
            {
                sb.AppendFormat("ErrorId: {0}\n", FullyQualifiedErrorId);
            }
            
            if (!string.IsNullOrEmpty(ScriptStackTrace))
            {
                sb.AppendLine("Stack Trace:");
                sb.AppendLine(ScriptStackTrace);
            }
            
            if (!string.IsNullOrEmpty(InnerException))
            {
                sb.AppendFormat("Inner Exception: {0}\n", InnerException);
            }
            
            sb.AppendLine("═══════════════════════════════════════════════════════════════");
            
            return sb.ToString();
        }
        
        public override string ToString()
        {
            return ToDisplayString();
        }
    }

    // Write-Host output with color info for the UI
    public class HostOutputRecord
    {
        public string Message { get; set; }
        public ConsoleColor? ForegroundColor { get; set; }
        public ConsoleColor? BackgroundColor { get; set; }
        public bool NoNewLine { get; set; }
        
        public HostOutputRecord(string message, ConsoleColor? foregroundColor = null, ConsoleColor? backgroundColor = null, bool noNewLine = false)
        {
            Message = message;
            ForegroundColor = foregroundColor;
            BackgroundColor = backgroundColor;
            NoNewLine = noNewLine;
        }
    }
}
