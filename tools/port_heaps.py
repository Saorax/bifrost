"""the new engine on Heaps: pinned libraries, builds and runs.

    python tools/port_heaps.py setup                 # fetch the pinned Heaps and its libraries into .tools/haxelib
    python tools/port_heaps.py spike [--driver sdl|dx] [--shot C:/abs/shot.png]
    python tools/port_heaps.py agal [--driver sdl|dx]  # the game's first draw, 120 frames, game's maps
    python tools/port_heaps.py shapes --dump .../shapes-dump.txt --air .../pix-air.txt [--driver sdl|dx]
    python tools/port_heaps.py game [--hl C:/abs/game.hl] [--seconds 30] [--headless] [--profile 1000] [--watchdog 8]
    python tools/port_heaps.py game --smoke [CMD...] [--no-build] [--shots C:/abs/a.png@1250 ...] --seconds 200
    python tools/port_heaps.py game --smoke --draws --repeat 3 [--against C:/abs/before.hl]  # medians, A/B interleaved
    python tools/port_heaps.py game --smoke --draws [--flicker]  # draw timing; --flicker: the window's black/red check
    python tools/port_heaps.py game --smoke --flicker --repeat 4 [--against C:/abs/before.hl]  # intermittent black frames
    python tools/port_heaps.py game --pix pix11 [--pix-against pix10] [--no-build]  # pixel check: vs AIR, byte-equal?
    python tools/port_heaps.py game --track-match C:/abs/after.txt [--track-against C:/abs/before.txt]  # allocations
    python tools/port_heaps.py boot [--stop-after 3] [--no-build] [--trace-loads] [--trace-errors] [--smoke [CMD...]]

``boot`` builds the headless game only, runs it until the ``--stop-after``th uncaught error (at most ``--seconds``,
default 120) and prints a summary: progress lines, the error count, each distinct error once and the first one's stack.
``--smoke`` builds the TEST build with the smoke driver instead and gives it commands (default: the boot check's
menu, Training, Couch vs bots and back); the driver's log is printed after the summary.

``game`` runs the game build on HashLink 1.15 against the test copy of the install (``build/game-test/port``) with
the port's own storage (``build/port-heaps/storage``), stops it after ``--seconds`` and prints its boot log
(``build/port-heaps/boot.txt``). it refuses to start while a ``Brawlhalla.exe`` runs.

``spike`` compiles ``port/engine-heaps/spike/HeapsSpike.hx`` and runs it on HashLink 1.15, printing the driver,
start-up and frame timings; ``--shot`` saves the scene as PNG.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
HAXE = ROOT / ".tools" / "haxe" / "haxe.exe"
HASHLINK = ROOT / ".tools" / "hashlink"
DXVK = ROOT / ".tools" / "dxvk"
DXC = ROOT / ".tools" / "dxc" / "bin" / "x64"
HAXELIB = ROOT / ".tools" / "haxelib"
DOWNLOADS = ROOT / ".tools" / "downloads" / "heaps-dl"
BUILD = ROOT / "build" / "port-heaps"
SPIKE = ROOT / "port" / "engine-heaps" / "spike"
FORMAT_COMMIT = "775a06f0a7aa64cbd060b5c3ba62f65d7fed684a"
LIBRARIES = (
    ("heaps", "2,1,0", "."),
    ("format", FORMAT_COMMIT, f"format-{FORMAT_COMMIT}"),
    ("hlsdl", "1,15,0", "sdl_release"),
    ("hldx", "1,15,0", "directx_release"),
)
HL_VERSION = "1.15.0"


def game_libhl() -> Path:
    patched = ROOT / "build" / "port-hashlink-1.15" / "libhl.dll"
    return patched if patched.exists() and os.environ.get("BH_PORT_LIBHL", "") != "stock" else HASHLINK / "libhl.dll"


def gc_marks_available() -> bool:
    try:
        return b"hl_gc_mark_stats" in game_libhl().read_bytes()
    except OSError:
        return False


def openal_path() -> Path:
    from tools import port_hashlink_build
    return port_hashlink_build.source("1.15") / "libs" / "openal"


def library_path(name: str) -> Path:
    if name == "hlopenal":
        return openal_path()
    for lib, version, sub in LIBRARIES:
        if lib == name:
            return HAXELIB / lib / version / sub
    raise KeyError(name)


def setup() -> int:
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    for lib, version, sub in LIBRARIES:
        target = HAXELIB / lib / version
        if (target / sub).exists():
            continue
        archive = DOWNLOADS / f"{lib}-{version}.zip"
        if not archive.exists():
            url = (f"https://github.com/HaxeFoundation/{lib}/archive/{version}.zip" if "," not in version
                   else f"https://lib.haxe.org/files/3.0/{lib}-{version}.zip")
            print(f"fetching {url}")
            urllib.request.urlretrieve(url, archive)
        with zipfile.ZipFile(archive) as z:
            z.extractall(target)
        print(f"{lib} {version.replace(',', '.')} -> {target}")
    for name in ("hl.exe", "sdl.hdll", "directx.hdll", "heaps.hdll", "SDL2.dll"):
        if not (HASHLINK / name).exists():
            print(f"missing {HASHLINK / name}: unpack .tools/hashlink-1.15.0-win.zip there")
            return 1
    return 0


def compile_args(main: str, class_paths: list[Path], out: Path, driver: str) -> list[str]:
    args = [str(HAXE), "--main", main, "--hl", str(out), "-D", f"hl-ver={HL_VERSION}",
            "-D", f"{'hlsdl' if driver == 'sdl' else 'hldx'}={HL_VERSION}", "-D", "heaps=2.1.0", "-D", "format=3.7.1",
            "-D", "hlopenal=1.4.0"]
    for path in class_paths + [library_path("heaps"), library_path("format"), library_path("hlopenal"),
                               library_path("hlsdl" if driver == "sdl" else "hldx")]:
        args += ["--class-path", str(path)]
    return args


def build_and_run(main: str, driver: str, env_extra: dict[str, str], timeout: float = 120,
                  game_maps: bool = False) -> int:
    if setup() != 0:
        return 1
    BUILD.mkdir(parents=True, exist_ok=True)
    out = BUILD / f"{main}-{driver}.hl"
    started = time.monotonic()
    args = compile_args(main, [SPIKE, ROOT / "port" / "engine-heaps" / "src"], out, driver)
    if game_maps:
        from tools import port_heaps_stubs
        port_heaps_stubs.patch_heaps()
        args[args.index("--class-path"):args.index("--class-path")] = ["--class-path", str(ROOT / "port" / "runtime" / "haxe")]
        args += ["--class-path", str(port_heaps_stubs.HEAPS_PATCHED)]
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(f"compile {'OK' if result.returncode == 0 else 'FAILED'} in {time.monotonic() - started:.1f} s")
    if result.stdout.strip():
        print(result.stdout.strip()[-4000:])
    if result.returncode != 0:
        return result.returncode
    env = dict(os.environ, **env_extra)
    started = time.monotonic()
    try:
        run = subprocess.run([str(HASHLINK / "hl.exe"), str(out)], cwd=HASHLINK, env=env, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        partial = error.output.decode("utf-8", "replace") if isinstance(error.output, bytes) else error.output or ""
        print(partial.strip()[-4000:])
        print(f"{main} did not exit within {timeout:.0f} s")
        return 1
    print(run.stdout.strip()[-4000:])
    print(f"ran {time.monotonic() - started:.1f} s, exit {run.returncode}")
    return run.returncode


def spike(driver: str, shot: Path | None) -> int:
    return build_and_run("HeapsSpike", driver, {"BH_HEAPS_SHOT": str(shot)} if shot is not None else {}, 60)


def shapes(driver: str, dump: Path, air: Path, out: Path) -> int:
    rc = build_and_run("ShapeBench", driver, {"BH_HEAPS_SHAPES": str(dump), "BH_HEAPS_OUT": str(out)})
    if rc != 0 or not air.exists():
        return rc
    from tools import port_pixcompare
    print("\n".join(port_pixcompare.compare(air, out)[0]))
    print("\n".join(port_pixcompare.levels([out])))
    gradients = gradient_symbols(dump)
    if gradients:
        print(f"\nsymbols with gradients: {len(gradients)}")
        print("\n".join(port_pixcompare.compare(air, out, only=gradients)[0]))
        cairo = dump.parent / "pix-fast.txt"
        if cairo.exists():
            drawn = gradients & set(port_pixcompare.load(out))
            print("\n".join(port_pixcompare.compare(air, cairo, only=drawn)[0]))
    return 0


def gradient_symbols(dump: Path) -> set[str]:
    names: set[str] = set()
    name, gradient, skipped = None, False, False
    for line in dump.read_text(encoding="utf-8").splitlines() + ["S"]:
        if line.startswith("S"):
            if name is not None and gradient and not skipped:
                names.add(name)
            parts = line.split(" ")
            name, gradient, skipped = (parts[1] if len(parts) > 1 else None), False, False
        elif line.startswith("G "):
            gradient = True
        elif line.startswith("U "):
            skipped = True
    return names


GAME_TEST = ROOT / "build" / "game-test" / "port"


def running_games() -> list[str]:
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Brawlhalla.exe", "/FO", "CSV", "/NH"],
                         capture_output=True, text=True).stdout
    return [line for line in out.splitlines() if line.startswith('"Brawlhalla.exe"')]


def process_paths() -> list[tuple[int, str]]:
    import ctypes
    from ctypes import wintypes
    psapi = ctypes.WinDLL("psapi", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
    kernel32.CloseHandle.argtypes = (wintypes.HANDLE,)
    kernel32.QueryFullProcessImageNameW.argtypes = (wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR,
                                                    ctypes.POINTER(wintypes.DWORD))
    ids = (wintypes.DWORD * 8192)()
    got = wintypes.DWORD()
    if not psapi.EnumProcesses(ids, ctypes.sizeof(ids), ctypes.byref(got)):
        return []
    found: list[tuple[int, str]] = []
    for pid in ids[:got.value // ctypes.sizeof(wintypes.DWORD)]:
        handle = kernel32.OpenProcess(0x1000, False, pid)
        if not handle:
            continue
        try:
            buffer = ctypes.create_unicode_buffer(1024)
            size = wintypes.DWORD(1024)
            if kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
                found.append((pid, buffer.value))
        finally:
            kernel32.CloseHandle(handle)
    return found


PORT_GAME_WAIT = 20.0


def running_port_games(processes: list[tuple[int, str]] | None = None) -> list[str]:
    roots = [str(BUILD).lower() + os.sep, str(Path("C:/Coding/BRAWLHALLA PROJECTS/bh-new-engine")).lower() + os.sep]
    if processes is None:
        processes = process_paths()
    return [f"{pid} {path}" for pid, path in processes
            if Path(path).name.lower() == "hl.exe" and any(path.lower().startswith(root) for root in roots)]


def running_other_games(processes: list[tuple[int, str]] | None = None) -> list[str]:
    if processes is None:
        processes = process_paths()
    ours = set(running_port_games(processes))
    return [f"{pid} {path}" for pid, path in processes
            if Path(path).name.lower() in ("hl.exe", "brawlhalla.exe") and f"{pid} {path}" not in ours]


RUN = BUILD / "run"


def prepare_run(dxvk: bool = False) -> Path:
    run = BUILD / "run-dxvk" if dxvk else RUN
    run.mkdir(parents=True, exist_ok=True)
    if dxvk:
        found = sorted(DXVK.glob("dxvk-*/x64"))
        if not found:
            raise RuntimeError(f"no DXVK under {DXVK}: unpack a release from github.com/doitsujin/dxvk there")
        for name in ("d3d11.dll", "dxgi.dll"):
            source, target = found[-1] / name, run / name
            if not target.exists() or target.stat().st_size != source.stat().st_size:
                shutil.copy2(source, target)
    sources = list(HASHLINK.iterdir()) + [DXC / name for name in ("dxcompiler.dll", "dxil.dll") if (DXC / name).exists()]
    for source in sources:
        if source.suffix.lower() in (".exe", ".dll", ".hdll"):
            target = run / source.name
            if not target.exists() or target.stat().st_mtime < source.stat().st_mtime:
                shutil.copy2(source, target)
    import filecmp
    libhl = game_libhl()
    if not filecmp.cmp(libhl, run / "libhl.dll", shallow=False):
        shutil.copy2(libhl, run / "libhl.dll")
    from tools import port_native_build
    sources = list(port_native_build.SRC.glob("*.[ch]"))
    newest = max(path.stat().st_mtime for path in sources) if sources else 0
    outputs = [run / "bhsound.hdll", run / "Adobe AIR.dll"]
    if any(not out.exists() or out.stat().st_mtime < newest for out in outputs):
        if port_native_build.build(run) != 0:
            raise RuntimeError("building the native helpers failed (tools/port_native_build.py)")
    return run


def window_texts(pid: int) -> list[str]:
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    proc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.SendMessageTimeoutW.argtypes = (wintypes.HWND, wintypes.UINT, wintypes.WPARAM, ctypes.c_void_p,
                                           wintypes.UINT, wintypes.UINT, ctypes.c_void_p)
    texts: list[str] = []

    def title_of(hwnd) -> str:
        buffer = ctypes.create_unicode_buffer(512)
        user32.GetWindowTextW(hwnd, buffer, 512)
        return buffer.value

    def text_of(hwnd) -> str:
        buffer = ctypes.create_unicode_buffer(8192)
        user32.SendMessageTimeoutW(hwnd, 0x000D, 8192, buffer, 0x0002, 200, None)
        return buffer.value

    def child(hwnd, _):
        value = text_of(hwnd)
        if value:
            texts.append(value)
        return True

    def top(hwnd, _):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            title = title_of(hwnd)
            texts.append("window: " + title)
            if title == "Fatal Error":
                user32.EnumChildWindows(hwnd, proc(child), 0)
        return True

    user32.EnumWindows(proc(top), 0)
    return texts


HL_STORAGE = ROOT / "build" / "port-hl" / "storage"
SEEDED_SAVES = ("bhport_sbSavedGameData.sol", "bhport_bhProfileData.sol")


def seed_storage(storage: Path) -> None:
    for name in SEEDED_SAVES:
        source, target = HL_STORAGE / "#SharedObjects" / name, storage / "#SharedObjects" / name
        if source.exists() and not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)


PROFILES_KEPT = 10


def game_storage(storage: Path | None = None) -> Path:
    if storage is None:
        storage = BUILD / "storage"
        storage.mkdir(parents=True, exist_ok=True)
        seed_storage(storage)
    else:
        storage.mkdir(parents=True, exist_ok=True)
    return storage


def keep_profile(dump: Path, hl: Path, folder: Path | None = None) -> Path:
    folder = folder or BUILD / "profiles"
    folder.mkdir(parents=True, exist_ok=True)
    kept = folder / f"{hl.stem}-{time.strftime('%m%d-%H%M%S')}.dump"
    shutil.copyfile(dump, kept)
    for old in sorted(folder.glob("*.dump"), key=lambda p: p.stat().st_mtime)[:-PROFILES_KEPT]:
        old.unlink()
    return kept


def game(hl: Path, seconds: float, headless: bool = False, profile: int = 0, watchdog: float = 0,
         trace: bool = False, env_extra: dict[str, str] | None = None, summary: bool = False,
         fail_log: Path | None = None, spans_log: Path | None = None, mem_series: Path | None = None,
         dxvk: bool = False, storage: Path | None = None) -> int:
    if not headless and running_games():
        print("a Brawlhalla.exe is running; not starting the game (one game at a time)")
        return 2
    others = running_port_games()
    waited = time.monotonic() + PORT_GAME_WAIT
    while others and time.monotonic() < waited:
        time.sleep(0.5)
        others = running_port_games()
    if others:
        print("another port game is running; not starting (one at a time): " + "; ".join(others))
        return 2
    if not hl.exists():
        print(f"missing {hl}: python tools/port_heaps_stubs.py stubs --build {hl}" + (" --headless" if headless else ""))
        return 2
    log = BUILD / "boot.txt"
    storage = game_storage(storage)
    log.unlink(missing_ok=True)
    env = dict(os.environ, BH_PORT_APP_DIR=str(GAME_TEST), BH_PORT_STORAGE_DIR=str(storage), BH_PORT_LOG=str(log))
    if "BH_PORT_BROWSER" not in os.environ:
        env["BH_PORT_BROWSER"] = str(BUILD / "browser.txt")
    if watchdog:
        env["BH_PORT_WATCHDOG"] = str(watchdog)
    if trace:
        env["BH_PORT_TRACE"] = "1"
    env.update(env_extra or {})
    if not profile and os.environ.get("BH_PORT_PROFILE", "").isdigit():
        profile = int(os.environ["BH_PORT_PROFILE"])
    started = time.monotonic()
    run = prepare_run(dxvk)
    (run / "hlprofile.dump").unlink(missing_ok=True)
    command = [str(run / "hl.exe")] + (["--profile", str(profile)] if profile else []) + [str(hl)]
    out_path = BUILD / "game-out.txt"
    out_file = open(out_path, "w", encoding="utf-8", errors="replace")
    process = subprocess.Popen(command, cwd=run, env=env, stdout=out_file, stderr=subprocess.STDOUT)
    series = start_mem_series(process, log) if mem_series is not None else None
    stopped = False
    fatal: list[str] = []
    failed = ""
    span_memory: list[tuple[str, tuple[int, int]]] = []
    spans_seen: set[str] = set()
    span_gpu = cpu_watch = None
    stuck: tuple[float, int, str] | None = None
    if spans_log is not None:
        from tools.port_hl_run import SPAN_LINE, CpuWatch, SpanGpu, memory_mb
        span_gpu, cpu_watch = SpanGpu(), CpuWatch(process.pid)
    from tools.port_run_state import keep_lock
    while process.poll() is None and time.monotonic() - started < seconds:
        time.sleep(0.25 if spans_log is not None else 0.5)
        keep_lock()
        if spans_log is not None:
            cpu_watch.sample()
            if spans_log.exists():
                for name in SPAN_LINE.findall(spans_log.read_text(encoding="utf-8", errors="replace")):
                    if name not in spans_seen:
                        spans_seen.add(name)
                        sample = memory_mb(process.pid)
                        if sample:
                            span_memory.append((name, sample))
                        span_gpu.read(name, process.pid)
                        cpu_watch.span(name)
        if fail_log is not None and fail_log.exists():
            failed = first_fail(fail_log.read_text(encoding="utf-8", errors="replace"))
            if failed:
                break
        stuck = stuck_after_uncaught(out_path, log, stuck)
        if stuck and time.monotonic() - stuck[0] > STUCK_SECONDS:
            failed = "uncaught error, then nothing for %.0f s: %s" % (STUCK_SECONDS, stuck[2])
            break
        texts = [] if headless else window_texts(process.pid)
        if any(text == "window: Fatal Error" for text in texts):
            fatal = texts
            break
    if failed:
        process.kill()
        process.wait()
        out_file.close()
        print(("run ended: " if failed.startswith("uncaught") else "smoke step failed, run ended: ") + failed[:300])
        return 4
    if process.poll() is None:
        stopped = not fatal
        process.kill()
        print("HashLink fatal error: " + " | ".join(t for t in fatal if not t.startswith("window:") and t != "OK")
              if fatal else f"stopped after {seconds:.0f} s (still running)")
    else:
        print(f"exited with {process.returncode} after {time.monotonic() - started:.1f} s"
              + (" (the watchdog: a game frame ran too long)" if watchdog and process.returncode == 3 else ""))
        if profile and (run / "hlprofile.dump").exists():
            kept = BUILD / "profile-last.dump"
            shutil.copyfile(run / "hlprofile.dump", kept)
            print(f"profile: python data/tools/port_hl_profile.py {kept} --top 30")
            print(f"profile kept as {keep_profile(kept, hl)}")
    process.wait()
    out_file.close()
    if series is not None:
        series[0].join()
        mem_series.parent.mkdir(parents=True, exist_ok=True)
        mem_series.write_text("seconds\tprivate MB\twrite-combined MB\tlast boot log line\n"
                              + "".join(f"{t:.1f}\t{p}\t{w}\t{line}\n" for t, p, w, line in series[1]),
                              encoding="utf-8")
        print(f"memory series ({len(series[1])} samples) -> {mem_series}")
        print("\n".join(memory_steps(series[1])))
    for name, (working, private) in span_memory:
        print(f"process memory at span {name}: working set {working} MB, private {private} MB")
    if span_gpu is not None:
        span_gpu.print()
        for line in cpu_watch.lines:
            print(line)
    if summary:
        print(boot_summary(log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""))
        return 0 if stopped or process.returncode == 5 else process.returncode
    tail = out_path.read_text(encoding="utf-8", errors="replace").strip()[-3000:]
    if tail:
        print("== output\n" + tail)
    if log.exists():
        print("== boot log\n" + log.read_text(encoding="utf-8", errors="replace")[-6000:])
    return 0 if stopped else 3 if fatal else process.returncode


STUCK_SECONDS = 20.0


def stuck_after_uncaught(out_path: Path, log: Path, stuck: tuple[float, int, str] | None):
    try:
        text = out_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    at = text.find("Uncaught exception")
    if at < 0:
        return None
    size = log.stat().st_size if log.exists() else 0
    if stuck is not None and stuck[1] == size:
        return stuck
    return time.monotonic(), size, text[at:at + 200].replace("\n", " | ")


def start_mem_series(process: subprocess.Popen, log: Path, interval: float = 1.0):
    import threading
    from tools.port_procmem import totals
    samples: list[tuple[float, int, int, str]] = []
    started = time.monotonic()

    def last_line() -> str:
        try:
            with open(log, "rb") as f:
                f.seek(0, 2)
                f.seek(max(0, f.tell() - 4096))
                lines = f.read().decode("utf-8", "replace").strip().splitlines()
            return lines[-1][20:160] if lines else ""
        except OSError:
            return ""

    def run() -> None:
        while process.poll() is None:
            try:
                private, wc = totals(process.pid)
            except OSError:
                break
            samples.append((time.monotonic() - started, private >> 20, wc >> 20, last_line().replace("\t", " ")))
            time.sleep(interval)

    thread = threading.Thread(target=run, daemon=True)
    thread.start()
    return thread, samples


def memory_steps(samples: list[tuple[float, int, int, str]], minimum: int = 16) -> list[str]:
    out = ["memory steps (private / write-combined MB growth while the boot log's last line was):"]
    i = 0
    while i < len(samples):
        j = i
        while j + 1 < len(samples) and samples[j + 1][3] == samples[i][3]:
            j += 1
        before = samples[i - 1] if i > 0 else samples[0]
        dp, dw = samples[j][1] - before[1], samples[j][2] - before[2]
        if dp >= minimum or dw >= minimum:
            out.append(f"  {samples[i][0]:6.1f}-{samples[j][0]:6.1f} s  +{dp:5,} / +{dw:5,}  (now {samples[j][1]:,} / "
                       f"{samples[j][2]:,})  {samples[i][3]}")
        i = j + 1
    return out


def start_flicker(seconds: float) -> tuple[subprocess.Popen, Path]:
    folder = BUILD / "flicker"
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    out = folder / "flicker.txt"
    command = [sys.executable, "-I", str(ROOT / "data" / "tools" / "port_flicker.py"), "--seconds", str(seconds), "--wait", "90",
               "--red-dir", str(folder / "red"), "--red-share", "0.05", "--black-dir", str(folder / "black")]
    handle = open(out, "w", encoding="utf-8", errors="replace")
    return subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT), out


def finish_flicker(sampler: tuple[subprocess.Popen, Path], grace: float = 15) -> str:
    process, out = sampler
    try:
        process.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    text = out.read_text(encoding="utf-8", errors="replace").strip() if out.exists() else ""
    return flicker_lines(text)


def flicker_lines(text: str) -> str:
    lines = [line for line in text.splitlines() if line.startswith(("flicker:", "red samples:", "no visible"))]
    return "\n".join(lines) or "flicker: no result (" + (text.strip()[-300:] or "no output") + ")"


def first_fail(log_text: str) -> str:
    for line in log_text.splitlines():
        if " FAIL " in line[:40]:
            return line
    return ""


DRAWS_SMOKE = ["waitmenu", "draws menu", "training", "wait 600", "draws training", "leave", "waitmenu",
               "draws trainret", "couch", "wait 900", "draws couch", "leave", "waitmenu", "draws couchret",
               "stats done", "quit"]

PIX_SMOKE = ["waitmenu", "wait 120", "pixdump heaps 1", "quit"]

TRACK_SMOKE = ["waitmenu", "couch", "wait 300", "track on 6", "wait 600", "track dump match", "shot track-match", "leave",
               "waitmenu", "wait 30", "shot track-menu", "quit"]
TRACK_LEAVE_SMOKE = ["waitmenu", "couch", "waitclock 30000", "track on 10", "leave", "waitmenu", "track dump match", "quit"]
TRACK_STRESS_SMOKE = ["waitmenu", "closepopup", "couch mode=TIMED time=150 ai=1 bots=7", "waitclock 30000", "track on 6",
                      "wait 600", "track dump match", "leave", "waitmenu", "quit"]
TRACK_ROUTES = {"match": TRACK_SMOKE, "leave": TRACK_LEAVE_SMOKE, "stress": TRACK_STRESS_SMOKE}


def track_windows(route: list[str], windows: int) -> list[str]:
    if windows <= 1:
        return list(route)
    start = route.index(next(c for c in route if c.startswith("track on")))
    end = route.index("track dump match")
    block = route[start:end]
    extra: list[str] = []
    for n in range(2, windows + 1):
        extra += ["wait 600"] + block + [f"track dump match{n}"]
    return route[:end + 1] + extra + route[end + 1:]


PIX_AIR = BUILD / "e0" / "pix-air.txt"


def pix_names(target: Path) -> Path | None:
    names = target / "pixnames.txt"
    if not names.exists():
        sources = sorted((d / "pixnames.txt" for d in BUILD.glob("pix*") if (d / "pixnames.txt").exists()),
                         key=lambda p: p.stat().st_mtime, reverse=True)
        if not sources:
            return None
        shutil.copyfile(sources[0], names)
    return names


def pix_report(dump: Path, against: Path | None) -> tuple[str, bool]:
    from tools import port_pixcompare
    if not dump.exists() or dump.stat().st_size == 0:
        return f"pix: no dump at {dump} (pixnames.txt missing or the run failed)", False
    lines = port_pixcompare.compare(PIX_AIR, dump)[0][:4]
    ok = True
    if against is not None:
        before = against / "pix-heaps.txt"
        if dump.read_bytes() == before.read_bytes():
            lines.append(f"byte-identical to {before}")
        else:
            old, new = port_pixcompare.load(before), port_pixcompare.load(dump)
            changed = sorted(k for k in set(old) | set(new) if old.get(k) != new.get(k))
            lines.append(f"DIFFERS from {before}: {len(changed)} symbols, e.g. {', '.join(changed[:8])}")
            ok = False
    return "\n".join(lines), ok


def draws_report(smoke_log: str, boot_log: str) -> str:
    lines = []
    for line in smoke_log.splitlines():
        body = line[20:] if len(line) > 20 and line[4] == "-" else line
        if body.startswith("draws ") and ": " in body and " draws, " in body:
            lines.append(body)
        elif body.startswith("FAIL") or " FAIL " in body:
            lines.append(body)
    gpu = [line for line in boot_log.splitlines() if "gpu at frame" in line]
    if gpu:
        last = gpu[-1]
        at = last.find("vector draws")
        lines.append(last[at:at + 900] if at >= 0 else last[:900])
    return "\n".join(lines)


def flicker_tally(reports: list[str]) -> str:
    import re
    counts = []
    for text in reports:
        found = re.search(r"real-to-black (\d+)", text)
        counts.append(int(found.group(1)) if found else -1)
    return f"{sum(1 for c in counts if c > 0)} of {len(counts)} ({', '.join(str(c) for c in counts)})"


def draws_medians(reports: list[str]) -> str:
    import re
    import statistics
    phases: dict[str, list[tuple[float, float]]] = {}
    pattern = re.compile(r"^draws (\S+): \d+ draws, ([\d.]+) ms.*on-stage rasters \d+ \(([\d.]+) ms")
    for report in reports:
        for line in report.splitlines():
            m = pattern.match(line)
            if m:
                phases.setdefault(m.group(1), []).append((float(m.group(2)), float(m.group(3))))
    out = [f"medians over {len(reports)} runs (draws + on-stage rasters = sum, ms; each run's sum):"]
    for phase, runs in phases.items():
        d = statistics.median(r[0] for r in runs)
        r = statistics.median(r[1] for r in runs)
        each = ", ".join(f"{a + b:.0f}" for a, b in runs)
        out.append(f"  {phase}: {d:.0f} + {r:.0f} = {d + r:.0f} ({each})")
    return "\n".join(out)


def boot_summary(text: str, stack_lines: int = 16) -> str:
    import re
    from collections import Counter
    stamp = re.compile(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d ")
    lines = text.splitlines()
    out = [line for line in lines if stamp.match(line) and " boot:" in line[:30]]
    out += [line[:300] for line in lines if stamp.match(line) and (" load:" in line[:30] or " error made:" in line[:40])][:40]
    errors = [(i, m) for i, line in enumerate(lines) if (m := re.match(stamp.pattern + r"uncaught in frame (\d+): (.*)", line))]
    out.append(f"uncaught errors: {len(errors)}")
    first_frame: dict[str, str] = {}
    for _, m in errors:
        first_frame.setdefault(m.group(2), m.group(1))
    for message, n in Counter(m.group(2) for _, m in errors).most_common(8):
        out.append(f"  {n:5} x {message[:160]} (first in frame {first_frame[message]})")
    if errors:
        start = errors[0][0]
        stack = [line for line in lines[start + 1:start + 1 + stack_lines * 2] if line.strip()]
        out.append("first error's stack:")
        for line in stack[:stack_lines]:
            if stamp.match(line):
                break
            out.append("  " + line)
    return "\n".join(out)


def without_option(argv: list[str], option: str) -> list[str]:
    out, skipping = [], False
    for arg in argv:
        if arg == option:
            skipping = True
        elif skipping and not arg.startswith("--"):
            continue
        else:
            skipping = False
            out.append(arg)
    return out


def frame_difference(a: Path, b: Path) -> str:
    if not a.exists() or not b.exists():
        return f"missing {a if not a.exists() else b}"
    try:
        from PIL import Image, ImageChops
    except ImportError:
        return "byte-equal files" if a.read_bytes() == b.read_bytes() else "files differ (no PIL to compare pixels)"
    ia, ib = Image.open(a).convert("RGBA"), Image.open(b).convert("RGBA")
    if ia.size != ib.size:
        return f"sizes differ {ia.size} {ib.size}"
    diff = ImageChops.difference(ia, ib)
    box = diff.getbbox(alpha_only=False)
    if box is None:
        return "pixel-equal"
    off = sum(1 for p in diff.getdata() if max(p) > 0)
    return f"{off} pixels differ in {box}"


def keep_log(to: Path) -> None:
    log = BUILD / "boot.txt"
    if log.exists():
        to.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(log, to)


def shots_ab(args: argparse.Namespace, given: list[str]) -> int:
    name, _, value = args.shots_env.partition("=")
    os.environ.setdefault("HL_RANDOM_SEED", "1")
    base = without_option(given, "--shots-env")
    first = main(base)
    logs = Path(args.shots[0].rsplit("@", 1)[0]).parent
    keep_log(logs / "boot.a.txt")
    other = [shot.replace(".png@", ".b.png@") for shot in args.shots]
    rest = without_option(base, "--shots")
    had = os.environ.get(name)
    os.environ[name] = value
    try:
        second = main(rest + ["--shots", *other] + ([] if "--no-build" in rest else ["--no-build"]))
    finally:
        if had is None:
            os.environ.pop(name, None)
        else:
            os.environ[name] = had
    keep_log(logs / "boot.b.txt")
    print(f"boot logs: {logs / 'boot.a.txt'} (as given), {logs / 'boot.b.txt'} ({name}={value})")
    same = True
    for a, b in zip(args.shots, other):
        line = frame_difference(Path(a.rsplit("@", 1)[0]), Path(b.rsplit("@", 1)[0]))
        same = same and line == "pixel-equal"
        print(f"shots {a.rsplit('@', 1)[1]} vs {name}={value}: {line}")
    return first or second or (0 if same else 2)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("setup", "spike", "agal", "shapes", "game", "boot"))
    parser.add_argument("--driver", choices=("sdl", "dx"), default="sdl")
    parser.add_argument("--shot", type=Path, help="spike: save the scene as PNG (absolute path)")
    parser.add_argument("--dump", type=Path, help="shapes: the driver's shapes-dump.txt")
    parser.add_argument("--air", type=Path, help="shapes: AIR's pix-air.txt of the same pixnames")
    parser.add_argument("--out", type=Path, help="shapes: the GPU's pix dump (default beside --dump)")
    parser.add_argument("--hl", type=Path, default=BUILD / "e2" / "game.hl", help="game: the build to run")
    parser.add_argument("--seconds", type=float, default=30, help="game: stop it after this long")
    parser.add_argument("--spans", action="store_true",
                        help="game --smoke: measure the process at each driver span (memory, GPU memory, other "
                             "programs' CPU) as port_hl_run.py does; port_soak.py --engine heaps passes it")
    parser.add_argument("--mem-series", type=Path,
                        help="game: private and write-combined memory each second, with the boot log's line then, "
                             "as TSV at this absolute path; the lines memory grew after are printed")
    parser.add_argument("--dxvk", action="store_true",
                        help="game: run from build/port-heaps/run-dxvk, DXVK's d3d11/dxgi beside hl.exe (a DirectX 11 "
                             "build drawn through Vulkan)")
    parser.add_argument("--headless", action="store_true", help="game: a headless build (no window, GPU or sound)")
    parser.add_argument("--storage", type=Path,
                        help="game: this absolute storage folder instead of build/port-heaps/storage, not seeded with "
                             "the OpenFL runs' saves (an empty one checks what a fresh install writes)")
    parser.add_argument("--profile", type=int, default=0, help="game: hl --profile N (samples per second)")
    parser.add_argument("--watchdog", type=float, default=0, help="game: end the run on a frame over N seconds")
    parser.add_argument("--trace", action="store_true", help="game: log each frame's steps")
    parser.add_argument("--keep-going", action="store_true",
                        help="game --smoke: run on after a failed step (default: the run ends at the first FAIL)")
    parser.add_argument("--stop-after", type=int, default=3, help="boot: stop at the Nth uncaught error")
    parser.add_argument("--no-build", action="store_true", help="boot: run the last headless build")
    parser.add_argument("--trace-loads", action="store_true", help="boot: log SWF loads and archive file states")
    parser.add_argument("--trace-errors", action="store_true", help="boot: log every Flash Error made")
    parser.add_argument("--smoke-dir", type=Path, default=None,
                        help="boot --smoke: the driver's folder (default build/port-heaps/smoke); its whole log is "
                             "printed (port_replay_suite.py --engine heaps)")
    parser.add_argument("--smoke", nargs="*", default=None,
                        help="boot/game: the TEST build with the smoke driver and these commands (none: the default "
                             "smoke, then quit); game builds e2/game-smoke.hl unless --hl or --no-build")
    parser.add_argument("--draws", action="store_true",
                        help="game --smoke: E4's timing route (DRAWS_SMOKE) and only its numbers printed")
    parser.add_argument("--repeat", type=int, default=1,
                        help="game --draws / --flicker: run N times (built once); --draws prints each phase's median, "
                             "--flicker the runs with black frames")
    parser.add_argument("--against", type=Path, default=None,
                        help="game --draws --repeat N: alternate each run with one of this build (absolute path, e.g. "
                             "a copy of e2/game-smoke.hl made before a change) and print both builds' medians")
    parser.add_argument("--pix", default=None,
                        help="game: E4's pixel check into build/port-heaps/NAME (pixdump of the 400 names, vs AIR)")
    parser.add_argument("--pix-against", default=None,
                        help="game --pix: an earlier check's folder name (build/port-heaps/NAME): byte-identical?")
    parser.add_argument("--flicker", action="store_true",
                        help="game: run data/tools/port_flicker.py on the window beside it (black, strobes, samples over 5%% red "
                             "saved under build/port-heaps/flicker) and print its line after the run")
    parser.add_argument("--shots", nargs="+", default=None,
                        help="game: save these frames, each C:/abs/path.png@FRAME (the windowed build)")
    parser.add_argument("--track-match", type=Path, default=None,
                        help="game: the TRACK_SMOKE route (600 match frames tracked), its dump copied here (absolute path) "
                             "and summed by site")
    parser.add_argument("--track-route", choices=sorted(TRACK_ROUTES), default="match",
                        help="game --track-match: what is tracked (match: 600 match frames; leave: a match end to the menu; "
                             "stress: 600 frames of an eight-bot timed match)")
    parser.add_argument("--track-windows", type=int, default=1,
                        help="game --track-match (match/stress routes): N tracked windows of the same match, merged "
                             "into one dump (one window varies 20-40%% between runs)")
    parser.add_argument("--track-seed", type=int, default=1,
                        help="game --track-match: HL_RANDOM_SEED for the tracked game (the soak's --seed 1: same maps, "
                             "legends and bots each run, so two builds' dumps compare like with like; -1: unseeded)")
    parser.add_argument("--track-against", type=Path, default=None,
                        help="game --track-match: an earlier dump, the change by site printed")
    parser.add_argument("--shots-env", default=None, metavar="ENV=VALUE",
                        help="game --shots: run again with ENV=VALUE set (frames saved as NAME.b.png, nothing built) and "
                             "compare each pair of frames pixel by pixel: an engine switch's A/B")
    args = parser.parse_args(argv)
    if args.command == "boot":
        smoke = args.smoke is not None
        hl = BUILD / "e2" / ("smoke.hl" if smoke else "headless.hl")
        if not args.no_build:
            from tools import port_heaps_stubs
            started = time.monotonic()
            if port_heaps_stubs.stubs(False, hl, main="port.engine.HeadlessMain",
                                      defines=("port_smoke",) if smoke else ()) != 0:
                return 1
            print(f"headless build in {time.monotonic() - started:.1f} s")
        env = {"BH_PORT_STOP_AFTER_ERRORS": str(args.stop_after)}
        smoke_dir = (args.smoke_dir or BUILD / "smoke").resolve()
        if smoke:
            from data.tools import port_boot_check
            commands = args.smoke or port_boot_check.SMOKE + ["quit"]
            smoke_dir.mkdir(parents=True, exist_ok=True)
            (smoke_dir / "log.txt").unlink(missing_ok=True)
            (smoke_dir / "commands.txt").write_text("".join(c + "\n" for c in commands), encoding="utf-8")
            env["BH_PORT_SMOKE_DIR"] = str(smoke_dir)
        if args.trace_loads:
            env["BH_PORT_TRACE_LOADS"] = "1"
        if args.trace_errors:
            env["BH_PORT_TRACE_ERRORS"] = "1"
        seconds = args.seconds if args.seconds != 30 else 120
        result = game(hl, seconds, headless=True, watchdog=args.watchdog, env_extra=env, summary=True)
        if smoke:
            log = smoke_dir / "log.txt"
            text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else "(none)"
            print("smoke log:\n" + (text if args.smoke_dir else text[-6000:]))
        return result
    if args.command == "setup":
        return setup()
    if args.command == "game" and args.shots and args.shots_env:
        return shots_ab(args, list(argv if argv is not None else sys.argv[1:]))
    if args.command == "game" and (args.draws or args.flicker) and args.repeat > 1:
        import contextlib
        import io
        given = list(argv if argv is not None else sys.argv[1:])
        once = []
        skip = False
        for arg in given:
            if skip:
                skip = False
            elif arg in ("--repeat", "--against"):
                skip = True
            else:
                once.append(arg)
        private: Path | None = None
        if "--hl" in once:
            print(f"note: --hl given, so nothing is built: the runs time {args.hl} as it is")
        if "--hl" not in once:
            default = BUILD / "e2" / "game-smoke.hl"
            if "--no-build" not in once:
                from tools import port_heaps_stubs
                if port_heaps_stubs.stubs(False, default.resolve(), defines=("port_smoke",)) != 0:
                    return 1
            private = BUILD / "e2" / f"repeat-{os.getpid()}.hl"
            shutil.copyfile(default, private)
            once = [a for a in once if a != "--no-build"] + ["--hl", str(private.resolve())]
        reports: list[str] = []
        others: list[str] = []
        whole: list[str] = []
        for run in range(args.repeat):
            for other in ([False, True] if args.against else [False]):
                if other:
                    extra = ["--hl", str(args.against.resolve())]
                else:
                    extra = ["--no-build"] if run and "--no-build" not in once else []
                buffer = io.StringIO()
                with contextlib.redirect_stdout(buffer):
                    main(once + extra)
                head = f"== run {run + 1}{' (against)' if other else ''}"
                whole.append(head + "\n" + buffer.getvalue().strip())
                keep = [line[:170] for line in buffer.getvalue().splitlines()
                        if line.startswith(("draws ", "exited with", "compile ", "smoke step failed", "HashLink fatal",
                                            "a Brawlhalla.exe", "missing ", "flicker:")) or "black game frame" in line][:40]
                print(head + "\n" + "\n".join(keep))
                (others if other else reports).append(buffer.getvalue())
        (BUILD / "repeat-last.txt").write_text("\n".join(whole) + "\n", encoding="utf-8")
        if private is not None:
            private.unlink(missing_ok=True)
        print(f"(every run's whole output: {BUILD / 'repeat-last.txt'})")
        if args.draws:
            print(draws_medians(reports))
            if args.against:
                print(f"against {args.against}:\n" + draws_medians(others))
        if args.flicker:
            print("flicker, runs with black frames after the first real one: " + flicker_tally(reports)
                  + (f"; against: {flicker_tally(others)}" if args.against else ""))
        return 0
    if args.command == "game":
        if args.pix:
            args.smoke = list(PIX_SMOKE)
            args.smoke_dir = BUILD / args.pix
            args.smoke_dir.mkdir(parents=True, exist_ok=True)
            (args.smoke_dir / "pix-heaps.txt").unlink(missing_ok=True)
            if pix_names(args.smoke_dir) is None:
                print("pix: no earlier build/port-heaps/pix*/pixnames.txt to copy")
                return 1
            if args.seconds == 30:
                args.seconds = 150
        if args.draws:
            if args.smoke is None or not args.smoke:
                args.smoke = list(DRAWS_SMOKE)
            if args.seconds == 30:
                args.seconds = 240
        if args.track_match:
            if args.track_windows > 1 and args.track_route == "leave":
                parser.error("--track-windows: the leave route tracks one match end")
            args.smoke = track_windows(TRACK_ROUTES[args.track_route], args.track_windows)
            if args.seconds == 30:
                args.seconds = 240
            for old_dump in ((args.smoke_dir or BUILD / "smoke").resolve()).glob("track-match*.txt"):
                old_dump.unlink(missing_ok=True)
        hl = args.hl if args.hl != BUILD / "e2" / "game.hl" or not args.headless else BUILD / "e2" / "headless.hl"
        env: dict[str, str] = {}
        if args.smoke is not None:
            if args.seconds == 30:
                args.seconds = 240
            if args.hl == BUILD / "e2" / "game.hl":
                hl = BUILD / "e2" / "game-smoke.hl"
                if not args.no_build:
                    from tools import port_heaps_stubs
                    if port_heaps_stubs.stubs(False, hl.resolve(), defines=("port_smoke",)) != 0:
                        return 1
            from data.tools import port_boot_check
            smoke_dir = (args.smoke_dir or BUILD / "smoke").resolve()
            smoke_dir.mkdir(parents=True, exist_ok=True)
            (smoke_dir / "log.txt").unlink(missing_ok=True)
            commands = args.smoke or port_boot_check.SMOKE + ["quit"]
            (smoke_dir / "commands.txt").write_text("".join(c + "\n" for c in commands), encoding="utf-8")
            env["BH_PORT_SMOKE_DIR"] = str(smoke_dir)
        if args.track_match and args.track_seed >= 0:
            env["HL_RANDOM_SEED"] = str(args.track_seed)
        if args.shots:
            env["BH_PORT_SHOTS"] = ",".join(args.shots)
        fail_log = None
        if args.smoke is not None and not args.keep_going:
            fail_log = (args.smoke_dir or BUILD / "smoke").resolve() / "log.txt"
        sampler = start_flicker(args.seconds) if args.flicker and not args.headless else None
        result = game(hl.resolve(), args.seconds, args.headless, args.profile, args.watchdog, args.trace, env_extra=env,
                      fail_log=fail_log,
                      spans_log=(args.smoke_dir or BUILD / "smoke").resolve() / "log.txt" if args.spans else None,
                      mem_series=args.mem_series.resolve() if args.mem_series else None, dxvk=args.dxvk,
                      storage=args.storage.resolve() if args.storage else None)
        if sampler is not None:
            print(finish_flicker(sampler))
        if args.smoke is not None:
            log = (args.smoke_dir or BUILD / "smoke").resolve() / "log.txt"
            text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else "(none)"
            if not log.exists():
                print(f"FAIL no smoke log: was {hl} built with `port_heaps_stubs.py stubs --build ... --define port_smoke`?")
                if result == 0:
                    result = 2
            if args.draws:
                boot = BUILD / "boot.txt"
                print(draws_report(text, boot.read_text(encoding="utf-8", errors="replace") if boot.exists() else ""))
            elif args.pix:
                timing = [line[20:] for line in text.splitlines() if "pixdump heaps:" in line]
                report, same = pix_report(args.smoke_dir / "pix-heaps.txt",
                                          BUILD / args.pix_against if args.pix_against else None)
                print("\n".join(timing + [report]))
                if not same and result == 0:
                    result = 2
            else:
                print("smoke log:\n" + "\n".join(line[:200] for line in text.splitlines()[-30:]))
            boot = BUILD / "boot.txt"
            blacks = [line for line in (boot.read_text(encoding="utf-8", errors="replace").splitlines()
                                        if boot.exists() else []) if "BLACK FRAME" in line]
            for line in blacks:
                print("FAIL black shot: " + line[:200])
            if blacks and result == 0:
                result = 2
            if args.track_match:
                dumped = (args.smoke_dir or BUILD / "smoke").resolve() / "track-match.txt"
                if not dumped.exists():
                    print("track: no track-match.txt (the smoke did not reach its dump)")
                    return result or 1
                target = args.track_match.resolve()
                target.parent.mkdir(parents=True, exist_ok=True)
                from tools import port_hl_track
                extra = [dumped.with_name(f"track-match{n}.txt") for n in range(2, args.track_windows + 1)]
                missing = [p.name for p in extra if not p.exists()]
                if missing:
                    print("track: missing " + ", ".join(missing) + " (the match ended before its windows?)")
                    return result or 1
                if extra:
                    texts = [p.read_text(encoding="utf-8", errors="replace") for p in [dumped] + extra]
                    target.write_text(port_hl_track.merge(texts), encoding="utf-8")
                    print(f"track: {len(texts)} windows merged")
                else:
                    shutil.copy2(dumped, target)
                track = [str(target), "--top", "15"]
                if args.track_against:
                    track += ["--against", str(args.track_against.resolve())]
                port_hl_track.main(track)
        return result
    if args.command == "shapes":
        if args.dump is None:
            parser.error("shapes needs --dump")
        dump = args.dump.resolve()
        out = (args.out or dump.parent / f"pix-heaps-{args.driver}.txt").resolve()
        return shapes(args.driver, dump, (args.air or dump.parent / "pix-air.txt").resolve(), out)
    if args.command == "agal":
        return build_and_run("AgalSpike", args.driver, {}, 30, game_maps=True)
    return spike(args.driver, args.shot.resolve() if args.shot else None)


if __name__ == "__main__":
    sys.exit(main())
