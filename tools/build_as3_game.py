"""build the game SWF from the AS3 source, with the original names and the mods applied.

    python tools/build_as3_game.py [--version 11.00.49] [--export] [--no-mods]

runs, stopping at the first failure:

1. ``export_as3.py`` (only with ``--export``, or when ``src/as3/<ver>/scripts``
   doesn't exist yet: exporting recreates that tree and would wipe edits there);
2. ``apply_platform.py``: the extension layer (``src/platform``) and its hook call
   sites, unless ``--no-platform``; ``--hook-test`` also builds in the hook
   test mod, ``--mod <name>`` the platform mod ``bh/mods/<name>``;
3. ``compile_as3.py`` -> ``build/as3/<ver>/game.swc``;
4. ``splice_as3.py`` -> ``build/as3/<ver>/BrawlhallaAir.swf`` (original bytecode
   where the compiled code still differs, unless edited);
5. ``rename_back.py`` -> ``build/as3/<ver>/BrawlhallaAir.original-names.swf``,
   checked method by method against the original SWF;
6. unless ``--no-mods``: ``abc_roundtrip.py disasm`` of that SWF into
   ``build/asasm-as3/<ver>``, ``apply_platform_bytecode.py`` (hooks inserted
   into the original bytecode, ``"mode": "bytecode"`` in patches.json), ``apply_mods.py`` into ``build/asasm-as3-modded/<ver>``,
   (every mod in ``src/mods`` except those named with ``--without-mod``, plus each
   ``--bytecode-mod`` from ``data/mods``), then ``abc_roundtrip.py build`` and ``verify``
   -> ``build/as3-modded/BrawlhallaAir.swf``.

steps 3-5 are skipped when their inputs (the AS3 tree after step 2, the
export's fixups, the symbol maps, the SWFs they read, the tools they run, the
compiler and RABCDAsm) hash to a kept result in ``build/cache/as3-build``
(the last 8 kept); ``--no-cache`` always runs them.

for another ``--version``, ``port_platform.py`` first carries ``src/platform``
and ``src/mods`` to that version's names, and the SWF goes to ``build/as3-modded/<ver>/``.

the last line printed is the SWF to copy into the game folder (``docs/smoke-test.md``).
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
BASE_VERSION = "10.11"


def step(name: str, args: list[str]) -> None:
    print(f"== {name}", flush=True)
    t0 = time.perf_counter()
    r = subprocess.run([sys.executable, str(ROOT / "tools" / args[0]), *args[1:]], cwd=ROOT)
    print(f"   ({name}: {time.perf_counter() - t0:.1f} s)", flush=True)
    if r.returncode:
        print(f"build_as3_game: {name} failed (exit {r.returncode})", file=sys.stderr)
        sys.exit(r.returncode)


CACHE = ROOT / "build" / "cache" / "as3-build"
CACHE_KEEP = 8
CACHED_STEPS = ("compile_as3.py", "splice_as3.py", "rename_back.py")
CACHED_OUTPUTS = ("game.swc", "as3-compile.json", "BrawlhallaAir.swf", "splice.json",
                  "BrawlhallaAir.original-names.swf")
IMPORT = re.compile(r"^\s*(?:from|import)\s+(.+)$", re.M)


def tool_sources(names) -> list[Path]:
    tools, seen, todo = ROOT / "tools", set(), list(names)
    while todo:
        name = todo.pop()
        if name in seen or not (tools / name).is_file():
            continue
        seen.add(name)
        for m in IMPORT.finditer((tools / name).read_text(encoding="utf-8")):
            todo += [w + ".py" for w in re.findall(r"\w+", m.group(1)) if (tools / (w + ".py")).is_file()]
    return [tools / n for n in sorted(seen)]


def as3_build_key(ver: str) -> str:
    from tools import compare_methods, setup_as3_compiler
    h = hashlib.sha256()

    def add(path: Path) -> None:
        h.update(path.relative_to(ROOT).as_posix().encode() + b"\0")
        if path.is_file():
            h.update(hashlib.sha256(path.read_bytes()).digest())
        else:
            h.update(b"missing")

    tree = ROOT / "src" / "as3" / ver / "scripts"
    for path in sorted(p for p in tree.rglob("*") if p.is_file()):
        add(path)
    out_dir = ROOT / "build" / "as3" / ver
    for path in (out_dir / "as3-fixups.json", out_dir / "as3-pristine.json",
                 ROOT / "versions" / ver / "BrawlhallaAir.swf", compare_methods.base_swf(ver),
                 *sorted((ROOT / "client" / "symbols").glob(f"{ver}.*json")),
                 *tool_sources(CACHED_STEPS + ("setup_as3_compiler.py",))):
        add(path)
    jar, rabc = setup_as3_compiler.compc_jar(), ROOT / ".tools" / "rabcdasm" / "bin"
    for path in (jar, setup_as3_compiler.AIRGLOBAL, *sorted(rabc.glob("*"))):
        st = path.stat() if path.exists() else None
        h.update(f"{path.as_posix()}:{st and st.st_size}:{st and st.st_mtime_ns}\0".encode())
    h.update(f"{setup_as3_compiler.VERSION}:{sys.version_info[:2]}".encode())
    return h.hexdigest()


def cache_load(key: str, out_dir: Path) -> bool:
    entry = CACHE / key
    if not all((entry / n).is_file() for n in CACHED_OUTPUTS):
        return False
    for n in CACHED_OUTPUTS:
        shutil.copyfile(entry / n, out_dir / n)
    os.utime(entry)
    return True


def cache_store(key: str, out_dir: Path) -> None:
    entry = CACHE / key
    tmp = CACHE / (key + ".tmp")
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)
    for n in CACHED_OUTPUTS:
        shutil.copyfile(out_dir / n, tmp / n)
    shutil.rmtree(entry, ignore_errors=True)
    tmp.rename(entry)
    entries = sorted((p for p in CACHE.iterdir() if p.is_dir() and not p.name.endswith(".tmp")),
                     key=lambda p: p.stat().st_mtime, reverse=True)
    for old in entries[CACHE_KEEP:]:
        shutil.rmtree(old, ignore_errors=True)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--version", default="11.00.49", help="game version to build (default 11.00.49, the current one since "
                   "2026-10-14; 10.11 for the old copy). src/platform and src/mods name 10.11's symbols and are "
                   "ported to it")
    p.add_argument("--export", action="store_true", help="re-export the AS3 tree first (wipes edits in it)")
    p.add_argument("--no-mods", action="store_true", help="stop after renaming back")
    p.add_argument("--no-platform", action="store_true", help="leave out the extension layer (src/platform)")
    p.add_argument("--hook-test", action="store_true", help="build in the hook test mod (logs to Documents\\Bifrost\\bh-hooks.txt)")
    p.add_argument("--mod", action="append", default=[], help="platform mod to build in (src/platform/as3/bh/mods/<mod>)")
    p.add_argument("--no-cache", action="store_true", help="always compile, splice and rename back (no build cache)")
    p.add_argument("--bytecode-mod", action="append", default=[],
                   help="also apply this bytecode mod from data/mods (private), e.g. smoke_probe")
    p.add_argument("--without-mod", action="append", default=[],
                   help="leave out this src/mods asasm mod (for finding which one breaks a build), e.g. offline_switch")
    args = p.parse_args(argv)
    ver = args.version
    tree = ROOT / "src" / "as3" / ver / "scripts"
    (ROOT / "build" / "as3").mkdir(parents=True, exist_ok=True)
    if args.export or not tree.exists():
        step("export", ["export_as3.py", "--version", ver])
    platform, mods_dir = [], []
    if ver != BASE_VERSION:
        step("port", ["port_platform.py", "--from", BASE_VERSION, "--to", ver])
        port = ROOT / "build" / f"port-{ver}"
        platform, mods_dir = ["--platform", str(port / "platform")], ["--mods", str(port / "mods")]
    if not args.no_platform:
        mods = (["hooktest"] if args.hook_test else []) + [m for m in args.mod if m != "hooktest"]
        step("platform", ["apply_platform.py", "--version", ver] + [a for m in mods for a in ("--mod", m)] + platform)
    out_dir = ROOT / "build" / "as3" / ver
    named = out_dir / "BrawlhallaAir.original-names.swf"
    t0 = time.perf_counter()
    key = None if args.no_cache else as3_build_key(ver)
    if key is not None and cache_load(key, out_dir):
        print(f"== compile, splice, rename back: cached ({key[:12]}, {time.perf_counter() - t0:.1f} s)", flush=True)
    else:
        step("compile", ["compile_as3.py", "--version", ver])
        step("splice", ["splice_as3.py", "--version", ver])
        step("rename back", ["rename_back.py", "--version", ver, "--out", str(named)])
        if key is not None:
            cache_store(key, out_dir)
    if args.no_mods:
        print(named)
        return 0
    asasm, modded = ROOT / "build" / "asasm-as3" / ver, ROOT / "build" / "asasm-as3-modded" / ver
    out = ROOT / "build" / "as3-modded" / ("" if ver == BASE_VERSION else ver) / "BrawlhallaAir.swf"
    for d in (asasm, modded):
        if d.exists():
            shutil.rmtree(d)
    step("disassemble", ["abc_roundtrip.py", "disasm", "--swf", str(named), "--src", str(asasm)])
    if not args.no_platform:
        step("bytecode hooks", ["apply_platform_bytecode.py", "--src", str(asasm), "--version", ver] + platform)
    only = []
    if args.without_mod or args.bytecode_mod:
        from tools.apply_mods import available_mods
        mods = available_mods(Path(mods_dir[1]) if mods_dir else None)
        unknown = sorted(set(args.without_mod) - set(mods))
        if unknown:
            print(f"build_as3_game: unknown --without-mod {unknown}; mods: {mods}", file=sys.stderr)
            return 2
        only = [a for m in mods + args.bytecode_mod if m not in args.without_mod for a in ("--mod", m)]
    step("apply mods", ["apply_mods.py", "--swf", str(named), "--src", str(asasm), "--out", str(modded)] + only + mods_dir)
    step("assemble", ["abc_roundtrip.py", "build", "--src", str(modded), "--swf", str(named), "--out", str(out)])
    step("verify", ["abc_roundtrip.py", "verify", "--src", str(modded), "--out", str(out)])
    if "discordpresence" in args.mod:
        step("Discord bridge", ["build_discord_bridge.py", "--out", str(out.with_name("BifrostDiscord.exe"))])
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
