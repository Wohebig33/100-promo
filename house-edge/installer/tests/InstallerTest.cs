using System;
using System.IO;
using System.Linq;
using HouseEdgeInstaller;

internal static class Program
{
    private static int _passed, _failed;
    private static string _tmp;

    private static void Check(string name, bool ok)
    {
        if (ok) _passed++; else _failed++;
        Console.WriteLine($"{(ok ? "PASS" : "FAIL")}  {name}");
    }

    // A file with just enough of a Windows PE header to say which CPU it's for.
    private static void Pe(string path, ushort machine, string tag = "")
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        var b = new byte[0x60];
        b[0] = (byte)'M'; b[1] = (byte)'Z';
        BitConverter.GetBytes(0x40).CopyTo(b, 0x3C);
        b[0x40] = (byte)'P'; b[0x41] = (byte)'E';
        BitConverter.GetBytes(machine).CopyTo(b, 0x44);
        File.WriteAllBytes(path, b.Concat(System.Text.Encoding.ASCII.GetBytes(tag)).ToArray());
    }

    private static string Game(string dir, string exe, ushort machine = 0x8664, bool il2cpp = false)
    {
        Pe(Path.Combine(dir, exe + ".exe"), machine);
        Pe(Path.Combine(dir, "UnityCrashHandler64.exe"), machine);
        File.WriteAllText(Path.Combine(dir, "UnityPlayer.dll"), "");
        Directory.CreateDirectory(Path.Combine(dir, exe + "_Data", "Managed"));
        if (il2cpp) File.WriteAllText(Path.Combine(dir, "GameAssembly.dll"), "");
        else Directory.CreateDirectory(Path.Combine(dir, "MonoBleedingEdge"));
        return dir;
    }

    private static string MakePackage(string dir)
    {
        Pe(Path.Combine(dir, "winhttp.dll"), 0x8664, "loader64");
        Pe(Path.Combine(dir, "BepInEx", Package.X86Folder, "winhttp.dll"), 0x014C, "loader32");
        File.WriteAllText(Path.Combine(dir, "doorstop_config.ini"), "[General]\nenabled=true\n");
        File.WriteAllText(Path.Combine(dir, ".doorstop_version"), "4");
        File.WriteAllText(Path.Combine(dir, "BepInEx", "core", "BepInEx.dll").Also(Dir), "core");
        File.WriteAllText(Path.Combine(dir, "BepInEx", "plugins", "HouseEdgeInGame", "HouseEdgeInGame.dll").Also(Dir), "plugin v2");
        File.WriteAllText(Path.Combine(dir, "BepInEx", "config", "BepInEx.cfg").Also(Dir), "[Chainloader]\r\nHideManagerGameObject = true\r\n");
        File.WriteAllText(Path.Combine(dir, "HOUSE EDGE - READ ME.txt"), "readme");
        File.WriteAllText(Path.Combine(dir, "Install House Edge.exe"), "installer");
        return dir;
    }

    private static string Also(this string path, Action<string> f) { f(path); return path; }
    private static void Dir(string file) => Directory.CreateDirectory(Path.GetDirectoryName(file));
    private static string Read(params string[] parts) => File.ReadAllText(Path.Combine(parts));
    private static bool Has(params string[] parts) => File.Exists(Path.Combine(parts)) || Directory.Exists(Path.Combine(parts));

    private static int Main()
    {
        _tmp = Path.Combine(Path.GetTempPath(), "he-installer-test-" + Guid.NewGuid().ToString("N"));
        try { Tests(); }
        finally { try { Directory.Delete(_tmp, true); } catch (Exception) { } }
        Console.WriteLine($"{_passed} passed, {_failed} failed");
        return _failed == 0 ? 0 : 1;
    }

    private static void Tests()
    {
        // Steam with two libraries: the full game in one, the demo and another game in the other. Old- and new-style vdf entries.
        var steam = Path.Combine(_tmp, "Steam");
        var lib2 = Path.Combine(_tmp, "SteamLibrary");
        var full = Game(Path.Combine(steam, "steamapps", "common", "We're All In"), "WereAllIn");
        var demo = Game(Path.Combine(lib2, "steamapps", "common", "WereAllInDemo"), "WereAllIn");
        Game(Path.Combine(lib2, "steamapps", "common", "Other Game"), "OtherGame");
        File.WriteAllText(Path.Combine(steam, "steamapps", "libraryfolders.vdf"),
            "\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"" + steam.Replace("\\", "\\\\") + "\"\n\t\t\"apps\"\n\t\t{\n\t\t\t\"228980\"\t\t\"1234\"\n\t\t}\n\t}\n" +
            "\t\"1\"\n\t{\n\t\t\"path\"\t\t\"" + lib2.Replace("\\", "\\\\") + "\"\n\t}\n}\n");

        var downloads = MakePackage(Path.Combine(_tmp, "Downloads", "HouseEdge-InGame"));
        var pkg = Package.Find(downloads);
        Check("package found in the unzipped folder, with both loaders", pkg != null && pkg.Winhttp86 != null);
        Check("not unzipped (exe run from inside the zip): no package", Package.Find(Path.Combine(_tmp, "Temp").Also(d => Directory.CreateDirectory(d))) == null);

        var found = Core.FindGames(downloads, new[] { steam, Path.Combine(_tmp, "no-such-steam") });
        Check("finds the full game and the demo across Steam libraries", found.Count == 2 && found.Any(f => f.EndsWith("We're All In")) && found.Any(f => f.EndsWith("WereAllInDemo")));
        Check("ignores other Unity games when searching", !found.Any(f => f.EndsWith("Other Game")));

        // Whole download folder dropped into the demo folder: install goes there, nowhere else.
        var nested = MakePackage(Path.Combine(demo, "HouseEdge-InGame"));
        var here = Core.FindGames(nested, new[] { steam });
        Check("download folder dropped inside the game folder: uses that game", here.Count == 1 && here[0] == Path.GetFullPath(demo));

        Check("reads 64-bit and 32-bit headers", Core.Machine(Path.Combine(full, "WereAllIn.exe")) == "x64" && Core.Machine(pkg.Winhttp86) == "x86");

        // Install into the full game.
        var r = Core.Install(pkg, full);
        Check("install 64-bit: " + r.Message, r.Ok);
        Check("64-bit loader next to the exe", Read(full, "winhttp.dll").EndsWith("loader64"));
        Check("doorstop config, BepInEx core and plugin copied", Has(full, "doorstop_config.ini") && Has(full, ".doorstop_version") && Has(full, "BepInEx", "core", "BepInEx.dll") && Read(full, "BepInEx", "plugins", "HouseEdgeInGame", "HouseEdgeInGame.dll") == "plugin v2");
        Check("installer, readme and 32-bit loader stay out of the game folder", !Has(full, "Install House Edge.exe") && !Has(full, "HOUSE EDGE - READ ME.txt") && !Has(full, "BepInEx", Package.X86Folder));
        Check("reports installed", Core.IsInstalled(full));

        // Update: keeps the player's pins and settings, still hides the manager object.
        File.WriteAllText(Path.Combine(full, "BepInEx", "config", "houseedge.ingame.pins.txt"), "my pins");
        File.WriteAllText(Path.Combine(full, "BepInEx", "config", "BepInEx.cfg"), "[Logging]\r\nUnityLogListening = true\r\n\r\n[Chainloader]\r\nHideManagerGameObject = false\r\n");
        File.WriteAllText(Path.Combine(full, "BepInEx", "config", "houseedge.ingame.cfg"), "MenuKeys = F1");
        r = Core.Install(pkg, full);
        var cfg = Read(full, "BepInEx", "config", "BepInEx.cfg");
        Check("update: " + r.Message, r.Ok);
        Check("update keeps pins and the player's menu keys", Read(full, "BepInEx", "config", "houseedge.ingame.pins.txt") == "my pins" && Read(full, "BepInEx", "config", "houseedge.ingame.cfg") == "MenuKeys = F1");
        Check("update keeps BepInEx settings but turns HideManagerGameObject on", cfg.Contains("UnityLogListening = true") && cfg.Contains("HideManagerGameObject = true\r\n") && !cfg.Contains("false"));

        // 32-bit game gets the 32-bit loader.
        var old = Game(Path.Combine(_tmp, "OldBuild"), "WereAllIn", machine: 0x014C);
        r = Core.Install(pkg, old);
        Check("install 32-bit: " + r.Message, r.Ok && Read(old, "winhttp.dll").EndsWith("loader32"));

        // Download unzipped straight into the game folder: running the installer from there still works.
        var direct = Game(Path.Combine(_tmp, "Direct"), "WereAllIn");
        MakePackage(direct);
        r = Core.Install(Package.Find(direct), direct);
        Check("unzipped straight into the game folder: " + r.Message, r.Ok && Core.IsInstalled(direct));

        // IL2CPP build: refuse with a clear reason.
        var il = Game(Path.Combine(_tmp, "Il2cpp"), "WereAllIn", il2cpp: true);
        r = Core.Install(pkg, il);
        Check("IL2CPP build refused: " + r.Message, !r.Ok && !Has(il, "winhttp.dll"));

        // Typed or dragged-in paths.
        Check("dragged-in exe path with quotes", Core.GameDirFromInput("\"" + Path.Combine(full, "WereAllIn.exe") + "\"") == Path.GetFullPath(full));
        Check("a folder inside the game folder", Core.GameDirFromInput(Path.Combine(full, "WereAllIn_Data", "Managed")) == Path.GetFullPath(full));
        Check("not a game folder", Core.GameDirFromInput(_tmp) == null);

        // Uninstall: everything goes when House Edge is the only mod.
        r = Core.Uninstall(full);
        Check("uninstall: " + r.Message, r.Ok && !Has(full, "winhttp.dll") && !Has(full, "doorstop_config.ini") && !Has(full, "BepInEx") && Has(full, "WereAllIn.exe"));

        // Uninstall with another mod installed: BepInEx stays.
        Core.Install(pkg, old);
        File.WriteAllText(Path.Combine(old, "BepInEx", "plugins", "SomeOtherMod.dll"), "");
        r = Core.Uninstall(old);
        Check("uninstall keeps BepInEx for other mods: " + r.Message, r.Ok && Has(old, "winhttp.dll") && Has(old, "BepInEx", "plugins", "SomeOtherMod.dll") && !Core.IsInstalled(old));
    }
}
