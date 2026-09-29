using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Reflection;
using System.Text;
using System.Windows.Data;

namespace PsUi
{
    /// <summary>
    /// What one value is, for anything deciding how to show it. Every cell, tooltip, popup, search index and export
    /// asks here, and Get-UiValueKind routes to Of, so a type that fools one of them fools none.
    /// </summary>
    public static class ValueKind
    {
        public const string Null = "Null";
        public const string Text = "Text";
        public const string Bool = "Bool";
        public const string Dictionary = "Dictionary";
        public const string List = "List";
        public const string Sequence = "Sequence";
        public const string Scalar = "Scalar";

        /// <summary>
        /// A Sequence is a reader or a generator, and one pass is all there is, so whoever gets one must not
        /// enumerate it.
        /// </summary>
        public static string Of(object value)
        {
            value = Unwrap(value);
            if (value == null)
            {
                return Null;
            }

            // Strings enumerate as characters, so this test comes before every enumerable one.
            if (value is string)
            {
                return Text;
            }
            if (value is bool)
            {
                return Bool;
            }

            // Hashtable answers ICollection too, so the dictionary test comes first.
            if (value is IDictionary)
            {
                return Dictionary;
            }
            if (value is ICollection)
            {
                return List;
            }

            // The walk below costs 74us on an int against 0.12us for this test, and an int is the common case.
            if (!(value is IEnumerable))
            {
                return Scalar;
            }

            // HashSet<T> answers only the generic interface, so the cheap test above would call it a stream.
            return GenericCount(value) >= 0 ? List : Sequence;
        }

        /// <summary>
        /// The Count, or -1 where there is none, which is also the signal not to enumerate the value.
        /// </summary>
        public static int Count(object value)
        {
            value = Unwrap(value);
            if (value == null || value is string)
            {
                return -1;
            }

            ICollection collection = value as ICollection;
            if (collection != null)
            {
                return collection.Count;
            }
            if (!(value is IEnumerable))
            {
                return -1;
            }

            return GenericCount(value);
        }

        /// <summary>
        /// A dictionary or a list holding at least one entry, so an empty one earns no click.
        /// </summary>
        public static bool IsExpandable(object value)
        {
            string kind = Of(value);
            if (kind != Dictionary && kind != List)
            {
                return false;
            }
            return Count(value) > 0;
        }

        /// <summary>
        /// The words a search can find one value by. Capped both ways, since a Get-Process row carries 115 modules
        /// and 5,000 ints join to 23,892 characters.
        /// </summary>
        public static string IndexText(object value, int maxElements, int maxChars)
        {
            string text = IndexTextAtDepth(value, maxElements, 0);
            if (text.Length > maxChars)
            {
                text = text.Substring(0, maxChars);
            }
            return text;
        }

        // One level of nesting is plenty for a search, and a list holding itself would otherwise never end.
        private static string IndexTextAtDepth(object value, int maxElements, int depth)
        {
            string kind = Of(value);
            if (kind == Null || kind == Sequence)
            {
                return "";
            }
            if (kind != Dictionary && kind != List)
            {
                return DisplayText(value);
            }
            if (depth > 1)
            {
                return "";
            }

            StringBuilder joined = new StringBuilder();
            int taken = 0;
            object plain = Unwrap(value);
            IDictionary dictionary = plain as IDictionary;
            if (dictionary != null)
            {
                foreach (DictionaryEntry entry in dictionary)
                {
                    if (taken++ >= maxElements) { break; }
                    if (joined.Length > 0) { joined.Append(' '); }
                    joined.Append(DisplayText(entry.Key)).Append('=').Append(IndexTextAtDepth(entry.Value, maxElements, depth + 1));
                }
                return joined.ToString();
            }

            foreach (object element in (IEnumerable)plain)
            {
                if (taken++ >= maxElements) { break; }
                if (joined.Length > 0) { joined.Append(' '); }
                joined.Append(IndexTextAtDepth(element, maxElements, depth + 1));
            }
            return joined.ToString();
        }

        /// <summary>
        /// One value as the text a cell, popup line, export or search index shows. Where PS's spelling comes
        /// back as the type's full name, the type's own ToString takes over, so a ServiceController in a
        /// RequiredServices column reads RpcSs rather than the type name three times.
        /// </summary>
        public static string DisplayText(object value)
        {
            string text = ScalarText(value);
            object plain = Unwrap(value);
            if (plain == null || text != plain.GetType().FullName)
            {
                return text;
            }

            // That ToString is a script method, so it wants a PS engine on this thread, and without one it hands back the same type name this is trying to replace.
            try
            {
                string scripted = PSObject.AsPSObject(plain).ToString();
                if (!string.IsNullOrEmpty(scripted))
                {
                    return scripted;
                }
            }
            catch (Exception) { }

            return text;
        }

        // PS's own spelling, so a number reads the same here as it does in the cell and under [string].
        private static string ScalarText(object value)
        {
            try
            {
                string text = LanguagePrimitives.ConvertTo(value, typeof(string)) as string;
                return text != null ? text : "";
            }
            catch (Exception)
            {
                object plain = Unwrap(value);
                return plain != null ? plain.ToString() : "";
            }
        }

        // PSCustomObject unwraps to its marker, which is not enumerable and lands on Scalar.
        internal static object Unwrap(object value)
        {
            PSObject wrapped = value as PSObject;
            return wrapped != null ? wrapped.BaseObject : value;
        }

        // Walked rather than looked up by name, since GetInterface throws AmbiguousMatchException on a type carrying ICollection<T> twice.
        private static int GenericCount(object value)
        {
            Type[] contracts = value.GetType().GetInterfaces();
            for (int i = 0; i < contracts.Length; i++)
            {
                if (!contracts[i].IsGenericType)
                {
                    continue;
                }
                if (contracts[i].GetGenericTypeDefinition().FullName != "System.Collections.Generic.ICollection`1")
                {
                    continue;
                }

                PropertyInfo countProperty = contracts[i].GetProperty("Count");
                if (countProperty != null)
                {
                    return (int)countProperty.GetValue(value, null);
                }
            }

            return -1;
        }
    }

    public class ArrayDisplayConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            string kind = ValueKind.Of(value);
            if (kind == ValueKind.Null) return null;
            if (kind == ValueKind.Text) return value;

            if (kind == ValueKind.Dictionary || kind == ValueKind.List)
            {
                int total = ValueKind.Count(value);
                if (total == 0) return "[empty]";
                string noun = kind == ValueKind.Dictionary ? "key" : "item";
                if (total == 1) return "[1 " + noun + "]";
                return string.Format("[{0} {1}s]", total, noun);
            }

            // No Count to read, so the cell says what it is without touching it.
            if (kind == ValueKind.Sequence) return "[sequence]";

            // Scalars land here when the first row held a list and this one holds a single object.
            // WPF spells one with the CLR ToString, so only the type name case is taken over and a date still reads the WPF way.
            object plain = ValueKind.Unwrap(value);
            try
            {
                if (plain != null && plain.ToString() == plain.GetType().FullName) return ValueKind.DisplayText(value);
            }
            catch (Exception) { }

            return value;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotSupportedException();
        }
    }

    public class ArrayTooltipConverter : IValueConverter
    {
        private int _maxItems = 10;

        public int MaxItems
        {
            get { return _maxItems; }
            set { _maxItems = value; }
        }

        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            return ExpandableValueTooltipConverter.Describe(value, _maxItems);
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotSupportedException();
        }
    }

    public class ExpandableValueTooltipConverter : IValueConverter
    {
        private int _maxItems = 5;

        public int MaxItems
        {
            get { return _maxItems; }
            set { _maxItems = value; }
        }

        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            return Describe(value, _maxItems);
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// Null for a value that can't be clicked, so an empty list or a scalar gets no tooltip at all.
        /// </summary>
        public static string Describe(object value, int maxItems)
        {
            string kind = ValueKind.Of(value);
            if (kind == ValueKind.Sequence)
            {
                return "A one pass sequence, left unread so the script can still read it.";
            }
            if (!ValueKind.IsExpandable(value))
            {
                return null;
            }

            int total = ValueKind.Count(value);
            List<string> lines = new List<string>();
            lines.Add(string.Format("Click to expand ({0} {1}):", total, kind == ValueKind.Dictionary ? (total == 1 ? "key" : "keys") : (total == 1 ? "item" : "items")));
            lines.Add("");

            int count = 0;
            foreach (object entry in Entries(value))
            {
                if (count >= maxItems)
                {
                    lines.Add("  ...");
                    break;
                }
                lines.Add("  " + entry);
                count++;
            }
            return string.Join("\n", lines.ToArray());
        }

        /// <summary>
        /// One string per entry, "key = value" for a dictionary and the item itself for a list. Never called on a
        /// Sequence.
        /// </summary>
        public static IEnumerable<string> Entries(object value)
        {
            PSObject wrapped = value as PSObject;
            if (wrapped != null)
            {
                value = wrapped.BaseObject;
            }

            IDictionary dict = value as IDictionary;
            if (dict != null)
            {
                foreach (object key in dict.Keys)
                {
                    yield return string.Format("{0} = {1}", key, Short(dict[key]));
                }
                yield break;
            }

            foreach (object item in (IEnumerable)value)
            {
                yield return Short(item);
            }
        }

        private static string Short(object val)
        {
            string kind = ValueKind.Of(val);
            string text;
            if (kind == ValueKind.Null) text = "$null";
            else if (kind == ValueKind.Text) text = "'" + val + "'";
            else if (kind == ValueKind.Bool) text = "$" + val.ToString();
            else if (kind == ValueKind.Dictionary) text = "@{...}";
            else if (kind == ValueKind.List) text = "[...]";
            else if (kind == ValueKind.Sequence) text = "[sequence]";
            else text = ValueKind.DisplayText(val);

            if (text.Length > 40) text = text.Substring(0, 37) + "...";
            return text;
        }
    }

    // FileVersionInfo's 14 line ToString makes a row like 240px tall
    public class SingleLineConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            if (value == null) return null;

            string text;
            try
            {
                text = value.ToString();
            }
            catch (Exception)
            {
                return value;
            }

            // One line goes back as it came, so a date keeps the binding's culture
            if (text == null || text.IndexOf('\n') < 0) return value;

            string first = null;
            foreach (string line in text.Split(new char[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string trimmed = line.Trim();
                if (trimmed.Length == 0) continue;
                if (first != null) return first + " ...";
                first = trimmed;
            }
            return first != null ? first : string.Empty;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotSupportedException();
        }
    }

    public class IsExpandableConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            return ValueKind.IsExpandable(value);
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotSupportedException();
        }
    }
}
