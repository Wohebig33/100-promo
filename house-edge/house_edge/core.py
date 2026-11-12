"""House Edge core: attaching to the game, the lock loop, hotkeys, and the local API the panel talks to."""
from __future__ import annotations

import json
import os
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from . import hotkeys, mods as M, scanner
from .memory import MemoryError_, Process, list_processes

UI_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui")
DEFAULT_SETTINGS = {
    "autoAttach": "",      # exe name to attach to as soon as it launches
    "onTop": True,         # keep the panel above the game
    "sounds": True,
    "hotkeys": True,
    "partyEvery": 20,      # seconds between Party Mode surprises
}


class Core:
    def __init__(self):
        self.lock = threading.RLock()
        self.dir = M.data_dir()
        self.settings = {**DEFAULT_SETTINGS, **M.load_json(os.path.join(self.dir, "settings.json"), {})}
        self.proc: Process | None = None
        self.game = ""
        self.modules = []
        self.mods: list[dict] = []
        self.scanner = scanner.Scanner()
        self.events: list[dict] = []
        self.seq = 0
        self.window = None  # set by app.py when a pywebview window is open
        threading.Thread(target=self._watch_loop, daemon=True, name="watch").start()
        threading.Thread(target=self._lock_loop, daemon=True, name="locks").start()
        hotkeys.HotkeyThread(self._bindings, self._hotkey, lambda: self.settings["hotkeys"] and self.proc is not None).start()

    # ------------------------------------------------------------ events (toasts in the panel)
    def emit(self, kind: str, text: str, **extra):
        with self.lock:
            self.seq += 1
            self.events.append({"seq": self.seq, "kind": kind, "text": text, **extra})
            self.events = self.events[-50:]

    # ------------------------------------------------------------ attach / detach
    def attach(self, pid: int, name: str | None = None):
        with self.lock:
            self.detach(quiet=True)
            if name is None:
                name = next((p.name for p in list_processes() if p.pid == pid), f"pid {pid}")
            self.proc = Process(pid)
            self.game = name
            self.modules = self.proc.modules()
            self.mods = M.load_profile(name)
            if self.settings.get("autoAttach", "").lower() != name.lower():
                self.settings["autoAttach"] = name
                self.save_settings()
            locked = sum(1 for m in self.mods if m["locked"] and not self._stale(m))
            self.emit("attach", f"Dealt in to {name}" + (f" · {locked} mods back on" if locked else ""))

    def detach(self, quiet=False):
        with self.lock:
            if self.proc:
                self.proc.close()
                if not quiet:
                    self.emit("detach", f"Left {self.game}")
            self.proc = None
            self.modules = []
            self.scanner.reset()

    def _stale(self, m) -> bool:
        return bool(m.get("session")) and (self.proc is None or m["session"] != self.proc.pid)

    def _watch_loop(self):
        tick = 0
        while True:
            time.sleep(1)
            tick += 1
            try:
                if self.proc is not None:
                    if not self.proc.alive():
                        name = self.game
                        self.detach(quiet=True)
                        self.emit("detach", f"{name} closed. Waiting for it to come back…")
                    elif tick % 5 == 0:
                        mods = self.proc.modules()  # games load DLLs late, e.g. GameAssembly.dll
                        with self.lock:
                            self.modules = mods
                    continue
                target = (self.settings.get("autoAttach") or "").lower()
                if target:
                    match = next((p for p in list_processes() if p.name.lower() == target), None)
                    if match:
                        time.sleep(1.5)  # let the game finish starting up
                        self.attach(match.pid, match.name)
            except MemoryError_ as e:
                self.emit("error", str(e))
                time.sleep(4)
            except Exception:  # noqa: BLE001 - keep watching no matter what
                pass

    def _lock_loop(self):
        while True:
            time.sleep(0.05)
            with self.lock:
                proc, mods, modules = self.proc, list(self.mods), self.modules
            if proc is None:
                continue
            for m in mods:
                if m["locked"] and m["lockValue"] is not None and not self._stale(m):
                    try:
                        M.write_value(proc, m, modules, m["lockValue"])
                    except Exception:  # noqa: BLE001
                        pass

    # ------------------------------------------------------------ hotkeys
    def _bindings(self):
        with self.lock:
            return {m["hotkey"]: m["id"] for m in self.mods if m.get("hotkey")}

    def _hotkey(self, mod_id):
        m = self.find(mod_id)
        if not m:
            return
        try:
            self.set_lock(mod_id, not m["locked"])
            self.emit("hotkey", f'{m["name"]} {"locked" if m["locked"] else "unlocked"}', on=m["locked"])
        except ValueError as e:
            self.emit("error", str(e))

    # ------------------------------------------------------------ mods
    def find(self, mod_id):
        return next((m for m in self.mods if m["id"] == mod_id), None)

    def save(self):
        if self.game:
            M.save_profile(self.game, self.mods)

    def save_settings(self):
        M.save_json(os.path.join(self.dir, "settings.json"), self.settings)

    def need_proc(self):
        if self.proc is None:
            raise ValueError("No game attached yet. Start the game, then pick it from the list.")
        return self.proc

    def add_mod(self, data: dict) -> dict:
        proc = self.need_proc()
        with self.lock:
            if "address" in data:
                data = {**data, **M.from_absolute(proc, int(data["address"]), self.modules)}
            m = M.normalize(data)
            self.mods.append(m)
            self.save()
            return m

    def update_mod(self, mod_id, fields: dict):
        with self.lock:
            m = self.find(mod_id)
            if not m:
                raise ValueError("That mod doesn't exist any more.")
            for k in ("name", "category", "hotkey", "presets", "party", "type", "module", "base", "offsets"):
                if k in fields:
                    m[k] = fields[k]
            if m.get("hotkey") and not hotkeys.parse(m["hotkey"]):
                bad = m["hotkey"]
                m["hotkey"] = None
                raise ValueError(f'"{bad}" isn’t a hotkey House Edge knows. Try F1 to F12, Num0 to Num9, or Ctrl/Shift/Alt plus a key.')
            m.update(M.normalize(m))
            self.save()

    def delete_mod(self, mod_id):
        with self.lock:
            self.mods = [m for m in self.mods if m["id"] != mod_id]
            self.save()

    def set_lock(self, mod_id, on: bool, value=None):
        proc = self.need_proc()
        with self.lock:
            m = self.find(mod_id)
            if not m:
                raise ValueError("That mod doesn't exist any more.")
            if on:
                if self._stale(m):
                    raise ValueError(f'{m["name"]} was found in an earlier run of the game. Use the value finder to find it again.')
                if value is None:
                    value = M.read_value(proc, m, self.modules)
                if value is None:
                    raise ValueError(f'Couldn’t read {m["name"]} right now. Is that part of the game loaded?')
                m["lockValue"] = scanner.unpack(m["type"], scanner.pack(m["type"], value))
            m["locked"] = on
            self.save()

    def set_value(self, mod_id, value=None, preset=None):
        proc = self.need_proc()
        with self.lock:
            m = self.find(mod_id)
            if not m:
                raise ValueError("That mod doesn't exist any more.")
            if self._stale(m):
                raise ValueError(f'{m["name"]} was found in an earlier run of the game. Use the value finder to find it again.')
            if preset is not None:
                value = M.apply_preset(M.read_value(proc, m, self.modules), preset, m["type"])
            value = scanner.unpack(m["type"], scanner.pack(m["type"], value))
            if m["locked"]:
                m["lockValue"] = value
                self.save()
            if not M.write_value(proc, m, self.modules, value):
                raise ValueError(f'Couldn’t write {m["name"]}. The game may have moved it.')
            return value

    def import_ct(self, text: str):
        self.need_proc()
        new, skipped = M.import_ct(text)
        with self.lock:
            self.mods.extend(new)
            self.save()
        return {"added": len(new), "skipped": skipped}

    # ------------------------------------------------------------ state for the panel
    def state(self, since: int = 0) -> dict:
        with self.lock:
            proc = self.proc
            out_mods = []
            for m in self.mods:
                stale = self._stale(m)
                val = None
                if proc and not stale:
                    try:
                        val = M.read_value(proc, m, self.modules)
                    except Exception:  # noqa: BLE001
                        val = None
                out_mods.append({**m, "value": val, "stale": stale, "where": M.describe_address(m)})
            return {
                "attached": proc is not None,
                "game": {"name": self.game, "pid": proc.pid, "bits": proc.pointer_size * 8} if proc else None,
                "mods": out_mods,
                "scan": self.scanner.status(),
                "settings": self.settings,
                "hotkeysSupported": hotkeys.SUPPORTED,
                "events": [e for e in self.events if e["seq"] > since],
                "seq": self.seq,
            }

    def processes(self):
        seen = {}
        for p in list_processes():
            seen.setdefault(p.name.lower(), p)
        return sorted(({"pid": p.pid, "name": p.name} for p in seen.values()), key=lambda p: p["name"].lower())

    # ------------------------------------------------------------ value finder
    def scan(self, kind: str, body: dict):
        proc = self.need_proc()
        if self.scanner.busy:
            raise ValueError("A scan is already running.")
        if kind == "first":
            scanner.parse_value(body.get("type", "int32"), body.get("value")) if body.get("mode") == "exact" else None
            target = lambda: self.scanner.first_scan(proc, body.get("type", "int32"), body.get("mode", "exact"), body.get("value"))  # noqa: E731
        else:
            if body.get("mode") == "exact":
                scanner.parse_value(self.scanner.type, body.get("value"))
            target = lambda: self.scanner.next_scan(proc, body.get("mode", "exact"), body.get("value"))  # noqa: E731
        self.scanner.busy = True
        self.scanner.progress = 0
        threading.Thread(target=target, daemon=True, name="scan").start()

    def scan_results(self):
        return {"status": self.scanner.status(), "results": self.scanner.results(self.proc)}

    def scan_write(self, address: int, value):
        proc = self.need_proc()
        t = self.scanner.type
        if not proc.write(int(address), scanner.pack(t, scanner.parse_value(t, value))):
            raise ValueError("Couldn't write to that address.")

    def update_settings(self, fields: dict):
        with self.lock:
            for k in DEFAULT_SETTINGS:
                if k in fields:
                    self.settings[k] = fields[k]
            self.save_settings()
        if self.window is not None and "onTop" in fields:
            try:
                self.window.on_top = bool(self.settings["onTop"])
            except Exception:  # noqa: BLE001
                pass


# ================================================================ HTTP API
def make_server(core: Core, port: int = 0):
    token = secrets.token_urlsafe(16)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *a):  # keep the console quiet
            pass

        def _send(self, code, body, ctype="application/json"):
            data = body if isinstance(body, bytes) else json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _host_ok(self):
            # Only answer requests addressed to 127.0.0.1, so a web page can't reach the API through DNS rebinding.
            host = (self.headers.get("Host") or "").split(":")[0]
            return host in ("127.0.0.1", "localhost")

        def _authed(self):
            return self._host_ok() and secrets.compare_digest(self.headers.get("X-Token", ""), token)

        def do_GET(self):
            if not self._host_ok():
                return self._send(403, {"error": "forbidden"})
            url = urlparse(self.path)
            if url.path in ("/", "/index.html"):
                with open(os.path.join(UI_DIR, "index.html"), "rb") as f:
                    return self._send(200, f.read(), "text/html; charset=utf-8")
            if not self._authed():
                return self._send(403, {"error": "forbidden"})
            q = parse_qs(url.query)
            try:
                if url.path == "/api/state":
                    return self._send(200, core.state(int(q.get("since", ["0"])[0])))
                if url.path == "/api/processes":
                    return self._send(200, core.processes())
                if url.path == "/api/scan/results":
                    return self._send(200, core.scan_results())
            except Exception as e:  # noqa: BLE001
                return self._send(400, {"error": str(e)})
            return self._send(404, {"error": "not found"})

        def do_POST(self):
            if not self._authed():
                return self._send(403, {"error": "forbidden"})
            try:
                n = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(n) or b"{}") if n else {}
                path = urlparse(self.path).path
                result = route(core, path, body)
                return self._send(200, {"ok": True, **(result or {})})
            except (ValueError, MemoryError_) as e:
                return self._send(400, {"error": str(e)})
            except KeyError as e:
                return self._send(400, {"error": f"Missing {e}"})
            except Exception as e:  # noqa: BLE001
                return self._send(500, {"error": f"Something went wrong: {e}"})

    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    srv.daemon_threads = True
    return srv, token


def route(core: Core, path: str, b: dict):
    if path == "/api/attach":
        core.attach(int(b["pid"]), b.get("name"))
    elif path == "/api/detach":
        core.detach()
        core.settings["autoAttach"] = ""
        core.save_settings()
    elif path == "/api/mod/add":
        return {"mod": core.add_mod(b)}
    elif path == "/api/mod/update":
        core.update_mod(b["id"], b)
    elif path == "/api/mod/delete":
        core.delete_mod(b["id"])
    elif path == "/api/mod/lock":
        core.set_lock(b["id"], bool(b["on"]), b.get("value"))
    elif path == "/api/mod/set":
        return {"value": core.set_value(b["id"], b.get("value"), b.get("preset"))}
    elif path == "/api/scan/first":
        core.scan("first", b)
    elif path == "/api/scan/next":
        core.scan("next", b)
    elif path == "/api/scan/reset":
        core.scanner.reset()
    elif path == "/api/scan/write":
        core.scan_write(b["address"], b["value"])
    elif path == "/api/import_ct":
        return core.import_ct(b["text"])
    elif path == "/api/settings":
        core.update_settings(b)
    else:
        raise ValueError(f"Unknown action {path}")
    return None
