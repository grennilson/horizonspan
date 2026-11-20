using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace ScreenSpan
{
    public static class AIWorker
    {
        public static bool HasNvidia()
        {
            try
            {
                using (var search = new System.Management.ManagementObjectSearcher("SELECT Name FROM Win32_VideoController"))
                foreach (System.Management.ManagementObject card in search.Get())
                using (card)
                {
                    if ((card["Name"] as string ?? "").IndexOf("NVIDIA", StringComparison.OrdinalIgnoreCase) >= 0)
                        return true;
                }
            }
            catch { }
            return false;
        }
        public static string Root => Path.Combine(Project.Support, "LocalAI-v1");
        static string WorkerScript()
        {
            Directory.CreateDirectory(Root);
            string file = Path.Combine(Root, "image_tools-1.0.0.py");
            using (var source = System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("ScreenSpan.image_tools.py"))
            using (var target = File.Create(file))
            {
                if (source == null)
                    throw new FileNotFoundException("The AI worker resource is missing.");
                source.CopyTo(target);
            }
            return file;
        }
        public static string Python => Path.Combine(Root, "env", "Scripts", "python.exe");
        public static string Quote(string value)
        {
            if (value.Length > 0 && !value.Any(c => char.IsWhiteSpace(c) || c == '"'))
                return value;
            var b = new StringBuilder("\"");
            int slash = 0;
            foreach (char c in value)
            {
                if (c == '\\')
                {
                    slash++;
                    continue;
                }
                if (c == '"')
                {
                    b.Append('\\', slash * 2 + 1);
                    b.Append(c);
                }
                else
                {
                    b.Append('\\', slash);
                    b.Append(c);
                }
                slash = 0;
            }
            b.Append('\\', slash * 2);
            return b.Append('"').ToString();
        }
        public static async Task RunProcess(string executable, string[] args, Action<string> progress, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            using (var process = new Process { StartInfo = new ProcessStartInfo { FileName = executable, Arguments = string.Join(" ", args.Select(Quote)), UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true } })
            {
                process.StartInfo.EnvironmentVariables["UV_CACHE_DIR"] = Path.Combine(Root, "cache");
                process.StartInfo.EnvironmentVariables["UV_PYTHON_INSTALL_DIR"] = Path.Combine(Root, "python");
                process.StartInfo.EnvironmentVariables["UV_NO_CONFIG"] = "1";
                process.StartInfo.EnvironmentVariables["UV_NO_PROGRESS"] = "1";
                process.StartInfo.EnvironmentVariables["HF_HUB_DISABLE_TELEMETRY"] = "1";
                process.StartInfo.EnvironmentVariables["PYTHONNOUSERSITE"] = "1";
                process.StartInfo.EnvironmentVariables.Remove("PYTHONHOME");
                process.StartInfo.EnvironmentVariables.Remove("PYTHONPATH");
                process.Start();
                using (token.Register(() => { try { if (!process.HasExited) using (var kill = Process.Start(new ProcessStartInfo { FileName = Path.Combine(Environment.SystemDirectory, "taskkill.exe"), Arguments = "/PID " + process.Id + " /T /F", CreateNoWindow = true, UseShellExecute = false })) { } } catch { } }))
                {
                    var error = new StringBuilder();
                    var stdout = Task.Run(async () => { string line; while ((line = await process.StandardOutput.ReadLineAsync()) != null) progress(line); });
                    var stderr = Task.Run(async () => { string line; while ((line = await process.StandardError.ReadLineAsync()) != null) { if (error.Length > 12000) error.Remove(0, 6000); error.AppendLine(line); progress(line); } });
                    await Task.WhenAll(stdout, stderr, Task.Run(() => process.WaitForExit()));
                    token.ThrowIfCancellationRequested();
                    if (process.ExitCode != 0)
                        throw new InvalidOperationException("AI processing failed: " + string.Join(" ", error.ToString().Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).Reverse().Take(3).Reverse()));
                }
            }
        }
        public static async Task Setup(bool cpu, Action<string> progress, CancellationToken token)
        {
            Directory.CreateDirectory(Root);
            string uv = Path.Combine(Root, "uv.exe"), ready = Path.Combine(Root, "ready");
            if (File.Exists(ready) && File.ReadAllText(ready) == (cpu ? "cpu" : "cuda") && File.Exists(Python))
                return;
            if (!File.Exists(uv))
            {
                progress("Downloading the local AI runtime…");
                string zip = Path.Combine(Root, "uv.zip");
                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                using (var client = new WebClient())
                using (token.Register(client.CancelAsync))
                    await client.DownloadFileTaskAsync(new Uri("https://github.com/astral-sh/uv/releases/download/0.13.8/uv-x86_64-pc-windows-msvc.zip"), zip);
                using (var sha = SHA256.Create())
                using (var stream = File.OpenRead(zip))
                {
                    string digest = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
                    if (digest != "529e78a9cec6cd7e3e014f7ecd8bda0c113969d4ed0f2efeedb85c30943325b8")
                        throw new InvalidDataException("AI runtime download did not pass its integrity check.");
                }
                using (var archive = ZipFile.OpenRead(zip))
                {
                    var entry = archive.Entries.Single(e => e.Name == "uv.exe");
                    entry.ExtractToFile(uv, true);
                }
                File.Delete(zip);
            }
            progress("Installing a private Python runtime and AI libraries…");
            await RunProcess(uv, new[] { "python", "install", "3.12", "--no-bin" }, progress, token);
            await RunProcess(uv, new[] { "venv", "--allow-existing", "--managed-python", "--python", "3.12", Path.Combine(Root, "env") }, progress, token);
            await RunProcess(uv, new[] { "pip", "install", "--python", Python, "torch==2.10.0", "torchvision==0.25.0", "--index-url", cpu ? "https://download.pytorch.org/whl/cpu" : "https://download.pytorch.org/whl/cu126" }, progress, token);
            await RunProcess(uv, new[] { "pip", "install", "--python", Python, "Pillow==12.1.1", "spandrel==0.4.2", "diffusers==0.37.0", "transformers==4.57.6", "accelerate==1.12.0", "huggingface-hub==0.36.2" }, progress, token);
            await RunProcess(Python, new[] { "-c", "import torch, spandrel; from diffusers import StableDiffusionXLInpaintPipeline; print('AI runtime ready; CUDA available:', torch.cuda.is_available())" }, progress, token);
            token.ThrowIfCancellationRequested();
            File.WriteAllText(ready, cpu ? "cpu" : "cuda");
        }
        public static async Task<string> Generate(EditState state, AIPlan plan, string action, string prompt, bool cpu, Action<string> progress, CancellationToken token, int steps = 26)
        {
            await Setup(cpu, progress, token);
            string result = Path.Combine(Root, "result-" + Guid.NewGuid() + ".png");
            var arguments = new System.Collections.Generic.List<string> { WorkerScript(), action, state.ImagePath, result, Path.Combine(Root, "models"), plan.Width.ToString(), plan.Height.ToString() };
            if (action == "extend")
            {
                arguments.Add("--leading-extension=" + plan.Leading);
                arguments.Add("--steps=" + steps);
                if (!string.IsNullOrWhiteSpace(prompt))
                    arguments.Add("--prompt=" + prompt.Substring(0, Math.Min(400, prompt.Length)));
            }
            if (cpu)
                arguments.Add("--cpu");
            try
            {
                await RunProcess(Python, arguments.ToArray(), progress, token);
                using (var image = Project.Load(result))
                {
                    if (image.Width != plan.Width || image.Height != plan.Height)
                        throw new InvalidDataException("AI returned unexpected image dimensions.");
                    return Project.Cache(image);
                }
            }
            finally { if (File.Exists(result)) File.Delete(result); }
        }
    }
}
