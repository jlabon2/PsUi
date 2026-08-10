using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
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
        // Reads all control values in one hop to the UI thread (N controls, 1 round-trip)
        public static Dictionary<string, object> ExtractAll(
            List<KeyValuePair<string, FrameworkElement>> controlsToRead,
            System.Windows.Threading.Dispatcher dispatcher)
        {
            if (controlsToRead == null || controlsToRead.Count == 0)
            {
                return new Dictionary<string, object>();
            }
            
            // If a dispatch to UI thread is needed, do ONE invoke for ALL controls
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

            // DataGrid MUST come before the Selector check. It derives from MultiSelector, itself a Selector, so that branch would short circuit to a singular SelectedItem and lose all but the first row.
            DataGrid dataGrid = control as DataGrid;
            if (dataGrid != null) return ExtractDataGridSnapshot(dataGrid);

            // ListView derives from ListBox (and thus Selector), so it has to be caught here too, otherwise the ListBox/Selector branches below eat it and return a lone SelectedItem instead of the snapshot. Same short circuit issue as DataGrid.
            ListView listView = control as ListView;
            if (listView != null) return ExtractListViewSnapshot(listView);

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

            // Unknown control type - no extractable value. Must return null, NOT the control itself. Returning a live WPF object crosses runspace boundaries and causes deadlocks when STA pool threads try to marshal it.
            return null;
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

        // TreeView snapshot - captured on UI thread for async access. Checkbox trees return an object[] of checked items instead. Matches -MultiSelect list / -PassThru datagrid hydration.
        private static object ExtractTreeViewSnapshot(TreeView treeView)
        {
            // Type-check before unbox - Tag is a PowerShell hashtable, anything goes.
            // Skip the `is bool` and a no-checkbox tree throws on the cast.
            Hashtable tag = treeView.Tag as Hashtable;
            if (tag != null && tag["IsCheckBoxTree"] is bool && (bool)tag["IsCheckBoxTree"])
            {
                bool parentMode = tag["ParentMode"] is bool && (bool)tag["ParentMode"];
                bool childMode = tag["ChildMode"] is bool && (bool)tag["ChildMode"];
                return ExtractCheckedTreeItems(treeView, parentMode, childMode);
            }

            var snapshot = new Hashtable();
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

        // Walks the visual tree and returns the checked source items - once each, in tree order.
        //  - both modes on : every checked TreeViewItem's source (parents + leaves)
        //  - parent-only   : descendant leaves of every checked branch (mass-select shorthand)
        //  - child-only    : checked leaves only
        // Skips path-mode stand-in parents (Tag carries Synthesized=$true).
        private static object[] ExtractCheckedTreeItems(TreeView treeView, bool parentMode, bool childMode)
        {
            var results = new List<object>();
            var seen = new HashSet<object>();
            CollectCheckedItems(treeView.Items, parentMode, childMode, results, seen);
            return results.ToArray();
        }

        private static void CollectCheckedItems(ItemCollection items, bool parentMode, bool childMode, List<object> results, HashSet<object> seen)
        {
            foreach (object item in items)
            {
                TreeViewItem tvi = item as TreeViewItem;
                if (tvi == null) continue;

                bool hasChildren = tvi.Items.Count > 0;
                CheckBox box = FindHeaderCheckBox(tvi);
                bool isChecked = box != null && box.IsChecked == true;

                if (parentMode && childMode)
                {
                    if (isChecked) AddSource(tvi, results, seen);
                    CollectCheckedItems(tvi.Items, parentMode, childMode, results, seen);
                }
                else if (parentMode)
                {
                    if (isChecked && hasChildren)
                    {
                        CollectLeafSources(tvi.Items, results, seen);
                    }
                    else
                    {
                        CollectCheckedItems(tvi.Items, parentMode, childMode, results, seen);
                    }
                }
                else if (childMode)
                {
                    if (isChecked && !hasChildren) AddSource(tvi, results, seen);
                    CollectCheckedItems(tvi.Items, parentMode, childMode, results, seen);
                }
            }
        }

        // Mass-select helper: under a checked branch, return every descendant leaf's source item.
        private static void CollectLeafSources(ItemCollection items, List<object> results, HashSet<object> seen)
        {
            foreach (object item in items)
            {
                TreeViewItem tvi = item as TreeViewItem;
                if (tvi == null) continue;

                if (tvi.Items.Count == 0)
                {
                    AddSource(tvi, results, seen);
                }
                else
                {
                    CollectLeafSources(tvi.Items, results, seen);
                }
            }
        }

        private static void AddSource(TreeViewItem tvi, List<object> results, HashSet<object> seen)
        {
            object source = tvi.Tag;
            if (source == null) return;
            // Path mode adds stand in parents for the path segments - skip them, your script only piped in real items. Check both the Hashtable and PSObject forms.
            PSObject pso = source as PSObject;
            object underlying = pso != null ? pso.BaseObject : source;
            Hashtable ht = underlying as Hashtable;
            if (ht != null && ht["Synthesized"] is bool && (bool)ht["Synthesized"]) return;
            if (pso != null)
            {
                PSMemberInfo m = pso.Members["Synthesized"];
                if (m != null && m.Value is bool && (bool)m.Value) return;
            }
            if (seen.Add(source)) results.Add(source);
        }

        // Knows the decoration's layout: CheckBox as a direct child of a StackPanel header.
        private static CheckBox FindHeaderCheckBox(TreeViewItem tvi)
        {
            StackPanel sp = tvi.Header as StackPanel;
            if (sp == null) return null;
            foreach (object child in sp.Children)
            {
                CheckBox cb = child as CheckBox;
                if (cb != null) return cb;
            }
            return null;
        }

        // Selected rows as a plain array so `foreach ($row in $varName)` works directly in actions.
        // Full grid control still accessible at (Get-UiSession).GetControl('varName').
        private static object[] ExtractDataGridSnapshot(DataGrid dataGrid)
        {
            List<object> selectedItems = new List<object>();
            foreach (object item in dataGrid.SelectedItems)
            {
                selectedItems.Add(UnwrapSnapshotRow(item));
            }
            return selectedItems.ToArray();
        }

        // Owned (-Items) grids snapshot each row into a PSCustomObject carrying _BaseObject (the original) and _SearchText (the filter index). Hand back the original so a hydrated selection doesn't leak those internal note properties into the calling script's pipeline - the same unwrap Out-Datagrid's PassThru path already does in PowerShell. Raw -ItemsSource rows have no _BaseObject and pass through untouched.
        private static object UnwrapSnapshotRow(object item)
        {
            if (item == null) { return null; }
            PSObject pso = item as PSObject;
            if (pso == null) { pso = PSObject.AsPSObject(item); }
            PSPropertyInfo baseProp = pso.Properties["_BaseObject"];
            if (baseProp != null && baseProp.Value != null) { return baseProp.Value; }
            return item;
        }

        // ListView snapshot with selection info
        private static Hashtable ExtractListViewSnapshot(ListView listView)
        {
            Hashtable snapshot = new Hashtable();
            snapshot["SelectedItem"] = listView.SelectedItem;
            snapshot["SelectedIndex"] = listView.SelectedIndex;

            // Copy selected items to array for thread-safe access
            List<object> selectedItems = new List<object>();
            foreach (object item in listView.SelectedItems)
            {
                selectedItems.Add(item);
            }
            snapshot["SelectedItems"] = selectedItems.ToArray();
            
            return snapshot;
        }
    }
}
