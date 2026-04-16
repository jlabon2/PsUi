using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Windows.Data;

namespace PsUi
{
    // Formats arrays as "[N items]" in DataGrid cells
    public class ArrayDisplayConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            if (value == null) return null;
            
            // Check if it's an array or collection (but not a string)
            if (value is string) return value;
            
            // Only count ICollection types (arrays, lists, etc.) - NOT raw IEnumerable
            // Iterating raw IEnumerable would consume forward-only streams (file readers, generators)
            ICollection collection = value as ICollection;
            if (collection != null)
            {
                int count = collection.Count;
                if (count == 0) return "[empty]";
                if (count == 1) return "[1 item]";
                return string.Format("[{0} items]", count);
            }
            
            // For non-ICollection enumerables, just indicate it's a sequence without consuming it
            IEnumerable enumerable = value as IEnumerable;
            if (enumerable != null)
            {
                return "[sequence]";
            }
            
            return value;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotSupportedException();
        }

        // Preview first few items for tooltip hover
        public static string GetTooltipPreview(object value, int maxItems)
        {
            if (value == null) return null;
            if (value is string) return null;
            
            // Only preview ICollection types - raw IEnumerable could be forward-only streams
            ICollection collection = value as ICollection;
            if (collection == null)
            {
                // Check if it's a non-ICollection enumerable and show a safe message
                IEnumerable enumerable = value as IEnumerable;
                if (enumerable != null)
                {
                    return "(sequence - cannot preview without consuming)";
                }
                return null;
            }
            
            List<string> items = new List<string>();
            int count = 0;
            int total = collection.Count;
            
            // Safe to enumerate ICollection (it supports multiple iteration)
            foreach (object item in collection)
            {
                if (count < maxItems)
                {
                    string itemStr = item != null ? item.ToString() : "(null)";
                    if (itemStr.Length > 50)
                    {
                        itemStr = itemStr.Substring(0, 47) + "...";
                    }
                    items.Add(itemStr);
                }
                count++;
                if (count >= maxItems) break;
            }
            
            string preview = string.Join("\n", items.ToArray());
            if (total > maxItems)
            {
                preview += string.Format("\n... and {0} more", total - maxItems);
            }
            
            return preview;
        }
    }

    // Generates click-to-expand tooltip preview for arrays
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
            string preview = ArrayDisplayConverter.GetTooltipPreview(value, _maxItems);
            if (string.IsNullOrEmpty(preview))
            {
                return null;
            }
            return "Click to expand:\n\n" + preview;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotSupportedException();
        }
    }

    // Tooltip for hashtables and nested objects in Value column
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
            if (value == null) return null;

            // Handle hashtables/dictionaries
            IDictionary dict = value as IDictionary;
            if (dict != null)
            {
                List<string> lines = new List<string>();
                lines.Add(string.Format("Click to expand ({0} keys):", dict.Count));
                lines.Add("");
                
                int count = 0;
                foreach (object key in dict.Keys)
                {
                    if (count >= _maxItems)
                    {
                        lines.Add("  ...");
                        break;
                    }
                    object val = dict[key];
                    string valStr;
                    if (val == null) valStr = "$null";
                    else if (val is string) valStr = "'" + val + "'";
                    else if (val is bool) valStr = "$" + val.ToString();
                    else if (val is IDictionary) valStr = "@{...}";
                    else if (val is IEnumerable && !(val is string)) valStr = "[...]";
                    else valStr = val.ToString();
                    
                    lines.Add(string.Format("  {0} = {1}", key, valStr));
                    count++;
                }
                return string.Join("\n", lines.ToArray());
            }

            // Handle arrays/collections
            IEnumerable enumerable = value as IEnumerable;
            if (enumerable != null && !(value is string))
            {
                List<string> lines = new List<string>();
                ICollection collection = value as ICollection;
                int total = collection != null ? collection.Count : -1;
                
                lines.Add(total >= 0 
                    ? string.Format("Click to expand ({0} items):", total)
                    : "Click to expand:");
                lines.Add("");

                int count = 0;
                foreach (object item in enumerable)
                {
                    if (count >= _maxItems)
                    {
                        lines.Add("  ...");
                        break;
                    }
                    string itemStr = item != null ? item.ToString() : "(null)";
                    if (itemStr.Length > 40) itemStr = itemStr.Substring(0, 37) + "...";
                    lines.Add("  " + itemStr);
                    count++;
                }
                return string.Join("\n", lines.ToArray());
            }

            return null;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotSupportedException();
        }
    }
}
