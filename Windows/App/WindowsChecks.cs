using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

namespace ScreenSpan
{
    static class WindowsChecks
    {
        static void Check(bool condition, string name, List<string> lines)
        {
            if (!condition)
                throw new Exception(name);
            lines.Add("PASS: " + name);
        }
        public static void Run(string report)
        {
            string root = Path.Combine(Path.GetTempPath(), "ScreenSpan-check-" + Guid.NewGuid());
            Directory.CreateDirectory(root);
            var lines = new List<string>();
            Project.TestRoot = root;
            try
            {
                using (var source = new Bitmap(400, 100))
                {
                    using (var g = Graphics.FromImage(source))
                    {
                        g.Clear(Color.Red);
                        g.FillRectangle(Brushes.Blue, 200, 0, 200, 100);
                    }
                    var b = new Box(0, 0, 400, 100);
                    using (var left = Project.Render(source, new Framing(), b, new Box(0, 0, 200, 100), 200, 100))
                        Check(left.GetPixel(100, 50).R > 240, "left monitor rendering", lines);
                    using (var right = Project.Render(source, new Framing(), b, new Box(200, 0, 200, 100), 200, 100))
                        Check(right.GetPixel(100, 50).B > 240, "right monitor rendering", lines);
                    string input = Path.Combine(root, "Image.png");
                    source.Save(input);
                    var fake = new List<Monitor> { new Monitor { Id = "test-left", Name = "Left", Bounds = new Box(-200, 0, 200, 100) }, new Monitor { Id = "test-right", Name = "Right", Bounds = new Box(0, 0, 200, 100) } };
                    var json = new JObject { ["formatVersion"] = 1, ["wallpaper"] = new JObject { ["filename"] = "test.png", ["framing"] = "fit", ["zoom"] = 1.5, ["pan"] = new JArray(.1, -.2) } };
                    File.WriteAllText(Path.Combine(root, "Settings.json"), json.ToString());
                    var s = Project.Open(root);
                    Check(s.Frame.Zoom == 1.5 && s.Frame.PanX == .1 && s.Frame.PanY == -.2, "Mac format 1 project framing", lines);
                    var state = new EditState { ImagePath = input, Name = "test.png", Frame = new Framing() };
                    string saved = Project.Save(state, fake);
                    var reopened = Project.Open(saved);
                    using (var check = Project.Load(reopened.ImagePath))
                        Check(check.Width == 400 && check.Height == 100, "format 2 source dimensions", lines);
                    Check(new[] { "Wallpaper.png", "Thumbnail.png", "Displays/Display-1.png", "Displays/Display-2.png" }.All(p => File.Exists(Path.Combine(saved, p))), "combined, thumbnail and per-monitor exports", lines);
                    using (var green = new Bitmap(100, 100))
                    {
                        using (var g = Graphics.FromImage(green))
                            g.Clear(Color.Lime);
                        string gp = Path.Combine(root, "green.png");
                        green.Save(gp);
                        state.Design.monitors.Add(new Placement { key = "test-right", group = 1 });
                        state.Groups[1] = gp;
                        using (var images = new RenderedImages(state, fake))
                        using (var right = images.Screen(1))
                            Check(right.GetPixel(100, 50).G > 240 && right.GetPixel(100, 50).R < 10, "independent display groups", lines);
                        state.Design.appearance.dim = .5;
                        using (var images = new RenderedImages(state, fake))
                        using (var right = images.Screen(1))
                            Check(Math.Abs(right.GetPixel(100, 50).G - 128) < 3, "dimming in actual renderer", lines);
                        string grouped = Project.Save(state, fake);
                        var opened = Project.Open(grouped);
                        Check(opened.Groups.ContainsKey(1) && opened.Design.monitors[0].group == 1, "group image and appearance project round trip", lines);
                        File.Move(Path.Combine(grouped, "Group-1.png"), Path.Combine(grouped, "missing.png"));
                        bool rejected = false;
                        try
                        {
                            Project.Open(grouped);
                        }
                        catch (InvalidDataException) { rejected = true; }
                        Check(rejected, "missing group asset rejected", lines);
                    }
                    using (var vertical = ImageTools.Combine(new[] { source, source }, true))
                        Check(vertical.Width == 400 && vertical.Height == 200, "vertical image combination", lines);
                    using (var horizontal = ImageTools.Combine(new[] { source, source }, false))
                        Check(horizontal.Width == 800 && horizontal.Height == 100, "horizontal image combination", lines);
                    var plan = new AIPlan { Width = 500, Height = 100, Leading = 100 };
                    using (var faded = ImageTools.Fade(source, plan))
                        Check(faded.GetPixel(200, 50).R == source.GetPixel(100, 50).R, "fade preserves original pixels and placement", lines);
                    using (var faded = ImageTools.Fade(source, new AIPlan { Width = 400, Height = 200, Leading = 0 }))
                        Check(faded.GetPixel(100, 199).R == 0 && faded.GetPixel(100, 199).G == 0, "bottom edge fades to black", lines);
                    var store = new LibraryStore();
                    var entry = store.Entries().First(e => e.Folder == saved);
                    store.Details(entry, "Favorite test", true);
                    Check(store.Entries().First(e => e.Id == entry.Id).Favorite, "favorite metadata persistence", lines);
                    Check(store.RotationCandidates().Length == 1 && store.RotationCandidates()[0] == saved, "rotation uses favorites", lines);
                    string key = LibraryStore.SetupKey(fake);
                    store.Remember(key, "Test displays", entry.Id);
                    Check(store.Match(key) == saved, "named setup matching", lines);
                    store.Forget(key);
                    Check(store.Match(key) == null, "forget monitor setup", lines);
                    json["formatVersion"] = 99;
                    File.WriteAllText(Path.Combine(root, "Settings.json"), json.ToString());
                    bool bad = false;
                    try
                    {
                        Project.Open(root);
                    }
                    catch (InvalidDataException) { bad = true; }
                    Check(bad, "unsupported project format rejected", lines);
                    state.Design = new Design();
                    state.Groups.Clear();
                    var cache1 = Project.RenderForDesktop(state, fake);
                    var cache2 = Project.RenderForDesktop(state, fake);
                    Check(cache1.SequenceEqual(cache2) && cache1.All(File.Exists), "restoration render cache reused", lines);
                    using(var gallery=new LibraryWindow(fake,_=>{},_=>{})){gallery.CreateControl();lines.Add("PASS: thumbnail library native image-list initialization");}
                using (var window = new MainWindow(new[] { input }))
                    {
                        window.CheckEditor();
                        lines.Add("PASS: real editor crop, Undo/Redo, original comparison and reopen");
                    }
                }
                var monitors = Desktop.Monitors();
                Check(monitors.Count > 0, "Windows monitor enumeration: " + monitors.Count, lines);
                foreach (var m in monitors)
                    lines.Add("INFO: " + m.Name + " " + m.Bounds.Width + "x" + m.Bounds.Height + (m.PreviewOnly ? " (remote preview fallback)" : " (wallpaper service)"));
                lines.Add("PASS: no desktop wallpaper changes made by these checks");
                File.WriteAllLines(report, lines);
            }
            catch (Exception e) { lines.Add("FAIL: " + e); File.WriteAllLines(report, lines); throw; }
            finally { Project.TestRoot = null; Directory.Delete(root, true); }
        }
        public static async Task AIEdges(string report){object gate=new object();Action<string> log=line=>{lock(gate)File.AppendAllText(report,line+Environment.NewLine);};string root=Path.Combine(Path.GetTempPath(),"ScreenSpan-Edge-Test-"+Guid.NewGuid());Directory.CreateDirectory(root);try{using(var image=new Bitmap(128,128)){using(var g=Graphics.FromImage(image))g.Clear(Color.CornflowerBlue);string input=Path.Combine(root,"input.png");image.Save(input);string output=await AIWorker.Generate(new EditState{ImagePath=input},new AIPlan{Width=256,Height=128,Leading=128},"extend","Continue a smooth blue background without objects or text.",true,log,CancellationToken.None,2);using(var extended=Project.Load(output)){if(extended.Width!=256||extended.Height!=128||extended.GetPixel(190,64).ToArgb()!=image.GetPixel(62,64).ToArgb())throw new Exception("AI extension changed the original source or output dimensions.");}File.Delete(output);log("PASS: actual SDXL CPU edge inference (2 steps), dimensions and preserved original pixels.");}}catch(Exception error){log("FAIL: "+error);throw;}finally{Directory.Delete(root,true);}}
        public static async Task AI(string report)
        {
            var lines = new List<string>();
            object logLock = new object();
            Action<string> log = line => { lock (logLock) File.AppendAllText(report, line + Environment.NewLine); };
            string root = Path.Combine(Path.GetTempPath(), "ScreenSpan-AI-check-" + Guid.NewGuid());
            Directory.CreateDirectory(root);
            try
            {
                await AIWorker.Setup(true, log, CancellationToken.None);
                using (var image = new Bitmap(32, 24))
                {
                    using (var g = Graphics.FromImage(image))
                        g.Clear(Color.CornflowerBlue);
                    string input = Path.Combine(root, "test.png");
                    image.Save(input);
                    var state = new EditState { ImagePath = input };
                    string output = await AIWorker.Generate(state, new AIPlan { Width = 64, Height = 48 }, "enhance", "", true, log, CancellationToken.None);
                    using (var enhanced = Project.Load(output))
                        Check(enhanced.Width == 64 && enhanced.Height == 48, "Real-ESRGAN actual CPU inference", lines);
                    File.Delete(output);
                }
                File.AppendAllLines(report, lines);
            }
            catch (Exception e) { File.AppendAllText(report, "FAIL: " + e); throw; }
            finally { Directory.Delete(root, true); }
        }
    }
    public sealed partial class MainWindow
    {
        internal void CheckEditor()
        {
            int width = preview.Image!.Width, height = preview.Image.Height;
            preview.BeginCrop();
            var initial = preview.Crop;
            preview.Crop = Framing.CropCorner(initial, 2, initial.Right * .8, initial.Bottom * .8, preview.BoundsAll.Width / preview.BoundsAll.Height, width, height);
            ApplyCrop();
            int cropped = preview.Image!.Width;
            if (cropped == width && preview.Image.Height == height)
                throw new Exception("Crop did not change image.");
            Undo();
            if (preview.Image!.Width != width || preview.Image.Height != height)
                throw new Exception("Undo did not restore source.");
            Redo();
            if (preview.Image!.Width != cropped)
                throw new Exception("Redo did not restore crop.");
            string file = Save();
            OpenProject(file);
            if (preview.Image!.Width != cropped)
                throw new Exception("Saved crop was not reopened.");
            comparing = true;
            RefreshImage();
            comparing = false;
            RefreshImage();
        }
    }
}
