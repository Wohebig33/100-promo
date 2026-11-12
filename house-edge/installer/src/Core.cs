using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace HouseEdgeInstaller
{
    /// <summary>What's in the download, wherever it was unzipped.</summary>
    public sealed class Package
    {
        public string Root;
        public string Winhttp64;   // winhttp.dll next to the installer: the 64-bit one, also what a manual drop-in uses
        public string Winhttp86;   // BepInEx/houseedge-x86/winhttp.dll: picked for 32-bit games

        public const string X86Folder = "houseedge-x86";

        /// <summary>The package in this folder, or null if the download wasn't unzipped (Windows runs an .exe inside a zip from a temp folder with nothing next to it).</summary>
        public static Package Find(string dir)
        {
            if (dir == null || !File.Exists(Path.Combine(dir, "doorstop_config.ini")) || !File.Exists(Path.Combine(dir, "winhttp.dll"))
                || !File.Exists(Path.Combine(dir, "BepInEx", "core", "BepInEx.dll"))) return null;
            var x86 = Path.Combine(dir, "BepInEx", X86Folder, "winhttp.dll");
            return new Package { Root = dir, Winhttp64 = Path.Combine(dir, "winhttp.dll"), Winhttp86 = File.Exists(x86) ? x86 : null };
        }
    }

    public sealed class Result
    {
        public bool Ok;
        public string Message;
        public static Result Fail(string m) => new Result { Ok = false, Message = m };
        public static Result Done(string m) => new Result { Ok = true, Message = m };
    }

    public static class Core
    {
        public const string PluginFolder = "HouseEdgeInGame";

        // ------------------------------------------------------------------ finding the game
        /// <summary>
        /// The game's .exe in this folder, or null. Strict: only We're All In (full game or demo).
        /// Not strict: any Unity game, for a folder the player picked themselves.
        /// </summary>
        public static string GameExe(string dir, bool strict = true)
        {
            try
            {
                if (dir == null || !Directory.Exists(dir) || !File.Exists(Path.Combine(dir, "UnityPlayer.dll"))) return null;
                foreach (var exe in Directory.GetFiles(dir, "*.exe"))
                {
                    var name = Path.GetFileNameWithoutExtension(exe);
                    if (name.StartsWith("UnityCrashHandler", StringComparison.OrdinalIgnoreCase)) continue;
                    if (strict && !name.StartsWith("WereAllIn", StringComparison.OrdinalIgnoreCase)) continue;
                    if (Directory.Exists(Path.Combine(dir, name + "_Data"))) return exe;
                }
            }
            catch (Exception) { }
            return null;
        }

        /// <summary>Every Steam library folder, read from each Steam install's libraryfolders.vdf.</summary>
        public static List<string> LibraryFolders(IEnumerable<string> steamRoots)
        {
            var libs = new List<string>();
            foreach (var root in steamRoots.Where(r => !string.IsNullOrEmpty(r)))
            {
                Add(libs, root);
                foreach (var vdf in new[] { Path.Combine(root, "steamapps", "libraryfolders.vdf"), Path.Combine(root, "config", "libraryfolders.vdf") })
                {
                    string text;
                    try { if (!File.Exists(vdf)) continue; text = File.ReadAllText(vdf); } catch (Exception) { continue; }
                    // New format: "path" "D:\\SteamLibrary". Old format: "1" "D:\\SteamLibrary".
                    foreach (Match m in Regex.Matches(text, "\"(?:path|\\d+)\"\\s+\"([^\"]+)\""))
                    {
                        var p = m.Groups[1].Value.Replace("\\\\", "\\");
                        if (p.Contains(":") || p.StartsWith("/")) Add(libs, p);
                    }
                }
            }
            return libs;
        }

        private static void Add(List<string> list, string dir)
        {
            try
            {
                if (!Directory.Exists(dir)) return;
                var full = Path.GetFullPath(dir).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                if (!list.Any(d => string.Equals(d, full, StringComparison.OrdinalIgnoreCase))) list.Add(full);
            }
            catch (Exception) { }
        }

        /// <summary>
        /// Where to install. First the folder the installer sits in and the two above it, so it still works when the whole
        /// download folder was dropped into the game folder. Then every Steam library, which finds the full game and the demo.
        /// </summary>
        public static List<string> FindGames(string selfDir, IEnumerable<string> steamRoots)
        {
            var found = new List<string>();
            var d = selfDir;
            for (int i = 0; i < 3 && d != null; i++, d = Parent(d))
                if (GameExe(d, strict: false) != null) { Add(found, d); return found; }

            foreach (var lib in LibraryFolders(steamRoots))
            {
                var common = Path.Combine(lib, "steamapps", "common");
                string[] dirs;
                try { dirs = Directory.Exists(common) ? Directory.GetDirectories(common) : new string[0]; } catch (Exception) { continue; }
                foreach (var g in dirs) if (GameExe(g) != null) Add(found, g);
            }
            return found;
        }

        private static string Parent(string d)
        {
            try { return Directory.GetParent(d)?.FullName; } catch (Exception) { return null; }
        }

        /// <summary>A path the player typed or dragged in. Accepts the game folder, the .exe, or a file inside the game folder.</summary>
        public static string GameDirFromInput(string input)
        {
            var p = (input ?? "").Trim().Trim('"', '\'').Trim();
            if (p.Length == 0) return null;
            try
            {
                if (File.Exists(p)) p = Path.GetDirectoryName(Path.GetFullPath(p));
                for (var d = p; d != null; d = Parent(d))
                    if (GameExe(d, strict: false) != null) return Path.GetFullPath(d);
            }
            catch (Exception) { }
            return null;
        }

        // ------------------------------------------------------------------ 32 or 64-bit
        /// <summary>"x64", "x86" or null, read from a Windows .exe or .dll header.</summary>
        public static string Machine(string pePath)
        {
            try
            {
                using (var r = new BinaryReader(File.OpenRead(pePath)))
                {
                    if (r.ReadUInt16() != 0x5A4D) return null;          // MZ
                    r.BaseStream.Seek(0x3C, SeekOrigin.Begin);
                    r.BaseStream.Seek(r.ReadInt32(), SeekOrigin.Begin);
                    if (r.ReadUInt32() != 0x00004550) return null;     // PE\0\0
                    var m = r.ReadUInt16();
                    return m == 0x8664 ? "x64" : m == 0x014C ? "x86" : m == 0xAA64 ? "arm64" : null;
                }
            }
            catch (Exception) { return null; }
        }

        // ------------------------------------------------------------------ install and uninstall
        public static bool IsInstalled(string gameDir) =>
            File.Exists(Path.Combine(gameDir, "BepInEx", "plugins", PluginFolder, "HouseEdgeInGame.dll"));

        public static bool IsRunning(string gameExe)
        {
            try { return Process.GetProcessesByName(Path.GetFileNameWithoutExtension(gameExe)).Length > 0; } catch (Exception) { return false; }
        }

        public static Result Install(Package pkg, string gameDir)
        {
            var exe = GameExe(gameDir, strict: false);
            if (exe == null) return Result.Fail($"{gameDir} doesn't look like a Unity game folder (no game .exe next to UnityPlayer.dll).");
            if (IsRunning(exe)) return Result.Fail($"{Path.GetFileName(exe)} is running. Close the game and run the installer again.");

            bool mono = Directory.Exists(Path.Combine(gameDir, "MonoBleedingEdge")) || Directory.Exists(Path.Combine(gameDir, "Mono"));
            if (!mono && File.Exists(Path.Combine(gameDir, "GameAssembly.dll")))
                return Result.Fail("This build of the game uses IL2CPP, which this version of BepInEx can't load.");

            var arch = Machine(exe) ?? "x64";
            string winhttp;
            if (arch == "x86")
            {
                if (pkg.Winhttp86 == null) return Result.Fail("This is a 32-bit game, and this download has no 32-bit loader.");
                winhttp = pkg.Winhttp86;
            }
            else if (arch == "x64") winhttp = pkg.Winhttp64;
            else return Result.Fail($"This game is built for {arch}, which BepInEx 5 doesn't support.");

            try
            {
                CopyFile(winhttp, Path.Combine(gameDir, "winhttp.dll"));
                CopyFile(Path.Combine(pkg.Root, "doorstop_config.ini"), Path.Combine(gameDir, "doorstop_config.ini"));
                var ver = Path.Combine(pkg.Root, ".doorstop_version");
                if (File.Exists(ver)) CopyFile(ver, Path.Combine(gameDir, ".doorstop_version"));
                CopyBepInEx(Path.Combine(pkg.Root, "BepInEx"), Path.Combine(gameDir, "BepInEx"));
                EnsureHiddenManager(Path.Combine(gameDir, "BepInEx", "config", "BepInEx.cfg"));
            }
            catch (UnauthorizedAccessException)
            {
                return Result.Fail("Windows didn't allow writing to the game folder. Right-click the installer and choose Run as administrator.");
            }
            catch (IOException e)
            {
                return Result.Fail($"Couldn't copy a file ({e.Message}). If the game is open, close it and try again.");
            }
            return Result.Done($"Installed into {gameDir} ({(arch == "x86" ? "32-bit" : "64-bit")}).");
        }

        public static Result Uninstall(string gameDir)
        {
            try
            {
                var exe = GameExe(gameDir, strict: false);
                if (exe != null && IsRunning(exe)) return Result.Fail($"{Path.GetFileName(exe)} is running. Close the game first.");
                var bep = Path.Combine(gameDir, "BepInEx");
                var plugins = Path.Combine(bep, "plugins");
                var ours = Path.Combine(plugins, PluginFolder);
                if (Directory.Exists(ours)) Directory.Delete(ours, true);

                // Leave BepInEx alone if other mods use it.
                bool others = Directory.Exists(plugins) && Directory.EnumerateFileSystemEntries(plugins).Any();
                if (others)
                    return Result.Done($"Removed House Edge from {gameDir}. Other mods are still installed there, so BepInEx stays.");
                foreach (var f in new[] { "winhttp.dll", "doorstop_config.ini", ".doorstop_version" })
                {
                    var p = Path.Combine(gameDir, f);
                    if (File.Exists(p)) File.Delete(p);
                }
                if (Directory.Exists(bep)) Directory.Delete(bep, true);
                return Result.Done($"Removed House Edge and BepInEx from {gameDir}. The game is back to normal.");
            }
            catch (Exception e) { return Result.Fail($"Couldn't remove everything ({e.Message}). Close the game and try again."); }
        }

        private static void CopyFile(string from, string to)
        {
            if (string.Equals(Path.GetFullPath(from), Path.GetFullPath(to), StringComparison.OrdinalIgnoreCase)) return; // unzipped straight into the game folder
            Directory.CreateDirectory(Path.GetDirectoryName(to));
            File.Copy(from, to, true);
        }

        /// <summary>Copies the BepInEx folder. Keeps the player's own settings and pins in BepInEx/config. Skips the 32-bit loader.</summary>
        private static void CopyBepInEx(string from, string to)
        {
            foreach (var file in Directory.GetFiles(from, "*", SearchOption.AllDirectories))
            {
                var rel = file.Substring(from.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                var top = rel.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)[0];
                if (string.Equals(top, Package.X86Folder, StringComparison.OrdinalIgnoreCase)) continue;
                var dest = Path.Combine(to, rel);
                if (string.Equals(top, "config", StringComparison.OrdinalIgnoreCase) && File.Exists(dest)) continue;
                CopyFile(file, dest);
            }
        }

        /// <summary>Some games clean up objects they don't recognise, which would remove the menu. BepInEx can hide its object from them.</summary>
        public static void EnsureHiddenManager(string cfg)
        {
            var text = File.Exists(cfg) ? File.ReadAllText(cfg) : "";
            var line = new Regex(@"^([ \t]*HideManagerGameObject[ \t]*=[ \t]*)[^\r\n]*", RegexOptions.Multiline);
            if (line.IsMatch(text)) text = line.Replace(text, "${1}true");
            else if (Regex.IsMatch(text, @"^\[Chainloader\][ \t]*\r?$", RegexOptions.Multiline))
                text = Regex.Replace(text, @"^\[Chainloader\][ \t]*(\r?)$", "[Chainloader]$1\nHideManagerGameObject = true$1", RegexOptions.Multiline);
            else text = text.TrimEnd() + (text.Length > 0 ? "\n\n" : "") + "[Chainloader]\nHideManagerGameObject = true\n";
            Directory.CreateDirectory(Path.GetDirectoryName(cfg));
            File.WriteAllText(cfg, text);
        }
    }
}
