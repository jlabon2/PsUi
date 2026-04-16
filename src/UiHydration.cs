using System;
using System.Windows;

namespace PsUi
{
    // Attached properties for generic control hydration.
    // Attached property tells hydration engine which property to read/write.
    public static class UiHydration
    {
        public static readonly DependencyProperty ValuePropertyProperty =
            DependencyProperty.RegisterAttached(
                "ValueProperty",
                typeof(string),
                typeof(UiHydration),
                new PropertyMetadata(null));

        public static void SetValueProperty(DependencyObject element, string value)
        {
            if (element == null) throw new ArgumentNullException("element");
            element.SetValue(ValuePropertyProperty, value);
        }

        public static string GetValueProperty(DependencyObject element)
        {
            if (element == null) throw new ArgumentNullException("element");
            return (string)element.GetValue(ValuePropertyProperty);
        }

        // Reads value via reflection on the attached property name
        public static bool TryExtractValue(FrameworkElement control, out object value)
        {
            value = null;
            if (control == null) return false;

            string propName = GetValueProperty(control);
            if (string.IsNullOrEmpty(propName)) return false;

            var prop = control.GetType().GetProperty(propName);
            if (prop == null || !prop.CanRead) return false;

            try
            {
                value = prop.GetValue(control);
                return true;
            }
            catch
            {
                return false;
            }
        }

        // Writes value back - same reflection trick as extraction
        public static bool TryApplyValue(FrameworkElement control, object value)
        {
            if (control == null) return false;

            string propName = GetValueProperty(control);
            if (string.IsNullOrEmpty(propName)) return false;

            var prop = control.GetType().GetProperty(propName);
            if (prop == null || !prop.CanWrite) return false;

            try
            {
                // Attempt type conversion if needed
                object convertedValue = value;
                if (value != null && prop.PropertyType != value.GetType())
                {
                    try
                    {
                        convertedValue = Convert.ChangeType(value, prop.PropertyType);
                    }
                    catch
                    {
                        // If conversion fails, try setting directly
                        convertedValue = value;
                    }
                }

                prop.SetValue(control, convertedValue);
                return true;
            }
            catch
            {
                return false;
            }
        }

        // Stores updateable data for controls with custom rendering (charts, etc.).
        // Unlike ValueProperty which uses reflection, Data is direct attached storage.
        public static readonly DependencyProperty DataProperty =
            DependencyProperty.RegisterAttached(
                "Data",
                typeof(object),
                typeof(UiHydration),
                new PropertyMetadata(null));

        public static void SetData(DependencyObject element, object value)
        {
            if (element == null) throw new ArgumentNullException("element");
            element.SetValue(DataProperty, value);
        }

        public static object GetData(DependencyObject element)
        {
            if (element == null) throw new ArgumentNullException("element");
            return element.GetValue(DataProperty);
        }

        // Callback invoked when data is applied during dehydration.
        // Controls that register this handle their own visual update (e.g. chart redraw).
        // Stored as Delegate - prefer registering as Action (no params) for reliability.
        public static readonly DependencyProperty OnDataChangedProperty =
            DependencyProperty.RegisterAttached(
                "OnDataChanged",
                typeof(Delegate),
                typeof(UiHydration),
                new PropertyMetadata(null));

        public static void SetOnDataChanged(DependencyObject element, Delegate value)
        {
            if (element == null) throw new ArgumentNullException("element");
            element.SetValue(OnDataChangedProperty, value);
        }

        public static Delegate GetOnDataChanged(DependencyObject element)
        {
            if (element == null) throw new ArgumentNullException("element");
            return (Delegate)element.GetValue(OnDataChangedProperty);
        }
    }
}
