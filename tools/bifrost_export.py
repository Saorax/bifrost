"""exports Bifrost on the new engine as a standalone folder, built and run on its own.

    python tools/bifrost_export.py --out C:/Coding/bh-bifrost-engine [--refresh] [--endpoint HOST:PORT | --offline]
                               [--no-build] [--boot-check SECONDS]

like ``port_raw_export.py``, but one folder holds everything Bifrost needs:

- ``bifrost-src/``: Bifrost's game as converted (copied from ``build/bifrost/export/src``; ``--refresh`` runs
  ``bifrost_build.py export`` first), with the release ``ModList`` (``bifrost/mods.txt``).
- the Heaps engine (``src/``, ``runtime/``, ``lib/``, ``tools/haxe``, ``bin/``, ``bin-vulkan/``), its own copy, with
  ``build-*.hxml`` building ``bifrost-src`` with ``-D bifrost``.
- ``install/``: hard links to the port's test install (``build/game-test/port``), the Discord bridge
  (``BifrostDiscord.exe``) and ``mods/`` (kept across exports).
- ``storage/``: the save folder (kept across exports). ``--endpoint`` (default ``127.0.0.1:7910``) writes
  ``storage/BhPort/Documents/Bifrost/bh-server.json``, keeping a saved sign-in for that server; ``--offline`` leaves
  no endpoint. official services are refused either way.
- ``build.bat``, ``run.bat``, ``README.md``.

without ``--no-build`` the folder is built with its own ``build.bat``; ``--boot-check S`` then runs ``run.bat`` for S
seconds (browser and Discord pipe off) and checks its boot log: main menu reached, no uncaught errors. refuses to write
while a ``hl.exe`` runs from the folder. generated from decompiled game code: local use only, never in Git.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import bifrost_build, engine_stamp, port_raw_export

MARKER = "bh-bifrost-engine.txt"
DEFAULT_OUT = Path("C:/Coding/bh-bifrost-engine")
DEFAULT_ENDPOINT = "127.0.0.1:7910"
INSTALL_SOURCE = ROOT / "build" / "game-test" / "port"
GAME_DIR = "bifrost-src"
GENERATED = (GAME_DIR, "src", "runtime", "lib", "bin", "bin-vulkan")
CONFIG_REL = Path("BhPort") / "Documents" / "Bifrost" / "bh-server.json"

BUILD_BAT = """@echo off
rem Compiles Bifrost (bifrost-src) with this folder's Heaps engine: one game per renderer and the launcher, into bin\\.
cd /d "%~dp0"
for %%r in (dx11 dx12) do (
  echo building bin\\game-%%r.hl
  "%~dp0tools\\haxe\\haxe.exe" build-%%r.hxml
  if errorlevel 1 exit /b 1
)
"%~dp0tools\\haxe\\haxe.exe" launcher.hxml
if errorlevel 1 exit /b 1
echo built bin\\game-dx11.hl, game-dx12.hl and launcher.hl
"""

RUN_BAT = """@echo off
rem Runs Bifrost on the Heaps engine. The game reads install\\ (its art and data; content mods in install\\mods) and
rem saves to storage\\ here, never to the AIR builds'. The server is storage\\BhPort\\Documents\\Bifrost\\bh-server.json;
rem without it the game stays offline. Official services are never contacted.
setlocal
set "BH_PORT_APP_DIR=%~dp0install"
if not "%~1"=="" set "BH_PORT_APP_DIR=%~1"
set "BH_PORT_STORAGE_DIR=%~dp0storage"
set "BH_PORT_LOG=%~dp0boot.txt"
if exist "%~dp0boot.txt" move /y "%~dp0boot.txt" "%~dp0boot-previous.txt" > nul
cd /d "%~dp0bin"
"%~dp0bin\\hl.exe" launcher.hl
"""

README = """# Bifrost on the new engine

Bifrost (the owner's build of Brawlhalla v{version}: its hooks, mods, server connection, P2P and menus) on the port's
Heaps engine instead of Adobe AIR. Exported {when} from `{root}` by `tools/bifrost_export.py` (Bifrost's layer at AIR
commit `{commit}`).

**Local use only.** `bifrost-src/` and `install/` hold game code and files from Ubisoft's game. Never commit this
folder to Git or share it.

## Run

```bat
run.bat
```

- The renderer is `storage\\engine.json`'s (`{{"renderer": "dx11"}}`: `dx11` default, `dx12`, `vulkan`),
  taken at the next start; the game's own Options set it too.
- Server: {server}. Edit `storage\\{storage_dir}\\Documents\\Bifrost\\bh-server.json` (`host`, `port`) for another, or
  delete it to play offline. Sign in with Discord in Options > SERVERS.
- Content mods go in `install\\mods\\` (as in the AIR build's `mods` folder). Saves, settings and the sign-in are in
  `storage\\`, the log in `boot.txt` (the last start's in `boot-previous.txt`). Both are kept by the next export.

## Build

```bat
build.bat
```

compiles `bifrost-src` once per renderer (`bin\\game-dx11.hl`, `game-dx12.hl`) and the launcher with
the bundled Haxe 4.3.7 (about 2 minutes). The export already built them.

## What is here

| Folder | Contents |
| --- | --- |
| `bifrost-src/` | Bifrost's game converted to Haxe: the raw v{version} game with Bifrost's hooks, and Bifrost's layer (release mods: {mods}) |
| `src/`, `runtime/`, `lib/`, `tools/haxe` | The Heaps engine, as in `bh-port-engine`: its `flash.*` classes, the runtime layer, Heaps 2.1.0 and its libraries (MIT) |
| `bin/`, `bin-vulkan/` | HashLink 1.15 and the native helpers; `bin-vulkan` adds DXVK (zlib licence) |
| `install/` | The game's files (hard links to the port's test copy), Bifrost's Discord bridge and `mods/` |
| `storage/` | Saves and settings |

Everything but `install\\mods` and `storage\\` is replaced by the next export: lasting fixes go in the port's
converter, runtime or engine, or in Bifrost's source in the AIR project. Re-export from the port folder:

```bat
python tools\\bifrost_export.py --out {out}
```
"""


def release_mod_list(mods: list[str], src: Path) -> str:
    classes = []
    for mod in mods:
        found = sorted(p.stem for p in (src / "bh" / "mods" / mod).glob("*Mod.hx"))
        if len(found) != 1:
            raise bifrost_build.TreeError(f"mod {mod}: expected one *Mod.hx in {src / 'bh' / 'mods' / mod}, found {found}")
        classes.append(found[0])
    imports = "".join(f"   import bh.mods.{m}.{c};\n" for m, c in zip(mods, classes))
    calls = "".join(f"         {c}.register();\n" for c in classes)
    return ("package bh.platform;\n\n" + imports +
            "\n   /** Generated by tools/bifrost_export.py from bifrost/mods.txt: the mods Bifrost registers. */\n"
            "   class ModList\n   {\n      public function new()\n      {\n      }\n\n"
            "      public static function registerAll():Void\n      {\n" + calls + "      }\n   }\n")


def release_mods() -> list[str]:
    return [line.strip() for line in bifrost_build.MODS_FILE.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.startswith("#")]


def running_from(folder: Path) -> list[str]:
    script = ("Get-CimInstance Win32_Process | Where-Object { $_.Name -in 'hl.exe','Brawlhalla.exe' } | "
              "ForEach-Object { $_.ExecutablePath }")
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, text=True,
                             timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    base = str(folder.resolve()).lower().rstrip("\\") + "\\"
    return [line.strip() for line in out.splitlines() if line.strip().lower().startswith(base)]


def link_install(source: Path, target: Path) -> tuple[int, int]:
    made = kept = 0
    for path in source.rglob("*"):
        rel = path.relative_to(source)
        if not path.is_file() or rel.parts[0].lower() == "mods" or rel.name == bifrost_build.BRIDGE:
            continue
        dest = target / rel
        if dest.exists():
            a, b = path.stat(), dest.stat()
            if a.st_size == b.st_size and (a.st_ino == b.st_ino or a.st_mtime_ns == b.st_mtime_ns):
                kept += 1
                continue
            dest.unlink()
        dest.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.link(path, dest)
        except OSError:
            shutil.copy2(path, dest)
        made += 1
    return made, kept


def install_extras(install: Path, air: Path) -> str:
    (install / "mods").mkdir(parents=True, exist_ok=True)
    bridge = bifrost_build.bridge_source(air)
    if bridge is None:
        return "no Discord bridge (no AIR build has BifrostDiscord.exe): Rich Presence logs it missing"
    shutil.copy2(bridge, install / bifrost_build.BRIDGE)
    return f"Discord bridge from {bridge}"


def write_endpoint(storage: Path, endpoint: str | None, seed: Path) -> str:
    config = storage / CONFIG_REL
    if endpoint is None:
        config.unlink(missing_ok=True)
        return "none (offline)"
    why = bifrost_build.endpoint_refused(endpoint)
    if why:
        raise bifrost_build.TreeError(f"--endpoint {endpoint}: {why}")
    host, port = endpoint.rsplit(":", 1)
    config.parent.mkdir(parents=True, exist_ok=True)
    if not config.exists() and seed.exists():
        shutil.copy2(seed, config)
    cfg = bifrost_build.endpoint_config(config, host, int(port))
    config.write_text(json.dumps(cfg), encoding="utf-8")
    return f"`{host}:{port}`" + (" (signed in)" if cfg.get("token") else "")


def boot_check(out: Path, seconds: int) -> tuple[bool, str]:
    env = dict(os.environ, BH_PORT_BROWSER="off", BH_PORT_NATIVEPROCESS_ARGS=bifrost_build.TEST_PIPE)
    proc = subprocess.Popen(["cmd", "/c", str(out / "run.bat")], cwd=out, env=env, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    try:
        proc.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        pass
    for exe in running_from(out):
        subprocess.run(["powershell", "-NoProfile", "-Command",
                        f"Get-CimInstance Win32_Process | Where-Object {{ $_.ExecutablePath -eq '{exe}' }} | "
                        "ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"], capture_output=True)
    proc.wait(timeout=30)
    def read(path: Path) -> str:
        return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    return boot_verdict(read(out / "boot.txt"),
                        read(out / "storage" / "BhPort" / "Documents" / "Bifrost" / "bh-errors.txt"))


def boot_verdict(log: str, errors: str = "") -> tuple[bool, str]:
    menu = "boot: main menu reached" in log
    uncaught = log.count("uncaught in frame")
    started = re.search(r"boot: start \(Heaps engine, application ([^)]*)\)", log)
    failures = [line for line in errors.splitlines()
                if re.search(r"handler failed|not set:|draw: |couldn't|could not apply", line)]
    ok = menu and uncaught == 0 and started is not None and not failures
    return ok, (f"boot log: {'started from ' + started.group(1) if started else 'never started'}; main menu "
                f"{'reached' if menu else 'NOT reached'}; uncaught errors {uncaught}; Bifrost failures "
                f"{len(failures)}" + "".join("\n  " + f[:200] for f in failures[:5]))


def game_version() -> str:
    hooks = bifrost_build.BUILD_DIR / "hooks.json"
    return json.loads(hooks.read_text(encoding="utf-8")).get("version", "10.11") if hooks.exists() else "10.11"


def export(out: Path, *, endpoint: str | None, air: Path, install: Path = INSTALL_SOURCE) -> int:
    started = time.monotonic()
    src = bifrost_build.EXPORT / "src"
    if not (src / "bh" / "platform" / "ModList.hx").exists():
        print(f"bifrost_export: no converted Bifrost tree in {src}: run with --refresh (bifrost_build.py export)")
        return 1
    if not port_raw_export._claim(out, MARKER):
        return 1
    busy = running_from(out)
    if busy:
        print(f"bifrost_export: {busy[0]} is running from {out}; not writing there while it runs")
        return 1
    (out / MARKER).write_text("Generated by tools/bifrost_export.py; safe to replace with a new export.\n",
                              encoding="utf-8")
    for name in GENERATED:
        shutil.rmtree(out / name, ignore_errors=True)
    shutil.copytree(src, out / GAME_DIR)
    mods = release_mods()
    (out / GAME_DIR / "bh" / "platform" / "ModList.hx").write_text(release_mod_list(mods, out / GAME_DIR),
                                                                    encoding="utf-8", newline="\n")
    rc = port_raw_export.copy_heaps_engine(out)
    if rc != 0:
        return rc
    port_raw_export.write_heaps_hxml(out, GAME_DIR, "Bifrost", ("bifrost",))
    made, kept = link_install(install, out / "install")
    bridge = install_extras(out / "install", air)
    (out / "storage").mkdir(exist_ok=True)
    server = write_endpoint(out / "storage", endpoint, bifrost_build.HEAPS_STORAGE / CONFIG_REL)
    (out / "build.bat").write_text(BUILD_BAT, encoding="utf-8", newline="\r\n")
    (out / "run.bat").write_text(RUN_BAT, encoding="utf-8", newline="\r\n")
    (out / "README.md").write_text(README.format(when=time.strftime("%Y-%m-%d %H:%M"), root=ROOT,
                                                 commit=bifrost_build.source_commit(), server=server, out=out,
                                                 version=game_version(), storage_dir=CONFIG_REL.parts[0],
                                                 mods=", ".join(mods)), encoding="utf-8")
    engine_stamp.write(out, ROOT, game_version())
    print(f"bifrost_export: Bifrost ({sum(1 for _ in (out / GAME_DIR).rglob('*.hx'))} files, mods {', '.join(mods)}) and"
          f" the Heaps engine -> {out} in {time.monotonic() - started:.0f} s; install {made} linked, {kept} kept; "
          f"{bridge}; server {server}")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", type=Path, default=DEFAULT_OUT, help="the folder (absolute; outside any Git repo)")
    p.add_argument("--refresh", action="store_true", help="convert Bifrost's tree again first (bifrost_build.py export)")
    p.add_argument("--endpoint", default=DEFAULT_ENDPOINT, metavar="HOST:PORT", help="the Bifrost server")
    p.add_argument("--offline", action="store_true", help="no server: the game stays offline")
    p.add_argument("--no-build", action="store_true", help="skip build.bat")
    p.add_argument("--boot-check", type=int, default=0, metavar="SECONDS",
                   help="after the build, start run.bat for SECONDS and check its boot log (menu, no uncaught errors)")
    p.add_argument("--air", type=Path, default=bifrost_build.bifrost_hookmap.DEFAULT_AIR, help="the AIR project (read only)")
    p.add_argument("--install-source", type=Path, default=INSTALL_SOURCE,
                   help="the install install/ links to (the game version Bifrost's tree was made for)")
    p.add_argument("--version", default=None, help="the game version (--refresh; default: the last tree's)")
    a = p.parse_args(argv)
    a.version = a.version or game_version()
    out = a.out.resolve()
    if out.is_relative_to(ROOT) or (out / ".git").exists():
        p.error("export outside the repository: the folder holds decompiled code")
    build = Path(__file__).resolve().with_name("bifrost_build.py")
    for step in (["tree"], ["export"]) if a.refresh else ():
        if subprocess.run([sys.executable, str(build), *step, "--version", a.version], cwd=ROOT).returncode != 0:
            print(f"bifrost_export: bifrost_build.py {step[0]} failed")
            return 1
    try:
        rc = export(out, endpoint=None if a.offline else a.endpoint, air=a.air, install=a.install_source.resolve())
    except bifrost_build.TreeError as e:
        print(f"bifrost_export: {e}")
        return 1
    if rc != 0 or a.no_build:
        return rc
    started = time.monotonic()
    result = subprocess.run(["cmd", "/c", str(out / "build.bat")], cwd=out, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    print(result.stdout.strip()[-3000:])
    print(f"build.bat {'OK' if result.returncode == 0 else 'FAILED'} in {time.monotonic() - started:.0f} s")
    if result.returncode != 0 or not a.boot_check:
        return result.returncode
    ok, what = boot_check(out, a.boot_check)
    print(f"boot check {'ok' if ok else 'FAILED'}: {what}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
