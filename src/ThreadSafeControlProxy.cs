using System;
using System.Security;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;

namespace PsUi
{
    // Thread-safe proxy for WPF controls. Auto-marshals property access to UI thread.
    public class ThreadSafeControlProxy
    {
        private readonly FrameworkElement _control;
        private readonly string _controlName;

        public ThreadSafeControlProxy(FrameworkElement control, string controlName)
        {
            if (control == null)
                throw new ArgumentNullException("control");
            
            _control = control;
            _controlName = controlName ?? string.Empty;
        }

        // Text property for TextBox, TextBlock, Label, PasswordBox - auto-marshals to UI thread
        public string Text
        {
            get
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    return GetTextInternal();
                }
                return (string)_control.Dispatcher.Invoke(new Func<string>(GetTextInternal));
            }
            set
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    SetTextInternal(value);
                }
                else
                {
                    _control.Dispatcher.Invoke(new Action<string>(SetTextInternal), value);
                }
            }
        }

        private string GetTextInternal()
        {
            TextBox textBox = _control as TextBox;
            if (textBox != null) return textBox.Text;

            TextBlock textBlock = _control as TextBlock;
            if (textBlock != null) return textBlock.Text;

            Label label = _control as Label;
            if (label != null) return label.Content as string;

            PasswordBox passwordBox = _control as PasswordBox;
            if (passwordBox != null) return passwordBox.Password;

            return null;
        }

        private void SetTextInternal(string value)
        {
            TextBox textBox = _control as TextBox;
            if (textBox != null) { textBox.Text = value ?? string.Empty; return; }

            TextBlock textBlock = _control as TextBlock;
            if (textBlock != null) { textBlock.Text = value ?? string.Empty; return; }

            Label label = _control as Label;
            if (label != null) { label.Content = value; return; }

            PasswordBox passwordBox = _control as PasswordBox;
            if (passwordBox != null) { passwordBox.Password = value ?? string.Empty; return; }
        }

        // SecurePassword for PasswordBox - returns SecureString, auto-marshals
        public SecureString SecurePassword
        {
            get
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    return GetSecurePasswordInternal();
                }
                return (SecureString)_control.Dispatcher.Invoke(new Func<SecureString>(GetSecurePasswordInternal));
            }
        }

        private SecureString GetSecurePasswordInternal()
        {
            PasswordBox passwordBox = _control as PasswordBox;
            if (passwordBox != null) return passwordBox.SecurePassword;
            return new SecureString();
        }

        // SelectedIndex for ComboBox/ListBox - auto-marshals
        public int SelectedIndex
        {
            get
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    return GetSelectedIndexInternal();
                }
                return (int)_control.Dispatcher.Invoke(new Func<int>(GetSelectedIndexInternal));
            }
            set
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    SetSelectedIndexInternal(value);
                }
                else
                {
                    _control.Dispatcher.Invoke(new Action<int>(SetSelectedIndexInternal), value);
                }
            }
        }

        private int GetSelectedIndexInternal()
        {
            Selector selector = _control as Selector;
            if (selector != null) return selector.SelectedIndex;
            return -1;
        }

        private void SetSelectedIndexInternal(int value)
        {
            Selector selector = _control as Selector;
            if (selector != null) selector.SelectedIndex = value;
        }

        // SelectedItem for ComboBox/ListBox - auto-marshals
        public object SelectedItem
        {
            get
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    return GetSelectedItemInternal();
                }
                return _control.Dispatcher.Invoke(new Func<object>(GetSelectedItemInternal));
            }
            set
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    SetSelectedItemInternal(value);
                }
                else
                {
                    _control.Dispatcher.Invoke(new Action<object>(SetSelectedItemInternal), value);
                }
            }
        }

        private object GetSelectedItemInternal()
        {
            Selector selector = _control as Selector;
            if (selector != null) return selector.SelectedItem;
            return null;
        }

        private void SetSelectedItemInternal(object value)
        {
            Selector selector = _control as Selector;
            if (selector != null) selector.SelectedItem = value;
        }

        // IsChecked for CheckBox/RadioButton/ToggleButton - auto-marshals
        public bool? IsChecked
        {
            get
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    return GetIsCheckedInternal();
                }
                return (bool?)_control.Dispatcher.Invoke(new Func<bool?>(GetIsCheckedInternal));
            }
            set
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    SetIsCheckedInternal(value);
                }
                else
                {
                    _control.Dispatcher.Invoke(new Action<bool?>(SetIsCheckedInternal), value);
                }
            }
        }

        private bool? GetIsCheckedInternal()
        {
            ToggleButton toggleButton = _control as ToggleButton;
            if (toggleButton != null) return toggleButton.IsChecked;
            return null;
        }

        private void SetIsCheckedInternal(bool? value)
        {
            ToggleButton toggleButton = _control as ToggleButton;
            if (toggleButton != null) toggleButton.IsChecked = value;
        }

        // IsEnabled for any control - auto-marshals
        public bool IsEnabled
        {
            get
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    return _control.IsEnabled;
                }
                return (bool)_control.Dispatcher.Invoke(new Func<bool>(() => _control.IsEnabled));
            }
            set
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    _control.IsEnabled = value;
                }
                else
                {
                    _control.Dispatcher.Invoke(new Action<bool>(v => _control.IsEnabled = v), value);
                }
            }
        }

        // Visibility for any control - auto-marshals
        public Visibility Visibility
        {
            get
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    return _control.Visibility;
                }
                return (Visibility)_control.Dispatcher.Invoke(new Func<Visibility>(() => _control.Visibility));
            }
            set
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    _control.Visibility = value;
                }
                else
                {
                    _control.Dispatcher.Invoke(new Action<Visibility>(v => _control.Visibility = v), value);
                }
            }
        }

        // SelectedDate for DatePicker - auto-marshals
        public DateTime? SelectedDate
        {
            get
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    return GetSelectedDateInternal();
                }
                return (DateTime?)_control.Dispatcher.Invoke(new Func<DateTime?>(GetSelectedDateInternal));
            }
            set
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    SetSelectedDateInternal(value);
                }
                else
                {
                    _control.Dispatcher.Invoke(new Action<DateTime?>(SetSelectedDateInternal), value);
                }
            }
        }

        private DateTime? GetSelectedDateInternal()
        {
            DatePicker datePicker = _control as DatePicker;
            if (datePicker != null) return datePicker.SelectedDate;
            return null;
        }

        private void SetSelectedDateInternal(DateTime? value)
        {
            DatePicker datePicker = _control as DatePicker;
            if (datePicker != null) datePicker.SelectedDate = value;
        }

        public FrameworkElement Control
        {
            get { return _control; }
        }

        public string Name
        {
            get { return _controlName; }
        }

        // Get typed value based on control - TextBox.Text, ComboBox.SelectedItem, CheckBox.IsChecked, etc.
        public object Value
        {
            get
            {
                if (_control.Dispatcher.CheckAccess())
                {
                    return GetValueInternal();
                }
                return _control.Dispatcher.Invoke(new Func<object>(GetValueInternal));
            }
        }

        private object GetValueInternal()
        {
            // TextBox
            TextBox textBox = _control as TextBox;
            if (textBox != null) return textBox.Text;

            // PasswordBox
            PasswordBox passwordBox = _control as PasswordBox;
            if (passwordBox != null) return passwordBox.Password;

            // TextBlock
            TextBlock textBlock = _control as TextBlock;
            if (textBlock != null) return textBlock.Text;

            // ComboBox / ListBox (Selector)
            Selector selector = _control as Selector;
            if (selector != null)
            {
                object selected = selector.SelectedItem;
                ComboBoxItem comboItem = selected as ComboBoxItem;
                if (comboItem != null) return comboItem.Content;
                ListBoxItem listItem = selected as ListBoxItem;
                if (listItem != null) return listItem.Content;
                return selected;
            }

            // CheckBox / RadioButton / ToggleButton
            ToggleButton toggleButton = _control as ToggleButton;
            if (toggleButton != null) return toggleButton.IsChecked == true;

            // DatePicker
            DatePicker datePicker = _control as DatePicker;
            if (datePicker != null) return datePicker.SelectedDate;

            // Slider
            Slider slider = _control as Slider;
            if (slider != null) return slider.Value;

            // ProgressBar
            ProgressBar progressBar = _control as ProgressBar;
            if (progressBar != null) return progressBar.Value;

            // StackPanel - RadioGroup or ComboButton
            StackPanel stackPanel = _control as StackPanel;
            if (stackPanel != null)
            {
                System.Collections.Hashtable tag = stackPanel.Tag as System.Collections.Hashtable;
                if (tag != null)
                {
                    string controlType = tag["ControlType"] as string;
                    if (controlType == "ComboButton") return tag["SelectedItem"];
                    if (controlType == "RadioGroup")
                    {
                        foreach (object child in stackPanel.Children)
                        {
                            RadioButton rb = child as RadioButton;
                            if (rb != null && rb.IsChecked == true) return rb.Tag;
                        }
                    }
                }
            }

            return null;
        }

        // Reset control to default state
        public void Clear()
        {
            if (_control.Dispatcher.CheckAccess())
            {
                ClearInternal();
            }
            else
            {
                _control.Dispatcher.Invoke(new Action(ClearInternal));
            }
        }

        private void ClearInternal()
        {
            TextBox textBox = _control as TextBox;
            if (textBox != null) { textBox.Text = string.Empty; return; }

            PasswordBox passwordBox = _control as PasswordBox;
            if (passwordBox != null) { passwordBox.Password = string.Empty; return; }

            ComboBox comboBox = _control as ComboBox;
            if (comboBox != null) { comboBox.SelectedIndex = -1; return; }

            ListBox listBox = _control as ListBox;
            if (listBox != null) { listBox.SelectedIndex = -1; return; }

            CheckBox checkBox = _control as CheckBox;
            if (checkBox != null) { checkBox.IsChecked = false; return; }

            DatePicker datePicker = _control as DatePicker;
            if (datePicker != null) { datePicker.SelectedDate = null; return; }
        }
    }
}
