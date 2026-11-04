"""build the machine-readable name map between the original SWF and FFDec's renamed SWF.

FFDec's `-renameInvalidIdentifiers typeNumber` keeps the constant pool order and every ABC table index (and appends a
few strings for names it had to split), so the two SWFs are matched index by index:

  - classes: instance_info index → original and renamed QName;
  - members: every trait of every instance, class and script;
  - methods: every method_info index, with its owner and role;
  - strings/namespaces: every constant-pool entry whose text changed.

usage:
  python tools/symbol_map.py build --original versions/10.11/BrawlhallaAir.swf \
      --renamed build/ffdec/renamed.swf --out client/symbols/10.11.json
  python tools/symbol_map.py check client/symbols/10.11.json [--as3 src/as3/10.11]

`check` validates the map's coverage (every class and method_info index of every ABC block) and, with --as3, that
every class has an exported `.as` file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parent))

from abc_reader import Abc, Trait, parse_abc, swf_abc_blocks

SCHEMA_VERSION = 2


class MapError(Exception):
    pass


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _ns_of(abc: Abc, mn_index: int) -> str | None:
    mn = abc.multinames[mn_index] if 0 < mn_index < len(abc.multinames) else None
    return abc.ns_name(mn.ns) if mn is not None and mn.ns else None


def _check_same_shape(block: str, a: Abc, b: Abc) -> None:
    shape = lambda x: (len(x.namespaces), len(x.ns_sets), len(x.multinames), x.method_count,
                       len(x.instances), len(x.scripts), len(x.body_methods))
    if shape(a) != shape(b):
        raise MapError(f"block {block!r}: renamed ABC tables differ in size {shape(a)} vs {shape(b)}")
    if len(b.strings) < len(a.strings):
        raise MapError(f"block {block!r}: renamed string pool is shorter")
    for i, (x, y) in enumerate(zip(a.multinames, b.multinames)):
        if x is not None and (x.kind != y.kind or x.ns != y.ns or x.ns_set != y.ns_set):
            raise MapError(f"block {block!r}: multiname {i} changed kind or namespace")


CLASS_COLUMNS = ["class_index", "original", "renamed", "super", "private", "interface", "iinit", "cinit"]
MEMBER_COLUMNS = ["scope", "owner", "kind", "original", "renamed", "ns", "ref"]
METHOD_COLUMNS = ["method", "role", "scope", "owner", "original", "renamed", "body"]
STRING_COLUMNS = ["index", "original", "renamed"]
TABLES = {"classes": CLASS_COLUMNS, "members": MEMBER_COLUMNS, "methods": METHOD_COLUMNS,
          "strings": STRING_COLUMNS, "namespaces": STRING_COLUMNS}


def _members(abc: Abc, ren: Abc, scope: str, owner: int, traits: list[Trait], ren_traits: list[Trait],
             members: list, methods: dict) -> None:
    for t, rt in zip(traits, ren_traits):
        original, renamed = abc.mn_name(t.name), ren.mn_name(rt.name)
        if t.method >= 0:
            ref = t.method
            methods[t.method] = [t.kind_name, scope, owner, original, renamed]
        elif t.class_index >= 0:
            ref = t.class_index
        else:
            ref = t.slot_id
        members.append([scope, owner, t.kind_name, original, renamed, _ns_of(abc, t.name), ref])


def build_block(index: int, name: str, abc: Abc, ren: Abc) -> dict:
    _check_same_shape(name, abc, ren)
    classes, members, methods = [], [], {}

    for ci, (inst, rinst, cls, rcls) in enumerate(zip(abc.instances, ren.instances, abc.classes, ren.classes)):
        cname, rname = abc.qname(inst.name), ren.qname(rinst.name)
        classes.append([ci, cname, rname, abc.qname(inst.super_name), abc.is_private(inst.name),
                        bool(inst.flags & 0x04), inst.iinit, cls.cinit])
        methods[inst.iinit] = ["iinit", "instance", ci, cname, rname]
        methods[cls.cinit] = ["cinit", "static", ci, cname, rname]
        _members(abc, ren, "instance", ci, inst.traits, rinst.traits, members, methods)
        _members(abc, ren, "static", ci, cls.traits, rcls.traits, members, methods)

    for si, (script, rscript) in enumerate(zip(abc.scripts, ren.scripts)):
        methods[script.init] = ["script_init", "script", si, None, None]
        _members(abc, ren, "script", si, script.traits, rscript.traits, members, methods)

    has_body = set(abc.body_methods)
    method_rows = [[mi, *methods.get(mi, ["closure", None, None, None, None]), mi in has_body]
                   for mi in range(abc.method_count)]

    strings = [[i, a, b] for i, (a, b) in enumerate(zip(abc.strings, ren.strings)) if i and a != b]
    namespaces = [[i, abc.string(a[1]), ren.string(b[1])]
                  for i, (a, b) in enumerate(zip(abc.namespaces, ren.namespaces))
                  if i and abc.string(a[1]) != ren.string(b[1])]

    return {
        "index": index, "name": name,
        "counts": {"classes": len(classes), "methods": abc.method_count, "bodies": len(abc.body_methods),
                   "scripts": len(abc.scripts), "strings": len(abc.strings), "renamed_strings": len(strings)},
        "classes": classes, "members": members, "methods": method_rows,
        "namespaces": namespaces, "strings": strings,
        "appended_strings": ren.strings[len(abc.strings):],
    }


def rows(block: dict, table: str) -> list[dict]:
    cols = TABLES[table]
    return [dict(zip(cols, r)) for r in block[table]]


def build_map(original: Path, renamed: Path, version: str, rename_type: str = "typeNumber",
              ffdec: str | None = None) -> dict:
    orig_blocks = swf_abc_blocks(original.read_bytes())
    ren_blocks = swf_abc_blocks(renamed.read_bytes())
    if [n for n, _ in orig_blocks] != [n for n, _ in ren_blocks]:
        raise MapError("renamed SWF has different DoABC blocks")
    blocks = [build_block(i, name, parse_abc(a), parse_abc(b))
              for i, ((name, a), (_, b)) in enumerate(zip(orig_blocks, ren_blocks))]
    return {
        "schema_version": SCHEMA_VERSION,
        "game_version": version,
        "input_sha256": sha256(original),
        "renamed_sha256": sha256(renamed),
        "renamer": {"tool": "FFDec -renameInvalidIdentifiers", "type": rename_type, "ffdec": ffdec},
        "columns": TABLES,
        "blocks": blocks,
        "symbols": [],
    }


def check_map(data: dict, as3_root: Path | None = None) -> list[str]:
    problems = []
    if data.get("schema_version") != SCHEMA_VERSION:
        problems.append(f"schema_version {data.get('schema_version')} != {SCHEMA_VERSION}")
    if data.get("columns") != TABLES:
        problems.append("column layout differs from this tool's")
    for block in data.get("blocks", []):
        tag = f"block {block['index']} {block['name']!r}"
        counts = block["counts"]
        classes = rows(block, "classes")
        if [c["class_index"] for c in classes] != list(range(counts["classes"])):
            problems.append(f"{tag}: class table does not cover 0..{counts['classes'] - 1}")
        if [m[0] for m in block["methods"]] != list(range(counts["methods"])):
            problems.append(f"{tag}: method table does not cover 0..{counts['methods'] - 1}")
        seen = set()
        for c in classes:
            if not c["original"] or not c["renamed"]:
                problems.append(f"{tag}: class {c['class_index']} has no name")
                continue
            key = (c["private"], c["renamed"])
            if key in seen:
                problems.append(f"{tag}: renamed class {c['renamed']} is not unique")
            seen.add(key)
            if not all(_valid_identifier(part) for part in c["renamed"].split(".")):
                problems.append(f"{tag}: renamed class {c['renamed']!r} is not a valid identifier")
            if as3_root is not None and not c["private"]:
                path = as3_root / "scripts" / (c["renamed"].replace(".", "/") + ".as")
                if not path.is_file():
                    problems.append(f"{tag}: no exported source for {c['renamed']} ({path})")
        for m in rows(block, "members"):
            if m["original"] is None or m["renamed"] is None:
                problems.append(f"{tag}: member without a name: {m}")
            elif not _valid_identifier(m["renamed"]):
                problems.append(f"{tag}: renamed member {m['renamed']!r} is not a valid identifier")
    return problems


RENAMED_TOKEN = re.compile(r"\b(?:class|method|var|const|package|namespace)_\d+\b")


def renamed_names(data: dict) -> set[str]:
    names = set()
    for block in data.get("blocks", []):
        names.update(row[2] for row in block.get("strings", []))
        names.update(row[2] for row in block.get("namespaces", []))
        names.update(block.get("appended_strings", []))
        for c in rows(block, "classes"):
            names.update(c["renamed"].split("."))
        names.update(m["renamed"] for m in rows(block, "members") if m["renamed"])
    return names


def unresolved_names(data: dict, scripts: Path) -> dict[str, list[str]]:
    known, found = renamed_names(data), {}
    for path in sorted(scripts.rglob("*.as")):
        text = path.read_text(encoding="utf-8", errors="replace")
        missing = sorted(set(RENAMED_TOKEN.findall(text)) - known)
        if missing:
            found[path.relative_to(scripts).as_posix()] = missing
    return found


def _valid_identifier(name: str) -> bool:
    if not name:
        return False
    first, rest = name[0], name[1:]
    ok = lambda ch, first: ch == "_" or ch == "$" or ch.isalpha() or (not first and ch.isdigit())
    return ok(first, True) and all(ok(ch, False) for ch in rest)


def dump(data: dict, out: Path) -> None:
    lines = ["{"]
    top = [k for k in data if k not in ("blocks", "symbols")]
    for k in top:
        lines.append(f"  {json.dumps(k)}: {json.dumps(data[k], ensure_ascii=False)},")
    lines.append('  "blocks": [')
    for bi, block in enumerate(data["blocks"]):
        lines.append("    {")
        keys = list(block)
        for ki, k in enumerate(keys):
            comma = "," if ki < len(keys) - 1 else ""
            v = block[k]
            if isinstance(v, list) and v:
                rows = [f"        {json.dumps(r, ensure_ascii=False)}" for r in v]
                lines.append(f"      {json.dumps(k)}: [\n" + ",\n".join(rows) + f"\n      ]{comma}")
            else:
                lines.append(f"      {json.dumps(k)}: {json.dumps(v, ensure_ascii=False)}{comma}")
        lines.append("    }" + ("," if bi < len(data["blocks"]) - 1 else ""))
    lines.append("  ],")
    lines.append(f'  "symbols": {json.dumps(data["symbols"], ensure_ascii=False, indent=2)}')
    lines.append("}")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--original", type=Path, required=True)
    b.add_argument("--renamed", type=Path, required=True)
    b.add_argument("--version", required=True)
    b.add_argument("--out", type=Path, required=True)
    b.add_argument("--ffdec", default=None, help="FFDec version/commit, recorded in the map")
    c = sub.add_parser("check")
    c.add_argument("map", type=Path)
    c.add_argument("--as3", type=Path, default=None, help="FFDec export root (with scripts/)")
    args = ap.parse_args(argv)

    if args.cmd == "build":
        data = build_map(args.original, args.renamed, args.version, ffdec=args.ffdec)
        problems = check_map(data)
        dump(data, args.out)
    else:
        data = load(args.map)
        problems = check_map(data, args.as3)
    total_classes = sum(b["counts"]["classes"] for b in data["blocks"])
    total_methods = sum(b["counts"]["methods"] for b in data["blocks"])
    total_members = sum(len(b["members"]) for b in data["blocks"])
    closures = sum(1 for b in data["blocks"] for m in b["methods"] if m[1] == "closure")
    total_strings = sum(len(b["strings"]) for b in data["blocks"])
    print(f"{len(data['blocks'])} blocks, {total_classes} classes, {total_members} traits, "
          f"{total_methods} methods ({closures} closures), {total_strings} renamed strings")
    for p in problems[:50]:
        print("PROBLEM:", p)
    if problems:
        print(f"{len(problems)} problem(s)")
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
