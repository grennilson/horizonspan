using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Linq;

namespace ScreenSpan
{
    public sealed class RenderedImages : IDisposable
    {
        readonly EditState state; readonly IReadOnlyList<Monitor> monitors;
        readonly Dictionary<int, Bitmap> images = new Dictionary<int, Bitmap>();
        public RenderedImages(EditState state, IReadOnlyList<Monitor> monitors)
        {
            state.Design.Validate();
            if (monitors.Count == 0)
                throw new ArgumentException("No displays connected.");
            this.state = state;
            this.monitors = monitors;
        }
        public Bitmap Screen(int index, double limit = 1)
        {
            var screen = monitors[index];
            var placement = state.Design.For(screen.Id);
            int group = placement.group;
            if (!images.TryGetValue(group, out var source))
            {
                source = Project.Load(group > 0 && state.Groups.TryGetValue(group, out var path) ? path : state.ImagePath);
                images[group] = source;
            }
            var virtuals = monitors.Where(m => state.Design.For(m.Id).group == group).Select(m => state.Design.For(m.Id).Virtual(m.Bounds));
            var bounds = Box.Union(virtuals);
            var v = placement.Virtual(screen.Bounds);
            int width = Math.Max(1, (int)Math.Round(screen.Bounds.Width * limit)), height = Math.Max(1, (int)Math.Round(screen.Bounds.Height * limit));
            if ((long)width * height > 64000000)
                throw new ArgumentException("One display exceeds the 64 megapixel limit.");
            var output = new Bitmap(width, height);
            var a = state.Design.appearance;
            var rect = state.Frame.ImageRect(source.Width, source.Height, bounds);
            using (var g = Graphics.FromImage(output))
            using (var attributes = new ImageAttributes())
            {
                g.Clear(Color.FromArgb((int)Math.Round(a.red * 255), (int)Math.Round(a.green * 255), (int)Math.Round(a.blue * 255)));
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                float sat = (float)a.saturation, dim = (float)(1 - a.dim), bright = (float)(a.brightness * (1 - a.dim)), lr = .2126f, lg = .7152f, lb = .0722f;
                attributes.SetColorMatrix(new ColorMatrix(new[] { new[] { dim * (lr * (1 - sat) + sat), dim * lr * (1 - sat), dim * lr * (1 - sat), 0f, 0f }, new[] { dim * lg * (1 - sat), dim * (lg * (1 - sat) + sat), dim * lg * (1 - sat), 0f, 0f }, new[] { dim * lb * (1 - sat), dim * lb * (1 - sat), dim * (lb * (1 - sat) + sat), 0f, 0f }, new[] { 0f, 0f, 0f, 1f, 0f }, new[] { bright, bright, bright, 0f, 1f } }));
                double sx = width / v.Width, sy = height / v.Height;
                float x = (float)((rect.X - (v.X - bounds.X)) * sx), y = (float)((rect.Y - (v.Y - bounds.Y)) * sy), w = (float)(rect.Width * sx), h = (float)(rect.Height * sy);
                g.DrawImage(source, new[] { new PointF(x, y), new PointF(x + w, y), new PointF(x, y + h) }, new RectangleF(0, 0, source.Width, source.Height), GraphicsUnit.Pixel, attributes);
            }
            return output;
        }
        public Bitmap Combined(double maxPixels = 64000000)
        {
            var bounds = Box.Union(monitors.Select(m => m.Bounds));
            double scale = Math.Min(1, Math.Sqrt(maxPixels / bounds.Width / bounds.Height));
            var bitmap = new Bitmap(Math.Max(1, (int)Math.Round(bounds.Width * scale)), Math.Max(1, (int)Math.Round(bounds.Height * scale)));
            try
            {
                using (var g = Graphics.FromImage(bitmap))
                {
                    g.Clear(Color.Black);
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    for (int i = 0; i < monitors.Count; i++)
                    {
                        var b = monitors[i].Bounds;
                        using (var image = Screen(i, scale))
                            g.DrawImage(image, new RectangleF((float)((b.X - bounds.X) * scale), (float)((b.Y - bounds.Y) * scale), (float)(b.Width * scale), (float)(b.Height * scale)));
                    }
                }
                return bitmap;
            }
            catch { bitmap.Dispose(); throw; }
        }
        public void Dispose()
        {
            foreach (var image in images.Values)
                image.Dispose();
        }
    }
}
