using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace ScreenSpan
{
    internal static class WallpaperFingerprint
    {
        internal static Design SavedDesign(EditState state)
        {
            var design = state.Design.Copy();
            design.customGroups = design.monitors.Select(m => m.group)
                .Where(g => g > 0 && state.Groups.ContainsKey(g)).Distinct().OrderBy(g => g).ToList();
            return design;
        }

        internal static string Of(EditState state, JArray displays)
        {
            var design = SavedDesign(state);
            var content = new JObject { ["filename"] = state.Name, ["framing"] = state.Frame.Mode,
                ["zoom"] = state.Frame.Zoom, ["pan"] = new JArray(state.Frame.PanX, state.Frame.PanY),
                ["design"] = JObject.FromObject(design), ["displays"] = displays.DeepClone() };
            using (var hash = SHA256.Create())
            {
                Action<byte[]> add = bytes => hash.TransformBlock(bytes, 0, bytes.Length, null, 0);
                add(Encoding.UTF8.GetBytes(content.ToString(Formatting.None)));
                Action<string> image = path =>
                {
                    using (var bitmap = Project.Load(path))
                    {
                        add(Encoding.UTF8.GetBytes("|" + bitmap.Width + "x" + bitmap.Height + "|"));
                        var data = bitmap.LockBits(new Rectangle(0, 0, bitmap.Width, bitmap.Height),
                            ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                        try
                        {
                            var row = new byte[bitmap.Width * 4];
                            for (int y = 0; y < bitmap.Height; y++)
                            {
                                Marshal.Copy(IntPtr.Add(data.Scan0, y * data.Stride), row, 0, row.Length);
                                add(row);
                            }
                        }
                        finally { bitmap.UnlockBits(data); }
                    }
                };
                image(state.ImagePath);
                foreach (int group in design.customGroups)
                {
                    add(Encoding.UTF8.GetBytes("|group=" + group + "|"));
                    image(state.Groups[group]);
                }
                hash.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
                return BitConverter.ToString(hash.Hash!).Replace("-", "");
            }
        }
    }
}
