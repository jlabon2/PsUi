using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Markup;

namespace PsUi
{
    // Factory for creating pre-styled WPF controls with modern Fluent design
    public static class ControlFactory
    {
        private const double DefaultCornerRadius = 4.0;
        private const double DefaultBorderThickness = 1.0;

        // Try to apply a named style from application resources. Returns true if applied.
        private static bool TryApplyStyle(FrameworkElement control, string styleName)
        {
            try
            {
                if (Application.Current != null && Application.Current.Resources.Contains(styleName))
                {
                    control.Style = Application.Current.Resources[styleName] as Style;
                    return true;
                }
            }
            catch (Exception ex)
            {
                DebugHelper.LogException("CONTROL", "TryApplyStyle " + styleName, ex);
            }
            return false;
        }

        // Bubble scroll events from controls that swallow them (TextBox) up to parent ScrollViewer
        private static void HandlePreviewMouseWheel(object sender, MouseWheelEventArgs e)
        {
            if (!e.Handled)
            {
                e.Handled = true;
                var eventArg = new MouseWheelEventArgs(e.MouseDevice, e.Timestamp, e.Delta);
                eventArg.RoutedEvent = UIElement.MouseWheelEvent;
                eventArg.Source = sender;
                var parent = ((Control)sender).Parent as UIElement;
                if (parent != null)
                {
                    parent.RaiseEvent(eventArg);
                }
            }
        }

        public static Button CreateButton(string content, double width = double.NaN, double height = 35)
        {
            // Visual properties (Font, Padding) are set by Set-ButtonStyle - only behavioral defaults here
            var button = new Button
            {
                Content = content,
                Height = height,
                Cursor = Cursors.Hand
            };

            if (!double.IsNaN(width))
            {
                button.Width = width;
            }

            // Try XAML style first (preferred over manual resource binding)
            if (TryApplyStyle(button, "ModernButtonStyle"))
            {
                button.Effect = new DropShadowEffect
                {
                    ShadowDepth = 2,
                    Direction = 315,
                    Color = Colors.Gray,
                    Opacity = 0.2,
                    BlurRadius = 4
                };
            }
            else
            {
                // No style - bind directly so theme changes still propagate
                button.SetResourceReference(Control.BackgroundProperty, "ButtonBackgroundBrush");
                button.SetResourceReference(Control.ForegroundProperty, "ButtonForegroundBrush");
                button.SetResourceReference(Control.BorderBrushProperty, "BorderBrush");
                button.BorderThickness = new Thickness(DefaultBorderThickness);
                
                // Fallback template for rounded corners if style is missing
                ApplyRoundedButtonStyleFallback(button);
            }

            ThemeEngine.RegisterElement(button);
            return button;
        }

        private static void ApplyRoundedButtonStyleFallback(Button button)
        {
            // Fallback uses TemplateBindings, so it respects the ResourceReferences set above.
            var xaml = string.Format(@"
<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
                 xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
                 TargetType='Button'>
    <Border x:Name='border' 
            Background='{{TemplateBinding Background}}'
            BorderBrush='{{TemplateBinding BorderBrush}}'
            BorderThickness='{{TemplateBinding BorderThickness}}'
            CornerRadius='{0}'
            SnapsToDevicePixels='true'>
        <ContentPresenter x:Name='contentPresenter'
                          Focusable='False'
                          HorizontalAlignment='{{TemplateBinding HorizontalContentAlignment}}'
                          Margin='{{TemplateBinding Padding}}'
                          RecognizesAccessKey='True'
                          SnapsToDevicePixels='{{TemplateBinding SnapsToDevicePixels}}'
                          VerticalAlignment='{{TemplateBinding VerticalContentAlignment}}'/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property='IsMouseOver' Value='true'>
             <Setter Property='Opacity' Value='0.8'/>
        </Trigger>
        <Trigger Property='IsEnabled' Value='false'>
            <Setter Property='Opacity' Value='0.5'/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>", DefaultCornerRadius);

            try
            {
                button.Template = (ControlTemplate)XamlReader.Parse(xaml);
            }
            catch (Exception ex)
            {
                DebugHelper.LogException("CONTROL", "ApplyRoundedButtonStyleFallback XAML parse", ex);
            }
        }

        public static GroupBox CreateGroupBox(string header, double height = 145)
        {
            // Visual properties (Font) are set by Set-GroupBoxStyle - only layout defaults here
            var groupBox = new GroupBox
            {
                Header = header,
                Height = height,
                Margin = new Thickness(4, 2, 6, 2),
                Padding = new Thickness(8, 4, 8, 8)
            };

            if (!TryApplyStyle(groupBox, "ModernGroupBoxStyle")) {
                // Fallback: bind directly so theme changes propagate
                groupBox.SetResourceReference(Control.BackgroundProperty, "WindowBackgroundBrush");
                groupBox.SetResourceReference(Control.BorderBrushProperty, "BorderBrush");
                groupBox.SetResourceReference(Control.ForegroundProperty, "ControlForegroundBrush");
                groupBox.BorderThickness = new Thickness(DefaultBorderThickness);
            }

            groupBox.Effect = new DropShadowEffect
            {
                ShadowDepth = 1,
                Direction = 315,
                Color = Colors.LightGray,
                Opacity = 0.4,
                BlurRadius = 3
            };

            ThemeEngine.RegisterElement(groupBox);
            return groupBox;
        }

        public static TabControl CreateTabControl()
        {
            // Visual properties (Font) are set by Set-TabControlStyle
            var tabControl = new TabControl();

            if (!TryApplyStyle(tabControl, "ModernTabControlStyle"))
            {
                tabControl.Background = Brushes.Transparent;
                tabControl.SetResourceReference(Control.BorderBrushProperty, "BorderBrush");
                tabControl.BorderThickness = new Thickness(0, 1, 0, 0);
                tabControl.Padding = new Thickness(0);
            }

            ThemeEngine.RegisterElement(tabControl);
            return tabControl;
        }

        public static TabItem CreateTabItem(string header)
        {
            // Visual properties (Font) are set by Set-TabItemStyle
            var tabItem = new TabItem
            {
                Header = header
            };

            TryApplyStyle(tabItem, "ModernTabItemStyle");

            // Fallback is omitted here as complex TabItem templates are best handled via XAML styles
            // The default WPF style will accept the Foreground/Background references if set
            
            ThemeEngine.RegisterElement(tabItem);
            return tabItem;
        }

        public static DataGrid CreateDataGrid()
        {
            var dataGrid = new DataGrid
            {
                AutoGenerateColumns = false,
                CanUserAddRows = false,
                CanUserDeleteRows = true,
                CanUserResizeRows = false,
                IsReadOnly = true,
                SelectionMode = DataGridSelectionMode.Single,
                SelectionUnit = DataGridSelectionUnit.FullRow,
                GridLinesVisibility = DataGridGridLinesVisibility.Horizontal,
                HeadersVisibility = DataGridHeadersVisibility.Column,
                RowHeaderWidth = 0,
                AlternationCount = 2,
                Margin = new Thickness(8),
                // Visual properties (Font) are set by Set-DataGridStyle
                EnableRowVirtualization = true,
                EnableColumnVirtualization = true
            };

            if (!TryApplyStyle(dataGrid, "ModernDataGridStyle")) {
                // Fallback: bind directly so theme changes propagate
                dataGrid.SetResourceReference(Control.BorderBrushProperty, "BorderBrush");
                dataGrid.SetResourceReference(Control.BackgroundProperty, "ControlBackgroundBrush");
                dataGrid.SetResourceReference(Control.ForegroundProperty, "ControlForegroundBrush");
                // AlternatingRowBackground is on DataGrid, not ItemsControl
                dataGrid.SetResourceReference(DataGrid.AlternatingRowBackgroundProperty, "GridAlternatingRowBrush");
                dataGrid.SetResourceReference(DataGrid.RowBackgroundProperty, "WindowBackgroundBrush");
                dataGrid.SetResourceReference(DataGrid.HorizontalGridLinesBrushProperty, "GridLineBrush");
                dataGrid.SetResourceReference(DataGrid.VerticalGridLinesBrushProperty, "GridLineBrush");
            }

            VirtualizingPanel.SetIsVirtualizing(dataGrid, true);
            VirtualizingPanel.SetVirtualizationMode(dataGrid, VirtualizationMode.Recycling);
            VirtualizingPanel.SetScrollUnit(dataGrid, ScrollUnit.Pixel);

            ThemeEngine.RegisterElement(dataGrid);
            return dataGrid;
        }

        public static TextBox CreateTextBox(string placeholder = null)
        {
            // Visual properties (Font, Padding) are set by Set-TextBoxStyle - only behavioral defaults here
            var textBox = new TextBox
            {
                VerticalContentAlignment = VerticalAlignment.Center
            };

            // Bubble mouse wheel to parent so ScrollViewers work
            textBox.PreviewMouseWheel += HandlePreviewMouseWheel;

            if (!TryApplyStyle(textBox, "ModernTextBoxStyle")) {
                // Fallback: bind directly so theme changes propagate
                textBox.SetResourceReference(Control.BackgroundProperty, "ControlBackgroundBrush");
                textBox.SetResourceReference(Control.ForegroundProperty, "ControlForegroundBrush");
                textBox.SetResourceReference(Control.BorderBrushProperty, "BorderBrush");
                textBox.BorderThickness = new Thickness(DefaultBorderThickness);
            }

            if (!string.IsNullOrEmpty(placeholder))
            {
                textBox.Tag = placeholder;
            }

            ThemeEngine.RegisterElement(textBox);
            return textBox;
        }

        public static ListBox CreateListBox()
        {
            // Visual properties (Font) are set by Set-ListBoxStyle - only layout defaults here
            var listBox = new ListBox
            {
                Margin = new Thickness(4, 4, 4, 8)
            };

            // Bubble mouse wheel to parent ScrollViewer
            listBox.PreviewMouseWheel += HandlePreviewMouseWheel;

            if (!TryApplyStyle(listBox, "ModernListBoxStyle")) {
                // Fallback: bind directly so theme changes propagate
                listBox.SetResourceReference(Control.BackgroundProperty, "ControlBackgroundBrush");
                listBox.SetResourceReference(Control.ForegroundProperty, "ControlForegroundBrush");
                listBox.SetResourceReference(Control.BorderBrushProperty, "BorderBrush");
                listBox.BorderThickness = new Thickness(1.0);
                // ListBoxItem style is now implicit in CommonStyles.xaml - no manual assignment needed
            }

            ThemeEngine.RegisterElement(listBox);
            return listBox;
        }

        public static ScrollViewer CreateScrollViewer()
        {
            return new ScrollViewer
            {
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
                Padding = new Thickness(0)
            };
        }

        public static StackPanel CreateStackPanel(Orientation orientation = Orientation.Vertical, double spacing = 4)
        {
            var panel = new StackPanel
            {
                Orientation = orientation,
                Margin = new Thickness(spacing)
            };

            return panel;
        }


    }
}