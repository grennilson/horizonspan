using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;
using Newtonsoft.Json.Linq;

namespace ScreenSpan
{
    public sealed partial class MainWindow
    {
        EditState? original; bool comparing, busy, featuresReady, autoMatch, cpuAI = !AIWorker.HasNvidia(); CheckBox? compare; ToolStripMenuItem? tools;
        public void HandleLaunch(string[] args)
        {
            if (args.Length == 1 && args[0] == "--quit")
            {
                Quit();
                return;
            }
            if (args.Length == 1 && args[0] == "--background")
                return;
            ShowEditor();
            if (args.Length > 0 && !args[0].StartsWith("--", StringComparison.Ordinal))
                Run(() => { if (Directory.Exists(args[0])) OpenProject(args[0]); else if (File.Exists(args[0])) Import(new[] { args[0] }); });
        }
        void InitializeFeatures(FlowLayoutPanel actions, MenuStrip menu, ContextMenuStrip trayMenu)
        {
            tools = new ToolStripMenuItem("Image Tools");
            tools.DropDownItems.Add("Extend with AI…", null, (s, e) => GenerateAI("extend"));
            tools.DropDownItems.Add("Enhance Detail…", null, (s, e) => GenerateAI("enhance"));
            tools.DropDownItems.Add("Fade Edges to Black", null, (s, e) => Run(Fade));
            tools.DropDownItems.Add("Displays & Appearance…", null, (s, e) => Run(DesignOptions));
            menu.Items.Insert(2, tools);
            var wallpaper = new ToolStripMenuItem("Wallpaper");
            wallpaper.DropDownItems.Add("Displays & Appearance…", null, (s, e) => Run(DesignOptions));
            wallpaper.DropDownItems.Add("Next Wallpaper", null, (s, e) => Run(Next));
            wallpaper.DropDownItems.Add("Reapply Saved Wallpaper", null, (s, e) => Run(Restore));
            wallpaper.DropDownItems.Add("Check for Updates…", null, (s, e) => CheckUpdates());
            menu.Items.Insert(3, wallpaper);
            compare = new CheckBox { Text = "Show Original", AutoSize = true, Margin = new Padding(5, 8, 8, 0) };
            compare.CheckedChanged += (s, e) => { if (comparing == compare.Checked) return; comparing = compare.Checked; RefreshImage(); };
            actions.Controls.Add(compare);
            actions.Controls.Add(Button("Revert to Original", () => { if (original == null) return; EnsureEditable(); Push(); state = original.Copy(); RefreshImage(); status.Text = "Restored the original image and settings."; }));
            menu.Items.Add("Third-Party Notices",null,(s,e)=>ShowNotices());
            featuresReady = true;
        }
        void ShowNotices(){using(var window=new Form{Text="Third-Party Notices",Size=new Size(720,520),StartPosition=FormStartPosition.CenterParent})using(var resource=System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("ScreenSpan.Notices")){if(resource==null)return;using(var reader=new StreamReader(resource)){window.Controls.Add(new TextBox{Dock=DockStyle.Fill,ReadOnly=true,Multiline=true,ScrollBars=ScrollBars.Vertical,Text=reader.ReadToEnd()});window.Shown+=(s,e)=>WindowSizing.Fit(window);window.ShowDialog(this);}}}
        void UpdateFeatureControls()
        {
            if (!featuresReady)
                return;
            if (compare != null)
            {
                compare.Enabled = original != null && !busy && !preview.Cropping;
                compare.Checked = comparing;
            }
            if (tools != null)
                tools.Enabled = preview.Image != null && !busy && !comparing && !preview.Cropping;
            preview.Comparing = comparing;
            var displayed = comparing && original != null ? original : state;
            preview.Composite?.Dispose();
            preview.Composite = null;
            if (preview.Image != null && !displayed.Design.Standard && preview.Monitors.Count > 0)
            using (var rendered = new RenderedImages(displayed, preview.Monitors))
                preview.Composite = rendered.Combined(800000);
        }
        void EnsureEditable()
        {
            if (comparing)
                throw new InvalidOperationException("Turn off Show Original before editing.");
            if (preview.Cropping)
                throw new InvalidOperationException("Apply or cancel the crop first.");
        }
        void DesignOptions()
        {
            if (preview.Image == null)
                return;
            EnsureEditable();
            using (var dialog = new DesignWindow(state, preview.Monitors))
            if (dialog.ShowDialog(this) == DialogResult.OK)
            {
                Push();
                state = dialog.Result;
                RefreshImage(false);
                status.Text = "Updated display groups and appearance.";
            }
        }
        void ActivateProject(string path)
        {
            var saved = Project.Open(path);
            Project.Remap(saved, preview.Monitors);
            Desktop.Apply(preview.Monitors, Project.RenderForDesktop(saved, preview.Monitors));
            active = path;
            SavePreferences();
        }
        void Background(Action action)
        {
            try
            {
                action();
            }
            catch (Exception e) { status.Text = "Wallpaper restoration: " + e.Message; try { string log = Path.Combine(Project.Support, "Background.log"); if (File.Exists(log) && new FileInfo(log).Length > 200000) File.WriteAllText(log, ""); File.AppendAllText(log, DateTime.UtcNow.ToString("O") + " " + e.Message + Environment.NewLine); } catch { } }
        }
        async void GenerateAI(string action)
        {
            if (busy || preview.Image == null)
                return;
            try
            {
                EnsureEditable();
                var snapshot = state.Copy();
                var plan = action == "extend" ? AIPlan.Extend(preview.Image.Width, preview.Image.Height, preview.BoundsAll, state.Frame) : AIPlan.Enhance(preview.Image.Width, preview.Image.Height, preview.BoundsAll, state.Frame);
                if (plan.Width == preview.Image.Width && plan.Height == preview.Image.Height)
                {
                    MessageBox.Show(this, "This image already matches your connected monitor ratio.");
                    return;
                }
                string prompt = "";
                using (var options = new Form { Text = action == "extend" ? "Extend with AI" : "Enhance Detail", Size = new Size(600, 310), StartPosition = FormStartPosition.CenterParent })
                {
                    var panel = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, Padding = new Padding(18), WrapContents = false };
                    panel.Controls.Add(new Label { Text = action == "extend" ? "Describe the scenery to continue at the edges:" : "Enhance detail to " + plan.Width + " × " + plan.Height + " pixels.", AutoSize = true, MaximumSize = new Size(540, 0) });
                    var text = new TextBox { Width = 530, Multiline = true, Height = 55, MaxLength = 400 };
                    if (action == "extend")
                        panel.Controls.Add(text);
                    panel.Controls.Add(new Label { Text = "Runs on this PC. First use downloads Python and AI libraries; models download separately (detail: 67 MB, edge generation: about 7 GB). Generative AI can invent details; review the result before applying it.", AutoSize = true, MaximumSize = new Size(530, 0) });
                    var start = new Button { Text = "Generate", DialogResult = DialogResult.OK, AutoSize = true };
                    panel.Controls.Add(start);
                    options.Controls.Add(panel);
                    if (options.ShowDialog(this) != DialogResult.OK)
                        return;
                    prompt = text.Text;
                }
                busy = true;
                UpdateControls();
                using (var cancel = new CancellationTokenSource())
                using (var progress = new Form { Text = action == "extend" ? "Extending edges with AI" : "Enhancing detail", Size = new Size(650, 240), StartPosition = FormStartPosition.CenterParent, ControlBox = false })
                {
                    var log = new TextBox { Dock = DockStyle.Fill, ReadOnly = true, Multiline = true, ScrollBars = ScrollBars.Vertical };
                    var stop = new Button { Text = "Cancel", Dock = DockStyle.Bottom, Height = 38 };
                    stop.Click += (s, e) => { stop.Enabled = false; cancel.Cancel(); };
                    progress.Controls.Add(log);
                    progress.Controls.Add(stop);
                    string? result = null;
                    Exception? error = null;
                    progress.Shown += async (s, e) => { try { result = await AIWorker.Generate(snapshot, plan, action, prompt, cpuAI, line => { if (!progress.IsDisposed) progress.BeginInvoke((Action)(() => { if (log.TextLength > 12000) log.Clear(); log.AppendText(line + Environment.NewLine); })); }, cancel.Token); } catch (Exception ex) { error = ex; } finally { progress.Close(); } };
                    progress.ShowDialog(this);
                    if (error is OperationCanceledException)
                    {
                        status.Text = "AI processing canceled. Your image is unchanged.";
                        return;
                    }
                    if (error != null)
                        throw error;
                    if (result != null)
                    {
                        history.Push(snapshot);
                        state.ImagePath = result;
                        state.Frame = new Framing();
                        RefreshImage();
                        status.Text = "AI result ready. Compare with Show Original, or Undo to restore the prior image.";
                    }
                }
            }
            catch (Exception e) { MessageBox.Show(this, e.Message, "AI Image Tools", MessageBoxButtons.OK, MessageBoxIcon.Error); }
            finally { busy = false; UpdateControls(); }
        }
        void ShowSettings()
        {
            using (var form = new Form { Text = "ScreenSpan Wallpaper Settings", Size = new Size(620, 460), StartPosition = FormStartPosition.CenterParent })
            {
                var panel = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, Padding = new Padding(20), AutoScroll = true, WrapContents = false };
                var keep = new CheckBox { Text = "Restore wallpaper after display changes and wake", AutoSize = true, Checked = reapply };
                var match = new CheckBox { Text = "Automatically match saved monitor setups", AutoSize = true, Checked = autoMatch };
                var cpu = new CheckBox { Text = "Use CPU for AI (turn off for NVIDIA CUDA)", AutoSize = true, Checked = cpuAI };
                panel.Controls.Add(keep);
                panel.Controls.Add(match);
                panel.Controls.Add(new Label { Text = "Rotate favorites (or all saved wallpapers if none are favorites):", AutoSize = true });
                var interval = new NumericUpDown { Minimum = 0, Maximum = 1440, Value = Math.Min(rotationMinutes, 1440) };
                panel.Controls.Add(interval);
                panel.Controls.Add(new Label { Text = "Minutes; 0 turns rotation off.", AutoSize = true });
                panel.Controls.Add(cpu);
                var start = new CheckBox { Text = "Start ScreenSpan when I sign in", AutoSize = true };
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))
                    start.Checked = key?.GetValue("ScreenSpanWallpaper") != null;
                panel.Controls.Add(start);
                var update = new Button { Text = "Check for Updates…", AutoSize = true };
                update.Click += (s, e) => CheckUpdates();
                panel.Controls.Add(update);
                var save = new Button { Text = "Save", DialogResult = DialogResult.OK, AutoSize = true };
                panel.Controls.Add(save);
                form.Controls.Add(panel);
                if (form.ShowDialog(this) == DialogResult.OK)
                {
                    reapply = keep.Checked;
                    autoMatch = match.Checked;
                    cpuAI = cpu.Checked;
                    rotationMinutes = (int)interval.Value;
                    nextRotation = rotationMinutes > 0 ? DateTime.UtcNow.AddMinutes(rotationMinutes) : DateTime.MaxValue;
                    using (var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))
                    {
                        if (start.Checked)
                            key.SetValue("ScreenSpanWallpaper", "\"" + Application.ExecutablePath + "\" --background");
                        else
                            key.DeleteValue("ScreenSpanWallpaper", false);
                    }
                    SavePreferences();
                }
            }
        }
        async void CheckUpdates()
        {
            try
            {
                using (var http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) })
                {
                    http.DefaultRequestHeaders.UserAgent.ParseAdd("ScreenSpan-Wallpaper/1.0.0");
                    string json = await http.GetStringAsync("https://api.github.com/repos/grennilson/horizonspan/releases?per_page=100");
                    var release = JArray.Parse(json).Where(r => (bool?)r["draft"] != true && (bool?)r["prerelease"] != true && ReleaseVersions.Parse((string?)r["tag_name"] ?? "") != null).OrderByDescending(r => ReleaseVersions.Parse((string)r["tag_name"]!)).FirstOrDefault();
                    if (release != null && ReleaseVersions.IsNewer((string)release["tag_name"]!, "1.0.0"))
                    {
                        string url = (string?)release["html_url"] ?? "";
                        var uri = new Uri(url);
                        if (uri.Scheme != "https" || uri.Host != "github.com" || !uri.AbsolutePath.StartsWith("/grennilson/horizonspan/releases/", StringComparison.Ordinal))
                            throw new InvalidDataException("Unexpected update URL.");
                        if (MessageBox.Show(this, "A newer Windows version is available. Open its download page?", "ScreenSpan Updates", MessageBoxButtons.YesNo) == DialogResult.Yes)
                            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true });
                    }
                    else
                        MessageBox.Show(this, "You are running the latest Windows version (1.0.0).", "ScreenSpan Updates");
                }
            }
            catch (Exception e) { MessageBox.Show(this, "Could not check for updates: " + e.Message, "ScreenSpan Updates"); }
        }
    }
}
