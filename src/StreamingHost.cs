using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
using System.Threading;

namespace PsUi
{
    public class StreamingHost : PSHost
    {
        private readonly AsyncExecutor _executor;
        private readonly StreamingHostUI _ui;
        private readonly Guid _instanceId = Guid.NewGuid();
        public StreamingHost(AsyncExecutor executor) { _executor = executor; _ui = new StreamingHostUI(executor); }
        public override PSHostUserInterface UI { get { return _ui; } }
        public override string Name { get { return "PsUi StreamingHost"; } }
        public override Version Version { get { return new Version(1, 0); } }
        public override Guid InstanceId { get { return _instanceId; } }
        public override CultureInfo CurrentCulture { get { return Thread.CurrentThread.CurrentCulture; } }
        public override CultureInfo CurrentUICulture { get { return Thread.CurrentThread.CurrentUICulture; } }
        public override void SetShouldExit(int exitCode) { }
        public override void EnterNestedPrompt() { }
        public override void ExitNestedPrompt() { }
        public override void NotifyBeginApplication() { }
        public override void NotifyEndApplication() { }
    }
    
    public class StreamingHostUI : PSHostUserInterface
    {
        private readonly AsyncExecutor _executor;
        private readonly StreamingHostRawUI _rawUI;
        public StreamingHostUI(AsyncExecutor executor) { _executor = executor; _rawUI = new StreamingHostRawUI(executor); }
        
        // Write and WriteLine route through the executor for Out-Host support.
        // The global Write-Host override also routes through the executor, but it won't cause
        // duplicates because Write-Host uses its own path via AsyncExecutor.RaiseOnHost directly.
        public override void Write(string value) 
        { 
            if (!string.IsNullOrEmpty(value))
            {
                _executor.RaiseOnHost(value, null, true);
            }
        }
        public override void WriteLine(string value) 
        { 
            _executor.RaiseOnHost(value ?? string.Empty);
        }
        public override void WriteLine(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value) 
        { 
            _executor.RaiseOnHost(value ?? string.Empty, foregroundColor);
        }
        // Error/Warning/Verbose are captured via ps.Streams.*.DataAdded - no duplicate events
        public override void WriteErrorLine(string value) { /* Handled by Streams.Error.DataAdded */ }
        public override void WriteWarningLine(string value) { /* Already handled by Streams.Warning.DataAdded */ }
        public override void WriteVerboseLine(string value) { /* Already handled by Streams.Verbose.DataAdded */ }
        public override void WriteDebugLine(string value) { /* Already handled by Streams.Debug.DataAdded */ }
        public override void WriteProgress(long sourceId, ProgressRecord record) { _executor.RaiseOnProgress(record); }
        
        // Colored Write routes through the executor
        public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value) 
        { 
            if (!string.IsNullOrEmpty(value))
            {
                _executor.RaiseOnHost(value, foregroundColor, true);
            }
        }
        public override PSHostRawUserInterface RawUI { get { return _rawUI; } }
        public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions) { return _executor.RaiseOnPrompt(caption, message, descriptions); }
        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) { return _executor.RaiseOnPromptForChoice(caption, message, choices, defaultChoice); }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName) { return _executor.RaiseOnPromptForCredential(caption, message, userName, targetName); }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes allowedCredentialTypes, PSCredentialUIOptions options) { return _executor.RaiseOnPromptForCredential(caption, message, userName, targetName); }

        public override string ReadLine() { return _executor.RaiseOnReadLine(null); }
        public override SecureString ReadLineAsSecureString() { return _executor.RaiseOnReadLineAsSecureString(null); }
    }

    public class StreamingHostRawUI : PSHostRawUserInterface
    {
        private readonly AsyncExecutor _executor;
        private System.Management.Automation.Host.Size _bufferSize = new System.Management.Automation.Host.Size(120, 50);
        private Coordinates _cursorPosition = new Coordinates(0, 0);
        private System.Management.Automation.Host.Size _windowSize = new System.Management.Automation.Host.Size(120, 50);
        private Coordinates _windowPosition = new Coordinates(0, 0);
        private int _cursorSize = 25;
        private ConsoleColor _foregroundColor = ConsoleColor.White;
        private ConsoleColor _backgroundColor = ConsoleColor.DarkBlue;

        public StreamingHostRawUI(AsyncExecutor executor) { _executor = executor; }

        public override KeyInfo ReadKey(ReadKeyOptions options)
        {
            return _executor.RaiseOnReadKey(options);
        }

        public override bool KeyAvailable { get { return false; } }

        public override System.Management.Automation.Host.Size BufferSize
        {
            get { return _bufferSize; }
            set { _bufferSize = value; }
        }

        public override Coordinates CursorPosition
        {
            get { return _cursorPosition; }
            set 
            { 
                // Detect Clear-Host pattern (cursor moved to 0,0)
                if (value.X == 0 && value.Y == 0 && _cursorPosition.X != 0 && _cursorPosition.Y != 0)
                {
                    _executor.RaiseOnClearHost();
                }
                _cursorPosition = value; 
            }
        }

        public override int CursorSize
        {
            get { return _cursorSize; }
            set { _cursorSize = value; }
        }

        public override ConsoleColor ForegroundColor
        {
            get { return _foregroundColor; }
            set { _foregroundColor = value; }
        }

        public override ConsoleColor BackgroundColor
        {
            get { return _backgroundColor; }
            set { _backgroundColor = value; }
        }

        public override System.Management.Automation.Host.Size MaxPhysicalWindowSize { get { return new System.Management.Automation.Host.Size(Int32.MaxValue, Int32.MaxValue); } }
        public override System.Management.Automation.Host.Size MaxWindowSize { get { return new System.Management.Automation.Host.Size(Int32.MaxValue, Int32.MaxValue); } }

        public override System.Management.Automation.Host.Size WindowSize
        {
            get { return _windowSize; }
            set { _windowSize = value; }
        }

        public override Coordinates WindowPosition
        {
            get { return _windowPosition; }
            set { _windowPosition = value; }
        }

        private string _windowTitle = "";
        public override string WindowTitle 
        { 
            get { return _windowTitle; }
            set 
            { 
                _windowTitle = value;
                _executor.RaiseOnWindowTitle(value);
            }
        }

        public override void FlushInputBuffer() { }
        public override BufferCell[,] GetBufferContents(Rectangle rectangle) { return new BufferCell[0, 0]; }
        public override void ScrollBufferContents(Rectangle source, Coordinates destination, Rectangle clip, BufferCell fill) { }
        public override void SetBufferContents(Rectangle rectangle, BufferCell fill) 
        { 
            // SetBufferContents with entire buffer is also a Clear-Host pattern
            if (rectangle.Left == 0 && rectangle.Top == 0 && rectangle.Right >= _bufferSize.Width - 1)
            {
                _executor.RaiseOnClearHost();
            }
        }
        public override void SetBufferContents(Coordinates origin, BufferCell[,] contents) { }
    }
}
