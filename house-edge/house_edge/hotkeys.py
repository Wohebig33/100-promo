"""Global hotkeys, so mods can be toggled while the game has focus.

Windows: polls GetAsyncKeyState about 30 times a second. That needs no window or message loop, and it
doesn't steal the key from the game. Other platforms: hotkeys are off and the panel buttons still work.

Combos look like "F1", "Ctrl+F2", "Shift+Num5" or "Alt+K".
"""
from __future__ import annotations

import sys
import threading
import time

SUPPORTED = sys.platform == "win32"

VK = {**{f"F{i}": 0x6F + i for i in range(1, 13)},
      **{f"Num{i}": 0x60 + i for i in range(10)},
      **{str(i): 0x30 + i for i in range(10)},
      **{chr(c): c for c in range(0x41, 0x5B)}}
MOD_VK = {"Ctrl": 0x11, "Shift": 0x10, "Alt": 0x12}


def parse(combo: str):
    """'Ctrl+F1' -> (frozenset({'Ctrl'}), 0x70). Returns None for anything unsupported."""
    if not combo:
        return None
    parts = [p.strip() for p in combo.split("+") if p.strip()]
    if not parts:
        return None
    key = parts[-1]
    key = key.upper() if len(key) == 1 else key[0].upper() + key[1:]
    mods = set()
    for p in parts[:-1]:
        p = p.capitalize()
        if p == "Control":
            p = "Ctrl"
        if p not in MOD_VK:
            return None
        mods.add(p)
    if key not in VK:
        return None
    return frozenset(mods), VK[key]


class HotkeyThread(threading.Thread):
    def __init__(self, get_bindings, on_fire, enabled):
        """get_bindings() -> {combo: id}; on_fire(id) runs on this thread; enabled() -> bool."""
        super().__init__(daemon=True, name="hotkeys")
        self.get_bindings = get_bindings
        self.on_fire = on_fire
        self.enabled = enabled
        self.down: set[str] = set()

    def run(self):
        if not SUPPORTED:
            return
        import ctypes
        user32 = ctypes.WinDLL("user32")
        gaks = user32.GetAsyncKeyState
        gaks.restype = ctypes.c_short
        gaks.argtypes = [ctypes.c_int]
        pressed = lambda vk: bool(gaks(vk) & 0x8000)  # noqa: E731
        while True:
            time.sleep(0.03)
            try:
                if not self.enabled():
                    self.down.clear()
                    continue
                held_mods = {m for m, vk in MOD_VK.items() if pressed(vk)}
                for combo, target in list(self.get_bindings().items()):
                    parsed = parse(combo)
                    if not parsed:
                        continue
                    need, vk = parsed
                    active = pressed(vk) and held_mods == set(need)
                    if active and combo not in self.down:
                        self.down.add(combo)
                        self.on_fire(target)
                    elif not active:
                        self.down.discard(combo)
            except Exception:  # noqa: BLE001 - a bad binding must never kill the thread
                continue
