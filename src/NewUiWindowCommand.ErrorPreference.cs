using System;
using System.Globalization;
using System.Management.Automation;

namespace PsUi
{
    /// <summary>
    /// $ErrorActionPreference as PsUi's own commands read it while a -Content block builds. It hands back the
    /// preference during the read, with Continue turned into Stop, so a control that can't build stops the
    /// window and one the block using SilentlyContinue or Ignore gets skipped
    /// </summary>
    public sealed class ContentErrorPreference : PSVariable
    {
        private readonly SessionState _content;
        private readonly bool _quiet;

        [ThreadStatic]
        private static bool _reading;

        public ContentErrorPreference(SessionState content, bool quiet)
            : base("ErrorActionPreference", ActionPreference.Stop, ScopedItemOptions.None)
        {
            if (content == null) { throw new ArgumentNullException("content"); }
            _content = content;
            _quiet = quiet;
        }

        public override object Value
        {
            get
            {
                // If the block is PsUi's own its lookup comes back through here
                if (_reading) { return ActionPreference.Stop; }

                _reading = true;
                try
                {
                    ActionPreference preference = ActionPreference.Continue;
                    object value = _content.PSVariable.GetValue("ErrorActionPreference");
                    if (value != null)
                    {
                        preference = (ActionPreference)LanguagePrimitives.ConvertTo(value, typeof(ActionPreference), CultureInfo.InvariantCulture);
                    }

                    if (preference != ActionPreference.Continue) { return preference; }
                    return _quiet ? ActionPreference.Continue : ActionPreference.Stop;
                }
                catch (PSInvalidCastException)
                {
                    return ActionPreference.Stop;
                }
                finally
                {
                    _reading = false;
                }
            }
            set { }
        }
    }
}
