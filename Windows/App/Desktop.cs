using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Linq;

namespace ScreenSpan
{
    public sealed class Monitor
    {
        public string Id = "", Name = ""; public bool PreviewOnly;
        public Box Bounds;
    }
    [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDesktopWallpaper
    {
        void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint monitorIndex);
        uint GetMonitorDevicePathCount();
        void GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID, out Rect displayRect);
        void SetBackgroundColor(uint color); uint GetBackgroundColor();
        void SetPosition(uint position); uint GetPosition();
    }
    [StructLayout(LayoutKind.Sequential)]
    struct Rect
    {
        public int Left, Top, Right, Bottom;
    }
    public static class Desktop
    {
        static IDesktopWallpaper Create() => (IDesktopWallpaper)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD")))!;
        public static List<Monitor> Monitors()
        {
            var list = new List<Monitor>();
            IDesktopWallpaper? desktop = null;
            try
            {
                desktop = Create();
                for (uint i = 0; i < desktop.GetMonitorDevicePathCount(); i++)
                {
                    var id = desktop.GetMonitorDevicePathAt(i);
                    Rect r;
                    try
                    {
                        desktop.GetMonitorRECT(id, out r);
                    }
                    catch (COMException) { continue; }
                    if (r.Right > r.Left && r.Bottom > r.Top)
                        list.Add(new Monitor { Id = id, Name = "Display " + (i + 1), Bounds = new Box(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top) });
                }
            }
            catch (COMException) { }
            finally { if (desktop != null) Marshal.ReleaseComObject(desktop); }
            if (list.Count == 0)
            foreach (var screen in Screen.AllScreens)
            {
                var b = screen.Bounds;
                list.Add(new Monitor { Id = "preview:" + screen.DeviceName, PreviewOnly = true, Name = "Remote display " + (list.Count + 1), Bounds = new Box(b.X, b.Y, b.Width, b.Height) });
            }
            if (list.Count == 0)
                throw new InvalidOperationException("Windows did not report any active displays.");
            return list;
        }
        public static void Apply(IReadOnlyList<Monitor> monitors, IReadOnlyList<string> images)
        {
            if (monitors.Count != images.Count)
                throw new ArgumentException("Monitor count changed. Please try again.");
            foreach (var monitor in monitors)
            if (monitor.PreviewOnly || string.IsNullOrEmpty(monitor.Id))
                throw new InvalidOperationException("This remote session exposes preview displays only. Apply Wallpaper must be tested on a PC with displays available to the Windows wallpaper service.");
            var desktop = Create();
            var original = new List<string>();
            uint position = desktop.GetPosition();
            try
            {
                foreach (var monitor in monitors)
                    original.Add(desktop.GetWallpaper(monitor.Id));
                desktop.SetPosition(2);
                for (int i = 0; i < monitors.Count; i++)
                    desktop.SetWallpaper(monitors[i].Id, images[i]);
            }
            catch { for (int i = 0; i < original.Count; i++) try { desktop.SetWallpaper(monitors[i].Id, original[i]); } catch { } try { desktop.SetPosition(position); } catch { } throw; }
            finally { Marshal.ReleaseComObject(desktop); }
        }
        public static void CheckWallpaper(string report)
        {
            var monitors = Monitors();
            if (monitors.Any(m => m.PreviewOnly))
                throw new InvalidOperationException("Wallpaper API unavailable in this remote session.");
            var desktop = Create();
            string root = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ScreenSpan-Wallpaper-Test-" + Guid.NewGuid());
            System.IO.Directory.CreateDirectory(root);
            var old = new List<string>();
            uint position = desktop.GetPosition();
            var results = new List<string>();
            try
            {
                foreach (var monitor in monitors)
                    old.Add(desktop.GetWallpaper(monitor.Id));
                var paths = new List<string>();
                for (int i = 0; i < monitors.Count; i++)
                {
                    string path = System.IO.Path.Combine(root, "test-" + i + ".png");
                    using (var image = new Bitmap(64, 64))
                    {
                        using (var g = Graphics.FromImage(image))
                            g.Clear(i % 2 == 0 ? Color.CornflowerBlue : Color.Orange);
                        image.Save(path, System.Drawing.Imaging.ImageFormat.Png);
                    }
                    paths.Add(path);
                }
                Apply(monitors, paths);
                for (int i = 0; i < monitors.Count; i++)
                if (!string.Equals(System.IO.Path.GetFullPath(desktop.GetWallpaper(monitors[i].Id)), System.IO.Path.GetFullPath(paths[i]), StringComparison.OrdinalIgnoreCase))
                    throw new Exception("Windows did not retain the assigned wallpaper path.");
                results.Add("PASS: assigned wallpaper paths read back through IDesktopWallpaper for " + monitors.Count + " active display(s).");
            }
            finally { bool restored = true; for (int i = 0; i < old.Count; i++) try { desktop.SetWallpaper(monitors[i].Id, old[i]); } catch { restored = false; } try { desktop.SetPosition(position); } catch { restored = false; } results.Add(restored ? "PASS: original wallpaper paths and display position restored." : "FAIL: restore needs attention."); System.IO.File.WriteAllLines(report, results); Marshal.ReleaseComObject(desktop); if (restored) System.IO.Directory.Delete(root, true); if (!restored) throw new Exception("The test could not restore every original wallpaper."); }
        }

    }
}
