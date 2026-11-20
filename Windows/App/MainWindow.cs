using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Windows.Forms;
using Microsoft.Win32;
using Newtonsoft.Json.Linq;

namespace ScreenSpan
{
    public sealed partial class MainWindow : Form
    {
        readonly Preview preview = new Preview(); readonly Label status = new Label(), info = new Label();
        readonly History<EditState> history = new History<EditState>(); EditState state = new EditState();
        readonly NotifyIcon tray; readonly Timer refresh = new Timer(), rotation = new Timer();
        readonly Button undo, redo, crop, applyCrop, cancelCrop; bool quitting, restoring;
        string? active; bool reapply = true; DateTime nextRotation = DateTime.MaxValue; int rotationMinutes;
        readonly string preferences = Path.Combine(Project.Support, "Preferences.json");
        public MainWindow(string[] args)
        {
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            Text = "ScreenSpan Wallpaper";
            Size = new Size(1120, 780);
            MinimumSize = new Size(820, 620);
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 10);
            AllowDrop = true;
            var menu = new MenuStrip();
            var file = new ToolStripMenuItem("File");
            file.DropDownItems.Add("New Wallpaper", null, (s, e) => New());
            file.DropDownItems.Add("Choose Images…", null, (s, e) => Choose());
            file.DropDownItems.Add("Open Saved Wallpaper…", null, (s, e) => Library());
            file.DropDownItems.Add("Open Project Folder…", null, (s, e) => Run(() => { using (var dialog = new FolderBrowserDialog { Description = "Choose a .ssw wallpaper project folder", SelectedPath = Project.Library }) if (dialog.ShowDialog(this) == DialogResult.OK) OpenProject(dialog.SelectedPath); }));
            file.DropDownItems.Add("Show Wallpaper Folder", null, (s, e) => ShowFolder());
            file.DropDownItems.Add("Quit", null, (s, e) => Quit());
            menu.Items.Add(file);
            var edit = new ToolStripMenuItem("Edit");
            ((ToolStripMenuItem)edit.DropDownItems.Add("Undo", null, (s, e) => Undo())).ShortcutKeys = Keys.Control | Keys.Z;
            ((ToolStripMenuItem)edit.DropDownItems.Add("Redo", null, (s, e) => Redo())).ShortcutKeys = Keys.Control | Keys.Y;
            menu.Items.Add(edit);
            menu.Items.Add("Settings", null, (s, e) => Settings());
            menu.Items.Add("About", null, (s, e) => MessageBox.Show("ScreenSpan Wallpaper\nWindows 1.0.0\nSpan, crop, extend and organize desktop wallpapers.", "About"));
            MainMenuStrip = menu;
            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(20), ColumnCount = 1, RowCount = 5 };
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 52));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 88));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));
            var top = new FlowLayoutPanel { Dock = DockStyle.Fill };
            top.Controls.Add(Button("Choose Images…", Choose));
            top.Controls.Add(Button("Saved Wallpapers…", Library));
            top.Controls.Add(info);
            info.AutoSize = true;
            info.Padding = new Padding(10, 9, 0, 0);
            layout.Controls.Add(top, 0, 0);
            preview.Dock = DockStyle.Fill;
            preview.BeforeEdit += Push;
            preview.Changed += () => { state.Frame = preview.Frame; UpdateControls(); };
            layout.Controls.Add(preview, 0, 1);
            var frame = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(0, 8, 0, 0) };
            frame.Controls.Add(Button("Fit Entire Photo", () => ChangeFrame("fit")));
            frame.Controls.Add(Button("Fill & Crop", () => ChangeFrame("fill")));
            crop = Button("Crop…", () => { preview.BeginCrop(); UpdateControls(); });
            frame.Controls.Add(crop);
            applyCrop = Button("Apply Crop", ApplyCrop);
            frame.Controls.Add(applyCrop);
            cancelCrop = Button("Cancel Crop", () => { preview.Cropping = false; preview.Invalidate(); UpdateControls(); });
            frame.Controls.Add(cancelCrop);
            frame.Controls.Add(Button("Reset Framing", () => { Push(); state.Frame = new Framing(); RefreshImage(false); }));
            layout.Controls.Add(frame, 0, 2);
            var actions = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(0, 6, 0, 0) };
            undo = Button("Undo", Undo);
            redo = Button("Redo", Redo);
            actions.Controls.Add(undo);
            actions.Controls.Add(redo);
            actions.Controls.Add(Button("Fade Edges to Black", Fade));
            actions.Controls.Add(Button("Save Project", () => Run(() => { var folder = Save(); status.Text = "Saved: " + Path.GetFileName(folder); })));
            actions.Controls.Add(Button("Apply Wallpaper", () => Run(Apply)));
            layout.Controls.Add(actions, 0, 3);
            status.Dock = DockStyle.Fill;
            status.AutoEllipsis = true;
            layout.Controls.Add(status, 0, 4);
            Controls.Add(layout);
            Controls.Add(menu);
            tray = new NotifyIcon { Text = "ScreenSpan Wallpaper", Icon = Icon, Visible = true };
            var trayMenu = new ContextMenuStrip();
            trayMenu.Items.Add("Open ScreenSpan Wallpaper", null, (s, e) => ShowEditor());
            trayMenu.Items.Add("New Wallpaper", null, (s, e) => { ShowEditor(); New(); });
            trayMenu.Items.Add("Saved Wallpapers…", null, (s, e) => { ShowEditor(); Library(); });
            trayMenu.Items.Add("Next Wallpaper", null, (s, e) => Run(Next));
            trayMenu.Items.Add("Reapply Wallpaper", null, (s, e) => Run(Restore));
            trayMenu.Items.Add("Settings…", null, (s, e) => { ShowEditor(); Settings(); });
            trayMenu.Items.Add(new ToolStripSeparator());
            trayMenu.Items.Add("Quit", null, (s, e) => Quit());
            tray.ContextMenuStrip = trayMenu;
            tray.DoubleClick += (s, e) => ShowEditor();
            DragEnter += (s, e) => { if (e.Data.GetDataPresent(DataFormats.FileDrop)) e.Effect = DragDropEffects.Copy; };
            DragDrop += (s, e) => Run(() => Import((string[])e.Data.GetData(DataFormats.FileDrop)));
            preview.AllowDrop = true;
            preview.DragEnter += (s, e) => { if (e.Data.GetDataPresent(DataFormats.FileDrop)) e.Effect = DragDropEffects.Copy; };
            preview.DragDrop += (s, e) => Run(() => Import((string[])e.Data.GetData(DataFormats.FileDrop)));
            InitializeFeatures(actions, menu, trayMenu);
            Shown += (s, e) => { var area = Screen.FromControl(this).WorkingArea; int w = Math.Min(Width, Math.Max(400, area.Width - 20)), h = Math.Min(Height, Math.Max(400, area.Height - 20)); MinimumSize = new Size(Math.Min(MinimumSize.Width, w), Math.Min(MinimumSize.Height, h)); Bounds = new Rectangle(area.X + (area.Width - w) / 2, area.Y + (area.Height - h) / 2, w, h); };
            FormClosing += (s, e) => { if (!quitting && e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); } };
            refresh.Interval = 1800;
            refresh.Tick += (s, e) => { refresh.Stop(); Background(() => { LoadMonitors(); if (reapply) Restore(); }); };
            rotation.Interval = 15000;
            rotation.Tick += (s, e) => { if (rotationMinutes > 0 && !busy && OwnedForms.Length == 0 && !preview.Cropping && DateTime.UtcNow >= nextRotation) { nextRotation = DateTime.UtcNow.AddMinutes(rotationMinutes); Background(Next); } };
            rotation.Start();
            SystemEvents.DisplaySettingsChanged += DisplaysChanged;
            SystemEvents.PowerModeChanged += PowerChanged;
            SystemEvents.SessionSwitch += SessionChanged;
            Run(() => { Directory.CreateDirectory(Project.Support); Directory.CreateDirectory(Project.Library); Background(LoadPreferences); LoadMonitors(); if (args.Length > 0 && Directory.Exists(args[0])) OpenProject(args[0]); else if (args.Length > 0 && File.Exists(args[0])) Import(new[] { args[0] }); else if (active != null && Directory.Exists(active)) OpenProject(active); });
            UpdateControls();
            Shown += (s, e) => { if (reapply) Background(Restore); if (args.Contains("--background")) BeginInvoke((Action)Hide); };
        }
        Button Button(string title, Action action)
        {
            var b = new Button { Text = title, UseMnemonic = false, AutoSize = true, Height = 32, Margin = new Padding(0, 0, 8, 0) };
            b.Click += (s, e) => Run(action);
            return b;
        }
        void Run(Action action)
        {
            if (busy)
                return;
            try
            {
                action();
            }
            catch (Exception e) { status.Text = e.Message; MessageBox.Show(this, e.Message, "ScreenSpan Wallpaper", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }
        void UpdateControls()
        {
            bool image = preview.Image != null;
            undo.Enabled = history.CanUndo;
            redo.Enabled = history.CanRedo;
            crop.Enabled = image && !preview.Cropping;
            applyCrop.Visible = cancelCrop.Visible = preview.Cropping;
            info.Text = image ? state.Name + " · " + preview.Image!.Width + " × " + preview.Image.Height : "Import a picture to begin";
            UpdateFeatureControls();
            preview.Invalidate();
        }
        void RefreshImage(bool reload = true)
        {
            if (reload)
            {
                preview.Image?.Dispose();
                var shown = comparing && original != null ? original : state;
                preview.Image = string.IsNullOrEmpty(shown.ImagePath) ? null : Project.Load(shown.ImagePath);
            }
            preview.Frame = (comparing && original != null ? original : state).Frame;
            preview.Cropping = false;
            UpdateControls();
        }
        void Push()
        {
            if (preview.Image != null)
                history.Push(state.Copy());
        }
        void Undo()
        {
            if (history.CanUndo)
            {
                comparing = false;
                state = history.Undo(state.Copy());
                RefreshImage();
                status.Text = "Undid the last edit.";
            }
        }
        void Redo()
        {
            if (history.CanRedo)
            {
                comparing = false;
                state = history.Redo(state.Copy());
                RefreshImage();
                status.Text = "Redid the last edit.";
            }
        }
        void ChangeFrame(string mode)
        {
            if (preview.Image == null)
                return;
            EnsureEditable();
            Push();
            state.Frame = new Framing { Mode = mode };
            RefreshImage(false);
        }
        void New()
        {
            original = null;
            comparing = false;
            state = new EditState();
            history.Clear();
            RefreshImage();
            ShowEditor();
            Choose();
        }
        void Choose()
        {
            using (var dialog = new OpenFileDialog { Title = "Choose one image, or several to combine", Filter = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff", Multiselect = true })
            if (dialog.ShowDialog(this) == DialogResult.OK)
                Import(dialog.FileNames);
        }
        void Import(string[] paths)
        {
            bool vertical = false;
            if (paths.Length == 0)
                return;
            if (paths.Length == 1 && Directory.Exists(paths[0]))
            {
                OpenProject(paths[0]);
                return;
            }
            if (paths.Length > 1)
            {
                using (var order = new Form { Text = "Combine Images — left to right", Size = new Size(600, 360), StartPosition = FormStartPosition.CenterParent })
                {
                    var list = new ListBox { Dock = DockStyle.Fill };
                    foreach (var p in paths)
                        list.Items.Add(p);
                    var tools = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 48 };
                    tools.Controls.Add(Button("Move Left", () => { int i = list.SelectedIndex; if (i <= 0) return; var p = list.Items[i]; list.Items.RemoveAt(i); list.Items.Insert(i - 1, p); list.SelectedIndex = i - 1; }));
                    tools.Controls.Add(Button("Move Right", () => { int i = list.SelectedIndex; if (i < 0 || i >= list.Items.Count - 1) return; var p = list.Items[i]; list.Items.RemoveAt(i); list.Items.Insert(i + 1, p); list.SelectedIndex = i + 1; }));
                    var stacked = new CheckBox { Text = "Stack vertically", AutoSize = true };
                    tools.Controls.Add(stacked);
                    var done = new Button { Text = "Combine", DialogResult = DialogResult.OK, AutoSize = true };
                    tools.Controls.Add(done);
                    order.Controls.Add(list);
                    order.Controls.Add(tools);
                    if (order.ShowDialog(this) != DialogResult.OK)
                        return;
                    paths = list.Items.Cast<string>().ToArray();
                    vertical = stacked.Checked;
                }
            }
            Bitmap bitmap;
            if (paths.Length == 1)
                bitmap = Project.Load(paths[0]);
            else
            {
                var images = new List<Bitmap>();
                try
                {
                    foreach (var path in paths)
                        images.Add(Project.Load(path));
                    bitmap = ImageTools.Combine(images, vertical);
                }
                finally { foreach (var im in images) im.Dispose(); }
            }
            using (bitmap)
            {
                Push();
                state = new EditState { ImagePath = Project.Cache(bitmap), Name = paths.Length == 1 ? Path.GetFileName(paths[0]) : "Combined Wallpaper.png" };
                original = state.Copy();
                comparing = false;
                RefreshImage();
                status.Text = "Drag to reposition; scroll to zoom. Crop uses your connected monitor ratio.";
            }
        }
        void ApplyCrop()
        {
            if (preview.Image == null || !preview.Cropping)
                return;
            var r = preview.Crop;
            int x = Math.Max(0, (int)Math.Round(r.X)), y = Math.Max(0, (int)Math.Round(r.Y)), w = Math.Min(preview.Image.Width - x, Math.Max(1, (int)Math.Round(r.Width))), h = Math.Min(preview.Image.Height - y, Math.Max(1, (int)Math.Round(r.Height)));
            using (var bitmap = preview.Image.Clone(new Rectangle(x, y, w, h), PixelFormat.Format32bppArgb))
            {
                Push();
                state.ImagePath = Project.Cache(bitmap);
                state.Frame = new Framing();
                RefreshImage();
                status.Text = "Crop applied. Undo restores the complete image.";
            }
        }
        void Fade()
        {
            if (preview.Image == null)
                return;
            EnsureEditable();
            var plan = AIPlan.Extend(preview.Image.Width, preview.Image.Height, preview.BoundsAll, state.Frame);
            if (plan.Width == preview.Image.Width && plan.Height == preview.Image.Height)
                return;
            using (var output = ImageTools.Fade(preview.Image, plan))
            {
                Push();
                state.ImagePath = Project.Cache(output);
                state.Frame = new Framing();
                RefreshImage();
                status.Text = "Edges faded to black. Undo restores the previous image.";
            }
        }
        string Save()
        {
            EnsureEditable();
            if (preview.Image == null)
                throw new InvalidOperationException("Choose an image first.");
            return Project.Save(state, preview.Monitors);
        }
        void Apply()
        {
            var folder = Save();
            var saved = Project.Open(folder);
            var paths = Project.RenderForDesktop(saved, preview.Monitors);
            Desktop.Apply(preview.Monitors, paths);
            active = folder;
            SavePreferences();
            status.Text = "Wallpaper applied and saved in Pictures → ScreenSpan Wallpaper.";
        }
        void OpenProject(string path)
        {
            var loaded = Project.Open(path);
            Project.Remap(loaded, preview.Monitors);
            using (var check = Project.Load(loaded.ImagePath))
            {
            }
            Push();
            state = loaded;
            original = state.Copy();
            comparing = false;
            RefreshImage();
            status.Text = "Opened saved wallpaper settings.";
        }
        void Library()
        {
            using (var library = new LibraryWindow(preview.Monitors, OpenProject, ActivateProject))
                library.ShowDialog(this);
        }
        void ShowFolder()
        {
            Directory.CreateDirectory(Project.Library);
            Process.Start("explorer.exe", Project.Library);
        }
        void ShowEditor()
        {
            Show();
            WindowState = FormWindowState.Normal;
            Activate();
        }
        void LoadMonitors()
        {
            preview.Monitors = Desktop.Monitors();
            if (autoMatch)
            {
                var matched = new LibraryStore().Match(LibraryStore.SetupKey(preview.Monitors));
                if (matched != null)
                    active = matched;
            }
            UpdateControls();
        }
        void Restore()
        {
            if (restoring || active == null || !Directory.Exists(active))
                return;
            restoring = true;
            try
            {
                var s = Project.Open(active);
                Project.Remap(s, preview.Monitors);
                Desktop.Apply(preview.Monitors, Project.RenderForDesktop(s, preview.Monitors));
            }
            finally { restoring = false; }
        }
        void Next()
        {
            var projects = new LibraryStore().RotationCandidates();
            if (projects.Length == 0)
                return;
            int index = Array.IndexOf(projects, active);
            Exception? last = null;
            for (int attempt = 1; attempt <= projects.Length; attempt++)
            {
                try
                {
                    ActivateProject(projects[(index + attempt) % projects.Length]);
                    status.Text = "Changed wallpaper. Your current editor draft is unchanged.";
                    return;
                }
                catch (Exception e) { last = e; }
            }
            if (last != null)
                throw last;
        }
        void Schedule()
        {
            if (IsDisposed || !IsHandleCreated)
                return;
            BeginInvoke((Action)(() => { refresh.Stop(); refresh.Start(); }));
        }
        void DisplaysChanged(object? s, EventArgs e) => Schedule(); void PowerChanged(object? s, PowerModeChangedEventArgs e)
        {
            if (e.Mode == PowerModes.Resume)
                Schedule();
        }
        void SessionChanged(object? s, SessionSwitchEventArgs e)
        {
            if (e.Reason == SessionSwitchReason.SessionUnlock || e.Reason == SessionSwitchReason.RemoteConnect || e.Reason == SessionSwitchReason.ConsoleConnect)
                Schedule();
        }
        void LoadPreferences()
        {
            if (!File.Exists(preferences))
                return;
            var p = SafeJson.Read(preferences);
            active = (string?)p["active"];
            reapply = (bool?)p["reapply"] ?? true;
            autoMatch = (bool?)p["autoMatch"] ?? false;
            cpuAI = (bool?)p["cpuAI"] ?? !AIWorker.HasNvidia();
            rotationMinutes = Math.Max(0, (int?)p["rotationMinutes"] ?? 0);
            nextRotation = rotationMinutes > 0 ? DateTime.UtcNow.AddMinutes(rotationMinutes) : DateTime.MaxValue;
        }
        void SavePreferences()
        {
            SafeJson.Write(preferences, new JObject { ["active"] = active, ["reapply"] = reapply, ["rotationMinutes"] = rotationMinutes, ["autoMatch"] = autoMatch, ["cpuAI"] = cpuAI });
        }
        void Settings()
        {
            ShowSettings();
        }
        void Quit()
        {
            if (busy)
            {
                MessageBox.Show(this, "Cancel AI processing before quitting.", "ScreenSpan Wallpaper");
                return;
            }
            quitting = true;
            Close();
        }
        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                SystemEvents.DisplaySettingsChanged -= DisplaysChanged;
                SystemEvents.PowerModeChanged -= PowerChanged;
                SystemEvents.SessionSwitch -= SessionChanged;
                refresh.Dispose();
                rotation.Dispose();
                tray.Visible = false;
                tray.Dispose();
                preview.Image?.Dispose();
                preview.Composite?.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
