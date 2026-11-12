"""Value finder: search a process's memory for a number, then narrow the results down.

It works the way Cheat Engine's basic scanning does:
  1. First scan: an exact value, or "unknown" to take a snapshot of everything.
  2. Change the value in the game.
  3. Next scan: exact, increased, decreased, changed or unchanged. Repeat until a few addresses are left.

Memory is read in chunks and compared with numpy, so a first scan of a few GB takes seconds rather than minutes.
"""
from __future__ import annotations

import os
import shutil
import tempfile
import threading

import numpy as np

TYPES = {
    "byte":   ("<u1", 1),
    "int16":  ("<i2", 2),
    "int32":  ("<i4", 4),
    "int64":  ("<i8", 8),
    "float":  ("<f4", 4),
    "double": ("<f8", 8),
}
TYPE_LABELS = {"byte": "Byte", "int16": "2 bytes", "int32": "4 bytes", "int64": "8 bytes", "float": "Float", "double": "Double"}
CHUNK = 8 << 20  # 8 MB per read
MAX_RESULTS_SHOWN = 200


def is_float(t: str) -> bool:
    return t in ("float", "double")


def parse_value(t: str, text) -> float | int:
    s = str(text).strip().replace(",", "")
    if s == "":
        raise ValueError("Type a value to search for.")
    return float(s) if is_float(t) else int(float(s))


def tolerance(text) -> float:
    """Float values match if they round to what was typed. "100" matches 99.5 to 100.5, and "1.25" matches 1.245 to 1.255."""
    s = str(text).strip()
    decimals = len(s.split(".", 1)[1]) if "." in s else 0
    return 0.5 * 10 ** -decimals


def pack(t: str, value) -> bytes:
    dt = np.dtype(TYPES[t][0])
    if not is_float(t):
        info = np.iinfo(dt)
        value = max(info.min, min(info.max, int(value)))
    return np.array([value], dtype=dt).tobytes()


def unpack(t: str, data: bytes):
    v = np.frombuffer(data, dtype=TYPES[t][0])[0]
    return round(float(v), 4) if is_float(t) else int(v)


class Chunk:
    """One slice of memory that might still hold matches.

    `idx` lists the element indices that still match, or is None for "all of them" right after an unknown first scan.
    `prev` holds the values from the last scan. For a whole-chunk snapshot it's a memory-mapped temp file so it doesn't fill RAM.
    """
    __slots__ = ("addr", "count", "idx", "prev")

    def __init__(self, addr, count, idx, prev):
        self.addr = addr
        self.count = count
        self.idx = idx
        self.prev = prev

    @property
    def matches(self) -> int:
        return self.count if self.idx is None else len(self.idx)


class Scanner:
    def __init__(self):
        self.lock = threading.Lock()
        self.reset()

    def reset(self):
        self.chunks: list[Chunk] = []
        self.type = "int32"
        self.scans = 0
        self.busy = False
        self.progress = 0.0
        self.error = ""
        self.total = 0
        self._cleanup()

    def _cleanup(self):
        if getattr(self, "_tmpdir", None):
            shutil.rmtree(self._tmpdir, ignore_errors=True)
        self._tmpdir = None

    def status(self) -> dict:
        return {"type": self.type, "scans": self.scans, "busy": self.busy, "progress": round(self.progress, 3),
                "error": self.error, "total": self.total}

    # ---------------- scans ----------------
    def first_scan(self, proc, t: str, mode: str, text=None):
        if t not in TYPES:
            raise ValueError(f"Unknown type {t}")
        value = parse_value(t, text) if mode == "exact" else None
        tol = tolerance(text) if (mode == "exact" and is_float(t)) else 0
        self.reset()
        self.type = t
        self.busy = True
        dtype, size = TYPES[t]
        try:
            regions = proc.regions(writable_only=True)
            total_bytes = sum(s for _, s in regions) or 1
            done = 0
            if mode == "unknown":
                self._tmpdir = tempfile.mkdtemp(prefix="house-edge-")
            for start, rsize in regions:
                off = 0
                while off < rsize:
                    n = min(CHUNK, rsize - off)
                    addr = start + off
                    data = proc.read(addr, n)
                    off += n
                    done += n
                    self.progress = done / total_bytes
                    if data is None:
                        continue
                    count = n // size
                    arr = np.frombuffer(data, dtype=dtype, count=count)
                    if mode == "unknown":
                        path = os.path.join(self._tmpdir, f"{addr:x}.npy")
                        np.save(path, arr)
                        self.chunks.append(Chunk(addr, count, None, path))
                        self.total += count
                    else:
                        mask = _cmp_exact(arr, value, tol)
                        idx = np.flatnonzero(mask)
                        if len(idx):
                            self.chunks.append(Chunk(addr, count, idx, arr[idx].copy()))
                            self.total += len(idx)
            self.scans = 1
        except Exception as e:  # noqa: BLE001 - shown to the user
            self.error = str(e)
        finally:
            self.busy = False
            self.progress = 1.0

    def next_scan(self, proc, mode: str, text=None):
        if not self.scans:
            raise ValueError("Run a first scan before a next scan.")
        t = self.type
        dtype, size = TYPES[t]
        value = parse_value(t, text) if mode == "exact" else None
        tol = tolerance(text) if (mode == "exact" and is_float(t)) else 0
        self.busy = True
        self.error = ""
        try:
            kept: list[Chunk] = []
            total = 0
            n_chunks = len(self.chunks) or 1
            for i, ch in enumerate(self.chunks):
                self.progress = i / n_chunks
                if ch.idx is None:
                    data = proc.read(ch.addr, ch.count * size)
                    if data is None:
                        continue
                    cur = np.frombuffer(data, dtype=dtype, count=ch.count)
                    prev = np.load(ch.prev, mmap_mode="r")
                    mask = _cmp(mode, cur, prev, value, tol)
                    idx = np.flatnonzero(mask)
                    vals = cur[idx].copy()
                    del prev, mask  # close the memory-mapped file so Windows lets us delete it
                else:
                    lo, hi = int(ch.idx[0]), int(ch.idx[-1])
                    data = proc.read(ch.addr + lo * size, (hi - lo + 1) * size)
                    if data is None:
                        continue
                    span = np.frombuffer(data, dtype=dtype)
                    cur = span[ch.idx - lo]
                    mask = _cmp(mode, cur, ch.prev, value, tol)
                    idx = ch.idx[mask]
                    vals = cur[mask].copy()
                if len(idx):
                    kept.append(Chunk(ch.addr, ch.count, idx, vals))
                    total += len(idx)
            self.chunks = kept
            self.total = total
            self.scans += 1
            self._cleanup()  # every chunk is an index list now, so the snapshot files can go
        except Exception as e:  # noqa: BLE001
            self.error = str(e)
        finally:
            self.busy = False
            self.progress = 1.0

    # ---------------- results ----------------
    def results(self, proc, limit: int = MAX_RESULTS_SHOWN) -> list[dict]:
        if self.busy or self.total == 0 or self.total > 100_000:
            return []
        t = self.type
        _dtype, size = TYPES[t]
        out = []
        for ch in self.chunks:
            if ch.idx is None:
                return []
            for j, i in enumerate(ch.idx):
                addr = ch.addr + int(i) * size
                data = proc.read(addr, size) if proc else None
                out.append({
                    "address": addr,
                    "value": unpack(t, data) if data else None,
                    "previous": round(float(ch.prev[j]), 4) if is_float(t) else int(ch.prev[j]),
                })
                if len(out) >= limit:
                    return out
        return out


def _cmp_exact(arr, value, tol):
    if tol:
        with np.errstate(invalid="ignore"):
            return np.abs(arr - value) < tol
    return arr == value


def _cmp(mode, cur, prev, value, tol):
    with np.errstate(invalid="ignore"):
        if mode == "exact":
            return _cmp_exact(cur, value, tol)
        if mode == "increased":
            return cur > prev
        if mode == "decreased":
            return cur < prev
        if mode == "changed":
            return cur != prev
        if mode == "unchanged":
            return cur == prev
    raise ValueError(f"Unknown scan mode {mode}")
