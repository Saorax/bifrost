"""where a running process's committed memory is, by kind (memory outside HashLink's GC heap).

    python tools/port_procmem.py PID [--top N]
    python tools/port_procmem.py --name hl

walks the process's address space with ``VirtualQueryEx`` (read-only: it opens the process with query rights only)
and prints the committed bytes by type (private, mapped, image), the private bytes by allocation (a ``VirtualAlloc``
reservation: HashLink's GC pages, the C heaps' segments, the GL driver's blocks), grouped by reservation size, and
the largest reservations. Windows only.
"""
from __future__ import annotations

import argparse
import bisect
import collections
import ctypes
import ctypes.wintypes as wt
import json
import pathlib
import re
import struct
import subprocess
import sys

PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010
MEM_COMMIT = 0x1000
TYPES = {0x20000: "private", 0x40000: "mapped", 0x1000000: "image"}


class MEMORY_BASIC_INFORMATION(ctypes.Structure):
    _fields_ = [("BaseAddress", ctypes.c_void_p), ("AllocationBase", ctypes.c_void_p), ("AllocationProtect", wt.DWORD),
                ("PartitionId", wt.WORD), ("RegionSize", ctypes.c_size_t), ("State", wt.DWORD),
                ("Protect", wt.DWORD), ("Type", wt.DWORD)]


def regions(pid: int):
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.restype = wt.HANDLE
    kernel32.VirtualQueryEx.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.POINTER(MEMORY_BASIC_INFORMATION),
                                        ctypes.c_size_t]
    kernel32.VirtualQueryEx.restype = ctypes.c_size_t
    handle = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION, False, pid)
    if not handle:
        raise OSError(f"cannot open process {pid} (error {ctypes.get_last_error()})")
    try:
        address, info = 0, MEMORY_BASIC_INFORMATION()
        while kernel32.VirtualQueryEx(handle, ctypes.c_void_p(address), ctypes.byref(info), ctypes.sizeof(info)):
            if info.State == MEM_COMMIT:
                yield info.AllocationBase or 0, info.RegionSize, TYPES.get(info.Type, hex(info.Type)), info.Protect
            address = (info.BaseAddress or 0) + info.RegionSize
            if address >= 1 << 47:
                break
    finally:
        kernel32.CloseHandle(handle)


def classify(pid: int, bases: list[int]) -> dict[int, str]:
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.restype = wt.HANDLE
    kernel32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
                                           ctypes.POINTER(ctypes.c_size_t)]
    handle = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    if not handle:
        return {}
    out = {}
    try:
        buf, got = ctypes.create_string_buffer(32), ctypes.c_size_t()
        for base in bases:
            if not kernel32.ReadProcessMemory(handle, ctypes.c_void_p(base), buf, 32, ctypes.byref(got)):
                out[base] = "unreadable"
            elif buf.raw[16:20] == bytes.fromhex("eeffeeff"):
                out[base] = "C heap"
            elif buf.raw == bytes(32):
                out[base] = "zeros"
            else:
                out[base] = "other"
    finally:
        kernel32.CloseHandle(handle)
    return out


def bucket(size: int) -> str:
    for limit, name in ((1 << 16, "<64 KB"), (1 << 20, "64 KB-1 MB"), (4 << 20, "1-4 MB"), (16 << 20, "4-16 MB"),
                        (64 << 20, "16-64 MB")):
        if size < limit:
            return name
    return ">=64 MB"


def report(pid: int, top: int = 12) -> list[str]:
    by_type: collections.Counter[str] = collections.Counter()
    allocations: collections.Counter[int] = collections.Counter()
    executable = write_combined = 0
    for base, size, kind, protect in regions(pid):
        by_type[kind] += size
        if kind == "private":
            allocations[base] += size
            if protect & 0xF0:
                executable += size
            if protect & 0x400:
                write_combined += size
    mb = 1 << 20
    lines = [f"process {pid}: committed " + ", ".join(f"{k} {v / mb:,.0f} MB" for k, v in by_type.most_common())]
    buckets: dict[str, list[int]] = collections.defaultdict(lambda: [0, 0])
    for size in allocations.values():
        b = buckets[bucket(size)]
        b[0] += 1
        b[1] += size
    lines.append("private committed by reservation size | reservations | MB")
    for name in ("<64 KB", "64 KB-1 MB", "1-4 MB", "4-16 MB", "16-64 MB", ">=64 MB"):
        if name in buckets:
            lines.append(f"  {name} | {buckets[name][0]:,} | {buckets[name][1] / mb:,.1f}")
    kinds: collections.Counter[str] = collections.Counter()
    large = [base for base, size in allocations.items() if size >= 4 << 20]
    for base, kind in classify(pid, large).items():
        kinds[kind] += allocations[base]
    lines.append("private reservations of 4 MB or more by their start: "
                 + ", ".join(f"{k} {v / mb:,.0f} MB" for k, v in kinds.most_common())
                 + f"; executable private {executable / mb:,.0f} MB; write-combined private (GPU driver) "
                   f"{write_combined / mb:,.0f} MB")
    lines.append("largest private reservations (MB): "
                 + ", ".join(f"{size / mb:.1f}" for _base, size in allocations.most_common(top)))
    return lines


def summary(pid: int) -> str:
    private: collections.Counter[int] = collections.Counter()
    write_combined = executable = 0
    for base, size, kind, protect in regions(pid):
        if kind != "private":
            continue
        private[base] += size
        if protect & 0x400:
            write_combined += size
        elif protect & 0xF0:
            executable += size
    if not private:
        return ""
    kinds = classify(pid, list(private))
    mb = 1 << 20
    heap = sum(private[base] for base, kind in kinds.items() if kind == "C heap")
    small = sum(size for base, size in private.items() if size < 4 << 20 and kinds.get(base) != "C heap")
    other = sum(size for base, size in private.items() if size >= 4 << 20 and kinds.get(base) != "C heap")
    return (f"private {sum(private.values()) / mb:,.0f} MB: under-4-MB reservations {small / mb:,.0f} MB, C heap"
            f" {heap / mb:,.0f} MB, other 4-MB+ reservations {other / mb:,.0f} MB; of all these write-combined"
            f" (GPU driver) {write_combined / mb:,.0f} MB, JIT code {executable / mb:,.0f} MB")


def totals(pid: int) -> tuple[int, int]:
    private = write_combined = 0
    for _base, size, kind, protect in regions(pid):
        if kind == "private":
            private += size
            if protect & 0x400:
                write_combined += size
    return private, write_combined


def snapshot(pid: int) -> dict[int, dict]:
    out: dict[int, dict] = {}
    for base, size, kind, protect in regions(pid):
        if kind != "private":
            continue
        r = out.setdefault(base, {"size": 0, "wc": False, "exec": False})
        r["size"] += size
        r["wc"] = r["wc"] or bool(protect & 0x400)
        r["exec"] = r["exec"] or bool(protect & 0xF0)
    for base, look in classify(pid, list(out)).items():
        out[base]["kind"] = look
    return out


def label(r: dict) -> str:
    size = "under 4 MB" if r["size"] < 4 << 20 else "4 MB or more"
    flags = " write-combined" if r["wc"] else " executable" if r["exec"] else ""
    return f"{size}, starts {r.get('kind', '?')}{flags}"


def diff(old: dict[int, dict], new: dict[int, dict]) -> list[str]:
    mb = 1 << 20
    rows: dict[str, list[float]] = collections.defaultdict(lambda: [0, 0.0, 0, 0.0, 0.0])
    for base, r in new.items():
        row = rows[label(r)]
        if base not in old:
            row[0] += 1
            row[1] += r["size"]
        else:
            row[4] += r["size"] - old[base]["size"]
    for base, r in old.items():
        if base not in new:
            row = rows[label(r)]
            row[2] += 1
            row[3] += r["size"]
    lines = ["reservations by kind | made | MB | released | MB | change in kept MB | net MB"]
    for name, (made, made_mb, gone, gone_mb, grown) in sorted(rows.items(), key=lambda kv: -abs(kv[1][1] - kv[1][3] + kv[1][4])):
        lines.append(f"{name} | {made:,} | {made_mb / mb:,.1f} | {gone:,} | {gone_mb / mb:,.1f} | {grown / mb:+,.1f}"
                     f" | {(made_mb - gone_mb + grown) / mb:+,.1f}")
    return lines


def modules(pid: int) -> list[tuple[int, int, str]]:
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    psapi = ctypes.WinDLL("psapi", use_last_error=True)
    kernel32.OpenProcess.restype = wt.HANDLE
    psapi.EnumProcessModulesEx.argtypes = [wt.HANDLE, ctypes.POINTER(ctypes.c_void_p), wt.DWORD,
                                           ctypes.POINTER(wt.DWORD), wt.DWORD]
    psapi.GetModuleBaseNameW.argtypes = [wt.HANDLE, ctypes.c_void_p, wt.LPWSTR, wt.DWORD]

    class MODULEINFO(ctypes.Structure):
        _fields_ = [("base", ctypes.c_void_p), ("size", wt.DWORD), ("entry", ctypes.c_void_p)]

    psapi.GetModuleInformation.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.POINTER(MODULEINFO), wt.DWORD]
    handle = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    if not handle:
        return []
    try:
        array, needed = (ctypes.c_void_p * 2048)(), wt.DWORD()
        if not psapi.EnumProcessModulesEx(handle, array, ctypes.sizeof(array), ctypes.byref(needed), 3):
            return []
        out = []
        for i in range(min(needed.value // ctypes.sizeof(ctypes.c_void_p), 2048)):
            name, info = ctypes.create_unicode_buffer(260), MODULEINFO()
            psapi.GetModuleBaseNameW(handle, array[i], name, 260)
            if psapi.GetModuleInformation(handle, array[i], ctypes.byref(info), ctypes.sizeof(info)):
                out.append((info.base or 0, (info.base or 0) + info.size, name.value))
        return sorted(out)
    finally:
        kernel32.CloseHandle(handle)


def read_reservation(pid: int, base: int, limit: int = 32 << 20) -> list[tuple[int, bytes]]:
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.restype = wt.HANDLE
    kernel32.VirtualQueryEx.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.POINTER(MEMORY_BASIC_INFORMATION),
                                        ctypes.c_size_t]
    kernel32.VirtualQueryEx.restype = ctypes.c_size_t
    kernel32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
                                           ctypes.POINTER(ctypes.c_size_t)]
    handle = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    if not handle:
        return []
    out, total = [], 0
    try:
        address, info = base, MEMORY_BASIC_INFORMATION()
        while total < limit and kernel32.VirtualQueryEx(handle, ctypes.c_void_p(address), ctypes.byref(info),
                                                        ctypes.sizeof(info)):
            if (info.AllocationBase or 0) != base:
                break
            if info.State == MEM_COMMIT and not info.Protect & 0x101:
                size = min(info.RegionSize, limit - total)
                buf, got = ctypes.create_string_buffer(size), ctypes.c_size_t()
                if kernel32.ReadProcessMemory(handle, ctypes.c_void_p(address), buf, size, ctypes.byref(got)):
                    out.append((address, buf.raw[:got.value]))
                    total += got.value
            address = (info.BaseAddress or 0) + info.RegionSize
    finally:
        kernel32.CloseHandle(handle)
    return out


def describe_block(data: bytes, mods: list[tuple[int, int, str]]) -> str:
    if not data:
        return "nothing readable"
    n = len(data)
    zeros = data.count(0) / n
    words = n // 4
    alpha = sum(1 for i in range(3, words * 4, 4 * 16) if data[i] in (0, 0xFF)) / max(1, len(range(3, words * 4, 64)))
    pointers: collections.Counter[str] = collections.Counter()
    starts = [m[0] for m in mods]
    for (value,) in struct.iter_unpack("<Q", data[: n - n % 8]):
        if value < 0x10000 or value >> 47:
            continue
        i = bisect.bisect_right(starts, value) - 1
        if i >= 0 and value < mods[i][1]:
            pointers[mods[i][2]] += 1
    strings = sorted({s.decode() for s in re.findall(rb"[ -~]{8,}", data[: 4 << 20])}, key=len, reverse=True)[:6]
    head = data[64:96].hex()
    return (f"{n / (1 << 20):.1f} MB read, zero bytes {zeros:.0%}, alpha-like {alpha:.0%}; pointers into modules: "
            + (", ".join(f"{k} {v}" for k, v in pointers.most_common(5)) or "none")
            + f"; strings: {strings!r}; bytes 64-96: {head}")


def row_width(data: bytes, low: int = 64, high: int = 4096) -> int | None:
    words = len(data) // 4
    if words < high * 4:
        return None
    best, best_score, scores = None, None, []
    sample = range(words // 3, words // 3 + 4096 * 4, 7)
    for width in range(low, high + 1, 4 if high > 1024 else 1):
        score = sum(abs(data[4 * i] - data[4 * (i + width)]) + abs(data[4 * i + 1] - data[4 * (i + width) + 1])
                    for i in sample if i + width < words)
        scores.append(score)
        if best_score is None or score < best_score:
            best, best_score = width, score
    scores.sort()
    return best if best_score is not None and best_score < scores[len(scores) // 2] / 3 else None


def inspect_new(pid: int, old: dict[int, dict], minimum: int = 1 << 20, dump_dir: str | None = None) -> list[str]:
    new = snapshot(pid)
    mods = modules(pid)
    lines = []
    for base, r in sorted(new.items()):
        if base in old or r["size"] < minimum or r["wc"] or r["exec"]:
            continue
        data = b"".join(chunk for _address, chunk in read_reservation(pid, base))
        width = row_width(data) if r["size"] >= 4 << 20 and data.count(0) < len(data) // 2 else None
        if dump_dir and r["size"] >= 4 << 20:
            pathlib.Path(dump_dir).mkdir(parents=True, exist_ok=True)
            pathlib.Path(dump_dir, f"{base:x}.bin").write_bytes(data)
        lines.append(f"new reservation {base:#x} ({r['size'] / (1 << 20):.1f} MB committed, starts {r.get('kind')}): "
                     + describe_block(data, mods) + (f"; rows of {width} pixels?" if width else ""))
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("pid", type=int, nargs="?")
    parser.add_argument("--name", help="the process by image name (e.g. hl, Brawlhalla) instead of a pid")
    parser.add_argument("--top", type=int, default=12)
    parser.add_argument("--save", help="also write every private reservation to this JSON file (for --diff)")
    parser.add_argument("--diff", help="instead of the report: what changed since the --save file, by kind")
    parser.add_argument("--inspect-new", help="instead of the report: what each reservation of 1 MB or more made "
                                              "since the --save file holds (zeros, pixels, module pointers, strings)")
    args = parser.parse_args(argv)
    pid = args.pid
    if pid is None and args.name:
        out = subprocess.run(["powershell", "-NoProfile", "-Command", f"(Get-Process {args.name}).Id"],
                             capture_output=True, text=True).stdout.split()
        pid = int(out[0]) if out else None
    if pid is None:
        print("no process", file=sys.stderr)
        return 2
    if args.inspect_new:
        old = {int(k): v for k, v in json.loads(open(args.inspect_new, encoding="utf-8").read()).items()}
        print("\n".join(inspect_new(pid, old)))
        return 0
    if args.diff:
        old = {int(k): v for k, v in json.loads(open(args.diff, encoding="utf-8").read()).items()}
        print("\n".join(diff(old, snapshot(pid))))
        return 0
    print("\n".join(report(pid, args.top)))
    if args.save:
        with open(args.save, "w", encoding="utf-8") as f:
            json.dump({str(k): v for k, v in snapshot(pid).items()}, f)
    return 0


if __name__ == "__main__":
    sys.exit(main())
