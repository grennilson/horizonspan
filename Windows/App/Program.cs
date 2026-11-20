using System;
using System.IO;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Newtonsoft.Json;

namespace ScreenSpan
{
    static class Program
    {
        static string PipeName => "ScreenSpan-Wallpaper-" + WindowsIdentity.GetCurrent().User.Value;
        [STAThread]
        internal static int Main(string[] args)
        {
            if (args.Length == 2 && args[0] == "--self-test")
            {
                try
                {
                    WindowsChecks.Run(args[1]);
                    return 0;
                }
                catch { return 1; }
            }
            if (args.Length == 2 && args[0] == "--wallpaper-smoke-test")
            {
                try
                {
                    Desktop.CheckWallpaper(args[1]);
                    return 0;
                }
                catch (Exception error) { File.AppendAllText(args[1], "FAIL: " + error); return 1; }
            }
            if (args.Length == 2 && args[0] == "--ai-smoke-test")
            {
                try
                {
                    WindowsChecks.AI(args[1]).GetAwaiter().GetResult();
                    return 0;
                }
                catch { return 1; }
            }
            using (var mutex = new Mutex(true, @"Local\" + PipeName, out bool first))
            {
                if (!first)
                {
                    try
                    {
                        using (var client = new NamedPipeClientStream(".", PipeName, PipeDirection.Out))
                        {
                            client.Connect(4000);
                            using (var writer = new StreamWriter(client))
                            {
                                writer.WriteLine(JsonConvert.SerializeObject(args));
                            }
                        }
                        return 0;
                    }
                    catch { return 1; }
                }
                if (args.Length == 1 && args[0] == "--quit")
                    return 0;
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.ThreadException += (s, e) => MessageBox.Show(e.Exception.Message, "ScreenSpan Wallpaper");
                using (var window = new MainWindow(args))
                using (var canceled = new CancellationTokenSource())
                {
                    Task server = Listen(window, canceled.Token);
                    Application.Run(window);
                    canceled.Cancel();
                }
                mutex.ReleaseMutex();
            }
            return 0;
        }
        static async Task Listen(MainWindow window, CancellationToken canceled)
        {
            while (!canceled.IsCancellationRequested)
            {
                try
                {
                    var security = new PipeSecurity();
                    security.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User, PipeAccessRights.FullControl, AccessControlType.Allow));
                    using (var pipe = new NamedPipeServerStream(PipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 4096, 4096, security))
                    {
                        await pipe.WaitForConnectionAsync(canceled).ConfigureAwait(false);
                        using (var reader = new StreamReader(pipe))
                        {
                            string? message = await reader.ReadLineAsync().ConfigureAwait(false);
                            if (message == null || message.Length > 32768)
                                continue;
                            var args = JsonConvert.DeserializeObject<string[]>(message);
                            if (args != null && !window.IsDisposed && window.IsHandleCreated)
                                window.BeginInvoke((Action)(() => window.HandleLaunch(args)));
                        }
                    }
                }
                catch (OperationCanceledException) { return; }
                catch { if (!canceled.IsCancellationRequested) await Task.Delay(100, canceled).ConfigureAwait(false); }
            }
        }
    }
}
