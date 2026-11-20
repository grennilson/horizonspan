using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;
using System.Linq;

namespace ScreenSpan
{
    public static class ImageTools
    {
        public static Bitmap Combine(IReadOnlyList<Bitmap> images, bool vertical)
        {
            if (images.Count == 0)
                throw new ArgumentException("Choose at least one image.");
            int cross = vertical ? images.Min(i => i.Width) : images.Min(i => i.Height);
            var lengths = images.Select(i => Math.Max(1, (int)Math.Round(vertical ? i.Height * (double)cross / i.Width : i.Width * (double)cross / i.Height))).ToArray();
            long length = lengths.Sum(i => (long)i);
            if (length * cross > 64000000 || length > int.MaxValue)
                throw new ArgumentException("Combined image exceeds 64 megapixels.");
            var result = new Bitmap(vertical ? cross : (int)length, vertical ? (int)length : cross);
            try
            {
                using (var g = Graphics.FromImage(result))
                {
                    g.Clear(Color.Black);
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    int pos = 0;
                    for (int i = 0; i < images.Count; i++)
                    {
                        g.DrawImage(images[i], vertical ? new Rectangle(0, pos, cross, lengths[i]) : new Rectangle(pos, 0, lengths[i], cross));
                        pos += lengths[i];
                    }
                }
                return result;
            }
            catch { result.Dispose(); throw; }
        }
        public static Bitmap Fade(Bitmap image, AIPlan plan)
        {
            var result = new Bitmap(plan.Width, plan.Height);
            int left = plan.Width > image.Width ? plan.Leading : 0, top = plan.Height > image.Height ? plan.Leading : 0;
            try
            {
                using (var g = Graphics.FromImage(result))
                {
                    g.Clear(Color.Black);
                    bool horizontal = plan.Width > image.Width;
                    int added = horizontal ? plan.Width - image.Width : plan.Height - image.Height;
                    foreach (bool leading in new[] { true, false })
                    {
                        int gap = leading ? plan.Leading : added - plan.Leading;
                        if (gap <= 0)
                            continue;
                        int extent = horizontal ? image.Width : image.Height;
                        int length = Math.Min(gap, Math.Max(1, (int)Math.Round(extent * .34))), sample = Math.Max(1, (int)(extent * .12));
                        Rectangle src = horizontal ? new Rectangle(leading ? 0 : image.Width - sample, 0, sample, image.Height) : new Rectangle(0, leading ? 0 : image.Height - sample, image.Width, sample);
                        Rectangle dst = horizontal ? new Rectangle(leading ? left - length : left + image.Width, top, length, image.Height) : new Rectangle(left, leading ? top - length : top + image.Height, image.Width, length);
                        g.DrawImage(image, dst, src, GraphicsUnit.Pixel);
                        var start = horizontal ? new Point(dst.Left, 0) : new Point(0, dst.Top);
                        var end = horizontal ? new Point(dst.Right, 0) : new Point(0, dst.Bottom);
                        using (var gradient = new LinearGradientBrush(start, end, leading ? Color.Black : Color.Transparent, leading ? Color.Transparent : Color.Black))
                            g.FillRectangle(gradient, dst);
                    }
                    g.DrawImageUnscaled(image, left, top);
                }
                return result;
            }
            catch { result.Dispose(); throw; }
        }
    }
}
