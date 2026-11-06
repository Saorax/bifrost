from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import port_version_names

OUT = ROOT / "build" / "version-tools"
STAMP = "STAGE.json"
KEEP_STAGES = 3
TEXT = {".py", ".hx", ".hxml", ".json", ".txt", ".md", ".xml"}
VERSIONED = {"port_haxe_compile.py", "as3_to_haxe.py", "compare_methods.py", "bifrost_build.py", "bifrost_hookmap.py",
             "port_raw_export.py", "bifrost_export.py"}


def stage_dir(version: str) -> Path:
    return OUT / version


def source_files() -> list[Path]:
    files = sorted((ROOT / "tools").glob("*.py"))
    files += sorted((ROOT / "data" / "tools").glob("*.py"))
    files += sorted(p for p in (ROOT / "port").rglob("*") if p.is_file() and ".git" not in p.parts)
    files += sorted(p for p in (ROOT / "data" / "runtime").rglob("*") if p.is_file())
    return files


def stage_key(version: str, files: list[Path]) -> str:
    digest = hashlib.sha256(version.encode())
    digest.update(str(ROOT).encode())
    digest.update(Path(__file__).read_bytes())
    digest.update(Path(port_version_names.__file__).read_bytes())
    table = port_version_names.OUT / f"10.11_to_{version}.json"
    digest.update(table.read_bytes() if table.exists() else b"<none>")
    for path in files:
        info = path.stat()
        digest.update(f"{path.relative_to(ROOT).as_posix()}|{info.st_size}|{info.st_mtime_ns}\n".encode())
    return digest.hexdigest()


def out_dir(version: str) -> Path:
    return ROOT / "build" / "version-out" / version


def rewrite_tool(text: str, target: Path, version: str) -> str:
    text = text.replace("Path(__file__).resolve().parents[1]", f"Path(r\"{ROOT}\")")
    text = text.replace("Path(__file__).resolve().parents[2]", f"Path(r\"{ROOT}\")")
    text = text.replace("sys.path.insert(0, str(ROOT))", f"sys.path.insert(0, r\"{target}\")")
    text = text.replace("if str(ROOT) not in sys.path:", f"if r\"{target}\" not in sys.path:")
    text = text.replace('ROOT / "port"', f'Path(r"{target}") / "port"')
    text = text.replace('ROOT / "data" / "runtime"', f'Path(r"{target}") / "data" / "runtime"')
    text = text.replace('ROOT / "tools" /', f'Path(r"{target}") / "tools" /')
    text = re.sub(r'"tools/(\w+\.py)"', lambda m: f'"{target.as_posix()}/tools/{m.group(1)}"', text)
    out = out_dir(version)
    text = re.sub(r'"C:/Coding/(BRAWLHALLA PROJECTS/bh-raw/bh-game|bh-port-engine-openfl)(?=[/"])',
                  lambda m: '"' + (out / ("bh-raw-game" if m.group(1).endswith("bh-game") else m.group(1))).as_posix(),
                  text)
    text = re.sub(r'ROOT\.parent / "(bh-raw-game|bh-port-engine-openfl)"',
                  lambda m: f'Path(r"{out / m.group(1)}")', text)
    text = text.replace('"build" / "port-heaps"', f'"build" / "port-heaps-{version}"')
    text = text.replace('"build" / "game-test" / "port"', f'"build" / "game-test" / "port-{version}"')
    text = text.replace('"build" / "bifrost"', f'"build" / "bifrost-{version}"')
    text = text.replace('"C:/Coding/bh-bifrost-engine"', '"C:/Coding/BRAWLHALLA PROJECTS/bifrost/bifrost-main"'
                        if version.startswith("11.00") else f'"C:/Coding/bh-bifrost-engine-{version}"')
    for parser in ("parser", "p"):
        text = text.replace(f'{parser}.add_argument("--version", default="10.11"',
                            f'{parser}.add_argument("--version", default="{version}"')
    return text


def own_storage(text: str, version: str) -> str:
    version = ".".join(version.split(".")[:2])
    tag = version.replace(".", "")
    text = text.replace('"BhPort"', f'"BhPort-{version}"').replace('"bhport_"', f'"bhport{tag}_"')
    text = text.replace('"bh-port-smoke"', f'"bh-port-smoke-{version}"')
    return text.replace('"build" / "port-parity"', f'"build" / "port-parity-{version}"')


def stage(version: str, *, force: bool = False) -> Path:
    files = source_files()
    key = stage_key(version, files)
    final = stage_dir(version) / key[:16]
    if not force and (final / STAMP).exists():
        return final
    carried = port_version_names.load_map("10.11", version)
    target = final.with_name(final.name + f".tmp{os.getpid()}")
    shutil.rmtree(target, ignore_errors=True)
    missing: dict[str, int] = {}
    for path in files:
        rel = path.relative_to(ROOT)
        out = target / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        if path.suffix not in TEXT:
            shutil.copy2(path, out)
            continue
        text = path.read_text(encoding="utf-8")
        names: set[str] = set()
        text = port_version_names.translate_text(text, carried, names)
        text = own_storage(text, version)
        if rel.parts[0] == "tools" or rel.parts[:2] == ("data", "tools"):
            text = rewrite_tool(text, final, version)
        out.write_text(text, encoding="utf-8")
        for name in names:
            missing[name] = missing.get(name, 0) + 1
    (target / "tools" / "__init__.py").touch()
    (target / STAMP).write_text(json.dumps({"key": key, "files": len(files), "uncarried": sorted(missing)}, indent=0)
                                + "\n", encoding="utf-8")
    if final.exists():
        shutil.rmtree(final, ignore_errors=True)
    target.rename(final)
    print(f"staged {len(files)} files for {version} -> {final} ({len(missing)} 10.11 names without a match)", flush=True)
    old = sorted((p for p in stage_dir(version).iterdir() if p.is_dir() and p != final and (p / STAMP).exists()),
                 key=lambda p: p.stat().st_mtime, reverse=True)
    for path in old[KEEP_STAGES - 1:]:
        shutil.rmtree(path, ignore_errors=True)
    return final


def run(version: str, tool: str, args: list[str]) -> int:
    target = stage(version)
    script = target / "tools" / tool
    if not script.exists():
        raise SystemExit(f"no tool {tool}")
    if tool in VERSIONED and "--version" not in args:
        args = args + ["--version", version]
    env = dict(os.environ, PYTHONPATH=str(target))
    return subprocess.call([sys.executable, str(script)] + args, cwd=ROOT, env=env)


def raw_chain(version: str, smoke_seconds: float) -> int:
    out = out_dir(version)
    steps = [["port_raw_export.py", "--out", str(out / "bh-raw-game"), "--openfl-engine",
              str(out / "bh-port-engine-openfl"), "--openfl-only", "--no-build"],
             ["port_heaps_stubs.py", "dump"]]
    if smoke_seconds > 0:
        steps.append(["port_heaps.py", "game", "--smoke", "--seconds", str(smoke_seconds)])
    for step in steps:
        print(f"== {' '.join(step[:2])}", flush=True)
        code = run(version, step[0], step[1:])
        if code != 0:
            print(f"{step[0]} failed ({code})")
            return code
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("stage", "run", "raw"))
    parser.add_argument("--smoke", type=float, default=200, help="raw: smoke seconds (0: export and dump only)")
    parser.add_argument("--version", required=True)
    parser.add_argument("--force", action="store_true")
    argv = list(sys.argv[1:] if argv is None else argv)
    rest = argv[argv.index("--") + 1:] if "--" in argv else []
    args = parser.parse_args(argv[:argv.index("--")] if "--" in argv else argv)
    if args.version == "10.11":
        parser.error("10.11 is the port's own version: run the tools directly")
    if args.command == "stage":
        stage(args.version, force=args.force)
        return 0
    if args.command == "raw":
        return raw_chain(args.version, args.smoke)
    if not rest:
        parser.error("run: name a tool, e.g. -- port_haxe_compile.py check-hl")
    return run(args.version, rest[0], rest[1:])


if __name__ == "__main__":
    raise SystemExit(main())
