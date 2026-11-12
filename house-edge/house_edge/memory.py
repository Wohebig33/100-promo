"""Read and write another process's memory.

Two backends share one interface:
  - Windows: kernel32 through ctypes (OpenProcess, ReadProcessMemory, ...).
  - Linux: /proc/<pid>/mem. This also covers games running through Proton on Linux or a Steam Deck.

Interface:
  list_processes() -> [ProcInfo]
  Process(pid).read(addr, size) -> bytes | None
  Process(pid).write(addr, data) -> bool
  Process(pid).regions(writable_only=True) -> [(start, size)]
  Process(pid).modules() -> [Module]
  Process(pid).pointer_size -> 4 | 8
"""
from __future__ import annotations

import os
import struct
import sys
from dataclasses import dataclass

IS_WINDOWS = sys.platform == "win32"


@dataclass
class ProcInfo:
    pid: int
    name: str


@dataclass
class Module:
    name: str
    base: int
    size: int


class MemoryError_(Exception):
    pass


# --------------------------------------------------------------------------
# Windows
# --------------------------------------------------------------------------
if IS_WINDOWS:
    import ctypes
    from ctypes import wintypes as wt

    k32 = ctypes.WinDLL("kernel32", use_last_error=True)

    PROCESS_QUERY_INFORMATION = 0x0400
    PROCESS_VM_OPERATION = 0x0008
    PROCESS_VM_READ = 0x0010
    PROCESS_VM_WRITE = 0x0020
    MEM_COMMIT = 0x1000
    MEM_MAPPED = 0x40000
    PAGE_NOACCESS = 0x01
    PAGE_GUARD = 0x100
    PAGE_READWRITE = 0x04
    PAGE_WRITECOPY = 0x08
    PAGE_EXECUTE_READWRITE = 0x40
    PAGE_EXECUTE_WRITECOPY = 0x80
    WRITABLE = PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY
    TH32CS_SNAPPROCESS = 0x2
    TH32CS_SNAPMODULE = 0x8
    TH32CS_SNAPMODULE32 = 0x10
    INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

    class MEMORY_BASIC_INFORMATION(ctypes.Structure):
        _fields_ = [
            ("BaseAddress", ctypes.c_void_p),
            ("AllocationBase", ctypes.c_void_p),
            ("AllocationProtect", wt.DWORD),
            ("PartitionId", wt.WORD),
            ("RegionSize", ctypes.c_size_t),
            ("State", wt.DWORD),
            ("Protect", wt.DWORD),
            ("Type", wt.DWORD),
        ]

    class PROCESSENTRY32W(ctypes.Structure):
        _fields_ = [
            ("dwSize", wt.DWORD),
            ("cntUsage", wt.DWORD),
            ("th32ProcessID", wt.DWORD),
            ("th32DefaultHeapID", ctypes.c_void_p),
            ("th32ModuleID", wt.DWORD),
            ("cntThreads", wt.DWORD),
            ("th32ParentProcessID", wt.DWORD),
            ("pcPriClassBase", ctypes.c_long),
            ("dwFlags", wt.DWORD),
            ("szExeFile", ctypes.c_wchar * 260),
        ]

    class MODULEENTRY32W(ctypes.Structure):
        _fields_ = [
            ("dwSize", wt.DWORD),
            ("th32ModuleID", wt.DWORD),
            ("th32ProcessID", wt.DWORD),
            ("GlblcntUsage", wt.DWORD),
            ("ProccntUsage", wt.DWORD),
            ("modBaseAddr", ctypes.c_void_p),
            ("modBaseSize", wt.DWORD),
            ("hModule", wt.HMODULE),
            ("szModule", ctypes.c_wchar * 256),
            ("szExePath", ctypes.c_wchar * 260),
        ]

    def _fn(name, restype, *argtypes):
        f = getattr(k32, name)
        f.restype = restype
        f.argtypes = argtypes
        return f

    OpenProcess = _fn("OpenProcess", wt.HANDLE, wt.DWORD, wt.BOOL, wt.DWORD)
    CloseHandle = _fn("CloseHandle", wt.BOOL, wt.HANDLE)
    ReadProcessMemory = _fn("ReadProcessMemory", wt.BOOL, wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t))
    WriteProcessMemory = _fn("WriteProcessMemory", wt.BOOL, wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t))
    VirtualQueryEx = _fn("VirtualQueryEx", ctypes.c_size_t, wt.HANDLE, ctypes.c_void_p, ctypes.POINTER(MEMORY_BASIC_INFORMATION), ctypes.c_size_t)
    VirtualProtectEx = _fn("VirtualProtectEx", wt.BOOL, wt.HANDLE, ctypes.c_void_p, ctypes.c_size_t, wt.DWORD, ctypes.POINTER(wt.DWORD))
    IsWow64Process = _fn("IsWow64Process", wt.BOOL, wt.HANDLE, ctypes.POINTER(wt.BOOL))
    GetExitCodeProcess = _fn("GetExitCodeProcess", wt.BOOL, wt.HANDLE, ctypes.POINTER(wt.DWORD))
    CreateToolhelp32Snapshot = _fn("CreateToolhelp32Snapshot", wt.HANDLE, wt.DWORD, wt.DWORD)
    Process32FirstW = _fn("Process32FirstW", wt.BOOL, wt.HANDLE, ctypes.POINTER(PROCESSENTRY32W))
    Process32NextW = _fn("Process32NextW", wt.BOOL, wt.HANDLE, ctypes.POINTER(PROCESSENTRY32W))
    Module32FirstW = _fn("Module32FirstW", wt.BOOL, wt.HANDLE, ctypes.POINTER(MODULEENTRY32W))
    Module32NextW = _fn("Module32NextW", wt.BOOL, wt.HANDLE, ctypes.POINTER(MODULEENTRY32W))

    def list_processes() -> list[ProcInfo]:
        snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
        if not snap or snap == INVALID_HANDLE_VALUE:
            return []
        out = []
        try:
            e = PROCESSENTRY32W()
            e.dwSize = ctypes.sizeof(e)
            ok = Process32FirstW(snap, ctypes.byref(e))
            while ok:
                if e.th32ProcessID and e.th32ProcessID != os.getpid():  # never list House Edge itself
                    out.append(ProcInfo(e.th32ProcessID, e.szExeFile))
                ok = Process32NextW(snap, ctypes.byref(e))
        finally:
            CloseHandle(snap)
        return out

    class Process:
        def __init__(self, pid: int):
            self.pid = pid
            access = PROCESS_QUERY_INFORMATION | PROCESS_VM_OPERATION | PROCESS_VM_READ | PROCESS_VM_WRITE
            self.h = OpenProcess(access, False, pid)
            if not self.h:
                err = ctypes.get_last_error()
                hint = " Try running House Edge as administrator." if err == 5 else ""
                raise MemoryError_(f"Couldn't open process {pid} (Windows error {err}).{hint}")
            wow = wt.BOOL(False)
            is64os = struct.calcsize("P") == 8
            IsWow64Process(self.h, ctypes.byref(wow))
            self.pointer_size = 4 if (wow.value or not is64os) else 8

        def close(self):
            if self.h:
                CloseHandle(self.h)
                self.h = None

        def alive(self) -> bool:
            code = wt.DWORD()
            return bool(self.h) and bool(GetExitCodeProcess(self.h, ctypes.byref(code))) and code.value == 259  # STILL_ACTIVE

        def read(self, addr: int, size: int) -> bytes | None:
            buf = ctypes.create_string_buffer(size)
            got = ctypes.c_size_t(0)
            if ReadProcessMemory(self.h, ctypes.c_void_p(addr), buf, size, ctypes.byref(got)) and got.value == size:
                return buf.raw
            return None

        def write(self, addr: int, data: bytes) -> bool:
            n = len(data)
            done = ctypes.c_size_t(0)
            if WriteProcessMemory(self.h, ctypes.c_void_p(addr), data, n, ctypes.byref(done)) and done.value == n:
                return True
            # The page might be read-only, for example a static in a module's .data or .rdata. Unlock it briefly.
            old = wt.DWORD(0)
            if not VirtualProtectEx(self.h, ctypes.c_void_p(addr), n, PAGE_EXECUTE_READWRITE, ctypes.byref(old)):
                return False
            ok = WriteProcessMemory(self.h, ctypes.c_void_p(addr), data, n, ctypes.byref(done))
            VirtualProtectEx(self.h, ctypes.c_void_p(addr), n, old.value, ctypes.byref(wt.DWORD(0)))
            return bool(ok) and done.value == n

        def regions(self, writable_only: bool = True) -> list[tuple[int, int]]:
            out = []
            mbi = MEMORY_BASIC_INFORMATION()
            addr = 0
            limit = 0x7FFFFFFF if self.pointer_size == 4 else 0x7FFFFFFFFFFF
            while addr < limit:
                if not VirtualQueryEx(self.h, ctypes.c_void_p(addr), ctypes.byref(mbi), ctypes.sizeof(mbi)):
                    break
                base = mbi.BaseAddress or 0
                size = mbi.RegionSize
                if size == 0:
                    break
                prot = mbi.Protect
                if (mbi.State == MEM_COMMIT and mbi.Type != MEM_MAPPED
                        and not prot & (PAGE_GUARD | PAGE_NOACCESS)
                        and (prot & WRITABLE or not writable_only)):
                    out.append((base, size))
                addr = base + size
            return _merge(out)

        def modules(self) -> list[Module]:
            snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, self.pid)
            if not snap or snap == INVALID_HANDLE_VALUE:
                return []
            out = []
            try:
                e = MODULEENTRY32W()
                e.dwSize = ctypes.sizeof(e)
                ok = Module32FirstW(snap, ctypes.byref(e))
                while ok:
                    out.append(Module(e.szModule, e.modBaseAddr or 0, e.modBaseSize))
                    ok = Module32NextW(snap, ctypes.byref(e))
            finally:
                CloseHandle(snap)
            return out

# --------------------------------------------------------------------------
# Linux (/proc)
# --------------------------------------------------------------------------
else:
    def list_processes() -> list[ProcInfo]:
        out = []
        for d in os.listdir("/proc"):
            if not d.isdigit():
                continue
            pid = int(d)
            if pid == os.getpid():
                continue
            try:
                with open(f"/proc/{d}/cmdline", "rb") as f:
                    argv0 = f.read().split(b"\0")[0].decode(errors="replace")
                with open(f"/proc/{d}/comm") as f:
                    comm = f.read().strip()
            except OSError:
                continue
            # Games under Proton/Wine show up with their Windows path in argv[0], so use the .exe name.
            base = argv0.replace("\\", "/").rsplit("/", 1)[-1]
            name = base if base.lower().endswith(".exe") else (comm or base)
            if name:
                out.append(ProcInfo(pid, name))
        return out

    class Process:
        def __init__(self, pid: int):
            self.pid = pid
            try:
                # pread/pwrite don't share a file position, so the scanner, the lock loop and the UI can all use this fd at once.
                self.fd = os.open(f"/proc/{pid}/mem", os.O_RDWR)
            except OSError as e:
                raise MemoryError_(f"Couldn't open process {pid}: {e.strerror}. Try running with sudo.") from e
            self.pointer_size = 8
            try:
                with open(f"/proc/{pid}/exe", "rb") as f:
                    hdr = f.read(5)
                if hdr[:4] == b"\x7fELF" and hdr[4] == 1:
                    self.pointer_size = 4
            except OSError:
                pass

        def close(self):
            if self.fd is not None:
                os.close(self.fd)
                self.fd = None

        def alive(self) -> bool:
            try:
                with open(f"/proc/{self.pid}/stat") as f:
                    state = f.read().rsplit(")", 1)[1].split()[0]
                return state not in ("Z", "X")  # a zombie has exited, it just hasn't been reaped yet
            except (OSError, IndexError):
                return False

        def read(self, addr: int, size: int) -> bytes | None:
            try:
                data = os.pread(self.fd, size, addr)
                return data if len(data) == size else None
            except (OSError, OverflowError, ValueError, TypeError):
                return None

        def write(self, addr: int, data: bytes) -> bool:
            try:
                return os.pwrite(self.fd, data, addr) == len(data)
            except (OSError, OverflowError, ValueError, TypeError):
                return False

        def _maps(self):
            with open(f"/proc/{self.pid}/maps") as f:
                for line in f:
                    parts = line.split(None, 5)
                    lo, hi = (int(x, 16) for x in parts[0].split("-"))
                    path = parts[5].strip() if len(parts) > 5 else ""
                    yield lo, hi, parts[1], path

        def regions(self, writable_only: bool = True) -> list[tuple[int, int]]:
            out = []
            for lo, hi, perms, path in self._maps():
                if perms[0] != "r" or (writable_only and perms[1] != "w"):
                    continue
                if path in ("[vvar]", "[vsyscall]", "[vdso]") or path.startswith("/dev/"):
                    continue
                out.append((lo, hi - lo))
            return _merge(out)

        def modules(self) -> list[Module]:
            spans: dict[str, list[int]] = {}
            for lo, hi, _perms, path in self._maps():
                if not path or path.startswith("["):
                    continue
                name = path.replace("\\", "/").rsplit("/", 1)[-1]
                s = spans.setdefault(name, [lo, hi])
                s[0] = min(s[0], lo)
                s[1] = max(s[1], hi)
            return [Module(n, lo, hi - lo) for n, (lo, hi) in spans.items()]


def _merge(regions: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """Merge neighbouring regions so the scanner makes fewer, bigger reads."""
    regions.sort()
    out: list[list[int]] = []
    for start, size in regions:
        if out and out[-1][0] + out[-1][1] == start:
            out[-1][1] += size
        else:
            out.append([start, size])
    return [(a, b) for a, b in out]


def read_pointer(proc, addr: int) -> int | None:
    data = proc.read(addr, proc.pointer_size)
    if data is None:
        return None
    return int.from_bytes(data, "little")
