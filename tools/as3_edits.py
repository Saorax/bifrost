"""find which methods of the AS3 tree were edited since it was exported.

    python tools/as3_edits.py [--version 10.11]        # list edited files and methods

``tools/as3_fixups.py`` writes a manifest of the pristine tree (``build/as3/<ver>/as3-pristine.json``): per ``.as``
file, a hash of each function and of everything outside the functions. ``tools/splice_as3.py`` compares the current
tree with it: edited methods always use the compiled code, unchanged ones that still differ from the original keep
the original bytecode.

a function is keyed by ``(static, kind, name)``: ``static`` is ``s`` or ``i``, ``kind`` is ``method``, ``getter``,
``setter`` or ``iinit`` (the constructor). Anything outside the functions except import lines (fields and their
initializers, the class header) is "rest": if it changed, the file's initializers (``iinit``/``cinit``/script init)
and its field declarations count as edited. A function that was added, removed or had its header changed counts as
edited under its new and old keys.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

HEADER = re.compile(r"\bfunction\s+(?:(get|set)\s+)?([A-Za-z_$][\w$]*)\s*\(")
CLASS = re.compile(r"\b(?:class|interface)\s+([A-Za-z_$][\w$]*)")
MODIFIERS = re.compile(r"(?:^|[\s;{}])((?:(?:override|public|private|protected|internal|static|final|native|dynamic)\s+)*)$")


def _skip(text: str, i: int) -> int:
    c = text[i]
    if c in "\"'":
        j = i + 1
        while j < len(text) and text[j] != c:
            j += 2 if text[j] == "\\" else 1
        return j + 1
    if text.startswith("//", i):
        j = text.find("\n", i)
        return len(text) if j < 0 else j
    if text.startswith("/*", i):
        j = text.find("*/", i + 2)
        return len(text) if j < 0 else j + 2
    return i


def _match_brace(text: str, i: int) -> int:
    depth = 0
    while i < len(text):
        j = _skip(text, i)
        if j != i:
            i = j
            continue
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError("unbalanced braces")


def split(text: str) -> tuple[dict[tuple[str, str, str], str], str]:
    cls = CLASS.search(text)
    class_name = cls.group(1) if cls else None
    body_start = text.find("{", cls.end()) if cls else -1
    functions: dict[tuple[str, str, str], str] = {}
    rest, last = [], 0
    if body_start < 0:
        return functions, text
    i = body_start + 1
    depth = 1
    while i < len(text) and depth > 0:
        j = _skip(text, i)
        if j != i:
            i = j
            continue
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        elif depth == 1 and text.startswith("function", i) and (i == 0 or not (text[i - 1].isalnum() or text[i - 1] in "_$")):
            m = HEADER.match(text, i)
            if m:
                line_start = text.rfind("\n", 0, i) + 1
                mods = MODIFIERS.search(text[line_start:i])
                modifiers = mods.group(1) if mods else ""
                open_brace = text.find("{", m.end())
                semicolon = text.find(";", m.end())
                if open_brace < 0 or (0 <= semicolon < open_brace):
                    end = semicolon + 1
                else:
                    end = _match_brace(text, open_brace)
                name = m.group(2)
                kind = {"get": "getter", "set": "setter"}.get(m.group(1) or "", "method")
                if name == class_name and kind == "method":
                    kind = "iinit"
                static = "s" if "static" in modifiers.split() else "i"
                functions[(static, kind, name)] = text[line_start:end]
                rest.append(text[last:line_start])
                last = end
                i = end
                continue
        i += 1
    rest.append(text[last:])
    return functions, "".join(rest)


IMPORT = re.compile(r"^[ \t]*import[ \t]+[\w.$*]+[ \t]*;[ \t]*\r?\n", re.M)


def _hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _rest_hash(rest: str) -> str:
    return _hash(IMPORT.sub("", rest))


def fingerprint(tree: Path) -> dict:
    out = {}
    for path in sorted(tree.rglob("*.as")):
        rel = path.relative_to(tree).as_posix()
        functions, rest = split(path.read_text(encoding="utf-8"))
        out[rel] = {"rest": _rest_hash(rest),
                    "functions": {"/".join(k): _hash(v) for k, v in sorted(functions.items())}}
    return out


def edits(tree: Path, pristine: dict) -> dict[str, dict]:
    now = fingerprint(tree)
    out = {}
    for rel, cur in now.items():
        old = pristine.get(rel)
        if old is None:
            out[rel] = {"new": True, "rest": True, "functions": sorted(cur["functions"])}
            continue
        changed = sorted(k for k in set(cur["functions"]) | set(old["functions"])
                         if cur["functions"].get(k) != old["functions"].get(k))
        if changed or cur["rest"] != old["rest"]:
            out[rel] = {"rest": cur["rest"] != old["rest"], "functions": changed}
    return out


def pristine_path(version: str) -> Path:
    return ROOT / "build" / "as3" / version / "as3-pristine.json"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--version", default="10.11")
    p.add_argument("--tree", type=Path)
    args = p.parse_args(argv)
    tree = args.tree or ROOT / "src" / "as3" / args.version / "scripts"
    manifest = pristine_path(args.version)
    if not manifest.exists():
        print(f"missing {manifest}: run tools/export_as3.py first", file=sys.stderr)
        return 2
    found = edits(tree, json.loads(manifest.read_text(encoding="utf-8")))
    for rel, e in sorted(found.items()):
        what = ["new file"] if e.get("new") else (["fields/initializers"] if e["rest"] else []) + e["functions"]
        print(f"{rel}: {', '.join(what)}")
    print(f"{len(found)} edited files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
