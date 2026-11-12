using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using UnityEngine;
using UObject = UnityEngine.Object;

namespace HouseEdgeInGame
{
    /// <summary>
    /// Which build of the game this is: full game or demo, its version, Unity version and 32/64-bit.
    /// The plugin itself doesn't depend on any of it. It's shown in the menu and the log so problems are easy to report.
    /// </summary>
    internal static class GameInfo
    {
        public static string Name => Safe(() => Application.productName, "this game");
        public static string Version => Safe(() => Application.version, "?");
        public static string Unity => Safe(() => Application.unityVersion, "?");
        public static string Bits => IntPtr.Size == 8 ? "64-bit" : "32-bit";

        public static string Exe => Safe(() => Path.GetFileName(System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName), "?");

        public static bool IsDemo
        {
            get
            {
                var text = Name + " " + Exe + " " + Safe(() => Application.dataPath, "");
                return text.IndexOf("demo", StringComparison.OrdinalIgnoreCase) >= 0;
            }
        }

        public static string Summary => $"{Name} {Version}{(IsDemo ? " (demo)" : "")}, Unity {Unity}, {Bits}, {Exe}";

        private static string Safe(Func<string> f, string fallback)
        {
            try { var s = f(); return string.IsNullOrEmpty(s) ? fallback : s; } catch (Exception) { return fallback; }
        }
    }

    /// <summary>Unity calls that changed between Unity versions, with a fallback for each.</summary>
    internal static class Compat
    {
        private static bool _noFindObjects;

        /// <summary>Every live object of a type in the open scenes. Works on old Unity and on Unity 6, where FindObjectsOfType is on its way out.</summary>
        public static UObject[] FindAll(Type t)
        {
            if (!_noFindObjects)
            {
                try { return FindObjectsOfTypeDirect(t); }
                catch (MissingMethodException) { _noFindObjects = true; }
            }
            return Resources.FindObjectsOfTypeAll(t).Where(InScene).ToArray();
        }

        // Kept in its own method: if a future Unity removes FindObjectsOfType, only this method fails to compile at runtime, and FindAll catches that.
        [MethodImpl(MethodImplOptions.NoInlining)]
        private static UObject[] FindObjectsOfTypeDirect(Type t) => UObject.FindObjectsOfType(t);

        private static bool InScene(UObject o)
        {
            if (o == null) return false;
            if (o is Component c) return c.gameObject != null && c.gameObject.scene.IsValid() && c.gameObject.activeInHierarchy;
            return true;
        }
    }
}
