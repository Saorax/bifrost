"""builds the player's engine kit (docs/player-engine-kit.md).

    python tools/player_kit.py build [--out build/player-kit] [--engine C:/Coding/BRAWLHALLA PROJECTS/bifrost/bifrost-main]
    python tools/player_kit.py audit [--out build/player-kit]

the player's app converts the player's own game on their PC, so the kit carries only what may ship: our tools and
name-only metadata, Bifrost's layer, the open-source toolchain and the prebuilt engine without the game. it mirrors
the workspace's layout (the tools find ``ROOT`` from their own place), plus:

- ``air/``: a second root for the AIR project's export tools (``tools/export_as3.py`` and every tool it imports, at
  the pin) with the 11.00 symbol maps and Bifrost's layer (``src/platform``, ``src/mods``), so the kit needs no git;
  the player's SWF goes to ``air/versions/11.00``.
- ``engine/``: the standalone export (``tools/bifrost_export.py``'s folder) without ``bifrost-src``, ``install``,
  ``storage`` or any ``.hl``.
- ``launcher/``: ``Brawlhalla.exe`` and ``bifrost-vm.dll`` built here with MSVC (players have no compiler).
- ``python/``, ``jre/``: Python's embeddable build and a Java runtime for FFDec (``jlink_runtime`` when the JDK is in
  ``.tools/player-jdk``, else Temurin's whole JRE).
- ``recovered/<ver>.json``: the recovered methods as edits of FFDec's text (``tools/recovered_edits.py``).
- ``player_engine.py``: the driver the app runs.

``audit`` (run by ``build`` too) refuses the kit when any file is game code or art: a SWF, ``.hl``, ``.asasm``,
``.abc`` or ``.pickle``, a folder of decompiled or converted game code, or an ``.as`` / ``.hx`` file outside the
places our own sources live.
"""
from __future__ import annotations

import argparse
import ast
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools import game_files

DEFAULT_OUT = ROOT / "build" / "player-kit"
DEFAULT_ENGINE = Path("C:/Coding/BRAWLHALLA PROJECTS/bifrost/bifrost-main")
VERSION = "11.00"

METADATA = [
    "client/symbols/10.11.json",
    f"client/symbols/{VERSION}.json",
    f"client/symbols/{VERSION}.aliases.json",
    f"client/symbols/{VERSION}.packets.json",
    f"build/version-match/10.11_to_{VERSION}.json",
    f"build/version-names/10.11_to_{VERSION}.json",
    f"build/port-haxe/{VERSION}/field-init-order.json",
    f"build/port-haxe/{VERSION}/hoisted-locals.json",
    f"build/port-haxe/{VERSION}/temp-receivers.json",
    f"build/port-haxe/{VERSION}/element-types.json",
    f"build/port-haxe/{VERSION}/conversion-tables.key",
]
TOOLCHAIN = [
             ".tools/haxelib/openfl/9,5,2", ".tools/haxelib/lime/8,3,2/src", ".tools/haxelib/lime/8,3,2/LICENSE.md",
             ".tools/haxelib/lime/8,3,2/haxelib.json", ".tools/haxelib/lime/8,3,2/extraParams.hxml"]
AIR_TOOLCHAIN = {".tools/ffdec": ".tools/ffdec", ".tools/rabcdasm/bin": ".tools/rabcdasm/bin"}
ENGINE_SKIP = {"bifrost-src", "install", "storage", "README.md",
               "boot.txt", "boot-previous.txt", "bh-bifrost-engine.txt", "run.bat", "build-gl.hxml"}
ENGINE_DROP = ("bin/SDL2.dll", "bin/sdl.hdll", "lib/hlsdl")
LAUNCHER = ["build/steam-launcher/Brawlhalla.exe", "build/steam-launcher/bifrost-vm.dll"]
RUNTIMES = {"python": ".tools/player-runtime-dl/python-3.13.5-embed-amd64.zip",
            "jre": ".tools/player-runtime-dl/temurin-21-jre-x64.zip"}
AIR_ENTRY = "tools/export_as3.py"

GAME_SUFFIXES = {".swf", ".hl", ".asasm", ".abc", ".pickle", ".swz"}
GAME_DIRS = {("src", "as3"), ("src", "asasm"), ("src", "as3-recovered"), ("versions",), ("bifrost-src",),
             ("install",), ("storage",), ("build", "as3"), ("build", "bifrost"), ("build", f"bifrost-{VERSION}")}
FROM_GIT = [("tools",), ("port",), ("bifrost",), ("air", "src"), ("air", "tools"), ("air", "examples")]
AS_PLACES = FROM_GIT
HX_PLACES = FROM_GIT + [("engine", "src"), ("engine", "runtime"), ("engine", "lib"), ("engine", "tools"),
                        (".tools", "haxe"), (".tools", "haxelib")]


class KitError(Exception):
    pass


def pin() -> tuple[Path, str]:
    from tools import pins
    p = pins.pins()
    return Path(p["repo"]), p["commit"]


def git(repo: Path, *args: str) -> bytes:
    out = subprocess.run(["git", "-C", str(repo), *args], capture_output=True)
    if out.returncode != 0:
        raise KitError(f"git {' '.join(args)}: {out.stderr.decode(errors='replace').strip()}")
    return out.stdout


def tracked(*paths: str) -> list[str]:
    out = git(ROOT, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *paths)
    return [p for p in out.decode("utf-8").split("\0") if p and (ROOT / p).is_file()]


def air_tool_closure(repo: Path, commit: str, entry: str = AIR_ENTRY) -> dict[str, bytes]:
    names = {Path(p).stem for p in git(repo, "ls-tree", "--name-only", commit, "tools/").decode().splitlines()
             if p.endswith(".py")}
    todo, found = [Path(entry).stem], {}
    while todo:
        name = todo.pop()
        if name in found:
            continue
        found[name] = git(repo, "show", f"{commit}:tools/{name}.py")
        for node in ast.walk(ast.parse(found[name])):
            if isinstance(node, ast.Import):
                todo += [a.name.split(".")[0] for a in node.names if a.name.split(".")[0] in names]
            elif isinstance(node, ast.ImportFrom):
                if node.module == "tools":
                    todo += [a.name for a in node.names if a.name in names]
                elif node.module and node.module.startswith("tools.") and node.module.split(".")[1] in names:
                    todo.append(node.module.split(".")[1])
                elif node.module and node.module.split(".")[0] in names:
                    todo.append(node.module.split(".")[0])
    return {f"tools/{n}.py": data for n, data in sorted(found.items())}


def copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(src, dst, dirs_exist_ok=True, ignore=shutil.ignore_patterns("__pycache__"))
    else:
        shutil.copy2(src, dst)


def build(out: Path, engine: Path, server: str | None = None, release: str | None = None) -> dict:
    started = time.monotonic()
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    for rel in tracked("tools", "port", "bifrost"):
        if rel.endswith(".py") and rel.startswith("tools/tests"):
            continue
        copy(ROOT / rel, out / rel)
    for rel in METADATA + TOOLCHAIN:
        if not (ROOT / rel).exists():
            raise KitError(f"missing {rel} (made by the 11.00 chain on this PC)")
        copy(ROOT / rel, out / rel)
    repo, commit = pin()
    air = out / "air"
    for rel, data in air_tool_closure(repo, commit).items():
        (air / rel).parent.mkdir(parents=True, exist_ok=True)
        (air / rel).write_bytes(data)
    for name in (f"{VERSION}.json", f"{VERSION}.aliases.json"):
        copy(ROOT / "client" / "symbols" / name, air / "client" / "symbols" / name)
    for src, dst in AIR_TOOLCHAIN.items():
        if not (repo / src).exists():
            raise KitError(f"missing {repo / src}")
        copy(repo / src, air / dst)
    rabcdasm_notice(repo, air / ".tools" / "rabcdasm")
    layer = subprocess.run(["git", "-C", str(repo), "archive", "--format=tar", commit, "src/platform", "src/mods",
                            "examples/mods"], capture_output=True)
    if layer.returncode != 0:
        raise KitError(f"git archive: {layer.stderr.decode(errors='replace')}")
    import io
    import tarfile
    with tarfile.open(fileobj=io.BytesIO(layer.stdout)) as tar:
        tar.extractall(air, filter="data")
    (air / "PIN.txt").write_text(f"{repo.name} {commit}\n", encoding="utf-8")
    dropped = drop_test_mods(air)
    if dropped:
        hooks_path = out / "bifrost" / "hooks-as3.json"
        hooks = json.loads(hooks_path.read_text(encoding="utf-8"))
        hooks["layer"] = [h for h in hooks.get("layer", [])
                          if not any(h.get("file", "").startswith(f"bh/mods/{m}/") for m in dropped)]
        hooks_path.write_text(json.dumps(hooks, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"player kit: test mods left out (not registered, not used by the platform code): {', '.join(dropped)}")
    from tools import recovered_edits
    ffdec_text = repo / "build" / "as3" / VERSION / "ffdec" / "export-aliased" / "scripts"
    if not ffdec_text.is_dir():
        raise KitError(f"missing {ffdec_text} (the AIR project's tools/export_as3.py --version {VERSION})")
    try:
        edits = recovered_edits.make(ROOT / "src" / "as3-recovered" / VERSION, ffdec_text)
    except recovered_edits.EditError as e:
        raise KitError(str(e))
    (out / "recovered").mkdir()
    (out / "recovered" / f"{VERSION}.json").write_text(json.dumps(edits, indent=1) + "\n", encoding="utf-8")
    if not (engine / "bin" / "hl.exe").exists():
        raise KitError(f"{engine}: no exported engine (tools/bifrost_export.py)")
    for item in engine.iterdir():
        if item.name in ENGINE_SKIP:
            continue
        copy(item, out / "engine" / item.name)
    for hl in (out / "engine").rglob("*.hl"):
        hl.unlink()
    for name in ENGINE_DROP:
        shutil.rmtree(out / "engine" / name) if (out / "engine" / name).is_dir() else (out / "engine" / name).unlink(missing_ok=True)
    for item in (out / "engine" / "bin-vulkan").iterdir():
        if item.name not in ("d3d11.dll", "dxgi.dll"):
            shutil.rmtree(item) if item.is_dir() else item.unlink()
    for rel in LAUNCHER:
        if not (ROOT / rel).exists():
            raise KitError(f"missing {rel} (python tools/port_steam_install.py stub)")
        copy(ROOT / rel, out / "launcher" / Path(rel).name)
    unpack_runtime(ROOT / RUNTIMES["python"], out / "python")
    if not jlink_runtime(out / "jre"):
        unpack_runtime(ROOT / RUNTIMES["jre"], out / "jre")
    if (ROOT / "tools" / "player_engine.py").exists():
        copy(ROOT / "tools" / "player_engine.py", out / "player_engine.py")
    problems = audit(out)
    if problems:
        raise KitError("the kit holds game files:\n" + "\n".join(problems[:40]))
    host, _, port = (server or default_server()).rpartition(":")
    if not host or not port.isdigit():
        raise KitError(f"--server {server}: host:port")
    (out / "server.json").write_text(json.dumps({"host": host, "port": int(port)}) + "\n", encoding="utf-8")
    port_commit = git(ROOT, "rev-parse", "--short", "HEAD").decode().strip()
    info = {"release": release or time.strftime("%Y.%m.%d-") + port_commit, "game": VERSION, "air_pin": commit,
            "port_commit": port_commit, "server": f"{host}:{port}", "built": time.strftime("%Y-%m-%d %H:%M:%S"),
            "game_files": game_files.fingerprint(ROOT / "versions" / VERSION),
            "size_mb": round(size(out) / 2**20, 1), "seconds": round(time.monotonic() - started)}
    (out / "kit.json").write_text(json.dumps(info, indent=1) + "\n", encoding="utf-8")
    return info


def drop_test_mods(air: Path) -> list[str]:
    import re
    mods_dir = air / "src" / "platform" / "as3" / "bh" / "mods"
    platform = air / "src" / "platform" / "as3" / "bh" / "platform"
    release = {line.strip() for line in (ROOT / "bifrost" / "mods.txt").read_text(encoding="utf-8").splitlines()
               if line.strip() and not line.startswith("#")}
    code = [line for path in platform.rglob("*.as") for line in path.read_text(encoding="utf-8").splitlines()
            if not line.strip().startswith(("//", "/*", "*"))]
    dropped = []
    for mod in sorted(p.name for p in mods_dir.iterdir() if p.is_dir()):
        if mod in release or any(re.search(rf"\bbh\.mods\.{re.escape(mod)}\b", line) for line in code):
            continue
        shutil.rmtree(mods_dir / mod)
        dropped.append(mod)
    return dropped


def rabcdasm_notice(repo: Path, dest: Path) -> None:
    import zipfile
    src = repo / ".tools" / "rabcdasm-src"
    if not (src / "COPYING").is_file():
        raise KitError(f"missing {src} (RABCDAsm's source, the AIR project's tools/setup_rabcdasm.py)")
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src / "COPYING", dest / "COPYING")
    with zipfile.ZipFile(dest / "rabcdasm-source.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(src.rglob("*")):
            rel = f.relative_to(src)
            if f.is_file() and rel.parts[0] not in ("obj", ".git") and f.suffix not in (".exe", ".obj", ".lib", ".pdb"):
                z.write(f, "RABCDAsm/" + rel.as_posix())
        z.write(repo / "tools" / "patches" / "rabcdasm-denormal-fix.patch", "rabcdasm-denormal-fix.patch")
    (dest / "README.txt").write_text("RABCDAsm (https://github.com/CyberShadow/RABCDAsm), GPL v3 (COPYING), built with "
                                     "rabcdasm-denormal-fix.patch; its source and the patch are in rabcdasm-source.zip.\n",
                                     encoding="utf-8")


DEFAULT_SERVER = "bifrost.saorax.com:7910"


def default_server() -> str:
    return DEFAULT_SERVER


JDK_GLOB = ".tools/player-jdk/jdk-21*"
JRE_MODULES = ("java.base", "java.compiler", "java.desktop", "java.logging", "java.scripting", "jdk.unsupported",
               "jdk.charsets", "jdk.zipfs")


def jlink_runtime(dest: Path) -> bool:
    jdks = sorted(ROOT.glob(JDK_GLOB))
    if not jdks:
        return False
    out = subprocess.run([str(jdks[-1] / "bin" / "jlink.exe"), "--add-modules", ",".join(JRE_MODULES), "--strip-debug",
                          "--no-man-pages", "--no-header-files", "--compress=zip-0", "--output", str(dest)],
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise KitError(f"jlink: {out.stdout}{out.stderr}")
    return True


def unpack_runtime(archive: Path, dest: Path) -> None:
    import zipfile
    if not archive.exists():
        raise KitError(f"missing {archive} (download it: docs/player-engine-kit.md)")
    with zipfile.ZipFile(archive) as z:
        z.extractall(dest)
    inner = list(dest.iterdir())
    if len(inner) == 1 and inner[0].is_dir():
        for child in inner[0].iterdir():
            shutil.move(str(child), str(dest / child.name))
        inner[0].rmdir()
    for pth in dest.glob("python*._pth"):
        pth.unlink()


def size(folder: Path) -> int:
    return sum(p.stat().st_size for p in folder.rglob("*") if p.is_file())


def under(rel: tuple[str, ...], places: list[tuple[str, ...]]) -> bool:
    return any(rel[:len(p)] == p for p in places)


def audit(out: Path) -> list[str]:
    problems = []
    for path in out.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(out).parts
        if path.suffix.lower() in GAME_SUFFIXES and not under(rel, FROM_GIT):
            problems.append(f"{'/'.join(rel)}: a {path.suffix} file")
        elif any(rel[i:i + len(d)] == d for d in GAME_DIRS for i in range(len(rel))):
            problems.append(f"{'/'.join(rel)}: in a folder of game code")
        elif path.suffix == ".as" and not under(rel, AS_PLACES):
            problems.append(f"{'/'.join(rel)}: AS3 outside our sources")
        elif path.suffix == ".hx" and not under(rel, HX_PLACES):
            problems.append(f"{'/'.join(rel)}: Haxe outside our sources")
    return problems


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("action", choices=("build", "audit"))
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    p.add_argument("--engine", type=Path, default=DEFAULT_ENGINE)
    p.add_argument("--server", default=None, help=f"host:port the engine plays on (default: {DEFAULT_SERVER})")
    p.add_argument("--release", default=None, help="the release name (default: date-portcommit)")
    a = p.parse_args(argv)
    try:
        if a.action == "build":
            info = build(a.out.resolve(), a.engine, a.server, a.release)
            print(f"player kit {info['release']} -> {a.out} ({info['size_mb']} MB, {info['seconds']} s; AIR pin "
                  f"{info['air_pin']}; server {info['server']})")
            return 0
        problems = audit(a.out)
        print("\n".join(problems) if problems else f"{a.out}: no game files")
        return 1 if problems else 0
    except KitError as e:
        print(f"player_kit: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
