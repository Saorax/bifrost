#!/usr/bin/env python3
"""bytecode-level source round-trip for BrawlhallaAir.swf using RABCDAsm (.asasm tree <-> SWF).

    python tools/abc_roundtrip.py disasm   # SWF -> src/asasm/<ver>/block-N/...
    python tools/abc_roundtrip.py build    # src/asasm -> build/roundtrip/BrawlhallaAir.swf
    python tools/abc_roundtrip.py verify   # rebuilt SWF == source tree (semantic check)

requires RABCDAsm (abcexport, rabcdasm, rabcasm) built with tools/patches/rabcdasm-denormal-fix.patch:
`python tools/setup_rabcdasm.py` builds them into .tools/rabcdasm/bin (the default); otherwise pass
--rabcdasm DIR or set RABCDASM_DIR.

the round trip is semantically lossless, not byte-identical: RABCDAsm merges duplicate namespaces, drops
unreachable bytes and unused labels, and renumbers closures. `verify` normalizes exactly those (plus
indentation, operand padding and comment-only lines, so a tree patched by tools/apply_mods.py verifies too).
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
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


def replace_blocks(swf: Path, blocks: dict[int, bytes]) -> None:
    data = swf.read_bytes()
    sig = data[:3]
    if sig not in (b"CWS", b"FWS"):
        raise ValueError(f"{swf}: not an uncompressed or zlib SWF ({sig!r})")
    raw = data[:8] + (zlib.decompress(data[8:]) if sig == b"CWS" else data[8:])
    nbits = raw[8] >> 3
    pos = 8 + (5 + 4 * nbits + 7) // 8 + 4
    out, index, done = [raw[:pos]], 0, set()
    while pos < len(raw):
        start = pos
        code_len = struct.unpack_from("<H", raw, pos)[0]
        pos += 2
        code, length, long_form = code_len >> 6, code_len & 0x3F, False
        if length == 0x3F:
            length, long_form = struct.unpack_from("<I", raw, pos)[0], True
            pos += 4
        body = raw[pos:pos + length]
        pos += length
        if code in (72, 82):
            if index in blocks:
                prefix = body[:body.index(b"\0", 4) + 1] if code == 82 else b""
                body = prefix + blocks[index]
                long_form = long_form or len(body) >= 0x3F
                out.append(struct.pack("<HI", (code << 6) | 0x3F, len(body)) if long_form
                           else struct.pack("<H", (code << 6) | len(body)))
                out.append(body)
                done.add(index)
                index += 1
                continue
            index += 1
        out.append(raw[start:pos])
        if code == 0:
            break
    missing = set(blocks) - done
    if missing:
        raise ValueError(f"{swf}: no ABC block {sorted(missing)} (it has {index})")
    body = b"".join(out)
    body = body[:4] + struct.pack("<I", len(body)) + body[8:]
    swf.write_bytes(body[:8] + zlib.compress(body[8:], 9) if sig == b"CWS" else body)


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def _touch_read(path: str) -> None:
    with open(path, "rb") as f:
        f.read(1)


def warm(*trees: Path) -> int:
    files = [os.path.join(d, n) for t in trees if Path(t).exists() for d, _, names in os.walk(t) for n in names]
    if files:
        _parallel(_touch_read, files)
    return len(files)


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


def _parallel(fn, items) -> list:
    import concurrent.futures
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        return list(pool.map(fn, items))


def disasm_into(args, blocks: list[Path], out: Path):
    def one(abc: Path) -> None:
        run([tool(args, "rabcdasm"), abc.name], cwd=abc.parent)
        shutil.move(str(abc.parent / abc.stem), str(out / abc.stem))
    _parallel(one, blocks)
    warm(out)


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
    warm(src)

    def one(d: Path) -> tuple[int, bytes]:
        main = d / f"{d.name}.main.asasm"
        abc = main.with_suffix(".abc")
        try:
            run([tool(args, "rabcasm"), str(main)])
            return int(d.name.split("-")[1]), abc.read_bytes()
        finally:
            abc.unlink(missing_ok=True)
    abcs = dict(_parallel(one, blocks))
    replace_blocks(out_swf, abcs)
    print(f"built {out_swf} ({out_swf.stat().st_size} bytes, sha256 {sha256(out_swf)})")


_NORM = [
    ('"#', re.compile(r', "#\d+"\)'), ')'),
    ('L', re.compile(r'L\d+'), 'L'),
    ('inline_method#', re.compile(r'inline_method#\d+'), 'inline_method#N'),
    ('refid "', re.compile(r'(refid ".*)#\d+"'), r'\1#N"'),
]
_LABEL = re.compile(r"L\d+:")
_OPCODE_PAD = re.compile(r"^(\S+)\s+")


def _file_lines(f: Path, prefix: str) -> list[str]:
    lines = []
    for line in f.read_text(encoding="utf-8", errors="surrogateescape").splitlines():
        s = line.strip()
        if not s or s.startswith(";") or _LABEL.fullmatch(s):
            continue
        line = _OPCODE_PAD.sub(r"\1 ", s)
        for needle, rx, rep in _NORM:
            if needle in line:
                line = rx.sub(rep, line)
        lines.append(prefix + line)
    return lines


def normalized(tree: Path, skip: frozenset[str] | set[str] = frozenset()) -> list[str]:
    lines = []
    for f in sorted(tree.rglob("*.asasm")):
        if f.name.endswith(".main.asasm") or (skip and f.relative_to(tree).as_posix() in skip):
            continue
        lines += _file_lines(f, f"{f.relative_to(tree).parent}|")
    return sorted(lines)


def _pair_chunk(a: str, b: str, rels: list[str]) -> tuple[list[str], list[str]]:
    la, lb = [], []
    for rel in rels:
        fa, fb = Path(a) / rel, Path(b) / rel
        x, y = fa.read_bytes(), fb.read_bytes()
        if x == y or x.replace(b"\r\n", b"\n") == y.replace(b"\r\n", b"\n"):
            continue
        prefix = f"{Path(rel).parent}|"
        na, nb = _file_lines(fa, prefix), _file_lines(fb, prefix)
        if sorted(na) != sorted(nb):
            la += na
            lb += nb
    return la, lb


PAIR_PARALLEL_MIN = 300


def normalized_pair(a: Path, b: Path) -> tuple[list[str], list[str]]:
    def rels(tree: Path) -> set[str]:
        return {f.relative_to(tree).as_posix() for f in tree.rglob("*.asasm") if not f.name.endswith(".main.asasm")}

    ra, rb = rels(a), rels(b)
    both = sorted(ra & rb)
    la = [line for rel in sorted(ra - rb) for line in _file_lines(a / rel, f"{Path(rel).parent}|")]
    lb = [line for rel in sorted(rb - ra) for line in _file_lines(b / rel, f"{Path(rel).parent}|")]
    parts = None
    if len(both) >= PAIR_PARALLEL_MIN and not os.environ.get("BH_NO_PARALLEL_VERIFY"):
        import concurrent.futures
        n = min(8, os.cpu_count() or 1)
        chunks = [both[i::n * 4] for i in range(n * 4)]
        try:
            with concurrent.futures.ProcessPoolExecutor(n) as pool:
                parts = list(pool.map(_pair_chunk, [str(a)] * len(chunks), [str(b)] * len(chunks), chunks))
        except (OSError, RuntimeError):
            parts = None
    if parts is None:
        parts = [_pair_chunk(str(a), str(b), both)]
    for x, y in parts:
        la += x
        lb += y
    return sorted(la), sorted(lb)


def cmd_verify(args):
    src = Path(args.src)
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        blocks = export_blocks(args, Path(args.out), tmp / "x")
        (tmp / "d").mkdir()
        disasm_into(args, blocks, tmp / "d")
        bad = 0
        for d in sorted(p for p in src.iterdir() if p.is_dir()):
            a, b = normalized_pair(d, tmp / "d" / d.name)
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


def newest_version(root: Path = ROOT) -> str | None:
    vdir = root / "versions"
    vers = sorted((d.name for d in vdir.iterdir() if (d / "BrawlhallaAir.swf").is_file()),
                  key=lambda v: [int(x) if x.isdigit() else x for x in v.split(".")]) if vdir.exists() else []
    return vers[-1] if vers else None


def main():
    ver = newest_version() or "10.11"
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
