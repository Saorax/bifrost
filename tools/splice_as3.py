"""put the original bytecode back into the compiled AS3 and rebuild the game SWF.

    python tools/splice_as3.py [--version 10.11] [--swc build/as3/<ver>/game.swc]
                               [--renamed-swf build/as3/renamed.swf] [--out build/as3/<ver>/BrawlhallaAir.swf]

steps: 1 disassemble, 2 regroup the compiled scripts into the original blocks, 3 splice BH_SPLICE stubs and script
initializers (3b: signature parts AS3 cannot say), 4 rename source-only renames back, 5 assemble into a copy of the
renamed SWF, 6 keep the original bytecode where the compiled code still differs, then verify. writes the spliced tree
to build/as3/<ver>/splice/src and a report to build/as3/<ver>/splice.json; exit 0 only when every check passed.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import functools
import hashlib
from collections import Counter
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
if __package__:
    from . import abc_roundtrip, as3_edits, compare_methods
else:
    import abc_roundtrip
    import as3_edits
    import compare_methods

STUB = re.compile(r'^\s*pushstring\s+"BH_SPLICE ([^"]+)"\s*$')
INCLUDE = re.compile(r'^\s*#include\s+"(.+)"\s*$')
NEWFUNCTION = re.compile(r'^\s*newfunction\s+"(.+)"\s*$')
REFID = re.compile(r'^(\s*)refid\s+"(.*)"\s*$')
TRAIT = re.compile(r'^\s*trait\s+(\w+)\s+(QName\(\w+\("(?:[^"\\]|\\.)*"(?:, "#\d+")?\), "((?:[^"\\]|\\.)*)"\))')
NS_DISAMBIGUATOR = re.compile(r'(\b\w*(?:Namespace|Ns)\("(?:[^"\\]|\\.)*"), "#\d+"\)')


class SpliceError(Exception):
    pass


def run(cmd: list[str], cwd: Path | None = None) -> None:
    r = subprocess.run([str(c) for c in cmd], cwd=cwd, capture_output=True, text=True)
    if r.returncode:
        raise SpliceError(f"command failed: {' '.join(map(str, cmd))}\n{r.stdout}{r.stderr}")


def read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8", errors="surrogateescape").split("\n")


def write_lines(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8", errors="surrogateescape")


def strip_disambiguators(text: str) -> str:
    return NS_DISAMBIGUATOR.sub(r"\1)", text)


CACHE = ROOT / "build" / "cache" / "rabcdasm"


def _tool_key(exe: Path) -> str:
    st = exe.stat()
    return hashlib.sha1(f"{exe.resolve()}|{st.st_size}|{st.st_mtime_ns}".encode()).hexdigest()[:12]


def _disassemble_one(exe: Path, abc: Path, cache_root: Path | None) -> Path:
    dest = abc.parent / abc.stem
    main = f"{abc.stem}.main.asasm"
    cached = cache_root / hashlib.sha1(abc.read_bytes()).hexdigest() if cache_root else None
    if cached is not None and (cached / "_.main.asasm").exists():
        os.utime(cached)
        shutil.copytree(cached, dest)
        (dest / "_.main.asasm").rename(dest / main)
    else:
        run([exe, abc])
        if cached is not None:
            tmp = cached.with_name(cached.name + f".tmp{os.getpid()}-{threading.get_ident()}")
            shutil.copytree(dest, tmp)
            (tmp / main).rename(tmp / "_.main.asasm")
            try:
                tmp.rename(cached)
            except OSError:
                shutil.rmtree(tmp, ignore_errors=True)
    abc.unlink()
    return dest


CACHE_DAYS = 2


def prune_cache(root: Path, days: float = CACHE_DAYS) -> int:
    if not CACHE.exists():
        return 0
    cutoff, n = time.time() - days * 86400, 0
    for tool in CACHE.iterdir():
        for entry in (tool.iterdir() if tool.is_dir() else ()):
            try:
                if entry.stat().st_mtime < cutoff:
                    shutil.rmtree(entry, ignore_errors=True)
                    n += 1
            except OSError:
                pass
        if tool != root and tool.is_dir() and not any(tool.iterdir()):
            tool.rmdir()
    return n


def disassemble(bin_dir: Path, swf: Path, work: Path, stem: str, cache: bool = True) -> list[Path]:
    work.mkdir(parents=True, exist_ok=True)
    copy = work / f"{stem}.swf"
    shutil.copyfile(swf, copy)
    run([bin_dir / ("abcexport" + abc_roundtrip.EXE), copy])
    exe = bin_dir / ("rabcdasm" + abc_roundtrip.EXE)
    cache_root = None
    if cache and not os.environ.get("BH_NO_DISASM_CACHE"):
        cache_root = CACHE / _tool_key(exe)
        cache_root.mkdir(parents=True, exist_ok=True)
        if stem == "library":
            prune_cache(cache_root)
    abcs = sorted(work.glob(f"{stem}-*.abc"), key=lambda p: int(p.stem.rsplit("-", 1)[1]))
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(16, (os.cpu_count() or 4))) as pool:
        dirs = list(pool.map(lambda abc: _disassemble_one(exe, abc, cache_root), abcs))
    copy.unlink()
    abc_roundtrip.warm(*dirs)
    return dirs


def program(tree: Path) -> tuple[list[str], list[str]]:
    lines = read_lines(tree / f"{tree.name}.main.asasm")
    header, includes = [], []
    for line in lines:
        m = INCLUDE.match(line)
        if m:
            includes.append(m.group(1))
        elif not includes and line.strip():
            header.append(line)
    return header, includes


def script_key(path: Path) -> str:
    for line in read_lines(path):
        m = TRAIT.match(line)
        if m:
            return strip_disambiguators(f"{m.group(1)} {m.group(2)}")
    raise SpliceError(f"{path}: script has no traits")


def orphan_index(tree: Path, includes: list[str]) -> dict[str, str]:
    index = {}
    for inc in includes:
        if inc.endswith(".method.asasm"):
            for line in read_lines(tree / inc):
                m = REFID.match(line)
                if m:
                    index[m.group(2)] = inc
                    break
    return index


def method_end(lines: list[str], start: int) -> int:
    for k in range(start + 1, len(lines)):
        if lines[k].strip() == "end ; method":
            return k
    raise SpliceError(f"unterminated method at line {start + 1}")


def locate(lines: list[str], start: int, sections: list[str] | None = None) -> tuple[str, str, str]:
    head = lines[start].strip()
    if head in ("iinit", "cinit", "sinit"):
        return head, head, ""
    trait = TRAIT.match(lines[start - 1]) if start else None
    if head != "method" or not trait:
        raise SpliceError(f"line {start + 1}: not a method block ({head!r})")
    return (sections[start] if sections is not None else section_at(lines, start)), trait.group(1), trait.group(3)


def section_at(lines: list[str], start: int) -> str:
    return _sections(tuple(lines))[start]


@functools.lru_cache(maxsize=64)
def _sections(lines: tuple[str, ...]) -> list[str]:
    out, ended, opened = [], False, False
    for line in lines:
        out.append("class" if ended else ("instance" if opened else "class"))
        t = line.strip()
        if t == "end ; instance":
            ended = True
        elif t.startswith("instance "):
            opened = True
    out.append("class" if ended else ("instance" if opened else "class"))
    return out


def find_block(lines: list[str], section: str, kind: str, name: str, index: dict | None = None) -> int:
    found = (index if index is not None else block_index(tuple(lines))).get((kind, "", "") if kind in INITS else (section, kind, name), [])
    if len(found) != 1:
        raise SpliceError(f"{section} {kind} {name!r}: {len(found)} matches in the original")
    return found[0]


@functools.lru_cache(maxsize=256)
def block_index(lines: tuple[str, ...]) -> dict[tuple[str, str, str], list[int]]:
    index: dict[tuple[str, str, str], list[int]] = {}
    ended = opened = False
    for i, line in enumerate(lines):
        s = line.strip()
        if s in INITS:
            index.setdefault((s, "", ""), []).append(i)
        if s == "end ; instance":
            ended = True
        elif s.startswith("instance "):
            opened = True
        if i + 1 < len(lines) and "trait" in line:
            m = TRAIT.match(line)
            if m and lines[i + 1].strip() == "method":
                section = "instance" if not ended and opened else "class"
                index.setdefault((section, m.group(1), m.group(3)), []).append(i + 1)
    return index


PRIVATE = re.compile(r'PrivateNamespace\("(?:[^"\\]|\\.)*"(?:, "[^"]*")?\)')


def private_namespaces(lines: list[str]) -> set[str]:
    return {m.group(0) for line in lines for m in PRIVATE.finditer(line)}


def check_private(lines: list[str], allowed: set[str]) -> None:
    unknown = private_namespaces(lines) - allowed
    if unknown:
        raise SpliceError(f"transplanted code uses private namespaces the compiled code lacks: {sorted(unknown)[:3]}")


def transplant(comp: list[str], c_start: int, orig: list[str], o_start: int,
               allowed_private: set[str] = frozenset()) -> tuple[list[str], list[str], list[str]]:
    c_end, o_end = method_end(comp, c_start), method_end(orig, o_start)
    replaced = [m.group(1) for m in map(NEWFUNCTION.match, comp[c_start:c_end]) if m]
    refid = next((l for l in comp[c_start + 1:c_end] if REFID.match(l)), None)
    body = []
    for line in orig[o_start + 1:o_end]:
        if REFID.match(line):
            if refid is not None:
                body.append(refid)
            continue
        body.append(strip_disambiguators(line))
    check_private(body, allowed_private)
    closures = [m.group(1) for m in map(NEWFUNCTION.match, body) if m]
    return comp[:c_start + 1] + body + comp[c_end:], closures, replaced


OPTIONAL = re.compile(r'^(\s*)optional\s+(\w+)\((.*)\)\s*$')
NUMERIC = ("Integer", "UInteger", "Double")
INITS = ("iinit", "cinit", "sinit")


def header(lines: list[str], start: int) -> tuple[int, int]:
    end = method_end(lines, start)
    body = next((k for k in range(start + 1, end) if lines[k].strip() == "body"), end)
    return start + 1, body


def numeric_value(kind: str, value: str) -> float | None:
    if kind not in NUMERIC:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def restore_signature(comp: list[str], c_start: int, orig: list[str], o_start: int) -> tuple[list[str], list[str]]:
    kind = comp[c_start].strip()
    c_first, c_body = header(comp, c_start)
    o_first, o_body = header(orig, o_start)
    ch, oh = comp[c_first:c_body], [strip_disambiguators(l) for l in orig[o_first:o_body]]

    def fields(lines: list[str], name: str) -> list[tuple[int, str]]:
        return [(i, l.strip()) for i, l in enumerate(lines) if l.strip().split(" ", 1)[0] == name]

    if [v for _, v in fields(ch, "param")] != [v for _, v in fields(oh, "param")]:
        return comp, []
    new, changes = list(ch), []
    for (ci, cv), (_, ov) in zip(fields(ch, "optional"), fields(oh, "optional")):
        cm, om = OPTIONAL.match(ch[ci]), OPTIONAL.match("   " + ov)
        if cv == ov or not cm or not om:
            continue
        a, b = numeric_value(cm.group(2), cm.group(3)), numeric_value(om.group(2), om.group(3))
        if a is not None and a == b:
            new[ci] = f"{cm.group(1)}{ov}"
            changes.append(f"optional {cm.group(2)}({cm.group(3)}) -> {om.group(2)}({om.group(3)})")
    o_ret = fields(oh, "returns")
    if kind in INITS and not fields(ch, "returns") and o_ret and o_ret[0][1].endswith(', "void")'):
        at = max([i + 1 for i, _ in fields(new, "param") + fields(new, "refid") + fields(new, "name")] or [0])
        indent = re.match(r"\s*", new[0] if new else comp[c_start] + " ").group(0)
        new.insert(at, indent + o_ret[0][1])
        changes.append("returns * -> void")
    if not changes:
        return comp, []
    return comp[:c_first] + new + comp[c_body:], changes


def method_starts(lines: list[str]) -> list[int]:
    return [i for i, line in enumerate(lines)
            if line.strip() in INITS or (line.strip() == "method" and i and TRAIT.match(lines[i - 1]))]


def restore_signatures(bdir: Path, otree: Path) -> list[dict]:
    restored = []
    for rel in sorted(p.relative_to(bdir).as_posix() for p in bdir.rglob("*.asasm")):
        if not rel.endswith((".class.asasm", ".script.asasm")) or not (otree / rel).exists():
            continue
        lines, orig = read_lines(bdir / rel), read_lines(otree / rel)
        changed = False
        sections, oindex = _sections(tuple(lines)), block_index(tuple(orig))
        for start in reversed(method_starts(lines)):
            where = locate(lines, start, sections)
            try:
                o_start = find_block(orig, *where, index=oindex)
            except SpliceError:
                continue
            lines, changes = restore_signature(lines, start, orig, o_start)
            if changes:
                restored.append({"file": rel, "section": where[0], "kind": where[1], "name": where[2],
                                 "changes": changes})
                changed = True
        if changed:
            write_lines(bdir / rel, lines)
    return restored


def splice(args: argparse.Namespace) -> dict:
    bin_dir = Path(args.rabcdasm)
    work = Path(args.work)
    if work.exists():
        shutil.rmtree(work)
    fixups = json.loads(Path(args.fixups).read_text(encoding="utf-8"))

    with zipfile.ZipFile(args.swc) as swc:
        (work / "in").mkdir(parents=True)
        (work / "in" / "library.swf").write_bytes(swc.read("library.swf"))
    comp_dirs = disassemble(bin_dir, work / "in" / "library.swf", work / "comp", "library")
    orig_dirs = disassemble(bin_dir, Path(args.renamed_swf), work / "orig", "block")

    placement: dict[str, tuple[int, int]] = {}
    orig_programs = []
    for b, tree in enumerate(orig_dirs):
        header, includes = program(tree)
        orig_programs.append((header, includes))
        scripts = [inc for inc in includes if inc.endswith(".script.asasm")]
        for pos, inc in enumerate(scripts):
            placement[script_key(tree / inc)] = (b, pos)
    src = work / "src"
    added: list[dict] = []
    seen_keys: set[str] = set()
    blocks: list[dict] = [{"scripts": [], "methods": []} for _ in orig_dirs]
    owner: dict[str, Path] = {}
    for tree in comp_dirs:
        _, includes = program(tree)
        scripts = [inc for inc in includes if inc.endswith(".script.asasm")]
        if len(scripts) != 1:
            raise SpliceError(f"{tree.name}: expected one script, found {len(scripts)}")
        key = script_key(tree / scripts[0])
        if key in placement:
            b, pos = placement.pop(key)
        elif key in seen_keys:
            raise SpliceError(f"{tree.name}: script {key} compiled twice")
        else:
            b = max(range(len(orig_dirs)), key=lambda i: len(orig_programs[i][1]))
            pos = 10 ** 6 + len(added)
            added.append({"script": key, "block": b, "classes": script_classes(tree, includes)})
        seen_keys.add(key)
        blocks[b]["scripts"].append((pos, scripts[0]))
        blocks[b]["methods"] += [inc for inc in includes if inc.endswith(".method.asasm")]
        for f in list(tree.rglob("*.asasm")):
            rel = f.relative_to(tree).as_posix()
            if f.name == f"{tree.name}.main.asasm":
                continue
            if rel in owner:
                raise SpliceError(f"{rel} is in both {owner[rel].name} and {tree.name}")
            owner[rel] = tree
            dest = src / f"block-{b}" / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            os.replace(f, dest)
    if placement:
        raise SpliceError(f"original scripts with no compiled script: {sorted(placement)[:5]}")

    report = {"version": args.version, "methods": [], "script_inits": [], "slot_traits": [],
              "closures": [], "removed_closures": [], "renames": [], "signatures": [],
              "added_scripts": added, "added_classes": sorted({c for a in added for c in a["classes"]})}
    pending_closures: dict[int, list[str]] = {b: [] for b in range(len(orig_dirs))}
    dead_closures: dict[int, list[str]] = {b: [] for b in range(len(orig_dirs))}
    block_private = {b: set().union(*(private_namespaces(read_lines(f)) for f in (src / f"block-{b}").rglob("*.asasm")))
                     for b in range(len(blocks))}
    for b in range(len(blocks)):
        bdir = src / f"block-{b}"
        otree = orig_dirs[b]
        for rel in sorted(p.relative_to(bdir).as_posix() for p in bdir.rglob("*.asasm")):
            lines = read_lines(bdir / rel)
            changed = False
            while True:
                hit = next(((i, m.group(1)) for i, m in enumerate(map(STUB.match, lines)) if m), None)
                if hit is None:
                    break
                i, label = hit
                start = max(j for j in range(i) if lines[j].strip() in ("method", "iinit", "cinit", "sinit"))
                where = locate(lines, start)
                if not (otree / rel).exists():
                    raise SpliceError(f"{rel}: no original file for stub {label}")
                orig = read_lines(otree / rel)
                lines, closures, replaced = transplant(lines, start, orig, find_block(orig, *where),
                                                      block_private[b])
                pending_closures[b] += closures
                dead_closures[b] += replaced
                report["methods"].append({"block": b, "file": rel, "stub": label, "section": where[0],
                                          "kind": where[1], "name": where[2], "closures": len(closures)})
                changed = True
            if rel.endswith(".script.asasm") and (otree / rel).exists():
                orig = read_lines(otree / rel)
                if needs_script_splice(rel, lines, orig, fixups):
                    start = find_block(lines, "sinit", "sinit", "")
                    lines, closures, replaced = transplant(
                        lines, start, orig, find_block(orig, "sinit", "sinit", ""), block_private[b])
                    pending_closures[b] += closures
                    dead_closures[b] += replaced
                    report["script_inits"].append({"block": b, "file": rel, "closures": len(closures)})
                    report["slot_traits"] += restore_slots(bdir, otree, rel, lines)
                    changed = True
            if changed:
                write_lines(bdir / rel, lines)

    for b in range(len(blocks)):
        report["signatures"] += restore_signatures(src / f"block-{b}", orig_dirs[b])

    settle_closures(src, blocks, orig_dirs, orig_programs, dead_closures, pending_closures, block_private, report)

    for item in fixups.get("renames", []):
        stem = Path(item["file"]).with_suffix("").as_posix()
        hits = 0
        for b in range(len(blocks)):
            for f in (src / f"block-{b}").glob(f"{stem}.*.asasm"):
                text = f.read_text(encoding="utf-8", errors="surrogateescape")
                if f'/{item["member"]}"' in text or any(
                        m and m.group(3) == item["member"] for m in map(TRAIT.match, text.split("\n"))):
                    raise SpliceError(f"{f}: {item['member']} already used; cannot rename back")
                n = text.count(item["source_name"])
                if n:
                    f.write_text(text.replace(item["source_name"], item["member"]),
                                 encoding="utf-8", errors="surrogateescape")
                    hits += n
        if not hits:
            raise SpliceError(f"rename {item['source_name']} not found in the compiled {stem}")
        report["renames"].append({"from": item["source_name"], "to": item["member"], "occurrences": hits})

    expected = {(s["class"], s["method"]) for s in fixups["splices"] if s["method"] != "<script init>"}
    done = {tuple(m["stub"].rsplit(".", 1)) for m in report["methods"]}
    if expected != done:
        raise SpliceError(f"stubs spliced {sorted(done ^ expected)} differ from as3-fixups.json")
    dropped = {s["file"] for s in fixups["splices"] if s["method"] == "<script init>"}
    spliced_inits = {Path(s["file"]).with_suffix("").with_suffix("").as_posix() + ".as" for s in report["script_inits"]}
    if not dropped <= spliced_inits:
        raise SpliceError(f"dropped script inits not spliced: {sorted(dropped - spliced_inits)}")

    out = assemble(args, src, blocks, orig_programs)

    if not args.compiled_only:
        keep_original(args, src, blocks, orig_dirs, orig_programs, block_private, out, report)
        out = assemble(args, src, blocks, orig_programs)
    report["out"] = str(out)
    report["sha256"] = abc_roundtrip.sha256(out)
    report["size"] = out.stat().st_size
    return report


def assemble(args: argparse.Namespace, src: Path, blocks: list[dict], orig_programs: list) -> Path:
    bin_dir = Path(args.rabcdasm)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.renamed_swf, out)
    for b, info in enumerate(blocks):
        header = orig_programs[b][0]
        includes = [s for _, s in sorted(info["scripts"])] + info["methods"]
        main = src / f"block-{b}" / f"block-{b}.main.asasm"
        write_lines(main, header + [""] + [f' #include "{inc}"' for inc in includes] + ["", "end ; program", ""])
    abc_roundtrip.warm(src)

    def one(b: int) -> bytes:
        main = src / f"block-{b}" / f"block-{b}.main.asasm"
        run([bin_dir / ("rabcasm" + abc_roundtrip.EXE), main])
        data = main.with_suffix(".abc").read_bytes()
        main.with_suffix(".abc").unlink()
        return data
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(16, len(blocks) or 1)) as pool:
        abcs = dict(enumerate(pool.map(one, range(len(blocks)))))
    abc_roundtrip.replace_blocks(out, abcs)
    return out


QNAME_PARTS = re.compile(r'QName\((\w+)\("((?:[^"\\]|\\.)*)"(?:, "#\d+")?\), "((?:[^"\\]|\\.)*)"\)')
NS_KIND = {"Namespace": "ns", "PackageNamespace": "pkg", "PackageInternalNs": "internal",
           "ProtectedNamespace": "protected", "ExplicitNamespace": "explicit",
           "StaticProtectedNs": "staticprotected", "PrivateNamespace": "private"}
SLOT_LINE = re.compile(r'^(\s*)trait (slot|const) (QName\(\w+\("(?:[^"\\]|\\.)*"(?:, "#\d+")?\), "(?:[^"\\]|\\.)*"\)).* end\s*$')


def key_name(qname: str, ns_aliases: dict[str, str]) -> str:
    m = QNAME_PARTS.match(qname)
    if not m:
        return qname
    kind, uri, local = NS_KIND.get(m.group(1), m.group(1)), m.group(2), m.group(3)
    if kind in ("pkg", "private", "protected", "staticprotected", "internal"):
        return local
    if kind == "ns":
        uri = ns_aliases.get(uri, uri)
    return f"{kind}:{uri}::{local}"


def class_of(qname: str) -> str:
    m = QNAME_PARTS.match(qname)
    return f"{m.group(2)}.{m.group(3)}" if m and m.group(2) else (m.group(3) if m else qname)


def block_keys(rel: str, lines: list[str], ns_aliases: dict[str, str]) -> dict[int, tuple[str, tuple[str, str, str]]]:
    out = {}
    if rel.endswith(".class.asasm"):
        inst = next((l for l in lines if l.strip().startswith("instance QName(")), None)
        if inst is None:
            return out
        cls = class_of(inst.strip()[len("instance "):])
        local = cls.rsplit(".", 1)[-1]
        for start in method_starts(lines):
            section, kind, name = locate(lines, start)
            if kind == "iinit":
                out[start] = (f"{cls}/iinit", ("i", "iinit", local))
            elif kind == "cinit":
                out[start] = (f"{cls}/cinit", ("", "rest", ""))
            else:
                trait = TRAIT.match(lines[start - 1])
                side = "i" if section == "instance" else "s"
                out[start] = (f"{cls}/{side}/{kind} {key_name(trait.group(2), ns_aliases)}", (side, kind, name))
    elif rel.endswith(".script.asasm"):
        first = next((TRAIT.match(l) for l in lines if TRAIT.match(l)), None)
        if first is None:
            return out
        head = class_of(first.group(2)) if first.group(1) == "class" else key_name(first.group(2), ns_aliases)
        for start in method_starts(lines):
            section, kind, name = locate(lines, start)
            if kind == "sinit":
                out[start] = (f"script {head}/init", ("", "rest", ""))
            elif section != "instance":
                trait = TRAIT.match(lines[start - 1])
                out[start] = (f"script {head}/{kind} {key_name(trait.group(2), ns_aliases)}", ("s", kind, name))
    return out


def is_edited(as3_rel: str, function: tuple[str, str, str], edits: dict[str, dict]) -> bool:
    e = edits.get(as3_rel)
    if e is None:
        return False
    if e.get("new") or (function[1] == "rest" and e["rest"]):
        return True
    return "/".join(function) in e["functions"]


def restore_fields(lines: list[str], orig: list[str]) -> tuple[list[str], int]:
    def sections(ls: list[str]) -> dict[tuple[str, str], int]:
        inside = set()
        for start in method_starts(ls):
            inside.update(range(start, method_end(ls, start) + 1))
        found, section = {}, "instance"
        for i, line in enumerate(ls):
            if line.strip() == "end ; instance":
                section = "class"
            m = SLOT_LINE.match(line) if i not in inside else None
            if m:
                found[(section, strip_disambiguators(m.group(3)))] = i
        return found

    comp_at, orig_at = sections(lines), sections(orig)
    new, n = list(lines), 0
    for key, i in comp_at.items():
        if key in orig_at:
            m = SLOT_LINE.match(lines[i])
            line = re.sub(r" slotid \d+", "", strip_disambiguators(orig[orig_at[key]].strip()))
            if line != lines[i].strip():
                new[i] = m.group(1) + line
                n += 1
    return new, n


@functools.lru_cache(maxsize=4)
def original_methods(renamed_swf: str, map_path: str) -> tuple[dict[str, str], dict[str, dict]]:
    ns_aliases = compare_methods.load_class_names(Path(map_path))
    blocks = compare_methods.swf_blocks(Path(renamed_swf))
    compare_methods.enable_canonical_cache()
    compare_methods.prepare(blocks, ns_aliases)
    return ns_aliases, compare_methods.collect(blocks, ns_aliases=ns_aliases, cache=True)


def keep_original(args: argparse.Namespace, src: Path, blocks: list[dict], orig_dirs: list[Path], orig_programs: list,
                  block_private: dict[int, set[str]], built: Path, report: dict) -> None:
    ns_aliases, original = original_methods(str(args.renamed_swf), str(args.map))
    result = compare_methods.compare(original, compare_methods.collect(compare_methods.swf_blocks(built),
                                                                          ns_aliases=ns_aliases))
    differs: set[str] = set()
    for key, m in result["methods"].items():
        if m["status"] not in ("equal", "equivalent"):
            differs.add(re.sub(r"(/fn\d+)+$", "", key))
    manifest = Path(args.pristine)
    edits = as3_edits.edits(Path(args.as3_tree), json.loads(manifest.read_text(encoding="utf-8")), cache=True) \
        if manifest.exists() else None
    report["edit_detection"] = "on" if edits is not None else f"off: {manifest} missing"
    edits = edits or {}
    report["kept_original"], report["edited_compiled"], report["fields_restored"] = [], [], 0
    dead = {b: [] for b in range(len(blocks))}
    pending = {b: [] for b in range(len(blocks))}
    mapped: set[str] = set()
    for b in range(len(blocks)):
        bdir, otree = src / f"block-{b}", orig_dirs[b]
        rels = [rel for rel in sorted(p.relative_to(bdir).as_posix() for p in bdir.rglob("*.asasm"))
                if rel.endswith((".class.asasm", ".script.asasm")) and (otree / rel).exists()]
        for part in _keep_parts(bdir, otree, rels, differs, edits, ns_aliases, block_private[b]):
            mapped.update(part["mapped"])
            report["edited_compiled"] += part["edited"]
            report["kept_original"] += part["kept"]
            report["fields_restored"] += part["fields"]
            pending[b] += part["closures"]
            dead[b] += part["replaced"]
    report["unmapped_differing"] = sorted(differs - mapped)
    settle_closures(src, blocks, orig_dirs, orig_programs, dead, pending, block_private, report)


KEEP_PARALLEL_MIN = 300


def _keep_parts(bdir: Path, otree: Path, rels: list[str], differs: set[str], edits: dict, ns_aliases: dict,
                private: set[str]) -> list[dict]:
    args = (str(bdir), str(otree), differs, edits, ns_aliases, private)
    if len(rels) >= KEEP_PARALLEL_MIN and not os.environ.get("BH_NO_PARALLEL_SPLICE"):
        n = min(8, os.cpu_count() or 1)
        step = -(-len(rels) // (n * 4))
        chunks = [rels[i:i + step] for i in range(0, len(rels), step)]
        with concurrent.futures.ProcessPoolExecutor(n) as pool:
            return list(pool.map(_keep_chunk, *zip(*[(*args, c) for c in chunks])))
    return [_keep_chunk(*args, rels)]


def _keep_chunk(bdir: str, otree: str, differs: set[str], edits: dict, ns_aliases: dict, private: set[str],
                rels: list[str]) -> dict:
    out = {"mapped": [], "edited": [], "kept": [], "fields": 0, "closures": [], "replaced": []}
    for rel in rels:
        as3_rel = rel.rsplit(".", 2)[0] + ".as"
        lines, orig = read_lines(Path(bdir) / rel), read_lines(Path(otree) / rel)
        changed = False
        sections, oindex = _sections(tuple(lines)), block_index(tuple(orig))
        for start, (key, function) in sorted(block_keys(rel, lines, ns_aliases).items(), reverse=True):
            out["mapped"].append(key)
            if key not in differs:
                continue
            if is_edited(as3_rel, function, edits):
                out["edited"].append(key)
                continue
            try:
                o_start = find_block(orig, *locate(lines, start, sections), index=oindex)
            except SpliceError:
                continue
            lines, closures, replaced = transplant(lines, start, orig, o_start, private)
            out["closures"] += closures
            out["replaced"] += replaced
            out["kept"].append(key)
            changed = True
        if not is_edited(as3_rel, ("", "rest", ""), edits):
            lines, n = restore_fields(lines, orig)
            out["fields"] += n
            changed = changed or n > 0
        if changed:
            write_lines(Path(bdir) / rel, lines)
    return out


def settle_closures(src: Path, blocks: list[dict], orig_dirs: list[Path], orig_programs: list,
                    dead_closures: dict[int, list[str]], pending_closures: dict[int, list[str]],
                    block_private: dict[int, set[str]], report: dict) -> None:
    for b, refids in dead_closures.items():
        bdir = src / f"block-{b}"
        index = orphan_index(bdir, blocks[b]["methods"])
        while refids:
            rel = index.pop(refids.pop(), None)
            if rel is None:
                raise SpliceError(f"block {b}: compiled closure of a replaced method not found")
            lines = read_lines(bdir / rel)
            refids += [m.group(1) for m in map(NEWFUNCTION.match, lines) if m]
            (bdir / rel).unlink()
            blocks[b]["methods"].remove(rel)
            report["removed_closures"].append({"block": b, "file": rel})

    for b, refids in pending_closures.items():
        otree = orig_dirs[b]
        index = orphan_index(otree, orig_programs[b][1])
        seen: set[str] = set()
        while refids:
            refid = refids.pop()
            if refid in seen:
                continue
            seen.add(refid)
            if refid not in index:
                raise SpliceError(f"block {b}: closure {refid!r} not found in the original")
            rel = index[refid]
            dest = src / f"block-{b}" / rel
            if dest.exists():
                raise SpliceError(f"block {b}: closure file {rel} clashes with a compiled file")
            lines = [strip_disambiguators(l) for l in read_lines(otree / rel)]
            check_private(lines, block_private[b])
            write_lines(dest, lines)
            blocks[b]["methods"].append(rel)
            report["closures"].append({"block": b, "refid": refid, "file": rel})
            refids += [m.group(1) for m in map(NEWFUNCTION.match, lines) if m]
    for item in report["closures"]:
        if sum(1 for c in report["closures"] if c["refid"] == item["refid"]) > 1:
            raise SpliceError(f"closure refid {item['refid']} transplanted twice")


def script_classes(tree: Path, includes: list[str]) -> list[str]:
    names = []
    for path in sorted(tree.rglob("*.class.asasm")):
        for line in read_lines(path):
            if line.strip().startswith("instance QName("):
                names.append(class_of(line.strip()[len("instance "):]))
                break
    return names


def key_class(key: str) -> str:
    head = key[len("script "):] if key.startswith("script ") else key
    return head.split("/", 1)[0]


def needs_script_splice(rel: str, comp: list[str], orig: list[str], fixups: dict) -> bool:
    source = Path(rel).with_suffix("").with_suffix("").as_posix() + ".as"
    if any(s["method"] == "<script init>" and s["file"] == source for s in fixups["splices"]):
        return True

    def closures(lines: list[str]) -> int:
        start = find_block(lines, "sinit", "sinit", "")
        return sum(1 for l in lines[start:method_end(lines, start)] if NEWFUNCTION.match(l))

    return closures(orig) > closures(comp)


def restore_slots(bdir: Path, otree: Path, script_rel: str, script_lines: list[str]) -> list[dict]:
    restored = []
    for inc in (INCLUDE.match(l) for l in script_lines):
        if not inc:
            continue
        rel = (Path(script_rel).parent / inc.group(1)).as_posix()
        comp, orig = read_lines(bdir / rel), read_lines(otree / rel)
        slots = {}
        for line in orig:
            m = TRAIT.match(line)
            if m and m.group(1) in ("slot", "const") and locate_trait_section(orig, line) == "class":
                slots[m.group(3)] = strip_disambiguators(line)
        i = 0
        while i < len(comp):
            m = TRAIT.match(comp[i])
            if m and m.group(1) == "method" and m.group(3) in slots and locate_trait_section(comp, comp[i]) == "class":
                end = next(k for k in range(i + 1, len(comp)) if comp[k].strip() == "end ; trait")
                comp[i:end + 1] = [slots[m.group(3)]]
                restored.append({"file": rel, "name": m.group(3)})
            i += 1
        write_lines(bdir / rel, comp)
    return restored


def locate_trait_section(lines: list[str], line: str) -> str:
    i = lines.index(line)
    before = [l.strip() for l in lines[:i]]
    return "class" if "end ; instance" in before else "instance"


def verify(args: argparse.Namespace, report: dict) -> list[str]:
    problems = []
    bin_dir = Path(args.rabcdasm)
    work = Path(args.work)
    back = disassemble(bin_dir, Path(report["out"]), work / "back", "block", cache=False)
    for b, tree in enumerate(back):
        a, c = abc_roundtrip.normalized_pair(work / "src" / f"block-{b}", tree)
        if a != c:
            sa, sc = set(a), set(c)
            problems.append(f"block-{b}: {len(sa - sc)} source-only / {len(sc - sa)} built-only lines, "
                            f"e.g. {sorted(sa - sc)[:2]} / {sorted(sc - sa)[:2]}")
    report["roundtrip"] = "OK" if not problems else "FAILED"

    ns_aliases, original = original_methods(str(args.renamed_swf), str(args.map))
    aliases = compare_methods.load_aliases(Path(args.fixups))
    before = compare_methods.compare(original, compare_methods.collect(
        compare_methods.swf_blocks(Path(args.swc)), aliases, ns_aliases, cache=True),
        compare_methods.load_dropped(Path(args.fixups)))
    after = compare_methods.compare(original, compare_methods.collect(
        compare_methods.swf_blocks(Path(report["out"])), ns_aliases=ns_aliases))
    spliced = sorted(k for k, m in before["methods"].items() if m["status"] == "splice")
    missing_before = {k for k, m in before["methods"].items() if m["status"] == "missing"}
    unequal = [k for k in spliced if after["methods"].get(k, {}).get("status") != "equal"]
    report["compare"] = {
        "spliced_methods": len(spliced),
        "spliced_equal": len(spliced) - len(unequal),
        "missing_now_equal": sorted(k for k in missing_before if after["methods"].get(k, {}).get("status") == "equal"),
        "before": before["totals"], "after": after["totals"],
        "regressed": sorted(k for k, m in after["methods"].items()
                            if m["status"] != "equal" and before["methods"].get(k, {}).get("status") == "equal"),
    }
    for k in unequal:
        problems.append(f"spliced method {k} is {after['methods'].get(k, {}).get('status')}: "
                        f"{after['methods'].get(k, {}).get('cause')}")
    if "kept_original" in report:
        edited = set(report["edited_compiled"])
        added = set(report.get("added_classes", []))
        left = sorted(k for k, m in after["methods"].items() if m["status"] not in ("equal", "equivalent")
                      and re.sub(r"(/fn\d+)+$", "", k) not in edited
                      and not (m["status"] == "extra" and key_class(k) in added))
        report["compare"]["differing_not_edited"] = left
        for k in left[:20]:
            problems.append(f"{k} still differs ({after['methods'][k]['status']}: {after['methods'][k]['cause']}) "
                            "and was not edited")
        if len(left) > 20:
            problems.append(f"... {len(left) - 20} more methods still differ and were not edited")
    if after["totals"].get("splice"):
        problems.append(f"{after['totals']['splice']} BH_SPLICE stubs left")
    for k in report["compare"]["regressed"]:
        if k in set(report.get("edited_compiled", [])):
            continue
        problems.append(f"{k} was equal before splicing and is not now")
    return problems


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--version", default="10.11")
    p.add_argument("--swc")
    p.add_argument("--renamed-swf", default=None,
                   help="the SWF the export came from (default build/as3/aliased.swf, else build/as3/renamed.swf)")
    p.add_argument("--fixups")
    p.add_argument("--map")
    p.add_argument("--out")
    p.add_argument("--work")
    p.add_argument("--report")
    p.add_argument("--rabcdasm", default=str(abc_roundtrip.LOCAL_RABCDASM))
    p.add_argument("--no-verify", action="store_true")
    p.add_argument("--compiled-only", action="store_true",
                   help="skip step 6: keep the compiled code even where it differs from the original")
    p.add_argument("--pristine", help="as3_fixups.py fingerprint (default build/as3/<ver>/as3-pristine.json)")
    p.add_argument("--as3-tree", help="the AS3 tree that was compiled (default src/as3/<ver>/scripts)")
    args = p.parse_args(argv)
    out_dir = ROOT / "build/as3" / args.version
    args.swc = args.swc or str(out_dir / "game.swc")
    args.fixups = args.fixups or str(out_dir / "as3-fixups.json")
    args.map = args.map or str(ROOT / "client/symbols" / f"{args.version}.json")
    args.out = args.out or str(out_dir / "BrawlhallaAir.swf")
    args.work = args.work or str(out_dir / "splice")
    args.renamed_swf = args.renamed_swf or str(compare_methods.base_swf(args.version))
    args.pristine = args.pristine or str(out_dir / "as3-pristine.json")
    args.as3_tree = args.as3_tree or str(ROOT / "src/as3" / args.version / "scripts")
    report_path = Path(args.report or out_dir / "splice.json")
    for path in (args.swc, args.renamed_swf, args.fixups):
        if not Path(path).exists():
            print(f"missing {path}: run tools/export_as3.py and tools/compile_as3.py first", file=sys.stderr)
            return 2
    try:
        report = splice(args)
        problems = [] if args.no_verify else verify(args, report)
    except SpliceError as e:
        print(f"splice FAILED: {e}", file=sys.stderr)
        return 1
    report["problems"] = problems
    report_path.write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    print(f"{len(report['methods'])} stubs, {len(report['script_inits'])} script inits, "
          f"{len(report['closures'])} closures, {len(report['slot_traits'])} slot traits and "
          f"{len(report['renames'])} renames spliced -> {report['out']} ({report['size']} bytes)")
    print(f"{len(report['signatures'])} signatures restored: "
          + ", ".join(f"{n} {k}" for k, n in sorted(Counter(
              re.sub(r"\(.*?\)", "", c) for s in report["signatures"] for c in s["changes"]).items())))
    if "compare" in report:
        c = report["compare"]
        print(f"round trip {report['roundtrip']}; spliced methods equal {c['spliced_equal']}/{c['spliced_methods']}; "
              f"after: " + ", ".join(f"{s} {c['after'].get(s, 0)}" for s in
                                     ("equal", "equivalent", "splice", "signature", "code", "missing", "extra")))
    if "kept_original" in report:
        print(f"{len(report['kept_original'])} methods kept as original bytecode, "
              f"{len(report['edited_compiled'])} edited methods compiled, "
              f"{report['fields_restored']} field declarations restored; edit detection {report['edit_detection']}")
    for line in problems:
        print("  " + line, file=sys.stderr)
    print("FAILED" if problems else "OK")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
