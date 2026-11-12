"""Global hotkeys, so mods can be toggled while the game has focus.

Windows: polls GetAsyncKeyState about 30 times a second. That needs no window or message loop, and it
doesn't steal the key from the game. Other platforms: hotkeys are off and the panel buttons still work.

Combos look like "F1", "Ctrl+F2", "Shift+Num5", "Alt+K", or two keys held together like "Q+E".
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
    """'Ctrl+F1' -> (frozenset({'Ctrl'}), (0x70,)); 'Q+E' -> (frozenset(), (0x51, 0x45)).

    Ctrl, Shift and Alt can go with one or two other keys. Returns None for anything unsupported.
    """
    if not combo:
        return None
    parts = [p.strip() for p in combo.split("+") if p.strip()]
    mods, keys = set(), []
    for p in parts:
        cap = p.capitalize()
        if cap == "Control":
            cap = "Ctrl"
        if cap in MOD_VK:
            mods.add(cap)
            continue
        key = p.upper() if len(p) == 1 else p[0].upper() + p[1:]
        if key not in VK or VK[key] in keys:
            return None
        keys.append(VK[key])
    if not 1 <= len(keys) <= 2:
        return None
    return frozenset(mods), tuple(keys)


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
                    need, vks = parsed
                    active = all(pressed(vk) for vk in vks) and held_mods == set(need)
                    if active and combo not in self.down:
                        self.down.add(combo)
                        self.on_fire(target)
                    elif not active:
                        self.down.discard(combo)
            except Exception:  # noqa: BLE001 - a bad binding must never kill the thread
                continue
