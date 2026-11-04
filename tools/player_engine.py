"""the engine kit's driver (docs/player-engine-kit.md), run by the player's app from the kit:

    python -I -u player_engine.py check|install|uninstall|clean --game <Brawlhalla folder> [--work DIR] [--until STEP]
                                [--server HOST:PORT] [--purge]
    python -I -u player_engine.py official|uninstall-official --game <Brawlhalla folder> --layer <official package>

``install`` makes Bifrost on the new engine from the player's own game on this PC and installs it; each step prints
``step n/m: ...`` (the app shows it). the work folder (default ``%LOCALAPPDATA%\\Bifrost\\engine-work``) gets a copy
of the kit's tools with the toolchain linked in; the game code it makes stays there and in the install. ``--until``
stops after a step (for checks). ``official`` builds the official-servers game (bh-client's layer, ``--layer``: the
unpacked official release) from the same game and installs it beside Bifrost. in the workspace this file is only the
source of the kit's copy.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

KIT = Path(__file__).resolve().parent
if str(KIT) not in sys.path:
    sys.path.insert(0, str(KIT))
from tools import game_files

VERSION = "11.00"
STEPS = ["check", "prepare", "decompile", "convert", "assemble", "build", "install"]
OFFICIAL = "official"


class Failed(Exception):
    pass


def say(n: int, text: str) -> None:
    print(f"step {n}/{len(STEPS)}: {text}", flush=True)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def kit_info() -> dict:
    path = KIT / "kit.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def expected_swf() -> str:
    return json.loads((KIT / "client" / "symbols" / f"{VERSION}.json").read_text(encoding="utf-8"))["input_sha256"]


def default_work() -> Path:
    base = os.environ.get("LOCALAPPDATA") or str(Path.home() / ".local" / "share")
    return Path(base) / "Bifrost" / "engine-work"


def env() -> dict:
    e = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1")
    jre = KIT / "jre" / "bin"
    if jre.is_dir():
        e["PATH"] = str(jre) + os.pathsep + e.get("PATH", "")
    return e


def run(cmd: list[str], cwd: Path, log: Path) -> None:
    with open(log, "a", encoding="utf-8", errors="replace") as f:
        f.write(f"\n--- {time.strftime('%H:%M:%S')} {subprocess.list2cmdline(cmd)}\n")
        f.flush()
        proc = subprocess.Popen(cmd, cwd=cwd, env=env(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace")
        assert proc.stdout is not None
        for line in proc.stdout:
            f.write(line)
            print("  | " + line.rstrip("\r\n")[:300], flush=True)
        code = proc.wait()
    if code != 0:
        tail = log.read_text(encoding="utf-8", errors="replace").splitlines()[-25:]
        name = next((Path(c).name for c in cmd if c.endswith(".py") or c.endswith(".bat")), Path(cmd[0]).name)
        raise Failed(f"{name} failed (exit {code}):\n" + "\n".join(tail))


def link_dir(link: Path, target: Path) -> None:
    link.parent.mkdir(parents=True, exist_ok=True)
    if os.name == "nt":
        out = subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(target)], capture_output=True, text=True)
        if out.returncode != 0:
            raise Failed(f"mklink /J {link}: {out.stdout}{out.stderr}")
    else:
        link.symlink_to(target, target_is_directory=True)


def unlink_link(path: Path) -> None:
    if path.is_symlink() and not path.is_dir():
        path.unlink()
    else:
        os.rmdir(path)


def remove_tree(path: Path) -> None:
    if path.is_junction() or path.is_symlink():
        unlink_link(path)
        return
    if not path.exists():
        return
    for child in path.iterdir():
        if child.is_junction() or child.is_symlink():
            unlink_link(child)
        elif child.is_dir():
            remove_tree(child)
        else:
            child.unlink()
    path.rmdir()


def engine_dir(game: Path) -> Path:
    from tools import port_steam_install
    return port_steam_install.engine_dir(game)


def marker_file(game: Path) -> Path:
    from tools import port_steam_install
    return port_steam_install.marker_path(game)


def files_ok(game: Path, info: dict, product: str) -> None:
    listed = info.get("game_file_list")
    if not listed:
        if info.get("game_files") and info["game_files"] != game_files.fingerprint(game):
            raise Failed(f"this game's files aren't the ones this {product} release is for: wait for the next "
                         "release, or verify the game files in Steam")
        return
    differ = game_files.differences(game, listed)
    blocking = [name for name in differ if game_files.core(name)]
    if blocking:
        raise Failed(f"this game's code isn't the version this {product} release is for (changed: "
                     f"{game_files.describe(blocking)}): wait for the next release, or verify the game files in Steam")
    if differ:
        print(f"note: not Steam's current files: {game_files.describe(differ)} (a mod, or a skipped Steam update). "
              "The build doesn't use them; if they look wrong in game, verify the game files in Steam", flush=True)


def check(game: Path) -> str:
    swf = game / "BrawlhallaAir.swf"
    marker = marker_file(game)
    original = game / "BrawlhallaAir.swf.bifrost-original"
    source = original if original.exists() else swf
    if not source.exists():
        raise Failed(f"{game}: no BrawlhallaAir.swf (pick the Brawlhalla folder)")
    if sha256(source) != expected_swf():
        raise Failed(f"this game isn't the Brawlhalla {VERSION} this Bifrost is for: update Bifrost, or verify the "
                     "game files in Steam")
    files_ok(game, kit_info(), "Bifrost")
    note =" (Bifrost on the new engine is installed; this rebuilds it)" if marker.exists() else ""
    return f"Brawlhalla {VERSION} found{note}"


def fresh_copy(src: Path, dst: Path) -> None:
    remove_tree(dst)
    shutil.copytree(src, dst, ignore=shutil.ignore_patterns("__pycache__"))


def prepare(game: Path, work: Path) -> None:
    work.mkdir(parents=True, exist_ok=True)
    for name in ("tools", "port", "bifrost", "client"):
        fresh_copy(KIT / name, work / name)
    shutil.copytree(KIT / "build", work / "build", dirs_exist_ok=True)
    remove_tree(work / ".tools")
    (work / ".tools").mkdir()
    for item in (KIT / ".tools").iterdir():
        link_dir(work / ".tools" / item.name, item)
    link_dir(work / ".tools" / "haxe", KIT / "engine" / "tools" / "haxe")
    air = work / "air"
    for name in ("tools", "client", "examples", "src/platform", "src/mods"):
        fresh_copy(KIT / "air" / name, air / name)
    remove_tree(air / ".tools")
    link_dir(air / ".tools", KIT / "air" / ".tools")
    original = game / "BrawlhallaAir.swf.bifrost-original"
    (air / "versions" / VERSION).mkdir(parents=True, exist_ok=True)
    shutil.copy2(original if original.exists() else game / "BrawlhallaAir.swf", air / "versions" / VERSION / "BrawlhallaAir.swf")
    shutil.copy2(KIT / "air" / "PIN.txt", air / "PIN.txt")


def sync_tree(src: Path, dst: Path) -> int:
    written = 0
    want = {p.relative_to(src) for p in src.rglob("*") if p.is_file()}
    if dst.exists():
        for p in [p for p in dst.rglob("*") if p.is_file() and p.relative_to(dst) not in want]:
            p.unlink()
    for rel in sorted(want):
        a, b = src / rel, dst / rel
        if b.exists() and b.stat().st_size == a.stat().st_size and b.read_bytes() == a.read_bytes():
            continue
        b.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(a, b)
        written += 1
    return written


def decompile(work: Path) -> None:
    air = work / "air"
    run([sys.executable, "-u", str(air / "tools" / "export_as3.py"), "--version", VERSION], air, work / "build.log")
    ffdec = work / "build" / "as3" / VERSION / "ffdec"
    ffdec.mkdir(parents=True, exist_ok=True)
    for name in ("renamed.swf", "aliased.swf"):
        shutil.copy2(air / "build" / "as3" / VERSION / "ffdec" / name, ffdec / name)
    changed = sync_tree(air / "src" / "as3" / VERSION / "scripts", work / "src" / "as3" / VERSION / "scripts")
    sys.path.insert(0, str(work))
    from tools import recovered_edits
    edits = json.loads((KIT / "recovered" / f"{VERSION}.json").read_text(encoding="utf-8"))
    rebuilt = work / "build" / "recovered-new"
    remove_tree(rebuilt)
    n = recovered_edits.apply(edits, air / "build" / "as3" / VERSION / "ffdec" / "export-aliased" / "scripts", rebuilt)
    changed += sync_tree(rebuilt, work / "src" / "as3-recovered" / VERSION)
    remove_tree(rebuilt)
    print(f"{n} recovered methods rebuilt; {changed} game files changed since the last build", flush=True)


def convert(work: Path) -> None:
    os.environ["BIFROST_AIR_TREE"] = str(work / "air")
    os.environ["BIFROST_LAYER_COMMIT"] = (work / "air" / "PIN.txt").read_text(encoding="utf-8").split()[-1]
    staged = [sys.executable, "-u", str(work / "tools" / "port_version_build.py"), "run", "--version", VERSION, "--"]
    run(staged + ["bifrost_build.py", "tree"], work, work / "build.log")
    run(staged + ["bifrost_build.py", "export"], work, work / "build.log")


ENGINE_LINKED = ("src", "runtime", "lib", "tools")
STORAGE = Path("BhPort-" + VERSION) / "Documents" / "Bifrost"


def tools_module(work: Path, name: str):
    if str(work) not in sys.path:
        sys.path.insert(0, str(work))
    import importlib
    return importlib.import_module(f"tools.{name}")


def assemble(work: Path) -> Path:
    out = work / "engine-build"
    remove_tree(out)
    out.mkdir()
    for item in (KIT / "engine").iterdir():
        if item.name in ENGINE_LINKED:
            link_dir(out / item.name, item)
        elif item.is_dir():
            shutil.copytree(item, out / item.name)
        else:
            shutil.copy2(item, out / item.name)
    shutil.copytree(work / "build" / f"bifrost-{VERSION}" / "export" / "src", out / "bifrost-src")
    bifrost_export = tools_module(work, "bifrost_export")
    mods = bifrost_export.release_mods()
    (out / "bifrost-src" / "bh" / "platform" / "ModList.hx").write_text(
        bifrost_export.release_mod_list(mods, out / "bifrost-src"), encoding="utf-8", newline="\n")
    (out / "README.md").write_text(f"Brawlhalla v{VERSION}: Bifrost on the new engine, made on this PC by the "
                                   "engine kit. Generated from your own game: never share this folder.\n", encoding="utf-8")
    print(f"mods: {', '.join(mods)}", flush=True)
    return out


RENDERERS = ("dx11", "dx12")
RENDERER_NAMES = {"dx11": "DirectX 11", "dx12": "DirectX 12"}


BUILD_KEY = "build-key.txt"


def build_key(*parts: Path) -> str:
    h = hashlib.sha256(VERSION.encode())
    for part in (KIT / "kit.json", *parts):
        h.update(part.read_bytes() if part.exists() else b"-")
    return h.hexdigest()


def built(out: Path, games: Path, key: str) -> bool:
    stamp = out / BUILD_KEY
    return (os.environ.get("BIFROST_FRESH") != "1" and stamp.exists()
            and stamp.read_text(encoding="utf-8").strip() == key
            and all((games / f"game-{r}.hl").exists() for r in RENDERERS))


def build_renderers(work: Path, out: Path, hxml: str, log_name: str, label: str) -> None:
    haxe = out / "tools" / "haxe" / "haxe.exe"
    at_once = max(1, min(len(RENDERERS), (os.cpu_count() or 2) // 2))
    pending, running, failed = list(RENDERERS), [], []
    while pending or running:
        while pending and len(running) < at_once:
            r = pending.pop(0)
            log = open(work / log_name.format(r), "w", encoding="utf-8", errors="replace")
            print(f"  | building {RENDERER_NAMES[r]}", flush=True)
            running.append((r, log, subprocess.Popen([str(haxe), hxml.format(r)], cwd=out, env=env(), stdout=log,
                                                     stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL), time.monotonic()))
        time.sleep(0.5)
        for item in [i for i in running if i[2].poll() is not None]:
            running.remove(item)
            item[1].close()
            print(f"  | built {RENDERER_NAMES[item[0]]} in {time.monotonic() - item[3]:.0f} s"
                  + ("" if item[2].returncode == 0 else " (failed)"), flush=True)
            if item[2].returncode != 0:
                failed.append(item[0])
    with open(work / "build.log", "a", encoding="utf-8", errors="replace") as f:
        for r in RENDERERS:
            f.write(f"\n--- {hxml.format(r)}\n" + (work / log_name.format(r)).read_text(encoding="utf-8", errors="replace"))
    if failed:
        tail = (work / log_name.format(failed[0])).read_text(encoding="utf-8", errors="replace").splitlines()[-25:]
        raise Failed(f"the {label}{failed[0]} build failed:\n" + "\n".join(tail))


def build(work: Path) -> None:
    out = work / "engine-build"
    for old in (out / "bin").glob("game-*.hl"):
        if old.stem.removeprefix("game-") not in RENDERERS:
            old.unlink()
    build_renderers(work, out, "build-{}.hxml", "build-{}.log", "")
    games = sorted(p.name for p in (out / "bin").glob("game-*.hl"))
    if len(games) != len(RENDERERS):
        raise Failed(f"the build made {games}, not the {len(RENDERERS)} renderers' games")
    (out / BUILD_KEY).write_text(build_key() + "\n", encoding="utf-8")


def install_engine(game: Path, work: Path, server: str | None = None) -> None:
    os.environ["BIFROST_LAUNCHER_DIR"] = str(KIT / "launcher")
    steam = tools_module(work, "port_steam_install")
    try:
        print(steam.install(game, work / "engine-build"), flush=True)
    except steam.InstallError as e:
        raise Failed(str(e))
    print(set_server(game, server), flush=True)
    marker = marker_file(game)
    data = json.loads(marker.read_text(encoding="utf-8"))
    data["release"] = kit_info().get("release", "?")
    data["game_files"] = game_files.fingerprint(game)
    marker.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    (engine_dir(game) / "game-files.txt").write_text(game_files.stats(game), encoding="utf-8", newline="\n")


def set_server(game: Path, address: str | None = None) -> str:
    server = json.loads((KIT / "server.json").read_text(encoding="utf-8"))
    main = {"host": server["host"], "port": server["port"]}
    if address:
        host, _, port = address.rpartition(":")
        server = {"host": host, "port": int(port)}
    path = engine_dir(game) / "storage" / STORAGE / "bh-server.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    cfg = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    if (cfg.get("host"), cfg.get("port")) != (server["host"], server["port"]):
        cfg = {k: v for k, v in cfg.items() if k not in ("token", "account")}
    cfg.update(host=server["host"], port=server["port"], main=main)
    path.write_text(json.dumps(cfg, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    return f"server {server['host']}:{server['port']}"


def uninstall(game: Path, work: Path, purge: bool = False) -> None:
    steam = tools_module(work if (work / "tools").exists() else KIT, "port_steam_install")
    try:
        print(steam.uninstall(game, purge=purge), flush=True)
    except steam.InstallError as e:
        raise Failed(str(e))


def move_engine(game: Path, work: Path, target: Path) -> None:
    steam = tools_module(work if (work / "tools").exists() else KIT, "port_steam_install")
    try:
        print(steam.move(game, target), flush=True)
    except steam.InstallError as e:
        raise Failed(str(e))


def layer_info(layer: Path) -> dict:
    path = layer / "official.json"
    if not path.exists():
        raise Failed(f"{layer}: not an official package (no official.json)")
    return json.loads(path.read_text(encoding="utf-8"))


def check_official(game: Path, layer: Path) -> str:
    info = layer_info(layer)
    if not (game / "BrawlhallaAir.swf").exists():
        raise Failed(f"{game}: no BrawlhallaAir.swf (pick the Brawlhalla folder)")
    files_ok(game, info, "Official")
    return f"Brawlhalla {VERSION} found; Official {info.get('version', '?')}"


def convert_raw(work: Path) -> Path:
    out = work / "build" / "official-game"
    remove_tree(out)
    remove_tree(work / "build" / "official-openfl")
    staged = [sys.executable, "-u", str(work / "tools" / "port_version_build.py"), "run", "--version", VERSION, "--"]
    run(staged + ["port_raw_export.py", "--out", str(out), "--openfl-engine", str(work / "build" / "official-openfl"),
                  "--openfl-only", "--no-build", "--convert", "--game-only"], work, work / "build.log")
    return out / "src"


def assemble_official(work: Path, layer: Path) -> Path:
    out = work / "official-build"
    remove_tree(out)
    out.mkdir()
    for item in (KIT / "engine").iterdir():
        if item.name in ENGINE_LINKED:
            link_dir(out / item.name, item)
        elif item.is_file() and item.suffix == ".hxml":
            shutil.copy2(item, out / item.name)
    sys.path.insert(0, str(layer / "tools"))
    try:
        import nc_layer
        print(nc_layer.make(out, work / "build" / "official-game" / "src", OFFICIAL), flush=True)
    except Exception as e:
        raise Failed(f"the official layer: {e}")
    finally:
        sys.path.remove(str(layer / "tools"))
    return out


def build_official(work: Path, layer: Path) -> None:
    out = work / "official-build"
    build_renderers(work, out, f"build-{OFFICIAL}-{{}}.hxml", f"{OFFICIAL}-{{}}.log", f"{OFFICIAL} ")
    (out / BUILD_KEY).write_text(build_key(layer / "official.json") + "\n", encoding="utf-8")


def install_official(game: Path, work: Path, layer: Path) -> None:
    info = layer_info(layer)
    os.environ["BIFROST_LAUNCHER_DIR"] = str(KIT / "launcher")
    steam = tools_module(work, "port_steam_install")
    try:
        if not marker_file(game).exists():
            print(steam.install(game, KIT / "engine"), flush=True)
        elif (fixed := steam.restore_launcher(game)) is not None:
            print(fixed, flush=True)
    except steam.InstallError as e:
        raise Failed(str(e))
    engine = engine_dir(game)
    target = engine / OFFICIAL
    target.mkdir(parents=True, exist_ok=True)
    for r in RENDERERS:
        shutil.copy2(work / "official-build" / OFFICIAL / f"game-{r}.hl", target / f"game-{r}.hl")
    (target / "native").mkdir(exist_ok=True)
    for dll in (layer / "native").iterdir():
        shutil.copy2(dll, engine / "bin" / dll.name)
        shutil.copy2(dll, target / "native" / dll.name)
    (target / "game-files.txt").write_text(game_files.stats(game), encoding="utf-8", newline="\n")
    marker = marker_file(game)
    data = json.loads(marker.read_text(encoding="utf-8"))
    data[OFFICIAL] = {"version": info.get("version", "?"), "game_files": info.get("game_files"),
                      "kit": kit_info().get("release"), "installed": time.strftime("%Y-%m-%d %H:%M:%S")}
    marker.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    print(f"Official {info.get('version', '?')} installed in {target}", flush=True)


def uninstall_official(game: Path, purge: bool = False) -> None:
    engine = engine_dir(game)
    remove_tree(engine / OFFICIAL)
    if purge:
        remove_tree(engine / "storage-official")
    marker = marker_file(game)
    if marker.exists():
        data = json.loads(marker.read_text(encoding="utf-8"))
        data.pop(OFFICIAL, None)
        if data.get("mode") == OFFICIAL:
            data["mode"] = "bifrost"
        marker.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    (engine / "mode.txt").unlink(missing_ok=True)
    print("Official removed" + ("" if purge else "; its saves kept"), flush=True)


def install_official_plan(game: Path, work: Path, layer: Path) -> None:
    plan = [
        ("checking your game", lambda: print(check_official(game, layer), flush=True)),
        (f"preparing the work folder ({work})", lambda: prepare(game, work)),
        ("reading your game's code (FFDec; about a minute)", lambda: decompile(work)),
        ("turning it into the official game for the new engine (a few minutes)", lambda: convert_raw(work)),
        ("putting the engine and the game together", lambda: assemble_official(work, layer)),
        ("building the game for each renderer (about a minute)", lambda: build_official(work, layer)),
        ("installing it into your game folder", lambda: install_official(game, work, layer)),
    ]
    started = time.monotonic()
    out = work / "official-build"
    reuse = built(out, out / OFFICIAL, build_key(layer / "official.json"))
    for n, (text, action) in enumerate(plan, 1):
        if reuse and 1 < n < len(plan):
            continue
        print(f"step {n}/{len(plan)}: {text}", flush=True)
        action()
        if reuse and n == 1:
            print("this game is already built for this release: reusing it", flush=True)
    print(f"done in {time.monotonic() - started:.0f} s", flush=True)


def install(game: Path, work: Path, until: str | None, start: str = "check", server: str | None = None) -> None:
    plan = [
        ("check", "checking your game", lambda: print(check(game), flush=True)),
        ("prepare", f"preparing the work folder ({work})", lambda: prepare(game, work)),
        ("decompile", "reading your game's code (FFDec; about a minute)", lambda: decompile(work)),
        ("convert", "turning it into Bifrost for the new engine (a few minutes)", lambda: convert(work)),
        ("assemble", "putting the engine and the game together", lambda: assemble(work)),
        ("build", "building the game for each renderer (about a minute)", lambda: build(work)),
        ("install", "installing it into your game folder", lambda: install_engine(game, work, server)),
    ]
    started = time.monotonic()
    if STEPS.index(start) > STEPS.index("prepare"):
        for name in ("tools", "port", "bifrost"):
            shutil.rmtree(work / name)
            shutil.copytree(KIT / name, work / name, ignore=shutil.ignore_patterns("__pycache__"))
    out = work / "engine-build"
    reuse = start == "check" and until is None and built(out, out / "bin", build_key())
    for n, (name, text, action) in enumerate(plan, 1):
        if n < STEPS.index(start) + 1 and name != "check":
            continue
        if reuse and name not in ("check", "install"):
            continue
        say(n, text)
        t = time.monotonic()
        action()
        if time.monotonic() - t >= 5:
            print(f"{name}: {time.monotonic() - t:.0f} s", flush=True)
        if reuse and name == "check":
            print("this game is already built for this release: reusing it", flush=True)
        if name == until:
            break
    print(f"done in {time.monotonic() - started:.0f} s", flush=True)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("action", choices=("check", "install", "uninstall", "clean", "official", "uninstall-official",
                                      "move-engine", "original", "launcher"))
    p.add_argument("--game", type=Path, required=True)
    p.add_argument("--work", type=Path, default=None)
    p.add_argument("--until", choices=STEPS, default=None)
    p.add_argument("--from", dest="start", choices=STEPS, default="check", help="resume a kept work folder")
    p.add_argument("--server", default=None, help="host:port to play on instead of the kit's server (the Server tab)")
    p.add_argument("--purge", action="store_true", help="uninstall: the saves too")
    p.add_argument("--layer", type=Path, default=None, help="official: the unpacked official release")
    p.add_argument("--to", type=Path, default=None, help="move-engine: the engine folder's new place")
    a = p.parse_args(argv)
    os.environ["BIFROST_PLAYER_INSTALL"] = "1"
    try:
        if a.action == "check":
            print(check(a.game))
        elif a.action == "install":
            install(a.game, (a.work or default_work()).resolve(), a.until, a.start, a.server)
        elif a.action == "official":
            if a.layer is None:
                raise Failed("official needs --layer (the unpacked official release)")
            install_official_plan(a.game, (a.work or default_work()).resolve(), a.layer.resolve())
        elif a.action == "uninstall-official":
            uninstall_official(a.game, a.purge)
        elif a.action == "move-engine":
            if a.to is None:
                raise Failed("move-engine needs --to (the engine folder's new place)")
            move_engine(a.game, (a.work or default_work()).resolve(), a.to.resolve())
        elif a.action in ("original", "launcher"):
            os.environ["BIFROST_LAUNCHER_DIR"] = str(KIT / "launcher")
            work = (a.work or default_work()).resolve()
            steam = tools_module(work if (work / "tools").exists() else KIT, "port_steam_install")
            try:
                if a.action == "original":
                    print(steam.original_launcher(a.game), flush=True)
                else:
                    print(steam.restore_launcher(a.game) or "Brawlhalla.exe is already Bifrost's launcher", flush=True)
            except steam.InstallError as e:
                raise Failed(str(e))
        elif a.action == "clean":
            remove_tree((a.work or default_work()).resolve())
            print("work folder removed", flush=True)
        else:
            uninstall(a.game, (a.work or default_work()).resolve(), a.purge)
        return 0
    except Failed as e:
        print(f"failed: {e}", flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
