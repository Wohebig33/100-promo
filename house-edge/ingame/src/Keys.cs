using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using UnityEngine;

namespace HouseEdgeInGame
{
    /// <summary>
    /// Reads keys for hotkeys like "Q+E" or "Ctrl+F1".
    /// It asks Windows directly (GetAsyncKeyState), which works whether the game uses Unity's old or new
    /// input system. If that isn't available, it falls back to Unity's legacy Input class.
    /// </summary>
    internal static class Keys
    {
        [DllImport("user32.dll")]
        private static extern short GetAsyncKeyState(int vKey);

        private static bool _win32 = true;

        private static readonly Dictionary<string, int> Vk = BuildVk();
        private static readonly Dictionary<string, int> ModVk = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        {
            { "Ctrl", 0x11 }, { "Control", 0x11 }, { "Shift", 0x10 }, { "Alt", 0x12 },
        };

        private static Dictionary<string, int> BuildVk()
        {
            var d = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            for (int i = 1; i <= 12; i++) d["F" + i] = 0x6F + i;
            for (int i = 0; i <= 9; i++) { d["Num" + i] = 0x60 + i; d[i.ToString()] = 0x30 + i; }
            for (char c = 'A'; c <= 'Z'; c++) d[c.ToString()] = c;
            return d;
        }

        public static bool IsDown(int vk)
        {
            if (_win32)
            {
                try { return (GetAsyncKeyState(vk) & 0x8000) != 0; }
                catch (Exception) { _win32 = false; } // not on Windows: use Unity's Input below
            }
            try { return Input.GetKey(ToKeyCode(vk)); }
            catch (Exception) { return false; } // the game only has the new Input System
        }

        private static KeyCode ToKeyCode(int vk)
        {
            if (vk >= 'A' && vk <= 'Z') return KeyCode.A + (vk - 'A');
            if (vk >= 0x30 && vk <= 0x39) return KeyCode.Alpha0 + (vk - 0x30);
            if (vk >= 0x60 && vk <= 0x69) return KeyCode.Keypad0 + (vk - 0x60);
            if (vk >= 0x70 && vk <= 0x7B) return KeyCode.F1 + (vk - 0x70);
            if (vk == 0x11) return KeyCode.LeftControl;
            if (vk == 0x10) return KeyCode.LeftShift;
            if (vk == 0x12) return KeyCode.LeftAlt;
            return KeyCode.None;
        }

        /// <summary>Parses "Q+E", "Ctrl+F1", "Shift+Num5". One or two main keys, plus any of Ctrl/Shift/Alt.</summary>
        public static Chord Parse(string combo)
        {
            if (string.IsNullOrEmpty(combo)) return null;
            var mods = new List<int>();
            var keys = new List<int>();
            foreach (var raw in combo.Split('+'))
            {
                var p = raw.Trim();
                if (p.Length == 0) continue;
                if (ModVk.TryGetValue(p, out var m)) { if (!mods.Contains(m)) mods.Add(m); continue; }
                if (!Vk.TryGetValue(p, out var k) || keys.Contains(k)) return null;
                keys.Add(k);
            }
            if (keys.Count < 1 || keys.Count > 2) return null;
            return new Chord(combo, mods.ToArray(), keys.ToArray());
        }
    }

    internal sealed class Chord
    {
        private static readonly int[] AllMods = { 0x10, 0x11, 0x12 };
        public readonly string Text;
        private readonly int[] _mods;
        private readonly int[] _keys;
        private bool _wasDown;

        public Chord(string text, int[] mods, int[] keys) { Text = text; _mods = mods; _keys = keys; }

        /// <summary>True once each time the whole combo goes down.</summary>
        public bool Pressed()
        {
            bool down = _keys.All(Keys.IsDown) && AllMods.All(m => Keys.IsDown(m) == _mods.Contains(m));
            bool fire = down && !_wasDown;
            _wasDown = down;
            return fire;
        }
    }
}
