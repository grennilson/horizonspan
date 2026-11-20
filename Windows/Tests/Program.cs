using System;
using ScreenSpan;
static class Tests {
    static int checks;
    static void Check(bool condition,string name){checks++;if(!condition)throw new Exception(name);}
    static bool Equal(double a,double b)=>Math.Abs(a-b)<.00001;
    static void Main(){
        var two=Box.Union(new[]{new Box(-1920,0,1920,1080),new Box(0,0,1920,1080)});
        Check(two.Width==3840&&two.Height==1080&&two.X==-1920,"Negative monitor origins");
        var four=Box.Union(new[]{new Box(0,0,1920,1080),new Box(1920,0,1920,1080),new Box(0,-1080,1920,1080),new Box(1920,-1080,1920,1080)});
        Check(four.Width==3840&&four.Height==2160,"Four monitor arrangement");
        var f=new Framing();var portrait=f.ImageRect(1000,2000,two);
        Check(Equal(portrait.Height,1080)&&Equal(portrait.Width,540),"Preserve entire portrait height");
        f.Mode="fill";var fill=f.ImageRect(1000,2000,two);Check(Equal(fill.Width,3840)&&fill.Height>two.Height,"Fill and crop");
        f.PanX=999;f.PanY=-999;var pan=f.ImageRect(1000,2000,two);Check(Equal(pan.X,0)&&Equal(pan.Y,two.Height-pan.Height),"Pan clamps to image edges");
        var original=new Box(100,100,800,225);
        for(int c=0;c<4;c++){
            var crop=Framing.CropCorner(original,c,c==0||c==3?-500:2500,c==0||c==1?-500:2500,32.0/9,1920,1080);
            Check(Equal(crop.Width/crop.Height,32.0/9),"Corner ratio "+c);
            Check(crop.X>=0&&crop.Y>=0&&crop.Right<=1920.001&&crop.Bottom<=1080.001,"Corner bounds "+c);
        }
        var history=new History<Framing>();var before=new Framing();history.Push(before.Copy());var after=new Framing{Zoom=2};var undone=history.Undo(after.Copy());Check(undone.Zoom==1&&history.CanRedo,"Undo");Check(history.Redo(undone).Zoom==2,"Redo");history.Undo(after);history.Push(new Framing());Check(!history.CanRedo,"New edit clears redo");
        var three=Box.Union(new[]{new Box(0,0,1920,1080),new Box(1920,-300,2560,1440),new Box(4480,0,1080,1920)});
        Check(three.Width==5560&&three.Height==2220,"Mixed three-display portrait layout");
        var plan=AIPlan.Extend(1000,2000,two,new Framing{PanX=.5});Check(plan.Width==7111&&plan.Height==2000&&plan.Leading==6111,"AI extension preserves height and right positioning");
        var up=AIPlan.Enhance(100,100,new Box(0,0,10000,10000),new Framing());Check(up.Width==400&&up.Height==400,"AI detail enlargement limited to 4x");
        var design=new Design();design.monitors.Add(new Placement{key="a",group=1,offsetY=50});design.Validate();var copy=design.Copy();copy.monitors[0].group=2;Check(design.monitors[0].group==1,"Deep copy for Undo includes monitor groups");
        var virtualBounds=design.monitors[0].Virtual(new Box(0,0,100,100));Check(virtualBounds.Y==-50,"Positive vertical alignment moves sampling upward");
        bool invalid=false;design.appearance.dim=double.NaN;try{design.Validate();}catch(ArgumentException){invalid=true;}Check(invalid,"NaN appearance rejected");
        invalid=false;design=new Design();design.monitors.Add(new Placement{key="a"});design.monitors.Add(new Placement{key="a"});try{design.Validate();}catch(ArgumentException){invalid=true;}Check(invalid,"Duplicate monitor identities rejected");
        Check(!ReleaseVersions.IsNewer("v9.0.0","1.0.0"),"Mac release is excluded from Windows update checks");Check(ReleaseVersions.IsNewer("windows-v1.0.1","1.0.0"),"Windows update version comparison");Check(!ReleaseVersions.IsNewer("windows-v1.0.0","1.0.0"),"Same version is not an update");
        var pairs=new[]{new System.Collections.Generic.KeyValuePair<string,Box>("a",new Box(-100,0,100,100)),new System.Collections.Generic.KeyValuePair<string,Box>("b",new Box(0,0,100,100))};
        Check(LibraryIndex.SetupKey(pairs)==LibraryIndex.SetupKey(new[]{pairs[1],pairs[0]}),"Monitor profile key ignores enumeration order");
        Console.WriteLine("Passed "+checks+" geometry and undo checks.");
    }
}
