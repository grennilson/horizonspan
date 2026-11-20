using System;
using System.Collections.Generic;
using System.Linq;

namespace ScreenSpan {
public struct Box {
    public double X, Y, Width, Height;
    public Box(double x, double y, double width, double height) { X=x; Y=y; Width=width; Height=height; }
    public double Right => X+Width;
    public double Bottom => Y+Height;
    public static Box Union(IEnumerable<Box> boxes) {
        var b=boxes.ToArray(); if(b.Length==0) throw new ArgumentException("No monitors connected.");
        double x=b.Min(r=>r.X), y=b.Min(r=>r.Y);
        return new Box(x,y,b.Max(r=>r.Right)-x,b.Max(r=>r.Bottom)-y);
    }
}
public sealed class Framing {
    public string Mode="fit";
    public double Zoom=1, PanX, PanY;
    public Framing Copy() => (Framing)MemberwiseClone();
    public static double Clamp(double x,double min,double max) => Math.Min(max,Math.Max(min,x));
    public Box ImageRect(double width,double height,Box bounds) {
        if(!Appearance.Range(width,1,64000000)||!Appearance.Range(height,1,64000000)||!Appearance.Range(bounds.Width,.001,1000000)||!Appearance.Range(bounds.Height,.001,1000000)||!Appearance.Range(Zoom,1,3)||!Appearance.Range(PanX,-1000000,1000000)||!Appearance.Range(PanY,-1000000,1000000)) throw new ArgumentException("Invalid image or monitor dimensions.");
        double s=(Mode=="fit" ? Math.Min(bounds.Width/width,bounds.Height/height) : Math.Max(bounds.Width/width,bounds.Height/height))*Zoom;
        double w=width*s,h=height*s;
        return new Box((bounds.Width-w)/2+Clamp(PanX*bounds.Width,-Math.Abs(w-bounds.Width)/2,Math.Abs(w-bounds.Width)/2),
            (bounds.Height-h)/2+Clamp(PanY*bounds.Height,-Math.Abs(h-bounds.Height)/2,Math.Abs(h-bounds.Height)/2),w,h);
    }
    public static Box CropCorner(Box initial,int corner,double x,double y,double ratio,double imageWidth,double imageHeight) {
        double ax=(corner==0||corner==3)?initial.Right:initial.X;
        double ay=(corner==0||corner==1)?initial.Bottom:initial.Y;
        double sx=(corner==0||corner==3)?-1:1,sy=(corner==0||corner==1)?-1:1;
        double maxW=Math.Min(sx<0?ax:imageWidth-ax,(sy<0?ay:imageHeight-ay)*ratio);
        double w=Clamp(Math.Max(Math.Abs(x-ax),Math.Abs(y-ay)*ratio),Math.Min(16,maxW),maxW),h=w/ratio;
        return new Box(sx<0?ax-w:ax,sy<0?ay-h:ay,w,h);
    }
}
public sealed class History<T> {
    readonly List<T> undo=new List<T>(),redo=new List<T>();
    public bool CanUndo=>undo.Count>0; public bool CanRedo=>redo.Count>0;
    public void Push(T state) { undo.Add(state); if(undo.Count>30) undo.RemoveAt(0); redo.Clear(); }
    public T Undo(T state) { if(!CanUndo) return state; redo.Add(state); var s=undo[undo.Count-1]; undo.RemoveAt(undo.Count-1); return s; }
    public T Redo(T state) { if(!CanRedo) return state; undo.Add(state); var s=redo[redo.Count-1]; redo.RemoveAt(redo.Count-1); return s; }
    public void Clear(){undo.Clear();redo.Clear();}
}
}
