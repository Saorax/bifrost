"""check that every sprite in a SWF survives what the game does with bone sprites, on the game's own runtime.

    python tools/sprite_check.py mods/bmod-x/bones/Bones_X.swf [--game versions/10.11] [--timeout 300]

the game recolours a skin's bone sprites by reading their vector data back and drawing it again (readGraphicsData,
drawGraphicsData, BitmapData.draw); some art crashes the runtime there natively, with no script error. this runs
tools/sprite_check/SpriteCheck.as in a copy of the game's captive runtime (build/sprite_check/runtime) on the SWF's
sprite classes; its log is written line by line, so after a crash the last line names the sprite, frame and step.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import bmod_import
import setup_as3_compiler

WORK = ROOT / "build" / "sprite_check"


def build_program() -> bytes:
    if not setup_as3_compiler.compc_jar().is_file():
        raise SystemExit("compiler missing; run python tools/setup_as3_compiler.py")
    return compile_app(ROOT / "tools" / "sprite_check", WORK / "spritecheck.swc", "SpriteCheck")


def compile_app(src: Path, swc: Path, document_class: str) -> bytes:
    jar = setup_as3_compiler.compc_jar()
    swc.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        config = Path(tmp, "config.xml")
        config.write_text("<royale-config/>\n", encoding="utf-8")
        cmd = ["java", "-jar", str(jar), f"-load-config={config}",
               f"-compiler.external-library-path+={setup_as3_compiler.AIRGLOBAL}",
               f"-compiler.source-path+={src}", f"-include-sources+={src}", f"-output={swc}"]
        r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        raise SystemExit("compc failed:\n" + r.stdout + r.stderr)
    with zipfile.ZipFile(swc) as z:
        library = z.read("library.swf")
    header, tags = bmod_import.read_swf(library)
    out, placed = [], False
    for code, body in tags:
        if code == bmod_import.SHOW_FRAME and not placed:
            out.append((bmod_import.SYMBOL_CLASS, bmod_import.symbol_class_tag([(0, document_class)])))
            placed = True
        out.append((code, body))
    rect = bytes([0x78, 0x00, 0x03, 0xE8, 0x00, 0x00, 0x0B, 0xB8, 0x00])
    return bmod_import.write_swf(dict(header, version=43, rect=rect, rate=30, count=1), out)


def runtime(game: Path, program: bytes) -> Path:
    rt = WORK / "runtime"
    if not (rt / "Brawlhalla.exe").exists():
        rt.mkdir(parents=True, exist_ok=True)
        shutil.copy(game / "Brawlhalla.exe", rt / "Brawlhalla.exe")
        shutil.copytree(game / "Adobe AIR", rt / "Adobe AIR", dirs_exist_ok=True)
        shutil.copytree(game / "META-INF", rt / "META-INF", dirs_exist_ok=True)
    (rt / "BrawlhallaAir.swf").write_bytes(program)
    descriptor = rt / "META-INF" / "AIR" / "application.xml"
    text = descriptor.read_text(encoding="utf-8")
    descriptor.write_text(text.replace("<id>BrawlhallaAir</id>", "<id>BrawlhallaAirSpriteCheck</id>"), encoding="utf-8")
    return rt


def check(swf: Path, game: Path, timeout: int, only: list[str] | None = None, start: int = 0,
          mode: str = "full") -> tuple[str, list[str]]:
    _, tags = bmod_import.read_swf(swf.read_bytes())
    classes = [name for code, body in tags if code == bmod_import.SYMBOL_CLASS
               for _, name in bmod_import.symbol_class(body)]
    classes = [c for c in classes if not only or c in only][start:]
    rt = runtime(game, build_program())
    log = WORK / "spritecheck.log"
    log.unlink(missing_ok=True)
    (rt / "spritecheck.json").write_text(json.dumps({"swf": str(swf.resolve()), "classes": classes,
                                                     "log": str(log), "mode": mode}), encoding="utf-8")
    proc = subprocess.Popen([str(rt / "Brawlhalla.exe")], cwd=rt)
    try:
        code = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        code = "timeout"
    lines = log.read_text(encoding="utf-8", errors="replace").splitlines() if log.exists() else []
    if lines and lines[-1].startswith("done:"):
        return "ok", lines
    return f"stopped (exit {code})", lines


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("swf", type=Path)
    p.add_argument("--game", type=Path, default=ROOT / "versions" / "10.11")
    p.add_argument("--timeout", type=int, default=300)
    p.add_argument("--only", action="append", help="check only this class (repeatable)")
    p.add_argument("--start", type=int, default=0, help="skip the first N classes")
    p.add_argument("--mode", choices=["full", "draw", "read"], default="full",
                   help="draw: no rasterizing; read: only read the vector data back")
    args = p.parse_args(argv)
    status, lines = check(args.swf, args.game, args.timeout, args.only, args.start, args.mode)
    errors = [l for l in lines if l.startswith("error ")]
    print(f"{args.swf.name}: {status}; {sum(1 for l in lines if l.endswith(' ok'))} sprites passed")
    for l in errors:
        print("  " + l)
    if status != "ok":
        print("  last steps before it stopped:")
        for l in lines[-4:]:
            print("    " + l)
    return 0 if status == "ok" and not errors else 1


if __name__ == "__main__":
    sys.exit(main())
