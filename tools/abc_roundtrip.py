#!/usr/bin/env python3
"""bytecode-level source round-trip for BrawlhallaAir.swf with RABCDAsm: the SWF's ABC blocks (block 11 is the game)
become an editable .asasm tree and build back into a SWF, the always-buildable baseline the AS3 recompilation is
checked against.

    python tools/abc_roundtrip.py disasm   # SWF -> src/asasm/<ver>/block-N/...
    python tools/abc_roundtrip.py build    # src/asasm -> build/roundtrip/BrawlhallaAir.swf
    python tools/abc_roundtrip.py verify   # rebuilt SWF == source tree (semantic check)

needs RABCDAsm (abcexport, rabcdasm, rabcasm, abcreplace) built with tools/patches/rabcdasm-denormal-fix.patch
(stock builds from a recent D compiler crash on this SWF's subnormal doubles); `python tools/setup_rabcdasm.py`
builds them into .tools/rabcdasm/bin, the default, else pass --rabcdasm DIR or set RABCDASM_DIR.

the round-trip is semantically lossless, not byte-identical: RABCDAsm merges duplicate constant-pool namespaces,
drops unreachable bytes after returns and unused labels, and renumbers anonymous closures. `verify` normalizes
exactly those (plus indentation, operand padding and comment-only lines, so a tree patched by tools/apply_mods.py
verifies too).
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXE = ".exe" if os.name == "nt" else ""
LOCAL_RABCDASM = ROOT / ".tools/rabcdasm/bin"


def tool(args, name: str) -> str:
    base = args.rabcdasm or os.environ.get("RABCDASM_DIR")
    if not base and (LOCAL_RABCDASM / (name + EXE)).exists():
        base = str(LOCAL_RABCDASM)
    path = Path(base) / (name + EXE) if base else shutil.which(name)
    if not path or not Path(path).exists():
        sys.exit(f"RABCDAsm tool '{name}' not found; pass --rabcdasm DIR or set RABCDASM_DIR")
    return str(path)


def run(cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"command failed: {' '.join(map(str, cmd))}\n{r.stdout}{r.stderr}")


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def export_blocks(args, swf: Path, work: Path) -> list[Path]:
    work.mkdir(parents=True, exist_ok=True)
    tmp = work / "input.swf"
    shutil.copyfile(swf, tmp)
    run([tool(args, "abcexport"), str(tmp)])
    blocks = []
    for f in sorted(work.glob("input-*.abc"), key=lambda p: int(p.stem.split("-")[1])):
        dst = work / f"block-{f.stem.split('-')[1]}.abc"
        f.replace(dst)
        blocks.append(dst)
    tmp.unlink()
    return blocks


def disasm_into(args, blocks: list[Path], out: Path):
    for abc in blocks:
        run([tool(args, "rabcdasm"), abc.name], cwd=abc.parent)
        shutil.move(str(abc.parent / abc.stem), str(out / abc.stem))


def cmd_disasm(args):
    out = Path(args.src)
    if out.exists() and any(out.iterdir()):
        sys.exit(f"{out} is not empty; refusing to overwrite source (use a fresh directory)")
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as t:
        blocks = export_blocks(args, Path(args.swf), Path(t))
        disasm_into(args, blocks, out)
    (out / "SOURCE.txt").write_text(
        f"Disassembled from {Path(args.swf).name}\nsha256 {sha256(Path(args.swf))}\n"
        f"blocks {len(blocks)}\n", encoding="utf-8")
    n = sum(1 for _ in out.rglob("*.asasm"))
    print(f"wrote {n} .asasm files for {len(blocks)} ABC blocks to {out}")


def cmd_build(args):
    src, out_swf = Path(args.src), Path(args.out)
    out_swf.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.swf, out_swf)
    blocks = sorted((d for d in src.iterdir() if d.is_dir() and d.name.startswith("block-")),
                    key=lambda d: int(d.name.split("-")[1]))
    with tempfile.TemporaryDirectory() as t:
        for d in blocks:
            stage = Path(t) / d.name
            shutil.copytree(d, stage)
            main = stage / f"{d.name}.main.asasm"
            run([tool(args, "rabcasm"), str(main)])
            run([tool(args, "abcreplace"), str(out_swf), d.name.split("-")[1],
                 str(main.with_suffix(".abc"))])
    print(f"built {out_swf} ({out_swf.stat().st_size} bytes, sha256 {sha256(out_swf)})")


_NORM = [
    ('"#', re.compile(r', "#\d+"\)'), ')'),
    ('L', re.compile(r'L\d+'), 'L'),
    ('inline_method#', re.compile(r'inline_method#\d+'), 'inline_method#N'),
    ('refid "', re.compile(r'(refid ".*)#\d+"'), r'\1#N"'),
]
_LABEL = re.compile(r"L\d+:")
_OPCODE_PAD = re.compile(r"^(\S+)\s+")


def normalized(tree: Path) -> list[str]:
    lines = []
    for f in sorted(tree.rglob("*.asasm")):
        if f.name.endswith(".main.asasm"):
            continue
        prefix = f"{f.relative_to(tree).parent}|"
        for line in f.read_text(encoding="utf-8", errors="surrogateescape").splitlines():
            s = line.strip()
            if not s or s.startswith(";") or _LABEL.fullmatch(s):
                continue
            line = _OPCODE_PAD.sub(r"\1 ", s)
            for needle, rx, rep in _NORM:
                if needle in line:
                    line = rx.sub(rep, line)
            lines.append(prefix + line)
    return sorted(lines)


def cmd_verify(args):
    src = Path(args.src)
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        blocks = export_blocks(args, Path(args.out), tmp / "x")
        (tmp / "d").mkdir()
        disasm_into(args, blocks, tmp / "d")
        bad = 0
        for d in sorted(p for p in src.iterdir() if p.is_dir()):
            a, b = normalized(d), normalized(tmp / "d" / d.name)
            if a != b:
                bad += 1
                sa, sb = set(a), set(b)
                print(f"{d.name}: {len(sa - sb)} source-only / {len(sb - sa)} built-only lines")
                for x in list(sa - sb)[:5]:
                    print("  -", x)
                for x in list(sb - sa)[:5]:
                    print("  +", x)
    if bad:
        sys.exit(f"verify FAILED for {bad} block(s)")
    print(f"verify OK: {args.out} matches {src}")


def main():
    vdir = ROOT / "versions"
    vers = sorted((d.name for d in vdir.iterdir() if d.is_dir()),
                  key=lambda v: [int(x) if x.isdigit() else x for x in v.split(".")]) if vdir.exists() else []
    ver = vers[-1] if vers else "10.11"
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=["disasm", "build", "verify"])
    p.add_argument("--rabcdasm", help="directory containing the RABCDAsm executables")
    p.add_argument("--swf", default=str(ROOT / f"versions/{ver}/BrawlhallaAir.swf"))
    p.add_argument("--src", default=str(ROOT / f"src/asasm/{ver}"))
    p.add_argument("--out", default=str(ROOT / "build/roundtrip/BrawlhallaAir.swf"))
    args = p.parse_args()
    {"disasm": cmd_disasm, "build": cmd_build, "verify": cmd_verify}[args.command](args)


if __name__ == "__main__":
    main()
