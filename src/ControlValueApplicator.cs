using System;
using System.Collections;
using System.Security;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;

namespace PsUi
{
    // Applies values to WPF controls during dehydration (syncing script changes back to UI).
    // Stateless - all control-type logic lives here, hydration engine just orchestrates.
    public static class ControlValueApplicator
    {
        public static void ApplyToProxy(ThreadSafeControlProxy proxy, object value, System.Windows.Threading.Dispatcher dispatcher)
        {
            FrameworkElement control = proxy.Control;
            if (control == null) return;

            Action applyAction = () => ApplyValue(control, value);

            if (dispatcher != null)
            {
                if (dispatcher.CheckAccess())
                {
                    applyAction();
                }
                else
                {
                    dispatcher.BeginInvoke(applyAction);
                }
            }
            else
            {
                // No dispatcher - attempt direct apply (may fail if cross-thread)
                DebugHelper.Log("DEHYDRATION", "Warning: No dispatcher available for control update");
                try
                {
                    applyAction();
                }
                catch (InvalidOperationException ex)
                {
                    DebugHelper.Log("DEHYDRATION", "Cross-thread access denied: " + ex.Message);
                }
            }
        }

        // Must be called on UI thread
        public static void ApplyValue(FrameworkElement control, object value)
        {
            if (control == null) return;

            // Handle SecureString specially for PasswordBox
            SecureString secureStr = value as SecureString;
            if (secureStr != null)
            {
                PasswordBox pBox = control as PasswordBox;
                if (pBox != null)
                {
                    ApplySecureStringToPasswordBox(pBox, secureStr);
                    return;
                }
            }

            string stringValue = value != null ? value.ToString() : string.Empty;

            // TextBox
            TextBox textBox = control as TextBox;
            if (textBox != null)
            {
                textBox.Text = stringValue;
                return;
            }

            // PasswordBox (plain string)
            PasswordBox passwordBox = control as PasswordBox;
            if (passwordBox != null)
            {
                passwordBox.Password = stringValue;
                return;
            }

            // TextBlock
            TextBlock textBlock = control as TextBlock;
            if (textBlock != null)
            {
                textBlock.Text = stringValue;
                return;
            }

            // ComboBox
            ComboBox comboBox = control as ComboBox;
            if (comboBox != null)
            {
                ApplyToComboBox(comboBox, value, stringValue);
                return;
            }

            // ListBox
            ListBox listBox = control as ListBox;
            if (listBox != null)
            {
                ApplyToListBox(listBox, value, stringValue);
                return;
            }

            // CheckBox / ToggleButton
            ToggleButton toggleButton = control as ToggleButton;
            if (toggleButton != null)
            {
                ApplyToToggleButton(toggleButton, value, stringValue);
                return;
            }

            // DatePicker
            DatePicker datePicker = control as DatePicker;
            if (datePicker != null)
            {
                ApplyToDatePicker(datePicker, value, stringValue);
                return;
            }

            // Slider
            Slider slider = control as Slider;
            if (slider != null)
            {
                ApplyToSlider(slider, value, stringValue);
                return;
            }

            // ProgressBar
            ProgressBar progressBar = control as ProgressBar;
            if (progressBar != null)
            {
                ApplyToProgressBar(progressBar, value, stringValue);
                return;
            }

            // RadioGroup (StackPanel with RadioButtons)
            StackPanel stackPanel = control as StackPanel;
            if (stackPanel != null)
            {
                if (ApplyToRadioGroup(stackPanel, stringValue)) return;
            }

            // Data-backed controls (charts, etc.) - store data and invoke redraw
            Delegate dataCallback = UiHydration.GetOnDataChanged(control);
            if (dataCallback != null)
            {
                UiHydration.SetData(control, value);
                try
                {
                    // Direct invoke avoids DynamicInvoke issues with PS scriptblocks
                    Action simpleCallback = dataCallback as Action;
                    if (simpleCallback != null)
                    {
                        simpleCallback();
                    }
                    else
                    {
                        // Wrap in object[] so arrays aren't splatted as params
                        dataCallback.DynamicInvoke(new object[] { value });
                    }
                }
                catch (Exception ex)
                {
                    string msg = ex.InnerException != null ? ex.InnerException.Message : ex.Message;
                    DebugHelper.Log("DEHYDRATION", "Data changed callback failed: " + msg);
                }
                return;
            }

            // Generic fallback: UiHydration.ValueProperty attached property
            UiHydration.TryApplyValue(control, value);
        }

        private static void ApplySecureStringToPasswordBox(PasswordBox pBox, SecureString secureStr)
        {
            IntPtr ptr = System.Runtime.InteropServices.Marshal.SecureStringToGlobalAllocUnicode(secureStr);
            try
            {
                pBox.Password = System.Runtime.InteropServices.Marshal.PtrToStringUni(ptr);
            }
            finally
            {
                System.Runtime.InteropServices.Marshal.ZeroFreeGlobalAllocUnicode(ptr);
            }
        }

        private static void ApplyToComboBox(ComboBox comboBox, object value, string stringValue)
        {
            // Try to find matching item
            foreach (object item in comboBox.Items)
            {
                if (item != null && item.ToString() == stringValue)
                {
                    comboBox.SelectedItem = item;
                    return;
                }
                ComboBoxItem cbi = item as ComboBoxItem;
                if (cbi != null && cbi.Content != null && cbi.Content.ToString() == stringValue)
                {
                    comboBox.SelectedItem = item;
                    return;
                }
            }
            // No match found - set directly
            comboBox.SelectedItem = value;
        }

        private static void ApplyToListBox(ListBox listBox, object value, string stringValue)
        {
            foreach (object item in listBox.Items)
            {
                if (item != null && item.ToString() == stringValue)
                {
                    listBox.SelectedItem = item;
                    return;
                }
            }
            listBox.SelectedItem = value;
        }

        private static void ApplyToToggleButton(ToggleButton toggleButton, object value, string stringValue)
        {
            if (value is bool)
            {
                toggleButton.IsChecked = (bool)value;
            }
            else
            {
                bool boolVal;
                if (bool.TryParse(stringValue, out boolVal))
                {
                    toggleButton.IsChecked = boolVal;
                }
            }
        }

        private static void ApplyToDatePicker(DatePicker datePicker, object value, string stringValue)
        {
            if (value is DateTime)
            {
                datePicker.SelectedDate = (DateTime)value;
            }
            else if (value is DateTime?)
            {
                datePicker.SelectedDate = (DateTime?)value;
            }
            else
            {
                DateTime dt;
                if (DateTime.TryParse(stringValue, out dt))
                {
                    datePicker.SelectedDate = dt;
                }
            }
        }

        private static void ApplyToSlider(Slider slider, object value, string stringValue)
        {
            if (value is double)
            {
                slider.Value = (double)value;
            }
            else if (value is int)
            {
                slider.Value = (int)value;
            }
            else
            {
                double dblVal;
                if (double.TryParse(stringValue, out dblVal))
                {
                    slider.Value = dblVal;
                }
            }
        }

        private static void ApplyToProgressBar(ProgressBar progressBar, object value, string stringValue)
        {
            if (value is double)
            {
                progressBar.Value = (double)value;
            }
            else if (value is int)
            {
                progressBar.Value = (int)value;
            }
            else
            {
                double dblVal;
                if (double.TryParse(stringValue, out dblVal))
                {
                    progressBar.Value = dblVal;
                }
            }
        }

        // Find and select matching RadioButton by Tag value
        private static bool ApplyToRadioGroup(StackPanel stackPanel, string stringValue)
        {
            Hashtable tag = stackPanel.Tag as Hashtable;
            if (tag == null || (tag["ControlType"] as string) != "RadioGroup")
            {
                return false;
            }

            foreach (object child in stackPanel.Children)
            {
                RadioButton rb = child as RadioButton;
                if (rb != null && rb.Tag != null && rb.Tag.ToString() == stringValue)
                {
                    rb.IsChecked = true;
                    return true;
                }
            }
            return false;
        }
    }
}
