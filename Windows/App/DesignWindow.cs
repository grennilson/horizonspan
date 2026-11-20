using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace ScreenSpan
{
    public sealed class DesignWindow : Form
    {
        public EditState Result; readonly IReadOnlyList<Monitor> monitors;
        public DesignWindow(EditState state, IReadOnlyList<Monitor> monitors)
        {
            Result = state.Copy();
            this.monitors = monitors;
            Text = "Displays & Appearance";
            Size = new Size(740, 600);
            MinimumSize = new Size(620, 430);
            StartPosition = FormStartPosition.CenterParent;
            Font = new Font("Segoe UI", 10);
            Shown += (s, e) => WindowSizing.Fit(this);
            var tabs = new TabControl { Dock = DockStyle.Fill };
            var displays = new TabPage("Displays & Groups");
            var panel = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(12) };
            displays.Controls.Add(panel);
            var span = new Button { Text = "Span All Displays", AutoSize = true };
            span.Click += (s, e) => { Result.Design.monitors.Clear(); BuildDisplays(panel); };
            panel.Controls.Add(span);
            BuildDisplays(panel);
            var appearance = new TabPage("Appearance");
            var form = new TableLayoutPanel { Dock = DockStyle.Top, ColumnCount = 2, AutoSize = true, Padding = new Padding(15) };
            var a = Result.Design.appearance;
            Add(form, "Brightness", -.5m, .5m, (decimal)a.brightness, v => a.brightness = (double)v);
            Add(form, "Saturation", 0, 2, (decimal)a.saturation, v => a.saturation = (double)v);
            Add(form, "Dim Wallpaper", 0, .8m, (decimal)a.dim, v => a.dim = (double)v);
            var background = new Button { Text = "Choose Background Color…", AutoSize = true };
            background.Click += (s, e) => { using (var color = new ColorDialog { Color = Color.FromArgb((int)(a.red * 255), (int)(a.green * 255), (int)(a.blue * 255)) }) if (color.ShowDialog(this) == DialogResult.OK) { a.red = color.Color.R / 255.0; a.green = color.Color.G / 255.0; a.blue = color.Color.B / 255.0; background.BackColor = color.Color; } };
            form.Controls.Add(background);
            appearance.Controls.Add(form);
            tabs.TabPages.Add(displays);
            tabs.TabPages.Add(appearance);
            var actions = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 48, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(8) };
            var done = new Button { Text = "Done", DialogResult = DialogResult.OK, AutoSize = true };
            var cancel = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel, AutoSize = true };
            actions.Controls.Add(done);
            actions.Controls.Add(cancel);
            AcceptButton = done;
            CancelButton = cancel;
            Controls.Add(tabs);
            Controls.Add(actions);
        }
        void BuildDisplays(FlowLayoutPanel panel)
        {
            while (panel.Controls.Count > 1)
            {
                var c = panel.Controls[1];
                panel.Controls.Remove(c);
                c.Dispose();
            }
            foreach (var monitor in monitors)
            {
                var value = Result.Design.For(monitor.Id);
                if (!Result.Design.monitors.Contains(value))
                    Result.Design.monitors.Add(value);
                var box = new GroupBox { Text = monitor.Name, Width = 650, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, MinimumSize = new Size(620, 0) };
                var grid = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 2, Padding = new Padding(10) };
                Add(grid, "Wallpaper group (0 = main panorama)", 0, 32, value.group, v => value.group = (int)v, 0);
                Add(grid, "Horizontal offset (pixels)", -20000, 20000, (decimal)value.offsetX, v => value.offsetX = (double)v, 0);
                Add(grid, "Vertical offset (positive moves up)", -20000, 20000, (decimal)value.offsetY, v => value.offsetY = (double)v, 0);
                Add(grid, "Relative display size", .25m, 4, (decimal)value.sizeScale, v => value.sizeScale = (double)v);
                var choose = new Button { Text = "Choose This Group's Image…", AutoSize = true };
                choose.Click += (s, e) => { if (value.group == 0) { MessageBox.Show(this, "Set a group number from 1 to 32 for a separate image, or use Choose Images for the main panorama."); return; } using (var dialog = new OpenFileDialog { Filter = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff" }) if (dialog.ShowDialog(this) == DialogResult.OK) { try { using (var image = Project.Load(dialog.FileName)) Result.Groups[value.group] = Project.Cache(image); choose.Text = "Group " + value.group + " image selected"; } catch (Exception error) { MessageBox.Show(this, error.Message); } } };
                var useMain = new Button { Text = "Use Main Image", AutoSize = true };
                useMain.Click += (s, e) => { Result.Groups.Remove(value.group); choose.Text = "Choose This Group's Image…"; };
                grid.Controls.Add(choose);
                grid.Controls.Add(useMain);
                box.Controls.Add(grid);
                panel.Controls.Add(box);
            }
            panel.Controls.Add(new Label { Text = "Displays with the same group number share one panorama. Offsets and relative size change the area sampled on each display.", AutoSize = true, MaximumSize = new Size(630, 0) });
        }
        static void Add(TableLayoutPanel panel, string label, decimal min, decimal max, decimal value, Action<decimal> changed, int places = 2)
        {
            int row = panel.RowCount++;
            panel.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left }, 0, row);
            var input = new NumericUpDown { Minimum = min, Maximum = max, Value = Math.Min(max, Math.Max(min, value)), DecimalPlaces = places, Increment = places == 0 ? 1 : .05m, Width = 120 };
            input.ValueChanged += (s, e) => changed(input.Value);
            panel.Controls.Add(input, 1, row);
        }
    }
}
