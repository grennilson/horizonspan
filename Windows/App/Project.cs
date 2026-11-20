using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json.Linq;

namespace ScreenSpan
{
    public sealed class EditState
    {
        public string ImagePath = "", Name = "";
        public Design Design = new Design();
        public Dictionary<int, string> Groups = new Dictionary<int, string>();
        public Framing Frame = new Framing();
        public EditState Copy() => new EditState { ImagePath = ImagePath, Name = Name, Frame = Frame.Copy(), Design = Design.Copy(), Groups = new Dictionary<int, string>(Groups) };
    }
    public static class Project
    {
        internal static string? TestRoot;
        public static string Library => TestRoot != null ? Path.Combine(TestRoot, "Pictures") : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "ScreenSpan Wallpaper");
        public static string Support => TestRoot != null ? Path.Combine(TestRoot, "Support") : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ScreenSpan Wallpaper");
        public static Bitmap Load(string path)
        {
            using (var image = Image.FromFile(path))
            {
                if (image.PropertyIdList.Contains(0x112))
                {
                    int orientation = image.GetPropertyItem(0x112).Value[0];
                    var rotations = new Dictionary<int, RotateFlipType> { { 2, RotateFlipType.RotateNoneFlipX }, { 3, RotateFlipType.Rotate180FlipNone }, { 4, RotateFlipType.Rotate180FlipX }, { 5, RotateFlipType.Rotate90FlipX }, { 6, RotateFlipType.Rotate90FlipNone }, { 7, RotateFlipType.Rotate270FlipX }, { 8, RotateFlipType.Rotate270FlipNone } };
                    if (rotations.TryGetValue(orientation, out var rotation))
                        image.RotateFlip(rotation);
                }
                if ((long)image.Width * image.Height > 64000000)
                    throw new InvalidDataException("The image exceeds the 64 megapixel limit.");
                return new Bitmap(image);
            }
        }
        public static string Cache(Bitmap image)
        {
            Directory.CreateDirectory(Path.Combine(Support, "Edits"));
            string path = Path.Combine(Support, "Edits", Guid.NewGuid() + ".png");
            image.Save(path, ImageFormat.Png);
            return path;
        }
        public static Bitmap Render(Bitmap source, Framing frame, Box bounds, Box screen, int width, int height)
        {
            if (width <= 0 || height <= 0 || (long)width * height > 64000000)
                throw new InvalidOperationException("Wallpaper exceeds the 64 megapixel limit.");
            var result = new Bitmap(width, height);
            var rect = frame.ImageRect(source.Width, source.Height, bounds);
            using (var g = Graphics.FromImage(result))
            {
                g.Clear(Color.Black);
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                double sx = width / screen.Width, sy = height / screen.Height;
                g.DrawImage(source, new RectangleF((float)((rect.X - screen.X) * sx), (float)((rect.Y - screen.Y) * sy), (float)(rect.Width * sx), (float)(rect.Height * sy)));
            }
            return result;
        }
        public static string Save(EditState state, IReadOnlyList<Monitor> monitors, string? library = null)
        {
            state.Design.Validate();
            library = library ?? Library;
            Directory.CreateDirectory(library);
            string id = Guid.NewGuid().ToString().ToUpperInvariant();
            string name = Path.GetFileNameWithoutExtension(state.Name);
            foreach (char c in Path.GetInvalidFileNameChars())
                name = name.Replace(c, '_');
            if (name.Length > 80)
                name = name.Substring(0, 80);
            if (name.Length == 0)
                name = "Wallpaper";
            string output = Path.Combine(library, name + " - " + id + ".ssw"), temp = Path.Combine(library, "." + Guid.NewGuid());
            Directory.CreateDirectory(temp);
            try
            {
                using (var source = Load(state.ImagePath))
                    source.Save(Path.Combine(temp, "Image.png"), ImageFormat.Png);
                var design = state.Design.Copy();
                design.customGroups = design.monitors.Select(m => m.group).Where(g => g > 0 && state.Groups.ContainsKey(g)).Distinct().ToList();
                foreach (int group in design.customGroups)
                using (var image = Load(state.Groups[group]))
                    image.Save(Path.Combine(temp, "Group-" + group + ".png"), ImageFormat.Png);
                Directory.CreateDirectory(Path.Combine(temp, "Displays"));
                using (var rendered = new RenderedImages(state, monitors))
                {
                    for (int i = 0; i < monitors.Count; i++)
                    using (var image = rendered.Screen(i))
                        image.Save(Path.Combine(temp, "Displays", "Display-" + (i + 1) + ".png"), ImageFormat.Png);
                    using (var combined = rendered.Combined())
                        combined.Save(Path.Combine(temp, "Wallpaper.png"), ImageFormat.Png);
                    using (var thumb = rendered.Combined(240000))
                        thumb.Save(Path.Combine(temp, "Thumbnail.png"), ImageFormat.Png);
                }
                var displays = new JArray(monitors.Select(m => new JObject { ["name"] = m.Name, ["frame"] = new JArray(new JArray(m.Bounds.X, -m.Bounds.Bottom), new JArray(m.Bounds.Width, m.Bounds.Height)), ["pixelWidth"] = (int)m.Bounds.Width, ["pixelHeight"] = (int)m.Bounds.Height }));
                var settings = new JObject { ["formatVersion"] = 2, ["wallpaper"] = new JObject { ["id"] = id, ["filename"] = state.Name, ["framing"] = state.Frame.Mode, ["zoom"] = state.Frame.Zoom, ["pan"] = new JArray(state.Frame.PanX, state.Frame.PanY), ["design"] = JObject.FromObject(design) }, ["displays"] = displays };
                File.WriteAllText(Path.Combine(temp, "Settings.json"), settings.ToString());
                Directory.Move(temp, output);
                return output;
            }
            finally { if (Directory.Exists(temp)) Directory.Delete(temp, true); }
        }
        public static EditState Open(string folder)
        {
            var settings = SafeJson.Read(Path.Combine(folder, "Settings.json"));
            int version = (int?)settings["formatVersion"] ?? 0;
            if (version < 1 || version > 2)
                throw new InvalidDataException("This wallpaper project version is not supported.");
            var w = settings["wallpaper"] ?? throw new InvalidDataException("Missing wallpaper settings.");
            var design = w["design"]?.Type == JTokenType.Object ? w["design"]!.ToObject<Design>()! : new Design();
            design.Validate();
            var groups = new Dictionary<int, string>();
            foreach (int group in design.customGroups)
            {
                string asset = Path.Combine(folder, "Group-" + group + ".png");
                if (!File.Exists(asset))
                    throw new InvalidDataException("Missing group image " + group + ".");
                groups[group] = asset;
            }
            var pan = w["pan"] as JArray;
            if (pan != null && pan.Count != 2)
                throw new InvalidDataException("Invalid image position.");
            double zoom = (double?)w["zoom"] ?? 1, px = (double?)pan?[0] ?? 0, py = (double?)pan?[1] ?? 0;
            string mode = (string?)w["framing"] ?? "fit";
            if (double.IsNaN(zoom) || double.IsInfinity(zoom) || zoom < 1 || zoom > 3 || double.IsNaN(px) || double.IsInfinity(px) || double.IsNaN(py) || double.IsInfinity(py) || (mode != "fit" && mode != "fill"))
                throw new InvalidDataException("Invalid framing settings.");
            string path = Path.Combine(folder, "Image.png");
            if (!File.Exists(path))
                throw new FileNotFoundException("The project image is missing.");
            return new EditState { ImagePath = path, Name = (string?)w["filename"] ?? "Wallpaper.png", Frame = new Framing { Mode = mode, Zoom = zoom, PanX = px, PanY = py }, Design = design, Groups = groups };
        }
        public static List<string> RenderForDesktop(EditState state, IReadOnlyList<Monitor> monitors)
        {
            string fingerprint = Newtonsoft.Json.JsonConvert.SerializeObject(new
            {
                state.Frame,
                state.Design,
                state.ImagePath,
                sourceTime = File.GetLastWriteTimeUtc(state.ImagePath).Ticks,
                assets = state.Groups.OrderBy(g => g.Key).Select(g => new { g.Key, g.Value, time = File.GetLastWriteTimeUtc(g.Value).Ticks }),
                screens = monitors.Select(m => new { m.Id, m.Bounds })
            });
            string key;
            using (var hash = SHA256.Create())
                key = BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(fingerprint))).Replace("-", "");
            string folder = Path.Combine(Support, "Rendered", key);
            Directory.CreateDirectory(folder);
            var paths = monitors.Select((m, i) => Path.Combine(folder, "Display-" + (i + 1) + ".png")).ToList();
            if (paths.All(File.Exists))
                return paths;
            using (var images = new RenderedImages(state, monitors))
            for (int i = 0; i < monitors.Count; i++)
            if (!File.Exists(paths[i]))
            {
                string tmp = paths[i] + "." + Guid.NewGuid() + ".tmp";
                try
                {
                    using (var image = images.Screen(i))
                        image.Save(tmp, ImageFormat.Png);
                    File.Move(tmp, paths[i]);
                }
                finally { if (File.Exists(tmp)) File.Delete(tmp); }
            }
            return paths;
        }
        public static void Remap(EditState state, IReadOnlyList<Monitor> monitors)
        {
            if (state.Design.monitors.Count > 0 && !state.Design.monitors.Any(p => monitors.Any(m => m.Id == p.key)))
            for (int i = 0; i < Math.Min(state.Design.monitors.Count, monitors.Count); i++)
                state.Design.monitors[i].key = monitors[i].Id;
        }
    }
}
