using System;
using System.Collections;
using System.Collections.Generic;
using System.Security;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;

namespace PsUi
{
    // Extracts values from WPF controls for hydration. Handles TextBox, ComboBox, CheckBox, Slider, etc.
    // Stateless - all control-type logic lives here, hydration engine just orchestrates.
    public static class ControlValueExtractor
    {
        // Reads all control values in one dispatcher call (N controls, 1 round-trip)
        public static Dictionary<string, object> ExtractAll(
            List<KeyValuePair<string, FrameworkElement>> controlsToRead,
            System.Windows.Threading.Dispatcher dispatcher)
        {
            if (controlsToRead == null || controlsToRead.Count == 0)
            {
                return new Dictionary<string, object>();
            }
            
            // If we need to dispatch to UI thread, do ONE invoke for ALL controls
            if (dispatcher != null && !dispatcher.CheckAccess())
            {
                return (Dictionary<string, object>)dispatcher.Invoke(new Func<object>(() =>
                {
                    var results = new Dictionary<string, object>();
                    foreach (var kvp in controlsToRead)
                    {
                        try
                        {
                            results[kvp.Key] = ExtractValue(kvp.Value);
                        }
                        catch (Exception ex)
                        {
                            DebugHelper.Log("HYDRATION", "Failed to read '{0}': {1}", kvp.Key, ex.Message);
                        }
                    }
                    return results;
                }));
            }
            
            // Already on UI thread - extract directly
            var directResults = new Dictionary<string, object>();
            foreach (var kvp in controlsToRead)
            {
                try
                {
                    directResults[kvp.Key] = ExtractValue(kvp.Value);
                }
                catch (Exception ex)
                {
                    DebugHelper.Log("HYDRATION", "Failed to read '{0}': {1}", kvp.Key, ex.Message);
                }
            }
            return directResults;
        }

        public static object ExtractFromProxy(ThreadSafeControlProxy proxy, System.Windows.Threading.Dispatcher dispatcher)
        {
            FrameworkElement control = proxy.Control;
            if (control == null) return null;

            if (dispatcher != null && !dispatcher.CheckAccess())
            {
                return dispatcher.Invoke(new Func<object>(() => ExtractValue(control)));
            }
            
            return ExtractValue(control);
        }

        // Must be called on UI thread
        public static object ExtractValue(FrameworkElement control)
        {
            if (control == null) return null;

            // TextBox
            TextBox textBox = control as TextBox;
            if (textBox != null) return textBox.Text;

            // PasswordBox - return SecureString for security
            PasswordBox passwordBox = control as PasswordBox;
            if (passwordBox != null) return passwordBox.SecurePassword;

            // TextBlock (read-only label)
            TextBlock textBlock = control as TextBlock;
            if (textBlock != null) return textBlock.Text;

            // ListBox with multi-select - return array of selected items
            ListBox listBox = control as ListBox;
            if (listBox != null && listBox.SelectionMode != SelectionMode.Single)
            {
                return ExtractMultiSelectListBox(listBox);
            }

            // ComboBox / ListBox single-select (Selector)
            Selector selector = control as Selector;
            if (selector != null)
            {
                return ExtractSelectorValue(selector);
            }

            // CheckBox / RadioButton / ToggleButton
            ToggleButton toggleButton = control as ToggleButton;
            if (toggleButton != null)
            {
                return toggleButton.IsChecked == true;
            }

            // DatePicker
            DatePicker datePicker = control as DatePicker;
            if (datePicker != null) return datePicker.SelectedDate;

            // Slider
            Slider slider = control as Slider;
            if (slider != null) return slider.Value;

            // ProgressBar
            ProgressBar progressBar = control as ProgressBar;
            if (progressBar != null) return progressBar.Value;

            // StackPanel - check for RadioGroup or ComboButton
            StackPanel stackPanel = control as StackPanel;
            if (stackPanel != null)
            {
                object stackValue = ExtractStackPanelValue(stackPanel);
                if (stackValue != null) return stackValue;
            }

            // Grid - check for TimePicker
            Grid grid = control as Grid;
            if (grid != null)
            {
                Hashtable tag = grid.Tag as Hashtable;
                if (tag != null && (tag["ControlType"] as string) == "TimePicker")
                {
                    return ExtractTimePickerValue(tag);
                }
            }

            // TreeView - extract selection snapshot (must be on UI thread)
            TreeView treeView = control as TreeView;
            if (treeView != null) return ExtractTreeViewSnapshot(treeView);

            // DataGrid - extract selection snapshot
            DataGrid dataGrid = control as DataGrid;
            if (dataGrid != null) return ExtractDataGridSnapshot(dataGrid);

            // ListView - extract selection snapshot
            ListView listView = control as ListView;
            if (listView != null) return ExtractListViewSnapshot(listView);

            // Data-backed controls (charts, etc.) - return stored dataset
            Delegate dataCallback = UiHydration.GetOnDataChanged(control);
            if (dataCallback != null)
            {
                return UiHydration.GetData(control);
            }

            // Generic fallback: UiHydration.ValueProperty attached property
            object attachedValue;
            if (UiHydration.TryExtractValue(control, out attachedValue))
            {
                return attachedValue;
            }

            // Final fallback - return the control itself rather than null
            return control;
        }

        private static object[] ExtractMultiSelectListBox(ListBox listBox)
        {
            List<object> selectedItems = new List<object>();
            foreach (object item in listBox.SelectedItems)
            {
                ListBoxItem lbi = item as ListBoxItem;
                if (lbi != null)
                {
                    selectedItems.Add(lbi.Content);
                }
                else
                {
                    selectedItems.Add(item);
                }
            }
            return selectedItems.ToArray();
        }

        private static object ExtractSelectorValue(Selector selector)
        {
            object selected = selector.SelectedItem;
            
            ComboBoxItem cbi = selected as ComboBoxItem;
            if (cbi != null) return cbi.Content;
            
            ListBoxItem lbi = selected as ListBoxItem;
            if (lbi != null) return lbi.Content;
            
            return selected;
        }

        // RadioGroup or ComboButton - check Tag for control type
        private static object ExtractStackPanelValue(StackPanel stackPanel)
        {
            Hashtable tag = stackPanel.Tag as Hashtable;
            if (tag == null) return null;

            string controlType = tag["ControlType"] as string;
            
            if (controlType == "ComboButton")
            {
                return tag["SelectedItem"];
            }
            
            if (controlType == "RadioGroup")
            {
                foreach (object child in stackPanel.Children)
                {
                    RadioButton rb = child as RadioButton;
                    if (rb != null && rb.IsChecked == true)
                    {
                        return rb.Tag;
                    }
                }
            }

            return null;
        }

        // TimePicker stores components in Tag hashtable
        private static TimeSpan? ExtractTimePickerValue(Hashtable tag)
        {
            try
            {
                int hour = 0;
                int minute = 0;
                string ampm = null;
                bool use24Hour = tag.ContainsKey("Use24Hour") && (bool)tag["Use24Hour"];

                // Support both ListBox and ComboBox styles
                ListBox hourList = tag["HourList"] as ListBox;
                ListBox minuteList = tag["MinuteList"] as ListBox;
                ListBox ampmList = tag["AmPmList"] as ListBox;

                if (hourList != null && hourList.SelectedItem != null)
                {
                    ListBoxItem item = hourList.SelectedItem as ListBoxItem;
                    if (item != null) int.TryParse(item.Content.ToString(), out hour);
                }

                if (minuteList != null && minuteList.SelectedItem != null)
                {
                    ListBoxItem item = minuteList.SelectedItem as ListBoxItem;
                    if (item != null) int.TryParse(item.Content.ToString(), out minute);
                }

                if (!use24Hour && ampmList != null && ampmList.SelectedItem != null)
                {
                    ListBoxItem item = ampmList.SelectedItem as ListBoxItem;
                    if (item != null) ampm = item.Content.ToString();
                    
                    if (ampm == "PM" && hour < 12) hour += 12;
                    if (ampm == "AM" && hour == 12) hour = 0;
                }

                return new TimeSpan(hour, minute, 0);
            }
            catch
            {
                return null;
            }
        }

        // TreeView snapshot with selection info - captured on UI thread for async access
        private static Hashtable ExtractTreeViewSnapshot(TreeView treeView)
        {
            var snapshot = new Hashtable();
            snapshot["Control"] = treeView;
            snapshot["SelectedItem"] = treeView.SelectedItem;
            snapshot["SelectedValue"] = treeView.SelectedValue;
            
            // Extract header text if selected item is TreeViewItem
            TreeViewItem selectedTvi = treeView.SelectedItem as TreeViewItem;
            if (selectedTvi != null)
            {
                snapshot["SelectedHeader"] = selectedTvi.Header;
                snapshot["SelectedTag"] = selectedTvi.Tag;
            }
            
            return snapshot;
        }

        // DataGrid snapshot with selection info
        private static Hashtable ExtractDataGridSnapshot(DataGrid dataGrid)
        {
            var snapshot = new Hashtable();
            snapshot["Control"] = dataGrid;
            snapshot["SelectedItem"] = dataGrid.SelectedItem;
            snapshot["SelectedIndex"] = dataGrid.SelectedIndex;
            
            // Copy selected items to array for thread-safe access
            var selectedItems = new List<object>();
            foreach (object item in dataGrid.SelectedItems)
            {
                selectedItems.Add(item);
            }
            snapshot["SelectedItems"] = selectedItems.ToArray();
            snapshot["ItemsSource"] = dataGrid.ItemsSource;
            
            return snapshot;
        }

        // ListView snapshot with selection info
        private static Hashtable ExtractListViewSnapshot(ListView listView)
        {
            var snapshot = new Hashtable();
            snapshot["Control"] = listView;
            snapshot["SelectedItem"] = listView.SelectedItem;
            snapshot["SelectedIndex"] = listView.SelectedIndex;
            
            // Copy selected items to array for thread-safe access
            var selectedItems = new List<object>();
            foreach (object item in listView.SelectedItems)
            {
                selectedItems.Add(item);
            }
            snapshot["SelectedItems"] = selectedItems.ToArray();
            
            return snapshot;
        }
    }
}
