#!/usr/bin/env python3
r"""apply src/mods/<mod>/ patches to a copy of the asasm source tree.

    python tools/apply_mods.py                       # every mod -> build/asasm-modded/<ver>/
    python tools/apply_mods.py --mod smoke_probe     # only the named mod(s)
    python tools/abc_roundtrip.py build --src build/asasm-modded/<ver> --out build/modded/BrawlhallaAir.swf
    python tools/abc_roundtrip.py verify --src build/asasm-modded/<ver> --out build/modded/BrawlhallaAir.swf

src/asasm/<ver>/ stays the untouched disassembly: the tree is copied to build/asasm-modded/<ver>/ and each mod's
mod.json is applied there, failing loudly when an anchor is missing or ambiguous (e.g. after a game update moved
the code).

mod.json:

    {
      "name": "smoke_probe",
      "block": "@document",                        # or "block-11"
      "add": ["asasm/bh_mods/smoke/SmokeProbe.script.asasm", ...],
      "include": ["bh_mods/smoke/SmokeProbe.script.asasm"],
      "patches": [
        {"class": "@document",                     # or a file path inside the tree
         "method": "iinit",                        # iinit | cinit | trait:<name>
         "after": "^constructsuper\b",            # regex on the stripped line; exactly one match
         "insert": ["getlocal0", "..."],
         "maxstack": 3}                            # raise the method's maxstack to at least this
      ]
    }

"add" files are copied into the block under their path relative to the mod's asasm/ folder, "include" lines go into
the block's main.asasm (before "end ; program"), and "@document" means the SWF's document class (SymbolClass id 0,
read from --swf).
"""
from __future__ import annotations

import argparse
import json
import lzma
import re
import shutil
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from tools.workspace_paths import checked_output
from tools.asasm_check import check as check_asasm

MODS = ROOT / "src/mods"
BUILD = ROOT / "build"


class ModError(Exception):
    pass


def swf_body(data: bytes) -> bytes:
    sig, size = data[:3], struct.unpack("<I", data[4:8])[0]
    if sig == b"FWS":
        return data[8:]
    if sig == b"CWS":
        return zlib.decompress(data[8:])
    if sig == b"ZWS":
        alone = data[12:17] + b"\xff" * 8 + data[17:]
        return lzma.LZMADecompressor(lzma.FORMAT_ALONE).decompress(alone)[:size - 8]
    raise ModError(f"not a SWF (signature {sig!r})")


def swf_tags(data: bytes):
    body = swf_body(data)
    nbits = body[0] >> 3
    pos = (5 + 4 * nbits + 7) // 8 + 4
    while pos + 2 <= len(body):
        code_len = struct.unpack_from("<H", body, pos)[0]
        code, length = code_len >> 6, code_len & 0x3F
        pos += 2
        if length == 0x3F:
            length = struct.unpack_from("<I", body, pos)[0]
            pos += 4
        yield code, body[pos:pos + length]
        pos += length
        if code == 0:
            break


def document_class(data: bytes) -> str:
    for code, payload in swf_tags(data):
        if code != 76:
            continue
        count, pos = struct.unpack_from("<H", payload)[0], 2
        for _ in range(count):
            tag_id = struct.unpack_from("<H", payload, pos)[0]
            end = payload.index(b"\0", pos + 2)
            name = payload[pos + 2:end].decode("utf-8")
            pos = end + 1
            if tag_id == 0:
                return name
    raise ModError("SWF has no document class (SymbolClass id 0)")


def blocks(tree: Path) -> list[Path]:
    return sorted((d for d in tree.iterdir() if d.is_dir() and d.name.startswith("block-")),
                  key=lambda d: int(d.name.split("-")[1]))


def find_class_file(tree: Path, qname: str) -> Path:
    pkg, _, name = qname.rpartition(".")
    decl = re.compile(rf'^instance QName\(PackageNamespace\("{re.escape(pkg)}"(, "#\d+")?\), "{re.escape(name)}"\)$')
    hits = []
    for block in blocks(tree):
        for f in block.rglob("*.class.asasm"):
            with f.open(encoding="utf-8", errors="surrogateescape") as fh:
                for line in fh:
                    if decl.match(line.strip()):
                        hits.append(f)
                        break
    if len(hits) != 1:
        raise ModError(f"class {qname}: expected one definition, found {len(hits)} {hits}")
    return hits[0]


def block_of(tree: Path, path: Path) -> Path:
    rel = path.relative_to(tree)
    return tree / rel.parts[0]


def method_span(lines: list[str], method: str) -> tuple[int, int]:
    if method in ("iinit", "cinit"):
        starts = [i for i, l in enumerate(lines) if l.strip() == method]
    elif method.startswith("trait:"):
        name = re.escape(method[6:])
        rx = re.compile(rf'^trait (method|getter|setter) QName\(.*, "{name}"\)')
        starts = [i for i, l in enumerate(lines) if rx.match(l.strip())]
    else:
        raise ModError(f"unknown method selector {method!r}")
    if len(starts) != 1:
        raise ModError(f"method {method}: expected one, found {len(starts)}")
    start = starts[0]
    for i in range(start, len(lines)):
        if lines[i].strip() == "end ; method":
            return start, i + 1
    raise ModError(f"method {method}: no 'end ; method'")


def apply_patch(path: Path, patch: dict) -> None:
    text = path.read_text(encoding="utf-8", errors="surrogateescape")
    lines = text.splitlines(keepends=True)
    start, end = method_span(lines, patch["method"])
    rx = re.compile(patch["after"])
    hits = [i for i in range(start, end) if rx.search(lines[i].strip())]
    if len(hits) != 1:
        raise ModError(f"{path.name} {patch['method']}: anchor {patch['after']!r} "
                       f"matched {len(hits)} lines, expected 1")
    anchor = lines[hits[0]]
    indent = anchor[:len(anchor) - len(anchor.lstrip())]
    lines[hits[0] + 1:hits[0] + 1] = [indent + ins + "\n" for ins in patch["insert"]]
    if "maxstack" in patch:
        for i in range(start, end):
            m = re.match(r"^(\s*maxstack\s+)(\d+)\s*$", lines[i])
            if m:
                if int(m.group(2)) < patch["maxstack"]:
                    lines[i] = f"{m.group(1)}{patch['maxstack']}\n"
                break
        else:
            raise ModError(f"{path.name} {patch['method']}: no maxstack line")
    path.write_text("".join(lines), encoding="utf-8", errors="surrogateescape")


def add_include(main: Path, include: str) -> None:
    lines = main.read_text(encoding="utf-8").splitlines(keepends=True)
    ends = [i for i, l in enumerate(lines) if l.strip() == "end ; program"]
    if len(ends) != 1:
        raise ModError(f"{main.name}: expected one 'end ; program'")
    lines.insert(ends[0], f' #include "{include}"\n')
    main.write_text("".join(lines), encoding="utf-8")


def verify_file(path: Path, tree: Path) -> None:
    errors = check_asasm(path.read_text(encoding="utf-8", errors="surrogateescape"))
    if errors:
        raise ModError(f"{path.relative_to(tree)} would fail AVM2 verification:\n  " + "\n  ".join(errors[:10]))


def apply_mod(tree: Path, mod_dir: Path, doc_class: str | None) -> list[str]:
    spec = json.loads((mod_dir / "mod.json").read_text(encoding="utf-8"))
    log = []

    def resolve_class(ref: str) -> Path:
        if ref == "@document":
            if not doc_class:
                raise ModError(f"{mod_dir.name}: '@document' needs --swf")
            return find_class_file(tree, doc_class)
        path = tree / ref
        if not path.is_file():
            raise ModError(f"{mod_dir.name}: {ref} not in the tree")
        return path

    block_ref = spec.get("block", "@document")
    if block_ref.startswith("block-"):
        block = tree / block_ref
    else:
        block = block_of(tree, resolve_class(block_ref))
    if not block.is_dir():
        raise ModError(f"{mod_dir.name}: {block.name} not in the tree")
    for rel in spec.get("add", []):
        src = mod_dir / rel
        dst = block / Path(rel).relative_to("asasm")
        if dst.exists():
            raise ModError(f"{mod_dir.name}: {dst.relative_to(tree)} already exists")
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        verify_file(dst, tree)
        log.append(f"add {dst.relative_to(tree)}")
    for inc in spec.get("include", []):
        add_include(block / f"{block.name}.main.asasm", inc)
        log.append(f"include {inc} in {block.name}")
    for patch in spec.get("patches", []):
        path = resolve_class(patch["class"])
        apply_patch(path, patch)
        verify_file(path, tree)
        log.append(f"patch {path.relative_to(tree)} {patch['method']} after /{patch['after']}/")
    return log


def available_mods(folder: Path | None = None) -> list[str]:
    folder = folder or MODS
    return sorted(d.name for d in folder.iterdir() if (d / "mod.json").is_file()) if folder.exists() else []


def main():
    vdir = ROOT / "versions"
    vers = sorted((d.name for d in vdir.iterdir() if d.is_dir()),
                  key=lambda v: [int(x) if x.isdigit() else x for x in v.split(".")]) if vdir.exists() else []
    ver = vers[-1] if vers else "10.11"
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--mod", action="append", help="mod to apply (repeatable; default: all in src/mods)")
    p.add_argument("--swf", default=str(ROOT / f"versions/{ver}/BrawlhallaAir.swf"),
                   help="original SWF, for the document class")
    p.add_argument("--src", default=str(ROOT / f"src/asasm/{ver}"))
    p.add_argument("--out", default=str(BUILD / f"asasm-modded/{ver}"))
    p.add_argument("--mods", type=Path, help="mods folder (default src/mods; tools/port_platform.py writes one "
                                             "for another version)")
    args = p.parse_args()
    global MODS
    MODS = args.mods or MODS

    src = Path(args.src)
    if not src.is_dir():
        sys.exit(f"{src} not found; run `python tools/abc_roundtrip.py disasm` first")
    try:
        out = checked_output(Path(args.out), BUILD)
    except ValueError as e:
        sys.exit(str(e))
    names = args.mod or available_mods()
    try:
        doc = document_class(Path(args.swf).read_bytes()) if Path(args.swf).is_file() else None
    except ModError as e:
        sys.exit(f"apply_mods FAILED: {args.swf}: {e}")

    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(src, out)
    log = [f"document class: {doc}"]
    try:
        for name in names:
            if not (MODS / name / "mod.json").is_file():
                raise ModError(f"no mod {name!r} in {MODS}")
            log += [f"[{name}] {x}" for x in apply_mod(out, MODS / name, doc)]
    except ModError as e:
        shutil.rmtree(out)
        sys.exit(f"apply_mods FAILED: {e}")
    (out / "MODS.txt").write_text("\n".join(log) + "\n", encoding="utf-8")
    print("\n".join(log))
    print(f"applied {len(names)} mod(s) to {out}")


if __name__ == "__main__":
    main()
