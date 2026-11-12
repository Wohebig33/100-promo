"""End-to-end test for House Edge, run against a stand-in "game" process.

  python selftest.py

It starts a small child process that keeps a few values in memory (money, health, and gold behind a pointer).
House Edge then has to find them, change them, lock them and follow the pointer. This runs on Windows and Linux;
CI runs it on Windows so the kernel32 backend is tested for real.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

os.environ["APPDATA"] = os.environ["XDG_CONFIG_HOME"] = tempfile.mkdtemp(prefix="he-test-")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from house_edge import mods as M, scanner  # noqa: E402
from house_edge.core import Core, make_server  # noqa: E402
from house_edge.memory import Process, list_processes  # noqa: E402

GAME = r'''
import ctypes, sys
money = ctypes.c_int32(123456789)
health = ctypes.c_float(77.25)
class Player(ctypes.Structure):
    _fields_ = [("pad", ctypes.c_char * 0x10), ("gold", ctypes.c_int32)]
player = Player(); player.gold = 31337
ptr = ctypes.pointer(player)
print(ctypes.addressof(money), ctypes.addressof(health), ctypes.addressof(ptr), flush=True)
vals = {"money": money, "health": health}
for line in sys.stdin:
    cmd = line.split()
    if not cmd: continue
    if cmd[0] == "set":
        v = vals[cmd[1]]; v.value = type(v.value)(float(cmd[2]) if cmd[1] == "health" else int(cmd[2]))
        print("ok", flush=True)
    elif cmd[0] == "get":
        print(player.gold if cmd[1] == "gold" else vals[cmd[1]].value, flush=True)
    elif cmd[0] == "quit":
        break
'''

passed = 0


def check(name, cond, detail=""):
    global passed
    if not cond:
        print(f"FAIL  {name} {detail}")
        sys.exit(1)
    passed += 1
    print(f"ok    {name}")


def wait_scan(sc):
    t0 = time.time()
    while sc.busy and time.time() - t0 < 120:
        time.sleep(0.05)


def main():
    child = subprocess.Popen([sys.executable, "-c", GAME], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def say(cmd):
        child.stdin.write(cmd + "\n")
        child.stdin.flush()
        return child.stdout.readline().strip()

    try:
        a_money, a_health, a_ptr = map(int, child.stdout.readline().split())
        pid = child.pid

        # --- memory backend
        check("process is listed", any(p.pid == pid for p in list_processes()))
        proc = Process(pid)
        check("pointer size detected", proc.pointer_size in (4, 8), proc.pointer_size)
        check("read int32", scanner.unpack("int32", proc.read(a_money, 4)) == 123456789)
        check("writable regions found", len(proc.regions()) > 0)
        mods_list = proc.modules()
        check("modules listed", len(mods_list) > 0)
        first = mods_list[0]
        head = proc.read(first.base, 2)
        check("module base readable (MZ/ELF header)", head in (b"MZ", b"\x7fE"), f"{first.name} {head!r}")

        # --- value finder: exact, then next
        sc = scanner.Scanner()
        sc.first_scan(proc, "int32", "exact", "123456789")
        check("first scan ran", sc.error == "" and sc.scans == 1, sc.error)
        addrs = {r["address"] for r in sc.results(proc)}
        check("first scan found money", a_money in addrs, f"{sc.total} results")
        say("set money 987654321")
        sc.next_scan(proc, "exact", "987654321")
        addrs = {r["address"] for r in sc.results(proc)}
        check("next scan kept money", a_money in addrs, f"{sc.total} results")
        check("next scan narrowed it down", sc.total <= 5, sc.total)

        # --- value finder: unknown start, went down, exact float
        sc2 = scanner.Scanner()
        sc2.first_scan(proc, "float", "unknown")
        check("unknown first scan ran", sc2.error == "" and sc2.total > 0, sc2.error)
        say("set health 50.5")
        sc2.next_scan(proc, "decreased")
        check("went-down scan ran", sc2.error == "", sc2.error)
        sc2.next_scan(proc, "exact", "50.5")
        addrs = {r["address"] for r in sc2.results(proc)}
        check("found health as a float", a_health in addrs, f"{sc2.total} results")
        check("snapshot temp files cleaned up", sc2._tmpdir is None)

        # --- pointer chains and module-relative addresses
        mod = M.normalize({"name": "Gold", "type": "int32", "base": a_ptr, "offsets": [0x10]})
        check("pointer chain read", M.read_value(proc, mod, mods_list) == 31337)
        check("pointer chain write", M.write_value(proc, mod, mods_list, 4242) and say("get gold") == "4242")
        hdr = M.normalize({"name": "Header", "type": "byte", "module": first.name, "base": 0})
        check("module-relative read", M.read_value(proc, hdr, mods_list) in (0x4D, 0x7F))
        rel = M.from_absolute(proc, first.base + 0x10, mods_list)
        check("static address saved relative to module", rel["module"] == first.name and rel["base"] == 0x10 and rel["session"] is None)
        check("presets", M.apply_preset(10, "x2", "int32") == 20 and M.apply_preset(10, "+5", "int32") == 15 and M.apply_preset(10, "99", "int32") == 99)
        proc.close()

        # --- Core: attach, lock, set, hotkey toggle, stale detection
        core = Core()
        core.attach(pid)
        check("core attached", core.proc is not None and core.game)
        core.settings["autoAttach"] = "no-such-game.exe"  # the stand-in is just "python", so don't rejoin other Pythons
        m = core.add_mod({"name": "Chips", "type": "int32", "address": a_money})
        check("found address becomes a session mod", m["session"] == pid)
        core.set_lock(m["id"], True, 1000)
        say("set money 5")
        time.sleep(0.4)
        check("lock holds the value", say("get money") == "1000")
        core.set_lock(m["id"], False)
        check("preset via core", core.set_value(m["id"], preset="x2") == 2000 and say("get money") == "2000")
        core._hotkey(m["id"])
        check("hotkey toggles lock on", core.find(m["id"])["locked"])
        core._hotkey(m["id"])
        check("hotkey toggles lock off", not core.find(m["id"])["locked"])
        st = core.state()
        check("state reports live value", st["mods"][0]["value"] == 2000 and not st["mods"][0]["stale"])
        check("profile saved", os.path.exists(M.profile_path(core.game)))
        check("profile reloads", M.load_profile(core.game)[0]["name"] == "Chips")

        # --- HTTP API security
        srv, token = make_server(core)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        base = f"http://127.0.0.1:{srv.server_address[1]}"

        def get(path, tok=token, host=None):
            req = urllib.request.Request(base + path, headers={"X-Token": tok, **({"Host": host} if host else {})})
            try:
                with urllib.request.urlopen(req, timeout=5) as r:
                    return r.status, r.read()
            except urllib.error.HTTPError as e:
                return e.code, e.read()

        code, body = get("/api/state")
        check("API answers with token", code == 200 and json.loads(body)["attached"])
        check("API refuses without token", get("/api/state", tok="nope")[0] == 403)
        check("API refuses other hosts", get("/api/state", host="evil.example")[0] == 403)
        check("panel page served", get("/")[0] == 200)
        srv.shutdown()

        # --- Cheat Engine import
        ct = """<?xml version="1.0"?><CheatTable><CheatEntries>
          <CheatEntry><Description>"Player"</Description><CheatEntries>
            <CheatEntry><Description>"Money"</Description><VariableType>4 Bytes</VariableType>
              <Address>"GameAssembly.dll"+01A2B3C</Address><Offsets><Offset>2C</Offset><Offset>10</Offset></Offsets>
              <Hotkeys><Hotkey><Action>Toggle Activation</Action><Keys><Key>17</Key><Key>112</Key></Keys></Hotkey></Hotkeys></CheatEntry>
            <CheatEntry><Description>"Speed"</Description><VariableType>Float</VariableType><Address>0040A1B0</Address></CheatEntry>
            <CheatEntry><Description>"God mode"</Description><VariableType>Auto Assembler Script</VariableType><AssemblerScript>[ENABLE]</AssemblerScript></CheatEntry>
          </CheatEntries></CheatEntry></CheatEntries></CheatTable>"""
        got, skipped = M.import_ct(ct)
        check("CT import count", len(got) == 2 and skipped == 1, (len(got), skipped))
        check("CT pointer offsets reversed", got[0]["offsets"] == [0x10, 0x2C] and got[0]["module"] == "GameAssembly.dll" and got[0]["base"] == 0x1A2B3C)
        check("CT hotkey and group", got[0]["hotkey"] == "Ctrl+F1" and got[0]["category"] == "Player")
        check("CT float absolute", got[1]["type"] == "float" and got[1]["base"] == 0x40A1B0 and got[1]["module"] is None)

        # --- the game closes and comes back: session mods go stale
        say("quit")
        child.wait(timeout=10)
        time.sleep(2.5)
        check("game exit detected", core.proc is None)
        check("session mod marked stale", core.state()["mods"][0]["stale"])

        # --- Steam launch options: House Edge starts the game, joins it, and quits once it closes
        core2 = Core()
        core2.settings["autoAttach"] = "no-such-game.exe"
        exited = threading.Event()
        core2.on_exit = exited.set
        core2.launch([sys.executable, "-c", "import time; time.sleep(4)"])
        t0 = time.time()
        while core2.proc is None and time.time() - t0 < 15:
            time.sleep(0.1)
        check("game started by House Edge is joined", core2.proc is not None and core2.proc.pid == core2.launched.pid)
        core2.settings["autoAttach"] = "no-such-game.exe"  # joining saved the name "python"; don't wait for other Pythons
        check("House Edge quits after the game it started closes", exited.wait(30))
        check("panel show/hide hotkey is Q+E", core2._bindings().get("Q+E") == "__panel__")
        from house_edge import hotkeys
        check("two-key chords parse", hotkeys.parse("Q+E") == (frozenset(), (0x51, 0x45)) and hotkeys.parse("ctrl+f1") == (frozenset({"Ctrl"}), (0x70,)))
        check("bad hotkeys rejected", hotkeys.parse("Q+Q") is None and hotkeys.parse("Ctrl") is None and hotkeys.parse("A+B+C") is None)
        check("Steam launch option ends with %command%", core2.launch_option().endswith("%command%"))
        check("own process not listed", all(p.pid != os.getpid() for p in list_processes()))
    finally:
        if child.poll() is None:
            child.kill()
    print(f"\nAll {passed} checks passed on {sys.platform}.")


if __name__ == "__main__":
    main()
