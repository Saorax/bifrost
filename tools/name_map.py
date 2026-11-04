"""build and check the name map: a valid AS3 identifier for every obfuscated name (`_-z28` -> `__z28`).

    python tools/name_map.py build   # versions/<newest>/BrawlhallaAir.swf -> data/symbols/<ver>.names.json
    python tools/name_map.py check   # reload the map, re-read the SWF, validate coverage and names
    python tools/name_map.py lookup _-z28

the names are mechanical, not evidence (research aliases live in ``client/symbols/<ver>.json``).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import lzma
from pathlib import Path
import re
import struct
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
SCHEMA_VERSION = 1

IDENTIFIER = re.compile(r"^[A-Za-z_$][A-Za-z0-9_$]*$")
RESERVED = frozenset(
    "as break case catch class const continue default delete do else extends "
    "false finally for function if implements import in instanceof interface "
    "internal is new null package private protected public return super switch "
    "this throw to true try typeof use var void while with".split()
)

NS_PRIVATE, NS_NAMESPACE, NS_PACKAGE, NS_PACKAGE_INTERNAL = 0x05, 0x08, 0x16, 0x17
NS_PROTECTED, NS_EXPLICIT, NS_STATIC_PROTECTED = 0x18, 0x19, 0x1A
NS_KIND_NAMES = {
    NS_PRIVATE: "private", NS_NAMESPACE: "namespace", NS_PACKAGE: "package",
    NS_PACKAGE_INTERNAL: "internal", NS_PROTECTED: "protected",
    NS_EXPLICIT: "explicit", NS_STATIC_PROTECTED: "static_protected",
}
MN_QNAME, MN_QNAME_A, MN_RTQNAME, MN_RTQNAME_A = 0x07, 0x0D, 0x0F, 0x10
MN_RTQNAME_L, MN_RTQNAME_LA, MN_MULTINAME, MN_MULTINAME_A = 0x11, 0x12, 0x09, 0x0E
MN_MULTINAME_L, MN_MULTINAME_LA, MN_TYPENAME = 0x1B, 0x1C, 0x1D
TRAIT_KIND_NAMES = {0: "slot", 1: "method", 2: "getter", 3: "setter", 4: "class", 5: "function", 6: "const"}
ATTR_METADATA = 0x40
HAS_OPTIONAL, HAS_PARAM_NAMES = 0x08, 0x80
CLASS_PROTECTED_NS = 0x08


def is_valid_identifier(name: str) -> bool:
    return bool(IDENTIFIER.match(name)) and name not in RESERVED


def is_valid_package(name: str) -> bool:
    return name == "" or all(is_valid_identifier(part) for part in name.split("."))


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def swf_body(data: bytes) -> bytes:
    sig = data[:3]
    if sig == b"FWS":
        return data[8:]
    if sig == b"CWS":
        return zlib.decompress(data[8:])
    if sig == b"ZWS":
        props = data[12:17]
        size = struct.unpack_from("<I", data, 4)[0] - 8
        header = props + struct.pack("<Q", size)
        return lzma.LZMADecompressor(lzma.FORMAT_ALONE).decompress(header + data[17:])
    raise ValueError(f"not a SWF (signature {sig!r})")


def abc_tags(data: bytes) -> list[dict]:
    body = swf_body(data)
    nbits = body[0] >> 3
    pos = (5 + 4 * nbits + 7) // 8 + 4
    out = []
    while pos + 2 <= len(body):
        code_len = struct.unpack_from("<H", body, pos)[0]
        pos += 2
        code, length = code_len >> 6, code_len & 0x3F
        if length == 0x3F:
            length = struct.unpack_from("<I", body, pos)[0]
            pos += 4
        payload = body[pos:pos + length]
        pos += length
        if code == 82:
            flags = struct.unpack_from("<I", payload, 0)[0]
            end = payload.index(b"\0", 4)
            name = payload[4:end].decode("utf-8", "replace")
            out.append({"tag": "DoABC", "flags": flags, "name": name, "abc": payload[end + 1:]})
        elif code == 72:
            out.append({"tag": "DoABCDefine", "flags": 0, "name": "", "abc": payload})
        elif code == 0:
            break
    return out


class Reader:
    def __init__(self, data: bytes):
        self.data, self.pos = data, 0

    def u8(self) -> int:
        value = self.data[self.pos]
        self.pos += 1
        return value

    def u16(self) -> int:
        value = struct.unpack_from("<H", self.data, self.pos)[0]
        self.pos += 2
        return value

    def u30(self) -> int:
        result, shift = 0, 0
        for _ in range(5):
            byte = self.data[self.pos]
            self.pos += 1
            result |= (byte & 0x7F) << shift
            if not byte & 0x80:
                break
            shift += 7
        return result & 0xFFFFFFFF

    def skip(self, count: int) -> None:
        self.pos += count


def parse_abc(abc: bytes) -> dict:
    r = Reader(abc)
    minor, major = r.u16(), r.u16()
    count = r.u30()
    for _ in range(max(count - 1, 0)):
        r.u30()
    count = r.u30()
    for _ in range(max(count - 1, 0)):
        r.u30()
    count = r.u30()
    r.skip(8 * max(count - 1, 0))
    strings = [None]
    for _ in range(max(r.u30() - 1, 0)):
        length = r.u30()
        strings.append(abc[r.pos:r.pos + length].decode("utf-8", "surrogatepass"))
        r.skip(length)
    namespaces = [None]
    for _ in range(max(r.u30() - 1, 0)):
        namespaces.append((r.u8(), r.u30()))
    ns_sets = [None]
    for _ in range(max(r.u30() - 1, 0)):
        ns_sets.append([r.u30() for _ in range(r.u30())])
    multinames = [None]
    for _ in range(max(r.u30() - 1, 0)):
        kind = r.u8()
        if kind in (MN_QNAME, MN_QNAME_A):
            multinames.append({"kind": kind, "ns": r.u30(), "name": r.u30()})
        elif kind in (MN_RTQNAME, MN_RTQNAME_A):
            multinames.append({"kind": kind, "name": r.u30()})
        elif kind in (MN_RTQNAME_L, MN_RTQNAME_LA):
            multinames.append({"kind": kind})
        elif kind in (MN_MULTINAME, MN_MULTINAME_A):
            multinames.append({"kind": kind, "name": r.u30(), "ns_set": r.u30()})
        elif kind in (MN_MULTINAME_L, MN_MULTINAME_LA):
            multinames.append({"kind": kind, "ns_set": r.u30()})
        elif kind == MN_TYPENAME:
            base = r.u30()
            multinames.append({"kind": kind, "base": base, "params": [r.u30() for _ in range(r.u30())]})
        else:
            raise ValueError(f"unknown multiname kind 0x{kind:02x} at {r.pos - 1}")

    methods = []
    for _ in range(r.u30()):
        param_count = r.u30()
        for _ in range(param_count + 1):
            r.u30()
        name = r.u30()
        flags = r.u8()
        if flags & HAS_OPTIONAL:
            for _ in range(r.u30()):
                r.u30()
                r.u8()
        param_names = [r.u30() for _ in range(param_count)] if flags & HAS_PARAM_NAMES else []
        methods.append({"params": param_count, "name": name, "flags": flags,
                        "param_names": param_names, "body": None})

    for _ in range(r.u30()):
        r.u30()
        items = r.u30()
        for _ in range(2 * items):
            r.u30()

    def traits() -> list[dict]:
        out = []
        for _ in range(r.u30()):
            name = r.u30()
            kind_byte = r.u8()
            kind, attrs = kind_byte & 0x0F, kind_byte >> 4
            trait = {"name": name, "kind": kind}
            if kind in (0, 6):
                trait["slot"] = r.u30()
                r.u30()
                if r.u30():
                    r.u8()
            elif kind in (1, 2, 3):
                trait["disp"] = r.u30()
                trait["method"] = r.u30()
            elif kind == 4:
                trait["slot"] = r.u30()
                trait["class"] = r.u30()
            elif kind == 5:
                trait["slot"] = r.u30()
                trait["method"] = r.u30()
            else:
                raise ValueError(f"unknown trait kind {kind} at {r.pos}")
            if (attrs << 4) & ATTR_METADATA:
                for _ in range(r.u30()):
                    r.u30()
            out.append(trait)
        return out

    class_count = r.u30()
    instances = []
    for _ in range(class_count):
        inst = {"name": r.u30(), "super": r.u30()}
        inst["flags"] = r.u8()
        if inst["flags"] & CLASS_PROTECTED_NS:
            r.u30()
        inst["interfaces"] = [r.u30() for _ in range(r.u30())]
        inst["iinit"] = r.u30()
        inst["traits"] = traits()
        instances.append(inst)
    classes = [{"cinit": r.u30(), "traits": traits()} for _ in range(class_count)]
    scripts = [{"init": r.u30(), "traits": traits()} for _ in range(r.u30())]
    bodies = []
    for _ in range(r.u30()):
        method = r.u30()
        r.u30(), r.u30(), r.u30(), r.u30()
        r.skip(r.u30())
        for _ in range(r.u30()):
            r.u30(), r.u30(), r.u30(), r.u30()
            r.u30()
        body = {"method": method, "traits": traits()}
        methods[method]["body"] = len(bodies)
        bodies.append(body)
    if r.pos != len(abc):
        raise ValueError(f"ABC parse ended at {r.pos}, block has {len(abc)} bytes")
    return {"version": [major, minor], "strings": strings, "namespaces": namespaces,
            "ns_sets": ns_sets, "multinames": multinames, "methods": methods,
            "instances": instances, "classes": classes, "scripts": scripts, "bodies": bodies}


class Block:

    def __init__(self, abc: dict):
        self.abc = abc

    def string(self, index: int) -> str | None:
        return self.abc["strings"][index] if index else None

    def ns(self, index: int) -> tuple[str, str]:
        kind, name = self.abc["namespaces"][index]
        return NS_KIND_NAMES.get(kind, f"0x{kind:02x}"), self.string(name) or ""

    def mn_name(self, index: int) -> str | None:
        if not index:
            return None
        mn = self.abc["multinames"][index]
        return self.string(mn.get("name", 0))

    def qualified(self, index: int) -> str:
        if not index:
            return "*"
        mn = self.abc["multinames"][index]
        if mn["kind"] == MN_TYPENAME:
            params = ", ".join(self.qualified(p) for p in mn["params"])
            return f"{self.qualified(mn['base'])}.<{params}>"
        name = self.string(mn.get("name", 0)) or "*"
        if mn["kind"] in (MN_QNAME, MN_QNAME_A):
            kind, ns = self.ns(mn["ns"])
            if kind in ("package", "internal"):
                return f"{ns}::{name}" if ns else name
            return f"{kind}({ns})::{name}" if ns else f"{kind}::{name}"
        return name


def collect_uses(block: Block) -> dict[str, set[str]]:
    abc = block.abc
    uses: dict[str, set[str]] = {}

    def add(name: str | None, kind: str) -> None:
        if name is not None:
            uses.setdefault(name, set()).add(kind)

    for inst in abc["instances"]:
        add(block.mn_name(inst["name"]), "class")
        for trait in inst["traits"]:
            add(block.mn_name(trait["name"]), TRAIT_KIND_NAMES[trait["kind"]])
    for cls in abc["classes"]:
        for trait in cls["traits"]:
            add(block.mn_name(trait["name"]), "static_" + TRAIT_KIND_NAMES[trait["kind"]])
    for script in abc["scripts"]:
        for trait in script["traits"]:
            add(block.mn_name(trait["name"]), "script_" + TRAIT_KIND_NAMES[trait["kind"]])
    for body in abc["bodies"]:
        for trait in body["traits"]:
            add(block.mn_name(trait["name"]), "local")
    for method in abc["methods"]:
        for index in method["param_names"]:
            add(block.string(index), "param")
    declared = set(uses)
    for mn in abc["multinames"][1:]:
        name = block.string(mn.get("name", 0))
        if name is not None and name not in declared:
            add(name, "reference")
    for kind, name in abc["namespaces"][1:]:
        if kind in (NS_PACKAGE, NS_PACKAGE_INTERNAL) and name:
            for part in block.string(name).split("."):
                add(part, "package")
    return uses


def needs_name(name: str) -> bool:
    return name not in ("", "void") and not is_valid_identifier(name)


def assign_names(uses: dict[str, set[str]]) -> dict[str, str]:
    taken = {name for name in uses if is_valid_identifier(name)}
    mapping = {}
    for name in sorted(n for n in uses if needs_name(n)):
        base = re.sub(r"[^A-Za-z0-9_$]", "_", name) or "_"
        if base[0].isdigit():
            base = "_" + base
        if base in RESERVED:
            base += "_"
        candidate, n = base, 2
        while candidate in taken:
            candidate, n = f"{base}_{n}", n + 1
        taken.add(candidate)
        mapping[name] = candidate
    return mapping


def trait_entries(block: Block, traits: list[dict]) -> list[dict]:
    out = []
    for trait in traits:
        entry = {"name": block.mn_name(trait["name"]), "kind": TRAIT_KIND_NAMES[trait["kind"]]}
        for key in ("method", "class", "slot", "disp"):
            if key in trait:
                entry[key] = trait[key]
        out.append(entry)
    return out


def describe_block(index: int, tag: dict, abc: dict) -> dict:
    block = Block(abc)
    classes = []
    for i, (inst, cls) in enumerate(zip(abc["instances"], abc["classes"])):
        classes.append({
            "index": i,
            "name": block.qualified(inst["name"]),
            "super": block.qualified(inst["super"]) if inst["super"] else None,
            "interface": bool(inst["flags"] & 0x04),
            "iinit": inst["iinit"],
            "cinit": cls["cinit"],
            "traits": trait_entries(block, inst["traits"]),
            "static_traits": trait_entries(block, cls["traits"]),
        })
    scripts = [{"index": i, "init": s["init"], "traits": trait_entries(block, s["traits"])}
               for i, s in enumerate(abc["scripts"])]
    return {
        "index": index,
        "tag": tag["tag"],
        "tag_name": tag["name"],
        "abc_sha256": sha256_bytes(tag["abc"]),
        "abc_version": abc["version"],
        "counts": {"strings": len(abc["strings"]) - 1, "multinames": len(abc["multinames"]) - 1,
                   "methods": len(abc["methods"]), "classes": len(classes),
                   "scripts": len(scripts), "bodies": len(abc["bodies"])},
        "classes": classes,
        "scripts": scripts,
    }


def build_map(swf: Path, version: str) -> dict:
    data = swf.read_bytes()
    tags = abc_tags(data)
    blocks, uses = [], {}
    for index, tag in enumerate(tags):
        abc = parse_abc(tag["abc"])
        blocks.append(describe_block(index, tag, abc))
        for name, kinds in collect_uses(Block(abc)).items():
            entry = uses.setdefault(name, {"kinds": set(), "blocks": set()})
            entry["kinds"] |= kinds
            entry["blocks"].add(index)
    mapping = assign_names({name: e["kinds"] for name, e in uses.items()})
    names = {old: {"name": new, "uses": sorted(uses[old]["kinds"]), "blocks": sorted(uses[old]["blocks"])}
             for old, new in sorted(mapping.items())}
    return {
        "schema_version": SCHEMA_VERSION,
        "game_version": version,
        "input": display_path(swf),
        "input_sha256": sha256_bytes(data),
        "note": ("Mechanical valid identifiers for names AS3 cannot spell. Not evidence: "
                 "research aliases live in client/symbols/<ver>.json. Keyed by the original "
                 "string, so one string always gets one name across all blocks."),
        "rule": ("Replace each character outside [A-Za-z0-9_$] with '_', prefix '_' before a "
                 "leading digit, append '_' to a keyword, then append _2, _3, ... on a clash "
                 "with any valid name in the SWF or an earlier assignment (originals sorted)."),
        "identifier_count": len(uses),
        "renamed_count": len(names),
        "names": names,
        "blocks": blocks,
    }


def valid_name_for(name: str | None, names: dict) -> bool:
    if name is None:
        return True
    return not needs_name(names[name]["name"] if name in names else name)


def check_map(doc: dict, swf: Path | None) -> list[str]:
    problems = []
    names = doc.get("names", {})
    new_names = [entry["name"] for entry in names.values()]
    for old, entry in names.items():
        if not needs_name(old):
            problems.append(f"already valid, should not be renamed: {old!r}")
        if not is_valid_identifier(entry["name"]):
            problems.append(f"invalid new name {entry['name']!r} for {old!r}")
    if len(set(new_names)) != len(new_names):
        problems.append("two originals share a new name")

    for block in doc.get("blocks", []):
        for cls in block["classes"]:
            short = cls["name"].rsplit("::", 1)[-1]
            package = cls["name"].rsplit("::", 1)[0] if "::" in cls["name"] else ""
            if not valid_name_for(short, names):
                problems.append(f"block {block['index']} class {cls['index']}: no valid name for {short!r}")
            for part in filter(None, package.split(".")):
                if not valid_name_for(part, names) and not part.startswith(("private(", "protected(")):
                    problems.append(f"block {block['index']} class {cls['index']}: package part {part!r}")
            for trait in cls["traits"] + cls["static_traits"]:
                if not valid_name_for(trait["name"], names):
                    problems.append(f"block {block['index']} class {cls['name']}: trait {trait['name']!r}")
        for script in block["scripts"]:
            for trait in script["traits"]:
                if not valid_name_for(trait["name"], names):
                    problems.append(f"block {block['index']} script {script['index']}: trait {trait['name']!r}")

    if swf is not None:
        data = swf.read_bytes()
        if sha256_bytes(data) != doc.get("input_sha256"):
            problems.append(f"{swf} does not match the map's input_sha256; rebuild the map")
        else:
            fresh = build_map(swf, doc.get("game_version", ""))
            if fresh["names"] != names:
                problems.append("names differ from a fresh build of the same SWF")
            if fresh["blocks"] != doc.get("blocks"):
                problems.append("block listing differs from a fresh build of the same SWF")
    return problems


def display_path(path: Path) -> str:
    path = path.resolve()
    return path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else path.name


def newest_version() -> str:
    versions = [p.name for p in (ROOT / "versions").iterdir()
                if p.is_dir() and (p / "BrawlhallaAir.swf").is_file()] if (ROOT / "versions").is_dir() else []
    if not versions:
        raise SystemExit("no versions/<ver>/BrawlhallaAir.swf found; pass --swf and --version")
    return max(versions, key=lambda v: [int(x) if x.isdigit() else x for x in re.split(r"[.\-]", v)])


def resolve(args) -> tuple[Path, Path, str]:
    version = args.version or (newest_version() if not args.swf else "unknown")
    swf = Path(args.swf) if args.swf else ROOT / "versions" / version / "BrawlhallaAir.swf"
    out = Path(args.map) if args.map else ROOT / "data" / "symbols" / f"{version}.names.json"
    return swf, out, version


def dumps(doc: dict) -> str:
    def one(value) -> str:
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))

    lines = ["{"]
    for key, value in doc.items():
        if key == "names":
            items = [f"  {one(old)}:{one(entry)}" for old, entry in value.items()]
            lines.append(' "names":{\n' + ",\n".join(items) + "\n },")
        elif key == "blocks":
            blocks = []
            for block in value:
                head = {k: v for k, v in block.items() if k not in ("classes", "scripts")}
                classes = ",\n".join(f"   {one(c)}" for c in block["classes"])
                scripts = ",\n".join(f"   {one(s)}" for s in block["scripts"])
                blocks.append(f"  {one(head)[:-1]},\n  \"classes\":[\n{classes}\n  ],\n"
                              f"  \"scripts\":[\n{scripts}\n  ]}}")
            lines.append(' "blocks":[\n' + ",\n".join(blocks) + "\n ],")
        else:
            lines.append(f" {one(key)}:{one(value)},")
    lines[-1] = lines[-1].rstrip(",")
    lines.append("}")
    return "\n".join(lines) + "\n"


def write_json(doc: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = dumps(doc)
    assert json.loads(text) == doc
    path.write_text(text, encoding="utf-8", newline="\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["build", "check", "lookup"])
    parser.add_argument("names", nargs="*", help="lookup: original or new names")
    parser.add_argument("--version", help="game version folder under versions/ (default: newest)")
    parser.add_argument("--swf", help="SWF to read (default: versions/<ver>/BrawlhallaAir.swf)")
    parser.add_argument("--map", help="map file (default: data/symbols/<ver>.names.json)")
    parser.add_argument("--no-swf", action="store_true", help="check: validate the map file alone")
    args = parser.parse_args(argv)
    swf, out, version = resolve(args)

    if args.command == "build":
        doc = build_map(swf, version)
        write_json(doc, out)
        classes = sum(len(b["classes"]) for b in doc["blocks"])
        print(f"{display_path(out)}: {len(doc['blocks'])} ABC blocks, {classes} classes, "
              f"{doc['identifier_count']} identifiers, {doc['renamed_count']} renamed")
        return 0

    doc = json.loads(out.read_text(encoding="utf-8"))
    if args.command == "check":
        problems = check_map(doc, None if args.no_swf else swf)
        for problem in problems[:50]:
            print(problem)
        if problems:
            print(f"FAIL: {len(problems)} problem(s)")
            return 1
        print(f"OK: {display_path(out)} covers {sum(len(b['classes']) for b in doc['blocks'])} classes "
              f"in {len(doc['blocks'])} blocks; {doc['renamed_count']} names renamed")
        return 0

    reverse = {entry["name"]: old for old, entry in doc["names"].items()}
    status = 0
    for name in args.names:
        if name in doc["names"]:
            entry = doc["names"][name]
            print(f"{name} -> {entry['name']}  uses={','.join(entry['uses'])} blocks={entry['blocks']}")
        elif name in reverse:
            print(f"{name} <- {reverse[name]}")
        else:
            print(f"{name}: not renamed")
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
