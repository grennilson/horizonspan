using System;
using System.Drawing;
using System.Windows.Forms;
namespace ScreenSpan
{
    internal static class WindowSizing
    {
        public static void Fit(Form form)
        {
            var area = Screen.FromControl(form).WorkingArea;
            int w = Math.Min(form.Width, Math.Max(300, area.Width - 20)), h = Math.Min(form.Height, Math.Max(300, area.Height - 20));
            form.MinimumSize = new Size(Math.Min(form.MinimumSize.Width, w), Math.Min(form.MinimumSize.Height, h));
            form.Bounds = new Rectangle(area.X + (area.Width - w) / 2, area.Y + (area.Height - h) / 2, w, h);
        }
    }
}
