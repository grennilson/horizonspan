using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace ScreenSpan
{
    public sealed class LibraryWindow : Form
    {
        readonly LibraryStore store = new LibraryStore(); readonly ListView list = new ListView(); readonly ImageList thumbnails = new ImageList(); readonly TextBox title = new TextBox(), setup = new TextBox(); readonly CheckBox favorite = new CheckBox(), filter = new CheckBox(); readonly Label message = new Label(); readonly Action<string> open, apply; readonly string key;
        public LibraryWindow(System.Collections.Generic.IReadOnlyList<Monitor> monitors, Action<string> open, Action<string> apply)
        {
            this.open = open;
            this.apply = apply;
            key = LibraryStore.SetupKey(monitors);
            Text = "Saved Wallpapers";
            Size = new Size(900, 600);
            MinimumSize = new Size(650, 450);
            StartPosition = FormStartPosition.CenterParent;
            Font = new Font("Segoe UI", 10);
            Shown += (s, e) => WindowSizing.Fit(this);
            thumbnails.ImageSize = new Size(180, 110);
            thumbnails.ColorDepth = ColorDepth.Depth32Bit;
            list.Dock = DockStyle.Fill;
            list.View = View.LargeIcon;
            list.LargeImageList = thumbnails;
            list.MultiSelect = false;
            list.HideSelection = false;
            list.SelectedIndexChanged += (s, e) => SelectEntry();
            list.DoubleClick += (s, e) => Act(() => { if (Selected is LibraryEntry entry) { open(entry.Folder); Close(); } });
            var panel = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 175, Padding = new Padding(12), AutoScroll = true };
            title.Width = 320;
            favorite.Text = "Favorite";
            favorite.AutoSize = true;
            filter.Text = "Favorites only";
            filter.AutoSize = true;
            filter.CheckedChanged += (s, e) => RefreshEntries();
            panel.Controls.Add(title);
            panel.Controls.Add(favorite);
            panel.Controls.Add(Make("Save Name & Favorite", () => { if (Selected is LibraryEntry entry) store.Details(entry, title.Text, favorite.Checked); RefreshEntries(); }));
            panel.Controls.Add(filter);
            panel.SetFlowBreak(filter, true);
            panel.Controls.Add(Make("Open in Editor", () => { if (Selected is LibraryEntry entry) { open(entry.Folder); Close(); } }));
            panel.Controls.Add(Make("Apply Wallpaper", () => { if (Selected is LibraryEntry entry) { apply(entry.Folder); message.Text = "Wallpaper applied."; } }));
            panel.Controls.Add(Make("Show Files", () => { if (Selected is LibraryEntry entry) System.Diagnostics.Process.Start("explorer.exe", entry.Folder); }));
            panel.Controls.Add(Make("Refresh", RefreshEntries));
            panel.SetFlowBreak(panel.Controls[panel.Controls.Count - 1], true);
            setup.Width = 260;
            setup.Text = "My monitor setup";
            panel.Controls.Add(setup);
            panel.Controls.Add(Make("Use for This Monitor Setup", () => { if (Selected is LibraryEntry entry) { store.Remember(key, setup.Text, entry.Id); message.Text = "Saved setup. Turn on automatic matching in Settings to use it."; } }));
            panel.Controls.Add(Make("Forget Setup", () => { store.Forget(key); message.Text = "Setup forgotten."; }));
            message.AutoSize = true;
            message.MaximumSize = new Size(800, 50);
            panel.SetFlowBreak(panel.Controls[panel.Controls.Count - 1], true);
            panel.Controls.Add(message);
            Controls.Add(list);
            Controls.Add(panel);
            RefreshEntries();
        }
        LibraryEntry? Selected => list.SelectedItems.Count > 0 ? list.SelectedItems[0].Tag as LibraryEntry : null;
        Button Make(string text, Action action)
        {
            var button = new Button { Text = text, AutoSize = true, Margin = new Padding(3, 4, 8, 4) };
            button.Click += (s, e) => Act(action);
            return button;
        }
        void Act(Action action)
        {
            try
            {
                action();
            }
            catch (Exception e) { MessageBox.Show(this, e.Message, "Wallpaper Library", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }
        void SelectEntry()
        {
            if (Selected is LibraryEntry entry)
            {
                title.Text = entry.Title;
                favorite.Checked = entry.Favorite;
            }
        }
        void RefreshEntries()
        {
            Act(() => { list.BeginUpdate(); try { list.Items.Clear(); thumbnails.Images.Clear(); foreach (var entry in store.Entries().Where(e => !filter.Checked || e.Favorite)) { string path = Path.Combine(entry.Folder, "Thumbnail.png"); if (!File.Exists(path)) path = Path.Combine(entry.Folder, "Wallpaper.png"); try { using (var image = Project.Load(path)) { var thumb = new Bitmap(180, 110); using (var g = Graphics.FromImage(thumb)) { g.Clear(Color.FromArgb(30, 34, 42)); double s = Math.Min(180.0 / image.Width, 110.0 / image.Height); g.DrawImage(image, new RectangleF((float)((180 - image.Width * s) / 2), (float)((110 - image.Height * s) / 2), (float)(image.Width * s), (float)(image.Height * s))); } thumbnails.Images.Add(thumb); thumb.Dispose(); } } catch { using (var blank = new Bitmap(180, 110)) thumbnails.Images.Add(blank); } var item = new ListViewItem(entry.ToString(), thumbnails.Images.Count - 1) { Tag = entry, ToolTipText = entry.Title }; list.Items.Add(item); } if (list.Items.Count > 0) list.Items[0].Selected = true; } finally { list.EndUpdate(); } });
        }
        protected override void Dispose(bool disposing)
        {
            if (disposing)
                thumbnails.Dispose();
            base.Dispose(disposing);
        }
    }
}
