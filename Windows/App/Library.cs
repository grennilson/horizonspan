using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace ScreenSpan
{
    public static class SafeJson
    {
        public static JObject Read(string path)
        {
            var info = new FileInfo(path);
            if (info.Length > 4000000)
                throw new InvalidDataException("Settings file is too large.");
            using (var stream = File.OpenText(path))
            using (var reader = new JsonTextReader(stream) { MaxDepth = 64 })
                return JObject.Load(reader);
        }
        public static void Write(string path, object data)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            string temp = path + "." + Guid.NewGuid() + ".tmp";
            try
            {
                File.WriteAllText(temp, JsonConvert.SerializeObject(data, Formatting.Indented));
                if (File.Exists(path))
                    File.Replace(temp, path, null);
                else
                    File.Move(temp, path);
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
    }
    public sealed class LibraryEntry
    {
        public string Id = "", Folder = "", Title = ""; public bool Favorite;
        public override string ToString() => (Favorite ? "★ " : "") + Title;
    }
    public sealed class LibraryStore
    {
        readonly string root; public LibraryStore(string? root = null)
        {
            this.root = root ?? Project.Library;
            Directory.CreateDirectory(this.root);
        }
        public LibraryIndex Read()
        {
            string path = Path.Combine(root, ".Library.json");
            var index = File.Exists(path) ? SafeJson.Read(path).ToObject<LibraryIndex>() ?? new LibraryIndex() : new LibraryIndex();
            if (index.entries == null || index.setups == null || index.entries.Count > 100000 || index.setups.Count > 10000 || index.entries.Any(e => e.Value == null) || index.setups.Any(e => e.Value == null))
                throw new InvalidDataException("Invalid wallpaper library metadata.");
            return index;
        }
        public void Write(LibraryIndex index) => SafeJson.Write(Path.Combine(root, ".Library.json"), index);
        public List<LibraryEntry> Entries()
        {
            var index = Read();
            var result = new List<LibraryEntry>();
            foreach (var folder in Directory.GetDirectories(root, "*.ssw").OrderByDescending(Directory.GetCreationTimeUtc))
            {
                try
                {
                    var json = SafeJson.Read(Path.Combine(folder, "Settings.json"));
                    int version = (int?)json["formatVersion"] ?? 0;
                    if (version < 1 || version > 2)
                        continue;
                    string id = (string?)json["wallpaper"]?["id"] ?? "";
                    if (!Guid.TryParse(id, out var parsed))
                        continue;
                    id = parsed.ToString().ToUpperInvariant();
                    var details = index.entries.FirstOrDefault(p => string.Equals(p.Key, id, StringComparison.OrdinalIgnoreCase)).Value;
                    result.Add(new LibraryEntry { Id = id, Folder = folder, Title = details?.title ?? (string?)json["title"] ?? Path.GetFileNameWithoutExtension((string?)json["wallpaper"]?["filename"] ?? "Wallpaper"), Favorite = details?.favorite ?? false });
                }
                catch (IOException) { }
                catch (JsonException) { }
                catch (ArgumentException) { }
            }
            var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var entry in result.AsEnumerable().Reverse())
            {
                string original = entry.Title; int number = 2;
                while (!used.Add(entry.Title)) entry.Title = original + " (" + number++ + ")";
            }
            return result;
        }
        public void Details(LibraryEntry entry, string title, bool favorite)
        {
            var index = Read();
            index.entries[entry.Id] = new LibraryDetails { title = string.IsNullOrWhiteSpace(title) ? entry.Title : title.Trim().Substring(0, Math.Min(title.Trim().Length, 160)), favorite = favorite };
            Write(index);
        }
        public static string SetupKey(IReadOnlyList<Monitor> displays) => LibraryIndex.SetupKey(displays.Select(d => new KeyValuePair<string, Box>(d.Id, d.Bounds)));
        public void Remember(string key, string name, string id)
        {
            var index = Read();
            index.setups[key] = new SetupProfile { name = name, projectID = id };
            Write(index);
        }
        public void Forget(string key)
        {
            var index = Read();
            index.setups.Remove(key);
            Write(index);
        }
        public string? Match(string key)
        {
            var index = Read();
            if (!index.setups.TryGetValue(key, out var profile))
                return null;
            return Entries().FirstOrDefault(e => string.Equals(e.Id, profile.projectID, StringComparison.OrdinalIgnoreCase))?.Folder;
        }
        public string[] RotationCandidates()
        {
            var entries = Entries();
            var favorites = entries.Where(e => e.Favorite).ToArray();
            return (favorites.Length > 0 ? favorites : entries.ToArray()).Select(e => e.Folder).ToArray();
        }
    }
}
