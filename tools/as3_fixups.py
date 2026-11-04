"""make a fresh FFDec AS3 export compilable, without committing decompiled code.

    python tools/as3_fixups.py --src <export>/scripts [--out src/as3/<ver>/scripts]
                               [--renamed-swf build/as3/renamed.swf]

the fixes are rules, not per-file patches, so they apply to any export of any version:

- bytecode splice: a method whose FFDec body still holds a ``§§`` pseudo-op is code AS3 cannot express. its body
  becomes a stub that throws ``BH_SPLICE <Class>.<method>``, with the FFDec body kept underneath as ``//``
  comments; tools/splice_as3.py puts the original method body back. FFDec's rendering of an unusual script
  initializer (the ``§§newclass`` lines after the package block) is dropped and listed as a script splice. a
  constructor with more than one ``super(...)`` is spliced the same way (AS3 allows a single call); its stub
  keeps the first ``super(...)`` so it compiles.
- member/type clash: a class member named like a top-level class the file uses as a type hides that type inside
  the class body, and AS3 cannot qualify a top-level name. the member is renamed ``<name>_bhsrc`` in source and
  listed for the post-compile rename back.

writes the fixed tree (default ``src/as3/<ver>/scripts``) and ``build/as3/<ver>/as3-fixups.json``: every splice
and rename, with the original ABC block, class index and name when ``--renamed-swf`` is given.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
if __package__:
    from . import as3_edits, name_map
else:
    import as3_edits
    import name_map

PSEUDO = "§§"
SPLICE_TAG = "BH_SPLICE"
RENAME_SUFFIX = "_bhsrc"
MEMBER = re.compile(
    r"^      (?:(?:public|private|protected|internal|override|static|final|native|[\w$]+::?)\s+)*"
    r"function\s+(?:(?P<acc>get|set)\s+)?(?P<name>[\w$]+)\s*\((?P<params>.*)\)\s*(?::\s*(?P<ret>[\w$.<>*]+))?\s*$"
)
STATIC_MEMBER = re.compile(
    r"^      (?:(?:public|private|protected|internal|override|final|[\w$]+::?)\s+)*static\s+"
    r"(?:(?:public|private|protected|internal|override|final)\s+)*"
    r"(?P<kind>function|var|const)\s+(?:(?:get|set)\s+)?(?P<name>[\w$]+)"
)
CLASS_DECL = re.compile(r"^   (?:[\w$]+\s+)*(?:class|interface)\s+(?P<name>[\w$]+)")
PACKAGE = re.compile(r"^package\s*(?P<name>[\w$.]*)")


def class_name(lines: list[str], rel: Path) -> str:
    package = next((m["name"] for m in map(PACKAGE.match, lines) if m), "")
    name = next((m["name"] for m in map(CLASS_DECL.match, lines) if m), rel.stem)
    return f"{package}.{name}" if package else name


def find_body(lines: list[str], start: int) -> tuple[int, int] | None:
    if start + 1 >= len(lines) or lines[start + 1].rstrip() != "      {":
        return None
    for i in range(start + 2, len(lines)):
        if lines[i].rstrip() == "      }":
            return start + 1, i
    return None


SUPER_CALL = re.compile(r"^\s*super\(.*\);\s*$")


def splice_methods(lines: list[str], cls: str) -> tuple[list[str], list[dict]]:
    out, splices, i = [], [], 0
    while i < len(lines):
        match = MEMBER.match(lines[i])
        body = find_body(lines, i) if match else None
        supers = [line for line in lines[body[0]:body[1]] if SUPER_CALL.match(line)] if body else []
        constructor = bool(match) and match["name"] == cls.rsplit(".", 1)[-1] and len(supers) > 1
        if body and (constructor or any(PSEUDO in line for line in lines[body[0]:body[1]])):
            opened, closed = body
            name = match["name"] if not match["acc"] else f"{match['acc']} {match['name']}"
            label = f"{cls}.{name}"
            splices.append({"class": cls, "method": name, "line": i + 1,
                            "pseudo_ops": sum(line.count(PSEUDO) for line in lines[opened:closed])}
                           | ({"super_calls": len(supers)} if constructor else {}))
            out += [lines[i], lines[opened]] + (["         " + supers[0].strip()] if constructor else []) + [
                    f'         throw new Error("{SPLICE_TAG} {label}");',
                    "         // FFDec body (pseudo-ops; replaced by the original bytecode in 1.3):"]
            out += ["         // " + line.strip() for line in lines[opened + 1:closed] if line.strip()]
            out.append(lines[closed])
            i = closed + 1
            continue
        out.append(lines[i])
        i += 1
    return out, splices


def drop_script_init(lines: list[str], cls: str) -> tuple[list[str], list[dict]]:
    end = max((i for i, line in enumerate(lines) if line.rstrip() == "}"), default=-1)
    tail = lines[end + 1:]
    if not any(PSEUDO in line for line in tail):
        return lines, []
    kept = [line for line in tail if not re.match(r"^var _temp_\d+:\*\s*=", line) and PSEUDO not in line]
    dropped = len(tail) - len(kept)
    return lines[:end + 1] + kept, [{"class": cls, "method": "<script init>", "line": end + 2,
                                     "pseudo_ops": sum(line.count(PSEUDO) for line in tail),
                                     "dropped_lines": dropped}]


def rename_clashes(lines: list[str], cls: str, top_level: set[str]) -> tuple[list[str], list[dict]]:
    renames = []
    for i, line in enumerate(lines):
        match = STATIC_MEMBER.match(line) or MEMBER.match(line)
        if not match or match["name"] not in top_level or match["name"] == cls.rsplit(".", 1)[-1]:
            continue
        name = match["name"]
        uses = re.compile(rf"(?::\s*{re.escape(name)}\b|\bnew\s+{re.escape(name)}\b|\bas\s+{re.escape(name)}\b|\bis\s+{re.escape(name)}\b)")
        if not any(uses.search(other) for other in lines):
            continue
        new = name + RENAME_SUFFIX
        lines[i] = re.sub(rf"\b(function\s+(?:(?:get|set)\s+)?|var\s+|const\s+){re.escape(name)}\b", rf"\g<1>{new}", line, count=1)
        member_ref = re.compile(rf"(?<=\.){re.escape(name)}(?=\s*\()")
        for j, other in enumerate(lines):
            if j != i:
                lines[j] = member_ref.sub(new, other)
        renames.append({"class": cls, "member": name, "source_name": new, "line": i + 1})
    return lines, renames


def external_refs(tree: Path, renames: list[dict]) -> list[dict]:
    found = []
    for item in renames:
        short = item["class"].rsplit(".", 1)[-1]
        pattern = re.compile(rf"\b{re.escape(short)}\.{re.escape(item['member'])}\b")
        for path in sorted(tree.rglob("*.as")):
            text = path.read_text(encoding="utf-8", errors="replace")
            if pattern.search(text):
                found.append({**item, "file": path.relative_to(tree).as_posix()})
    return found


def original_names(renamed_swf: Path, original_swf: Path) -> dict[str, dict]:
    result = {}
    renamed, original = name_map.abc_tags(renamed_swf.read_bytes()), name_map.abc_tags(original_swf.read_bytes())
    if len(renamed) != len(original):
        raise ValueError(f"ABC block count differs: {len(renamed)} vs {len(original)}")
    for block_index, (new_tag, old_tag) in enumerate(zip(renamed, original)):
        new_abc, old_abc = name_map.parse_abc(new_tag["abc"]), name_map.parse_abc(old_tag["abc"])
        new_block, old_block = name_map.Block(new_abc), name_map.Block(old_abc)
        if len(new_abc["instances"]) != len(old_abc["instances"]):
            raise ValueError(f"block {block_index}: class count differs")
        for i, (new_inst, old_inst) in enumerate(zip(new_abc["instances"], old_abc["instances"])):
            name = new_block.qualified(new_inst["name"]).replace("::", ".")
            result[name] = {"block": block_index, "class_index": i,
                            "original": old_block.qualified(old_inst["name"])}
    return result


def fix_tree(src: Path, out: Path) -> dict:
    if not src.is_dir():
        raise FileNotFoundError(f"no FFDec export at {src}; run the FFDec rename and export first (docs/as3-compile.md)")
    if out.resolve() == src.resolve():
        raise ValueError("--out must differ from --src")
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(src, out)
    top_level = {p.stem for p in out.glob("*.as")}
    splices, renames = [], []
    for path in sorted(out.rglob("*.as")):
        text = path.read_text(encoding="utf-8")
        lines = text.split("\n")
        rel = path.relative_to(out)
        cls = class_name(lines, rel)
        changed = False
        if PSEUDO in text or len(re.findall(r"(?m)^\s*super\(", text)) > 1:
            lines, found = splice_methods(lines, cls)
            lines, init = drop_script_init(lines, cls)
            for item in found + init:
                item["file"] = rel.as_posix()
            splices += found + init
            changed = bool(found or init)
        before = list(lines)
        lines, clashes = rename_clashes(lines, cls, top_level)
        for item in clashes:
            item["file"] = rel.as_posix()
        renames += clashes
        if changed or lines != before:
            path.write_text("\n".join(lines), encoding="utf-8")
    left = sorted(p.relative_to(out).as_posix() for p in out.rglob("*.as")
                  if PSEUDO in "\n".join(l for l in p.read_text(encoding="utf-8").split("\n")
                                         if not l.lstrip().startswith("//")))
    return {"source": str(src), "out": str(out), "splices": splices, "renames": renames,
            "external_rename_refs": external_refs(out, renames), "unresolved_files": left}


def attach_originals(report: dict, names: dict[str, dict]) -> None:
    for item in report["splices"] + report["renames"]:
        if item["class"] in names:
            item.update(names[item["class"]])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--src", type=Path, required=True, help="FFDec export scripts folder")
    parser.add_argument("--version", default=None)
    parser.add_argument("--out", type=Path, default=None, help="fixed tree (default src/as3/<ver>/scripts)")
    parser.add_argument("--report", type=Path, default=None)
    parser.add_argument("--renamed-swf", type=Path, default=None,
                        help="the SWF the export came from, to record original class names")
    parser.add_argument("--original-swf", type=Path, default=None)
    args = parser.parse_args(argv)
    version = args.version or name_map.newest_version()
    out = args.out or ROOT / "src" / "as3" / version / "scripts"
    try:
        report = fix_tree(args.src.resolve(), out.resolve())
    except FileNotFoundError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    report["version"] = version
    if args.renamed_swf:
        original = args.original_swf or ROOT / "versions" / version / "BrawlhallaAir.swf"
        attach_originals(report, original_names(args.renamed_swf, original))
    path = args.report or ROOT / "build" / "as3" / version / "as3-fixups.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    pristine = path.with_name("as3-pristine.json")
    pristine.write_text(json.dumps(as3_edits.fingerprint(out), indent=0) + "\n", encoding="utf-8")
    files = len({s["file"] for s in report["splices"]})
    print(f"{len(report['splices'])} splices in {files} files, {len(report['renames'])} renames -> {out}")
    for item in report["external_rename_refs"]:
        print(f"warning: {item['file']} uses renamed {item['class']}.{item['member']}", file=sys.stderr)
    if report["unresolved_files"]:
        print("unresolved pseudo-ops in: " + ", ".join(report["unresolved_files"]), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
