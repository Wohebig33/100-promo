using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace HouseEdgeInstaller
{
    /// <summary>
    /// Install House Edge.exe: double-click it and it puts House Edge into We're All In.
    ///   Finds the game in every Steam library (full game and demo), or uses the folder it was dropped into.
    ///   Picks the 32-bit or 64-bit loader to match the game.
    ///   Keeps your settings and pins when updating. Run it again to update or uninstall.
    /// Drag a game folder onto it to install somewhere else.
    /// Command line: [folder...] [--uninstall] [--yes]
    /// </summary>
    internal static class Program
    {
        private static bool _yes;

        private static int Main(string[] args)
        {
            _yes = args.Contains("--yes");
            bool uninstall = args.Contains("--uninstall");
            var paths = args.Where(a => !a.StartsWith("--")).ToList();
            int code;
            try { code = Run(paths, uninstall); }
            catch (Exception e) { Say("Something went wrong: " + e.Message); code = 1; }
            if (!_yes) { Console.WriteLine(); Console.Write("Press Enter to close."); Console.ReadLine(); }
            return code;
        }

        private static int Run(List<string> paths, bool uninstall)
        {
            Console.Title = "House Edge installer";
            Say("HOUSE EDGE: mod menu for We're All In");
            Say("");

            var self = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
            var pkg = Package.Find(self);
            if (pkg == null && !uninstall)
            {
                Say("The download isn't unzipped yet, so the installer can't find the files it needs.");
                Say("Right-click the zip you downloaded, choose Extract All, then open the new folder and run Install House Edge.exe from there.");
                return 1;
            }

            var games = new List<string>();
            foreach (var p in paths)
            {
                var d = Core.GameDirFromInput(p);
                if (d == null) Say($"Skipping {p}: no game found there.");
                else if (!games.Contains(d, StringComparer.OrdinalIgnoreCase)) games.Add(d);
            }
            if (games.Count == 0)
            {
                Say("Looking for We're All In...");
                games = Core.FindGames(self, SteamRoots());
            }
            while (games.Count == 0)
            {
                Say("");
                Say("Couldn't find We're All In by itself.");
                Say("In Steam, right-click the game and choose Manage > Browse local files.");
                Say("Then drag that folder (or WereAllIn.exe) into this window and press Enter. Press Enter on its own to quit.");
                if (_yes) return 1;
                Console.Write("> ");
                var line = Console.ReadLine();
                if (string.IsNullOrWhiteSpace(line)) return 1;
                var d = Core.GameDirFromInput(line);
                if (d != null) games.Add(d);
                else Say("That isn't a game folder. Look for the folder with WereAllIn.exe and UnityPlayer.dll in it.");
            }

            Say("");
            foreach (var g in games) Say($"Found: {g}{(Core.IsInstalled(g) ? "   (House Edge is already installed)" : "")}");
            Say("");

            if (!uninstall && games.Any(Core.IsInstalled) && !_yes)
            {
                Say("Press Enter to update House Edge, or type U and press Enter to uninstall it.");
                Console.Write("> ");
                uninstall = (Console.ReadLine() ?? "").Trim().Equals("u", StringComparison.OrdinalIgnoreCase);
            }

            bool allOk = true;
            foreach (var g in games)
            {
                var r = uninstall ? Core.Uninstall(g) : Core.Install(pkg, g);
                Say((r.Ok ? "OK    " : "ERROR ") + r.Message);
                allOk &= r.Ok;
            }

            Say("");
            if (!allOk) Say("Not everything worked. The lines above say why.");
            else if (uninstall) Say("Done.");
            else
            {
                Say("Done. Start the game from Steam and hold Q + E together for the menu.");
                Say("The first start takes a little longer while BepInEx sets itself up.");
            }
            return allOk ? 0 : 1;
        }

        /// <summary>Where Steam is installed, from the registry, plus the usual default folders.</summary>
        private static IEnumerable<string> SteamRoots()
        {
            var roots = new List<string>();
            void Reg(string key, string value)
            {
                try { if (Microsoft.Win32.Registry.GetValue(key, value, null) is string s && s.Length > 0) roots.Add(s.Replace('/', '\\')); }
                catch (Exception) { }
            }
            Reg(@"HKEY_CURRENT_USER\Software\Valve\Steam", "SteamPath");
            Reg(@"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath");
            Reg(@"HKEY_LOCAL_MACHINE\SOFTWARE\Valve\Steam", "InstallPath");
            foreach (var env in new[] { "ProgramFiles(x86)", "ProgramFiles" })
            {
                var pf = Environment.GetEnvironmentVariable(env);
                if (!string.IsNullOrEmpty(pf)) roots.Add(Path.Combine(pf, "Steam"));
            }
            return roots;
        }

        private static void Say(string s) => Console.WriteLine(s);
    }
}
