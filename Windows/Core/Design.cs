using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json;

namespace ScreenSpan {
public sealed class Appearance {
    public double brightness, saturation=1, dim, red, green, blue;
    public void Validate() { if(!Range(brightness,-.5,.5)||!Range(saturation,0,2)||!Range(dim,0,.8)||!Range(red,0,1)||!Range(green,0,1)||!Range(blue,0,1))throw new ArgumentException("Invalid appearance settings."); }
    public static bool Range(double n,double min,double max)=>!double.IsNaN(n)&&!double.IsInfinity(n)&&n>=min&&n<=max;
    [JsonIgnore] public bool Standard=>brightness==0&&saturation==1&&dim==0&&red==0&&green==0&&blue==0;
}
public sealed class Placement {
    public string key="";
    public int group;
    public double offsetX,offsetY,sizeScale=1;
    public void Validate(){if(key==null||key.Length>4096||group<0||group>32||!Appearance.Range(offsetX,-20000,20000)||!Appearance.Range(offsetY,-20000,20000)||!Appearance.Range(sizeScale,.25,4))throw new ArgumentException("Invalid display alignment.");}
    public Box Virtual(Box physical)=>new Box(physical.X+offsetX,physical.Y-offsetY,physical.Width*sizeScale,physical.Height*sizeScale);
}
public sealed class Design {
    public Appearance appearance=new Appearance();
    public List<Placement> monitors=new List<Placement>();
    public List<int> customGroups=new List<int>();
    public void Validate(){if(appearance==null||monitors==null||customGroups==null||monitors.Count>32||customGroups.Count>32)throw new ArgumentException("Invalid wallpaper design.");appearance.Validate();foreach(var m in monitors){if(m==null)throw new ArgumentException("Missing monitor settings.");m.Validate();}if(monitors.Select(m=>m.key).Distinct().Count()!=monitors.Count||customGroups.Distinct().Count()!=customGroups.Count||customGroups.Any(g=>g<1||g>32))throw new ArgumentException("Invalid wallpaper groups.");}
    public Placement For(string key)=>monitors.FirstOrDefault(m=>m.key==key)??new Placement{key=key};
    public Design Copy()=>JsonConvert.DeserializeObject<Design>(JsonConvert.SerializeObject(this))!;
    [JsonIgnore] public bool Standard=>appearance.Standard&&monitors.All(m=>m.group==0&&m.offsetX==0&&m.offsetY==0&&m.sizeScale==1);
}
public sealed class LibraryDetails { public string title=""; public bool favorite; }
public sealed class SetupProfile { public string name="", projectID=""; }
public sealed class LibraryIndex {
    public Dictionary<string,LibraryDetails> entries=new Dictionary<string,LibraryDetails>(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string,SetupProfile> setups=new Dictionary<string,SetupProfile>();
    public static string SetupKey(IEnumerable<KeyValuePair<string,Box>> displays){var ds=displays.ToArray();var b=Box.Union(ds.Select(d=>d.Value));return string.Join("|",ds.Select(d=>d.Key+":"+string.Join(",",new[]{d.Value.X-b.X,d.Value.Y-b.Y,d.Value.Width,d.Value.Height}.Select(n=>n.ToString("R",System.Globalization.CultureInfo.InvariantCulture)))).OrderBy(s=>s,StringComparer.Ordinal));}
}
public struct AIPlan {
    public int Width,Height,Leading;
    public static AIPlan Extend(int width,int height,Box bounds,Framing frame){double ratio=bounds.Width/bounds.Height;int w=width,h=height;if((double)width/height<ratio)w=(int)Math.Round(height*ratio);else h=(int)Math.Round(width/ratio);if((long)w*h>64000000)throw new ArgumentException("The extended image exceeds 64 megapixels. Reduce its size first.");int space=w>width?w-width:h-height;return new AIPlan{Width=w,Height=h,Leading=(int)Math.Round(Framing.Clamp(space/2.0+(w>width?frame.PanX*w:frame.PanY*h),0,space))};}
    public static AIPlan Enhance(int width,int height,Box bounds,Framing frame){double factor=(frame.Mode=="fit"?Math.Min(bounds.Width/width,bounds.Height/height):Math.Max(bounds.Width/width,bounds.Height/height))*frame.Zoom;factor=Math.Min(4,Math.Min(factor,Math.Sqrt(64000000.0/width/height)));if(factor<=1.01)throw new ArgumentException("This image already has enough detail for the current display framing.");return new AIPlan{Width=(int)(width*factor),Height=(int)(height*factor)};}
}
public static class ReleaseVersions {
    public static Version? Parse(string value){const string prefix="windows-v";if(!value.StartsWith(prefix,StringComparison.Ordinal))return null;return Version.TryParse(value.Substring(prefix.Length),out var v)?v:null;}
    public static bool IsNewer(string tag,string current)=>Parse(tag) is Version next&&Version.TryParse(current,out var installed)&&next>installed;
}
}
