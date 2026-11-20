using System;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;

namespace ScreenSpan
{
    static class Entry
    {
        [STAThread]
        static int Main(string[] args)
        {
            AppDomain.CurrentDomain.AssemblyResolve += (sender, eventArgs) => { string name = new AssemblyName(eventArgs.Name).Name; if (name != "Newtonsoft.Json" && name != "ScreenSpan.Core") return null; using (var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("ScreenSpan." + name + ".dll")) { if (resource == null) return null; using (var memory = new MemoryStream()) { resource.CopyTo(memory); return Assembly.Load(memory.ToArray()); } } };
            return Start(args);
        }
        [MethodImpl(MethodImplOptions.NoInlining)] static int Start(string[] args) => Program.Main(args);
    }
}
