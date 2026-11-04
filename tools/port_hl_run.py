"""runs the port's HashLink build against the test copy of the install and reports what happened.

    python tools/port_haxe_compile.py build-hl --no-convert --out build/port-hl/run/game.hl
    python tools/port_hl_run.py --seconds 30

sets up ``build/port-hl/run`` with Lime's HashLink runtime (``hl.exe``, ``libhl.dll``, the ``.hdll`` files and
``lime.hdll``), runs ``game.hl`` with ``BH_PORT_APP_DIR`` set to the test install (``build/game-test/port`` by default)
and ``BH_PORT_STORAGE_DIR`` set to ``build/port-hl/storage``, samples the process's memory, stops it after
``--seconds`` and prints the run's boot log (``build/port-hl/boot.txt``; repeated OpenFL/Lime stack frames left out).
"""

from __future__ import annotations

import argparse
import concurrent.futures
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
LIME = ROOT / ".tools" / "haxelib" / "lime" / "8,3,2"
RUN = ROOT / "build" / "port-hl" / "run"
STORAGE = ROOT / "build" / "port-hl" / "storage"
GAME = ROOT / "build" / "game-test" / "port"
BOOT_LOG = Path(os.environ.get("USERPROFILE", str(Path.home()))) / "Documents" / "Bifrost" / "bh-port-boot.txt"
SMOKE_DIR = BOOT_LOG.parent / "bh-port-smoke"
LINE_LIMIT = 400
RUNTIME_FILES = ("hl.exe", "libhl.dll", "fmt.hdll", "ssl.hdll", "ui.hdll", "uv.hdll", "mysql.hdll")
ANGLE_FILES = ("libEGL.dll", "libGLESv2.dll", "d3dcompiler_47.dll")
DEFAULT_LIME = ROOT / "build" / "port-lime" / "gl"
DEFAULT_LIBHL = ROOT / "build" / "port-hashlink" / "libhl.dll"


def prepare(run: Path) -> None:
    run.mkdir(parents=True, exist_ok=True)
    sources = [LIME / "templates" / "bin" / "hl" / "Windows64" / name for name in RUNTIME_FILES]
    sources.append(LIME / "ndll" / "Windows64" / "lime.hdll")
    for source in sources:
        if not source.exists():
            raise FileNotFoundError(f"missing {source}: run python tools/setup_openfl.py")
        target = run / source.name
        if not target.exists() or target.stat().st_size != source.stat().st_size:
            shutil.copy2(source, target)
    custom = os.environ.get("BH_PORT_LIBHL")
    if custom is None and DEFAULT_LIBHL.exists():
        custom = str(DEFAULT_LIBHL)
    elif custom is None:
        print(f"warning: {DEFAULT_LIBHL} missing (python tools/port_hashlink_build.py); running Lime's libhl.dll")
    if custom == "stock":
        custom = None
    target = run / "libhl.dll"
    if custom:
        shutil.copy2(custom, target)
    elif target.read_bytes() != (LIME / "templates" / "bin" / "hl" / "Windows64" / "libhl.dll").read_bytes():
        shutil.copy2(LIME / "templates" / "bin" / "hl" / "Windows64" / "libhl.dll", target)
    custom_lime = os.environ.get("BH_PORT_LIME")
    if custom_lime is None and (DEFAULT_LIME / "lime.hdll").exists():
        custom_lime = str(DEFAULT_LIME)
    elif custom_lime is None:
        print(f"warning: {DEFAULT_LIME / 'lime.hdll'} missing (python data/tools/port_lime_build.py); Lime's own lime.hdll"
              " leaks every image it decodes")
    if custom_lime == "stock":
        custom_lime = None
    stock = LIME / "ndll" / "Windows64" / "lime.hdll"
    if custom_lime:
        for source in Path(custom_lime).iterdir():
            if source.suffix.lower() in (".hdll", ".dll"):
                shutil.copy2(source, run / source.name)
        for name in ANGLE_FILES:
            if not (Path(custom_lime) / name).exists():
                (run / name).unlink(missing_ok=True)
    else:
        if (run / "lime.hdll").read_bytes() != stock.read_bytes():
            shutil.copy2(stock, run / "lime.hdll")
        for name in ANGLE_FILES:
            (run / name).unlink(missing_ok=True)
    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))
    from tools import port_native_build
    sources = list(port_native_build.SRC.glob("*.[ch]"))
    newest = max(path.stat().st_mtime for path in sources) if sources else 0
    outputs = [run / "bhsound.hdll", run / "Adobe AIR.dll"]
    if any(not out.exists() or out.stat().st_mtime < newest for out in outputs):
        if port_native_build.build(run) != 0:
            raise RuntimeError("building the native helpers failed (tools/port_native_build.py)")


def _memory_mb_win32(pid: int) -> tuple[int, int] | None:
    import ctypes
    from ctypes import wintypes

    class Counters(ctypes.Structure):
        _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                    ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t),
                    ("PrivateUsage", ctypes.c_size_t)]

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
    kernel32.K32GetProcessMemoryInfo.argtypes = (wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD)
    kernel32.CloseHandle.argtypes = (wintypes.HANDLE,)
    handle = kernel32.OpenProcess(0x1000 | 0x0010, False, pid)
    if not handle:
        return None
    try:
        counters = Counters()
        counters.cb = ctypes.sizeof(Counters)
        if not kernel32.K32GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
            return None
        return counters.WorkingSetSize >> 20, counters.PrivateUsage >> 20
    finally:
        kernel32.CloseHandle(handle)


def memory_mb(pid: int) -> tuple[int, int] | None:
    if sys.platform == "win32":
        try:
            return _memory_mb_win32(pid)
        except (OSError, AttributeError):
            pass
    command = (f"$p = Get-Process -Id {pid} -ErrorAction SilentlyContinue; "
               "if ($p) { '{0} {1}' -f [int]($p.WorkingSet64/1MB), [int]($p.PrivateMemorySize64/1MB) }")
    result = subprocess.run(["powershell", "-NoProfile", "-Command", command], capture_output=True, text=True)
    parts = result.stdout.split()
    return (int(parts[0]), int(parts[1])) if len(parts) == 2 else None


def gpu_mb(pid: int) -> tuple[int, int] | None:
    if sys.platform != "win32":
        return None
    command = (f"$s = (Get-Counter '\\GPU Process Memory(pid_{pid}_*)\\Dedicated Usage',"
               f"'\\GPU Process Memory(pid_{pid}_*)\\Shared Usage' -ErrorAction SilentlyContinue).CounterSamples; "
               "if ($s) { '{0} {1}' -f [int](($s | ? Path -like '*dedicated*' | Measure CookedValue -Sum).Sum/1MB),"
               " [int](($s | ? Path -like '*shared*' | Measure CookedValue -Sum).Sum/1MB) }")
    child = subprocess.Popen(["powershell", "-NoProfile", "-Command", command], stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True)
    try:
        stdout, _ = child.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        child.kill()
        child.communicate()
        return None
    finally:
        CpuWatch.add_helper(child)
    parts = stdout.split()
    return (int(parts[0]), int(parts[1])) if len(parts) == 2 else None


class CpuWatch:

    helper_seconds = 0.0

    def __init__(self, pid: int) -> None:
        self.pid = pid
        self.ok = sys.platform == "win32"
        self.last: tuple[float, float] | None = None
        self.window: list[tuple[float, float]] = []
        self.span_start: tuple[float, float] | None = None
        self.peak = 0.0
        self.lines: list[str] = []

    @staticmethod
    def _times(handle) -> float:
        import ctypes
        from ctypes import wintypes
        t = [wintypes.FILETIME() for _ in range(4)]
        if not ctypes.windll.kernel32.GetProcessTimes(handle, *[ctypes.byref(x) for x in t]):
            return 0.0
        return sum((x.dwHighDateTime << 32 | x.dwLowDateTime) for x in t[2:]) / 1e7

    @classmethod
    def add_helper(cls, child: subprocess.Popen) -> None:
        handle = getattr(child, "_handle", None)
        if sys.platform == "win32" and handle is not None:
            try:
                cls.helper_seconds += cls._times(int(handle))
            except (OSError, ValueError):
                pass

    def _other(self) -> tuple[float, float] | None:
        import ctypes
        from ctypes import wintypes
        kernel32 = ctypes.windll.kernel32
        idle, kernel, user = wintypes.FILETIME(), wintypes.FILETIME(), wintypes.FILETIME()
        if not kernel32.GetSystemTimes(ctypes.byref(idle), ctypes.byref(kernel), ctypes.byref(user)):
            return None
        value = lambda x: (x.dwHighDateTime << 32 | x.dwLowDateTime) / 1e7
        busy = value(kernel) + value(user) - value(idle)
        kernel32.OpenProcess.restype = wintypes.HANDLE
        handle = kernel32.OpenProcess(0x1000, False, self.pid)
        if not handle:
            return None
        try:
            game = self._times(handle)
        finally:
            kernel32.CloseHandle(handle)
        own = self._times(kernel32.GetCurrentProcess())
        return time.monotonic(), busy - game - own - CpuWatch.helper_seconds

    def sample(self) -> None:
        if not self.ok:
            return
        try:
            now = self._other()
        except (OSError, AttributeError):
            self.ok = False
            return
        if now is None:
            return
        if self.span_start is None:
            self.span_start = now
        self.window.append(now)
        while len(self.window) > 2 and now[0] - self.window[0][0] > 1.0:
            self.window.pop(0)
        first = self.window[0]
        if now[0] - first[0] >= 0.75:
            self.peak = max(self.peak, (now[1] - first[1]) / (now[0] - first[0]))

    def span(self, name: str) -> None:
        if not self.ok or self.span_start is None or not self.window:
            return
        start, now = self.span_start, self.window[-1]
        if now[0] > start[0]:
            self.lines.append(f"other CPU at span {name}: average {(now[1] - start[1]) / (now[0] - start[0]):.2f} "
                              f"cores, peak {self.peak:.2f} cores")
        self.span_start, self.peak = now, 0.0


def system_commit_mb() -> int | None:
    if sys.platform != "win32":
        return None
    import ctypes
    from ctypes import wintypes

    class Info(ctypes.Structure):
        _fields_ = [("cb", wintypes.DWORD), ("CommitTotal", ctypes.c_size_t), ("CommitLimit", ctypes.c_size_t),
                    ("CommitPeak", ctypes.c_size_t), ("PhysicalTotal", ctypes.c_size_t),
                    ("PhysicalAvailable", ctypes.c_size_t), ("SystemCache", ctypes.c_size_t),
                    ("KernelTotal", ctypes.c_size_t), ("KernelPaged", ctypes.c_size_t),
                    ("KernelNonpaged", ctypes.c_size_t), ("PageSize", ctypes.c_size_t),
                    ("HandleCount", wintypes.DWORD), ("ProcessCount", wintypes.DWORD),
                    ("ThreadCount", wintypes.DWORD)]

    try:
        info = Info()
        info.cb = ctypes.sizeof(Info)
        if not ctypes.WinDLL("kernel32").K32GetPerformanceInfo(ctypes.byref(info), info.cb):
            return None
        return (info.CommitTotal * info.PageSize) >> 20
    except (OSError, AttributeError):
        return None


def others_private_mb(skip: int) -> int | None:
    if sys.platform != "win32":
        return None
    import ctypes
    from ctypes import wintypes
    try:
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.OpenProcess.restype = wintypes.HANDLE
        kernel32.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
        kernel32.K32GetProcessMemoryInfo.argtypes = (wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD)
        kernel32.CloseHandle.argtypes = (wintypes.HANDLE,)
        pids = (wintypes.DWORD * 8192)()
        needed = wintypes.DWORD()
        if not kernel32.K32EnumProcesses(pids, ctypes.sizeof(pids), ctypes.byref(needed)):
            return None
        counters = (ctypes.c_size_t * 11)()
        total = 0
        for pid in pids[:needed.value // ctypes.sizeof(wintypes.DWORD)]:
            if pid in (0, skip):
                continue
            handle = kernel32.OpenProcess(0x1000, False, pid)
            if not handle:
                continue
            try:
                cb = 4 + 4 + 8 * 9
                ctypes.memset(counters, 0, ctypes.sizeof(counters))
                ctypes.cast(counters, ctypes.POINTER(wintypes.DWORD))[0] = cb
                if kernel32.K32GetProcessMemoryInfo(handle, counters, cb):
                    total += counters[9]
            finally:
                kernel32.CloseHandle(handle)
        return total >> 20
    except (OSError, AttributeError):
        return None


class SpanGpu:

    def __init__(self, inspect: bool = False) -> None:
        self.pool = concurrent.futures.ThreadPoolExecutor(1)
        self.reads: list[tuple[str, concurrent.futures.Future]] = []
        self.kinds: list[tuple[str, concurrent.futures.Future]] = []
        self.inspect = inspect
        self.last_snapshot: dict | None = None
        self.blocks: list[tuple[str, concurrent.futures.Future]] = []
        self.commit0 = system_commit_mb()
        self.others0: int | None = None
        self.commits: list[tuple[str, int, int | None]] = []

    def read(self, name: str, pid: int) -> None:
        self.reads.append((name, self.pool.submit(gpu_mb, pid)))
        commit = system_commit_mb()
        if commit is not None and self.commit0 is not None:
            others = others_private_mb(pid)
            if self.others0 is None:
                self.others0 = others
            grown = None if others is None or self.others0 is None else others - self.others0
            self.commits.append((name, commit - self.commit0, grown))
        if name.startswith("menu") or name == "boot":
            self.kinds.append((name, self.pool.submit(procmem_summary, pid)))
            if self.inspect:
                self.blocks.append((name, self.pool.submit(self.inspect_blocks, pid)))

    def inspect_blocks(self, pid: int) -> list[str]:
        try:
            if str(ROOT) not in sys.path:
                sys.path.insert(0, str(ROOT))
            from tools.port_procmem import inspect_new, snapshot
            lines = inspect_new(pid, self.last_snapshot, dump_dir=os.environ.get("BH_PORT_INSPECT_DUMP")) if self.last_snapshot is not None else []
            self.last_snapshot = snapshot(pid)
            return lines
        except Exception as error:
            return [f"inspect failed: {error}"]

    def print(self) -> None:
        for name, future in self.reads:
            sample = future.result()
            if sample:
                print(f"process GPU memory at span {name}: dedicated {sample[0]} MB, shared {sample[1]} MB")
        for name, grown, others in self.commits:
            print(f"system commit at span {name}: {grown:+d} MB since the game started"
                  + (f" (other processes' private {others:+d} MB since the first span)" if others is not None else ""))
        for name, future in self.kinds:
            line = future.result()
            if line:
                print(f"process memory kinds at span {name}: {line}")
        for name, future in self.blocks:
            for line in future.result():
                print(f"new block at span {name}: {line}")
        self.pool.shutdown()


def procmem_summary(pid: int) -> str | None:
    try:
        if str(ROOT) not in sys.path:
            sys.path.insert(0, str(ROOT))
        from tools.port_procmem import summary
        return summary(pid)
    except Exception:
        return None


def take_shot(pid: int, out: Path) -> None:
    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))
    from data.tools.port_boot_check import screenshot
    try:
        out.parent.mkdir(parents=True, exist_ok=True)
        screenshot(pid, out)
        print(f"screenshot: {out}")
    except Exception as error:
        print(f"screenshot failed: {error}")


RUNNER_FILE = ".runner"


def process_alive(pid: int) -> bool:
    if sys.platform != "win32":
        return False
    import ctypes
    from ctypes import wintypes

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.restype = wintypes.HANDLE
    handle = kernel32.OpenProcess(0x1000, False, pid)
    if not handle:
        return False
    try:
        code = wintypes.DWORD()
        return bool(kernel32.GetExitCodeProcess(handle, ctypes.byref(code))) and code.value == 259
    finally:
        kernel32.CloseHandle(handle)


def active_runner(run: Path) -> int | None:
    try:
        pid = int((run / RUNNER_FILE).read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return None
    return pid if pid != os.getpid() and process_alive(pid) else None


def running_games(run: Path) -> tuple[list[str], list[int]]:
    command = ("Get-CimInstance Win32_Process -Filter \"Name='Brawlhalla.exe' or Name='hl.exe'\" | "
               "ForEach-Object { '{0}|{1}|{2}' -f $_.Name, $_.ProcessId, $_.ExecutablePath }")
    try:
        result = subprocess.run(["powershell", "-NoProfile", "-Command", command], capture_output=True, text=True,
                                timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return [], []
    others, leftovers = [], []
    port_root = str(ROOT).lower()
    for line in result.stdout.splitlines():
        parts = line.strip().split("|", 2)
        if len(parts) != 3:
            continue
        name, pid, path = parts
        if name.lower() == "hl.exe" and path and Path(path).resolve() == (run / "hl.exe").resolve():
            leftovers.append(int(pid))
        elif name.lower() == "brawlhalla.exe" and not path.lower().startswith(port_root):
            others.append(f"{path} (pid {pid})")
    return others, leftovers


SPAN_LINE = re.compile(r"(?m)^\S+ \S+ span (\S+)(?: gc)?: frames ")
SHOTS = ROOT / "build" / "shots"
SHOT_LINE = re.compile(r"^\S+ \S+ shot ([A-Za-z0-9_.-]+)\s*$")


def handle_shots(pid: int, log_text: str, taken: set[str], smoke: Path | None = None) -> None:
    for line in log_text.splitlines():
        match = SHOT_LINE.match(line)
        if not match or match.group(1) in taken:
            continue
        name = match.group(1)
        taken.add(name)
        take_shot(pid, SHOTS / f"{name}.png")
        with open((smoke or SMOKE_DIR) / "shot-done.txt", "a", encoding="utf-8") as done:
            done.write(name + "\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--hl", type=Path, default=RUN / "game.hl", help="the HashLink build (build-hl --out)")
    parser.add_argument("--game", type=Path, default=GAME, help="the test copy of the install")
    parser.add_argument("--seconds", type=float, default=30.0, help="stop the game after this long (with --commands: at the latest; it stops once the last command is done)")
    parser.add_argument("--shot", type=Path, action="append", default=[],
                        help="screenshot of the game window before it is stopped (repeat for several, taken"
                             " evenly over the run; the window's own pixels, no input is sent)")
    parser.add_argument("--commands", nargs="*", default=None,
                        help="smoke driver commands (a build-hl --smoke TEST build), e.g. waitmenu \"stats menu\";"
                             " the driver's log is printed at the end")
    parser.add_argument("--profile", type=int, default=0,
                        help="HashLink's sampling profiler (hl --profile N): hlprofile.dump in the run folder, written"
                             " when the game exits by itself (end the commands with quit); read it with"
                             " data/tools/port_hl_profile.py")
    parser.add_argument("--storage", type=Path, default=STORAGE,
                        help="the run's storage folder (BH_PORT_STORAGE_DIR: .sol saves, BhPort); an empty one shows "
                             "what the game creates (default build/port-hl/storage)")
    parser.add_argument("--smoke-dir", type=Path, default=SMOKE_DIR,
                        help="the smoke driver's folder (commands, log, dumps; BH_PORT_SMOKE_DIR): another one than"
                             " the Flash build's lets a native run go beside a Flash run")
    parser.add_argument("--allow-other-game", action="store_true",
                        help="launch even while a Brawlhalla.exe from outside the port runs (by default the run"
                             " refuses: only one game at a time)")
    parser.add_argument("--build", action="store_true",
                        help="first compile the TEST build into --hl (build-hl --smoke --no-convert: the converted tree as"
                             " it is, the runtime layer as it is now); no run if the compile fails")
    parser.add_argument("--libhl", type=Path,
                        help="run with this libhl.dll (tools/port_hashlink_build.py) instead of Lime's (sets"
                             " BH_PORT_LIBHL)")
    parser.add_argument("--lime", type=Path,
                        help="run with the lime.hdll in this folder (data/tools/port_lime_build.py; an ANGLE build's DLLs"
                             " beside it) instead of the default build/port-lime/gl (sets BH_PORT_LIME; 'stock' runs Lime's own)")
    parser.add_argument("--inspect-blocks", action="store_true",
                        help="at each menu span, describe every private reservation of 1 MB or more made since the"
                             " previous menu span (tools/port_procmem.py inspect_new: zeros, pixels, module pointers)")
    args = parser.parse_args(argv)
    if args.libhl:
        os.environ["BH_PORT_LIBHL"] = str(args.libhl.resolve())
    if args.lime:
        os.environ["BH_PORT_LIME"] = "stock" if str(args.lime) == "stock" else str(args.lime.resolve())
    if args.build:
        built = subprocess.run([sys.executable, str(ROOT / "tools" / "port_haxe_compile.py"), "build-hl", "--smoke",
                                "--no-convert", "--out", str(args.hl.resolve())], cwd=ROOT, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        print(built.stdout.strip().splitlines()[-1] if built.stdout.strip() else "build-hl printed nothing")
        if built.returncode != 0:
            print(built.stdout[-3000:], file=sys.stderr)
            return 4
    runner = active_runner(args.hl.resolve().parent)
    if runner is not None:
        print(f"{args.hl.resolve().parent} is in use by another run (runner pid {runner}); run a copy of the build "
              "from another folder", file=sys.stderr)
        return 5
    others, leftovers = running_games(args.hl.resolve().parent)
    for pid in leftovers:
        print(f"stopping a leftover port run (hl.exe pid {pid})")
        subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True)
    if others and not args.allow_other_game:
        print("another game is running, not launching: " + "; ".join(others), file=sys.stderr)
        return 3
    smoke = args.smoke_dir.resolve()
    if args.commands is not None:
        smoke.mkdir(parents=True, exist_ok=True)
        (smoke / "log.txt").unlink(missing_ok=True)
        (smoke / "shot-done.txt").unlink(missing_ok=True)
        (smoke / "commands.txt").write_text("".join(c + "\n" for c in args.commands), encoding="utf-8")
    if not args.hl.exists():
        print(f"missing {args.hl}: python tools/port_haxe_compile.py build-hl --out {args.hl}", file=sys.stderr)
        return 2
    run = args.hl.resolve().parent
    prepare(run)
    (run / RUNNER_FILE).write_text(str(os.getpid()), encoding="utf-8")
    try:
        return _run(args, run, smoke)
    finally:
        (run / RUNNER_FILE).unlink(missing_ok=True)


def _run(args: argparse.Namespace, run: Path, smoke: Path) -> int:
    args.storage.mkdir(parents=True, exist_ok=True)
    run_log = run.parent / "boot.txt"
    run_log.unlink(missing_ok=True)
    env = dict(os.environ, BH_PORT_APP_DIR=str(args.game.resolve()), BH_PORT_STORAGE_DIR=str(args.storage.resolve()),
               BH_PORT_LOG=str(run_log), BH_PORT_SMOKE_DIR=str(smoke))
    started = time.monotonic()
    with open(run.parent / "hl-run.out", "w", encoding="utf-8") as out:
        process = subprocess.Popen([str(run / "hl.exe")] + (["--profile", str(args.profile)] if args.profile else []) + [args.hl.name], cwd=run, env=env, stdout=out,
                                   stderr=subprocess.STDOUT)
        peak = None
        shots = list(args.shot)
        done_line = f"ok {args.commands[-1]} (" if args.commands else None
        finished = False
        shot_names: set[str] = set()
        span_memory: list[tuple[str, tuple[int, int]]] = []
        span_gpu = SpanGpu(args.inspect_blocks)
        cpu_watch = None
        spans_seen: set[str] = set()
        context_seen = no_gl = False
        while process.poll() is None and time.monotonic() - started < args.seconds and not finished:
            time.sleep(0.25 if done_line else 1.0)
            if cpu_watch is None:
                cpu_watch = CpuWatch(process.pid)
            cpu_watch.sample()
            if not context_seen and run_log.exists():
                context = next((line for line in run_log.read_text(encoding="utf-8", errors="replace").splitlines()
                                if "window context:" in line), None)
                if context is not None:
                    context_seen = True
                    no_gl = "(no GL)" in context and os.environ.get("BH_PORT_ALLOW_NO_GL") != "1"
                    if no_gl:
                        print(f"stopping: {context.strip()} (check lime.hdll; BH_PORT_ALLOW_NO_GL=1 runs anyway)")
                        break
            if done_line:
                log = smoke / "log.txt"
                text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
                handle_shots(process.pid, text, shot_names, smoke)
                for name in SPAN_LINE.findall(text):
                    if name not in spans_seen:
                        spans_seen.add(name)
                        sample = memory_mb(process.pid)
                        if sample:
                            span_memory.append((name, sample))
                        span_gpu.read(name, process.pid)
                        cpu_watch.span(name)
                finished = done_line in text
                if finished:
                    for shot in shots:
                        take_shot(process.pid, shot)
                    shots = []
            sample = memory_mb(process.pid)
            if sample and (peak is None or sample[1] > peak[1]):
                peak = sample
            if shots and time.monotonic() - started >= args.seconds * (len(args.shot) - len(shots) + 1) / (
                    len(args.shot)) - 2:
                take_shot(process.pid, shots.pop(0))
        exited = process.poll()
        if exited is None:
            process.kill()
            process.wait()
    elapsed = time.monotonic() - started
    print(f"ran {elapsed:.1f} s; " + (f"exited with {exited}" if exited is not None else
                                      "stopped after the last driver command" if finished else "stopped")
          + (f"; peak working set {peak[0]} MB, private {peak[1]} MB" if peak else ""))
    for name, (working, private) in span_memory:
        print(f"process memory at span {name}: working set {working} MB, private {private} MB")
    span_gpu.print()
    for line in cpu_watch.lines if cpu_watch is not None else []:
        print(line)
    print(f"== boot log ({run_log})")
    if run_log.exists():
        text = run_log.read_bytes().decode("utf-8", "replace")
        for line in text.splitlines():
            if line.startswith("Called from openfl.") or line.startswith("Called from lime."):
                continue
            if len(line) > LINE_LIMIT:
                line = line[:LINE_LIMIT] + f" ... ({len(line) - LINE_LIMIT} more characters in the log file)"
            print(line)
    if args.commands is not None:
        print("== driver log (bh-port-smoke)")
        log = smoke / "log.txt"
        print(log.read_text(encoding="utf-8", errors="replace").rstrip() if log.exists() else "(empty)")
    return 3 if no_gl else 0


if __name__ == "__main__":
    raise SystemExit(main())
