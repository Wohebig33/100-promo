"""Mods: the cheats shown in the panel.

Each mod points at one value in the game's memory:
  - module + offset (+ an optional pointer chain). This survives restarting the game, or
  - an absolute address from the value finder. Heap addresses change every launch, so these
    are tied to the process they were found in and marked "stale" after a restart.

This file also handles Cheat Engine table (.CT) import and saving profiles to disk.
"""
from __future__ import annotations

import json
import os
import re
import sys
import uuid
import xml.etree.ElementTree as ET

from . import scanner
from .memory import read_pointer

# ---------------------------------------------------------------- storage
def data_dir() -> str:
    if sys.platform == "win32":
        root = os.environ.get("APPDATA") or os.path.expanduser("~")
        path = os.path.join(root, "HouseEdge")
    else:
        root = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
        path = os.path.join(root, "house-edge")
    os.makedirs(os.path.join(path, "profiles"), exist_ok=True)
    return path


def _safe(name: str) -> str:
    return re.sub(r"[^a-z0-9._-]+", "_", name.lower()) or "default"


def load_json(path: str, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json(path: str, data) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)


def profile_path(exe: str) -> str:
    return os.path.join(data_dir(), "profiles", _safe(exe) + ".json")


def load_profile(exe: str) -> list[dict]:
    return [normalize(m) for m in load_json(profile_path(exe), {"mods": []}).get("mods", [])]


def save_profile(exe: str, mods: list[dict]) -> None:
    keep = [{k: v for k, v in m.items() if not k.startswith("_")} for m in mods]
    save_json(profile_path(exe), {"game": exe, "mods": keep})


# ---------------------------------------------------------------- model
def default_presets(t: str) -> list[str]:
    return ["+10", "x2", "999"] if scanner.is_float(t) else ["+100", "x2", "9999"]


def normalize(m: dict) -> dict:
    t = m.get("type") if m.get("type") in scanner.TYPES else "int32"
    return {
        "id": m.get("id") or uuid.uuid4().hex[:10],
        "name": str(m.get("name") or "New mod")[:60],
        "category": str(m.get("category") or "Mods")[:40],
        "type": t,
        "module": m.get("module") or None,
        "base": int(m.get("base") or 0),
        "offsets": [int(o) for o in (m.get("offsets") or [])],
        "session": m.get("session"),          # pid it was found in, if the address is only valid for that run
        "locked": bool(m.get("locked", False)),
        "lockValue": m.get("lockValue"),
        "hotkey": m.get("hotkey") or None,
        "presets": list(m.get("presets") or default_presets(t))[:4],
        "party": bool(m.get("party", True)),
    }


def describe_address(m: dict) -> str:
    s = f'{m["module"]}+{m["base"]:X}' if m["module"] else f'{m["base"]:X}'
    for o in m["offsets"]:
        s = f"[{s}]+{o:X}"
    return s


def from_absolute(proc, addr: int, modules) -> dict:
    """Turn a found address into a mod. Static addresses inside a module are saved relative to it so they work next launch too."""
    for mod in modules:
        if mod.base <= addr < mod.base + mod.size:
            return {"module": mod.name, "base": addr - mod.base, "offsets": [], "session": None}
    return {"module": None, "base": addr, "offsets": [], "session": proc.pid}


def resolve(proc, m: dict, modules) -> int | None:
    if m.get("session") and m["session"] != proc.pid:
        return None
    if m["module"]:
        mod = next((x for x in modules if x.name.lower() == m["module"].lower()), None)
        if not mod:
            return None
        addr = mod.base + m["base"]
    else:
        addr = m["base"]
    for off in m["offsets"]:
        ptr = read_pointer(proc, addr)
        if not ptr:
            return None
        addr = ptr + off
    return addr


def read_value(proc, m: dict, modules):
    addr = resolve(proc, m, modules)
    if addr is None:
        return None
    data = proc.read(addr, scanner.TYPES[m["type"]][1])
    return scanner.unpack(m["type"], data) if data else None


def write_value(proc, m: dict, modules, value) -> bool:
    addr = resolve(proc, m, modules)
    if addr is None:
        return False
    return proc.write(addr, scanner.pack(m["type"], value))


def apply_preset(current, preset: str, t: str):
    """Presets: "+N" adds, "-N" subtracts, "xN" multiplies, anything else sets that value."""
    p = preset.strip().lower().replace("×", "x")
    num = float if scanner.is_float(t) else (lambda s: int(float(s)))
    if p.startswith("x"):
        return num(str((current or 0) * float(p[1:])))
    if p.startswith("+") or (p.startswith("-") and current is not None):
        return num(str((current or 0) + float(p)))
    return num(p)


# ---------------------------------------------------------------- Cheat Engine tables
CE_TYPES = {"byte": "byte", "2 bytes": "int16", "4 bytes": "int32", "8 bytes": "int64", "float": "float", "double": "double"}
VK_NAMES = {**{112 + i: f"F{i + 1}" for i in range(12)}, **{96 + i: f"Num{i}" for i in range(10)},
            **{48 + i: str(i) for i in range(10)}, **{65 + i: chr(65 + i) for i in range(26)}}
VK_MODS = {16: "Shift", 17: "Ctrl", 18: "Alt"}


def import_ct(xml_text: str) -> tuple[list[dict], int]:
    """Import simple entries from a Cheat Engine table. Returns (mods, skipped count).

    Entries that are addresses (module+offset or hex, optionally with pointer offsets) come across.
    Auto Assembler scripts, strings, byte arrays and symbol-based addresses are skipped, because they need Cheat Engine itself.
    """
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError as e:
        raise ValueError(f"That doesn't look like a Cheat Engine table ({e}).") from e
    mods: list[dict] = []
    skipped = 0

    def walk(entries, category):
        nonlocal skipped
        if entries is None:
            return
        for e in entries.findall("CheatEntry"):
            desc = (e.findtext("Description") or "").strip().strip('"') or "Unnamed"
            vtype = (e.findtext("VariableType") or "").strip().lower()
            addr_text = (e.findtext("Address") or "").strip()
            children = e.find("CheatEntries")
            if vtype in CE_TYPES and addr_text:
                parsed = _parse_ce_address(addr_text)
                if parsed:
                    module, base = parsed
                    offs = [int((o.text or "0").strip(), 16) for o in e.findall("Offsets/Offset")]
                    offs.reverse()  # Cheat Engine stores the last offset first
                    mods.append(normalize({
                        "name": desc, "category": category, "type": CE_TYPES[vtype],
                        "module": module, "base": base, "offsets": offs, "hotkey": _ce_hotkey(e),
                    }))
                else:
                    skipped += 1
            elif vtype or e.find("AssemblerScript") is not None:
                skipped += 1
            walk(children, desc if children is not None and not vtype else category)

    walk(root.find("CheatEntries"), "Imported")
    return mods, skipped


def _parse_ce_address(text: str):
    t = text.replace(" ", "")
    m = re.fullmatch(r'"?([^"+\[\]]+?\.(?:exe|dll))"?\+([0-9A-Fa-f]+)', t, re.I)
    if m:
        return m.group(1), int(m.group(2), 16)
    if re.fullmatch(r"[0-9A-Fa-f]{4,16}", t):
        return None, int(t, 16)
    return None


def _ce_hotkey(entry) -> str | None:
    for hk in entry.findall("Hotkeys/Hotkey"):
        keys = [int(k.text) for k in hk.findall("Keys/Key") if (k.text or "").strip().isdigit()]
        mods = [VK_MODS[k] for k in keys if k in VK_MODS]
        main = [VK_NAMES[k] for k in keys if k in VK_NAMES]
        if len(main) == 1:
            return "+".join(mods + main)
    return None
