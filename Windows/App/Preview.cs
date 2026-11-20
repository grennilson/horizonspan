using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

namespace ScreenSpan
{
    public sealed class Preview : Control
    {
        public Bitmap? Image, Composite;
        public bool Comparing;
        public Framing Frame = new Framing();
        public List<Monitor> Monitors = new List<Monitor>();
        public bool Cropping;
        public Box Crop;
        public event Action? BeforeEdit, Changed;
        Point start; Framing? before; Box cropBefore; int corner = -1; bool dragging;
        public Preview()
        {
            DoubleBuffered = true;
            BackColor = Color.FromArgb(24, 28, 36);
            TabStop = true;
            SetStyle(ControlStyles.Selectable, true);
        }
        public Box BoundsAll => Monitors.Count > 0 ? Box.Union(Monitors.Select(m => m.Bounds)) : new Box(0, 0, 32, 9);
        public void BeginCrop()
        {
            if (Image == null)
                return;
            Cropping = true;
            double ratio = BoundsAll.Width / BoundsAll.Height, w = Math.Min(Image.Width, Image.Height * ratio), h = w / ratio;
            Crop = new Box((Image.Width - w) / 2, (Image.Height - h) / 2, w, h);
            Invalidate();
        }
        double Scale(out double ox, out double oy)
        {
            var b = Cropping && Image != null ? new Box(0, 0, Image.Width, Image.Height) : BoundsAll;
            double s = Math.Max(.0001, Math.Min((ClientSize.Width - 48) / b.Width, (ClientSize.Height - 48) / b.Height));
            ox = (ClientSize.Width - b.Width * s) / 2;
            oy = (ClientSize.Height - b.Height * s) / 2;
            return s;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            var g = e.Graphics;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            if (Image == null)
            {
                using (var f = new Font(Font.FontFamily, 15))
                using (var b = new SolidBrush(Color.LightGray))
                {
                    var text = "Drop images here or choose an image";
                    var size = g.MeasureString(text, f);
                    g.DrawString(text, f, b, (Width - size.Width) / 2, (Height - size.Height) / 2);
                }
                return;
            }
            double s = Scale(out double ox, out double oy);
            var bounds = BoundsAll;
            if (Cropping)
            {
                g.DrawImage(Image, new RectangleF((float)ox, (float)oy, (float)(Image.Width * s), (float)(Image.Height * s)));
                var r = new RectangleF((float)(ox + Crop.X * s), (float)(oy + Crop.Y * s), (float)(Crop.Width * s), (float)(Crop.Height * s));
                using (var shade = new SolidBrush(Color.FromArgb(130, 0, 0, 0)))
                using (var path = new GraphicsPath(FillMode.Alternate))
                {
                    path.AddRectangle(new RectangleF((float)ox, (float)oy, (float)(Image.Width * s), (float)(Image.Height * s)));
                    path.AddRectangle(r);
                    g.FillPath(shade, path);
                }
                using (var p = new Pen(Color.DeepSkyBlue, 2))
                    g.DrawRectangle(p, r.X, r.Y, r.Width, r.Height);
                foreach (var pt in Corners(r))
                    g.FillRectangle(Brushes.White, pt.X - 6, pt.Y - 6, 12, 12);
            }
            else
            {
                var rect = Frame.ImageRect(Image.Width, Image.Height, bounds);
                var clip = g.Save();
                g.SetClip(new RectangleF((float)ox, (float)oy, (float)(bounds.Width * s), (float)(bounds.Height * s)));
                if (Composite != null)
                    g.DrawImage(Composite, new RectangleF((float)ox, (float)oy, (float)(bounds.Width * s), (float)(bounds.Height * s)));
                else
                    g.DrawImage(Image, new RectangleF((float)(ox + rect.X * s), (float)(oy + rect.Y * s), (float)(rect.Width * s), (float)(rect.Height * s)));
                g.Restore(clip);
                for (int i = 0; i < Monitors.Count; i++)
                {
                    var b = Monitors[i].Bounds;
                    var r = new RectangleF((float)(ox + (b.X - bounds.X) * s), (float)(oy + (b.Y - bounds.Y) * s), (float)(b.Width * s), (float)(b.Height * s));
                    g.DrawRectangle(Pens.White, r.X, r.Y, r.Width, r.Height);
                    g.FillRectangle(Brushes.Black, r.X + 8, r.Y + 8, 28, 24);
                    g.DrawString((i + 1).ToString(), Font, Brushes.White, r.X + 16, r.Y + 12);
                }
            }
        }
        PointF[] Corners(RectangleF r) => new[] { new PointF(r.Left, r.Top), new PointF(r.Right, r.Top), new PointF(r.Right, r.Bottom), new PointF(r.Left, r.Bottom) };
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (Comparing || Image == null || e.Button != MouseButtons.Left)
                return;
            Focus();
            Capture = true;
            dragging = true;
            start = e.Location;
            before = Frame.Copy();
            cropBefore = Crop;
            corner = -1;
            if (Cropping)
            {
                double s = Scale(out double ox, out double oy);
                var r = new RectangleF((float)(ox + Crop.X * s), (float)(oy + Crop.Y * s), (float)(Crop.Width * s), (float)(Crop.Height * s));
                var points = Corners(r);
                for (int i = 0; i < 4; i++)
                if (Math.Abs(e.X - points[i].X) < 14 && Math.Abs(e.Y - points[i].Y) < 14)
                    corner = i;
            }
            else
                BeforeEdit?.Invoke();
        }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (!dragging || Image == null || before == null)
                return;
            double s = Scale(out double ox, out double oy);
            if (Cropping)
            {
                if (corner >= 0)
                    Crop = Framing.CropCorner(cropBefore, corner, (e.X - ox) / s, (e.Y - oy) / s, BoundsAll.Width / BoundsAll.Height, Image.Width, Image.Height);
                else
                    Crop = new Box(Framing.Clamp(cropBefore.X + (e.X - start.X) / s, 0, Image.Width - Crop.Width), Framing.Clamp(cropBefore.Y + (e.Y - start.Y) / s, 0, Image.Height - Crop.Height), Crop.Width, Crop.Height);
            }
            else
            {
                Frame.PanX = before.PanX + (e.X - start.X) / s / BoundsAll.Width;
                Frame.PanY = before.PanY + (e.Y - start.Y) / s / BoundsAll.Height;
                Changed?.Invoke();
            }
            Invalidate();
        }
        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            dragging = false;
            Capture = false;
        }
        protected override void OnMouseWheel(MouseEventArgs e)
        {
            base.OnMouseWheel(e);
            if (Comparing || Image == null)
                return;
            if (Cropping)
            {
                double factor = Math.Pow(1.12, -e.Delta / 120.0), cx = Crop.X + Crop.Width / 2, cy = Crop.Y + Crop.Height / 2;
                double max = Math.Min(Image.Width, Image.Height * BoundsAll.Width / BoundsAll.Height);
                double w = Framing.Clamp(Crop.Width * factor, Math.Min(16, max), max), h = w * BoundsAll.Height / BoundsAll.Width;
                Crop = new Box(Framing.Clamp(cx - w / 2, 0, Image.Width - w), Framing.Clamp(cy - h / 2, 0, Image.Height - h), w, h);
            }
            else
            {
                BeforeEdit?.Invoke();
                Frame.Zoom = Framing.Clamp(Frame.Zoom * Math.Pow(1.12, e.Delta / 120.0), 1, 3);
                Changed?.Invoke();
            }
            Invalidate();
        }
    }
}
